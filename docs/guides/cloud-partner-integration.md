---
page_title: "Cloud Partner Integration Guide"
description: |-
  How cloud partners can use the Shoehorn Terraform modules
  to offer automated Shoehorn deployments on their Kubernetes platforms.
---

# Cloud Partner Integration Guide

This guide explains how cloud partners integrate Shoehorn into their Kubernetes offerings, so customers can deploy a fully configured Intelligent Developer Platform with a single `terraform apply`.

## Architecture

```
Cloud Partner's Terraform Config
    │
    ├── Their infrastructure (K8s cluster, managed DB, DNS, etc.)
    │
    └── module "shoehorn" {
          source = "shoehorn-dev/kubernetes"
          # Deploys: Shoehorn platform + K8s Agent
          # In a single apply using bootstrap API key
        }
```

**Prerequisite**: A running Kubernetes cluster with `kubectl` access. The Shoehorn module handles everything else.

## The Kubernetes Module

The `modules/Kubernetes` module is the core integration point. It deploys Shoehorn onto any existing Kubernetes cluster:

```hcl
module "shoehorn" {
  source = "shoehorn-dev/kubernetes"

  # Required
  domain            = "portal.customer.com"
  credentials       = { ... }    # Secrets (passwords, JWT, encryption keys)

  # Auth (Okta, Zitadel, or Entra ID)
  auth_provider     = "okta"
  auth_config       = { domain = "...", clientId = "...", issuer = "..." }
  admin_email       = "admin@customer.com"

  # Bootstrap: single-apply agent deployment
  enable_bootstrap  = true
  deploy_agent      = true
  cluster_id        = "customer-prod-eu"
  cluster_name      = "Customer Production (EU)"
}
```

### What It Creates

| Phase | Resources | Depends On |
|---|---|---|
| 1 | Kubernetes namespace + credentials secret | none |
| 2 | Shoehorn Helm release (all microservices) | Phase 1 |
| 3 | Health check gate | Phase 2 |
| 4 | Bootstrap API key K8s Job | Phase 3 |
| 5 | K8s Agent registration | Phase 4 |
| 6 | K8s Agent Helm release | Phase 5 |

## Bootstrap: Single-Apply Deployment

The bootstrap mechanism solves the chicken-and-egg problem: the Shoehorn provider needs an API key to register the agent, but API keys are created through the Shoehorn API which isn't running yet.

### How It Works

1. **Terraform derives a deterministic API key** from `JWT_SECRET` using `HMAC-SHA256`
2. **A K8s Job seeds that key** into the database after the platform is healthy
3. **The Shoehorn provider authenticates** with the same derived key to register the agent
4. **The key auto-expires** after 1 hour (security safeguard)
5. **After deploy**, the customer creates a permanent API key in the UI for subsequent applies

### Security Safeguards

The bootstrap key is designed for initial deployment only:

| Safeguard | Description |
|---|---|
| HMAC-SHA256 derivation | Not plain SHA256. Prevents length-extension attacks |
| Minimal scope | `k8s-agents:write` only. Cannot access admin APIs |
| 1-hour TTL | Auto-expires, cannot be used for persistent access |
| Environment gate | Refuses to run in production (fail-closed allowlist) |
| Deterministic UUID5 | Idempotent upserts. Safe to re-run |
| Revocation guard | Cannot un-revoke a manually revoked key |
| Audit logging | WARN-level log on creation with key prefix, tenant, scopes |

### Bootstrap Key Derivation

Both sides (Terraform and Go) independently compute the same key:

```
raw_key = "shp_svc_" + base64url(HMAC-SHA256(key=JWT_SECRET, msg="shoehorn-bootstrap-api-key-v1"))
```

**Terraform** (via Python external data source):
```python
hmac.new(jwt_secret.encode(), b"shoehorn-bootstrap-api-key-v1", hashlib.sha256)
```

**Go** (in the K8s Job via `--bootstrap-api-key` CLI flag):
```go
mac := hmac.New(sha256.New, []byte(jwtSecret))
mac.Write([]byte("shoehorn-bootstrap-api-key-v1"))
```

## Two-Phase Lifecycle

### Phase 1: Initial Deploy (Bootstrap)

```hcl
provider "shoehorn" {
  host    = "https://portal.customer.com"
  api_key = local.bootstrap_api_key  # Derived from JWT_SECRET
}

module "shoehorn" {
  enable_bootstrap = true
  deploy_agent     = true
  # ... full config
}
```

```bash
terraform apply  # Single command deploys everything
```

### Phase 2: Ongoing Management (Permanent Key)

After the initial deploy, the customer:
1. Logs into Shoehorn UI
2. Creates a permanent API key (Settings → API Keys)
3. Updates the Terraform config:

```hcl
provider "shoehorn" {
  host    = "https://portal.customer.com"
  api_key = var.shoehorn_api_key  # Permanent key from UI
}
```

Subsequent `terraform apply` calls use the permanent key. No bootstrap needed.

## Database Options

The module supports two PostgreSQL modes:

### Chart-Deployed (Default)

The Helm chart deploys its own PostgreSQL StatefulSet. No external database needed.

```hcl
module "shoehorn" {
  # database_host not set → chart deploys PostgreSQL
  storage_class = "your-storage-class"
}
```

### External Managed Database

For production, use a managed PostgreSQL (RDS, Cloud SQL, UpCloud Managed DB, etc.):

```hcl
module "shoehorn" {
  database_host    = "managed-db.provider.com"
  database_port    = 5432
  database_name    = "shoehorn"
  database_user    = "shoehorn_user"
  database_sslmode = "require"
}
```

**Note**: When using a managed database, the `shoehorn_user` role must be created beforehand with `BYPASSRLS` and `LOGIN` privileges.

## Secrets Generation

Shoehorn requires several secrets, each with a specific format. **Do not reuse secrets across keys**, especially `postgres_password` and `db_password` which protect RLS (Row-Level Security) separation.

### Terraform (Recommended)

```hcl
# Database passwords (separate for migration user vs runtime user. RLS security depends on this)
resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

# JWT signing secret (hex-encoded, 256-bit)
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# Auth encryption key (MUST be base64-encoded 32 bytes for AES-256-GCM)
resource "random_bytes" "auth_encryption_key" {
  length = 32
}

# Session encryption key (MUST be base64-encoded 32 bytes, same shape as auth_encryption_key)
resource "random_bytes" "session_encryption_key" {
  length = 32
}

# Service passwords
resource "random_password" "valkey_password" {
  length  = 32
  special = false
}

resource "random_password" "meilisearch_master_key" {
  length  = 32
  special = false
}
```

Then pass them to the module:

```hcl
module "shoehorn" {
  credentials = {
    # Database (MUST be different. RLS security depends on this)
    postgres_password      = random_password.postgres_password.result       # Migration user (BYPASSRLS)
    db_password            = random_password.db_password.result             # Runtime user (NOBYPASSRLS)

    # Signing & encryption
    jwt_secret             = random_password.jwt_secret.result              # JWT token signing
    auth_encryption_key    = random_bytes.auth_encryption_key.base64        # AES-256-GCM (base64!)
    session_encryption_key = random_bytes.session_encryption_key.base64     # base64 of 32 bytes

    # Service passwords
    valkey_password        = random_password.valkey_password.result         # Valkey/Redis
    meilisearch_master_key = random_password.meilisearch_master_key.result  # Meilisearch

    # Auth provider (add based on your provider)
    okta_client_secret     = var.okta_client_secret                        # Okta only
    okta_api_token         = var.okta_api_token                            # Okta user/group sync
  }
}
```

### Manual (kubectl)

Equivalent using `openssl`:

```bash
kubectl create secret generic shoehorn-credentials -n shoehorn \
  --from-literal=postgres_password="$(openssl rand -base64 24)" \
  --from-literal=db_password="$(openssl rand -base64 24)" \
  --from-literal=jwt_secret="$(openssl rand -hex 32)" \
  --from-literal=auth_encryption_key="$(openssl rand -base64 32)" \
  --from-literal=session_encryption_key="$(openssl rand -base64 32)" \
  --from-literal=valkey_password="$(openssl rand -base64 24)" \
  --from-literal=meilisearch_master_key="$(openssl rand -hex 32)" \
  --from-literal=okta_client_secret="YOUR_OKTA_CLIENT_SECRET"
```

### Key Format Reference

#### Core (always required)

| Secret | Format | Description |
|---|---|---|
| `postgres_password` | Any string | Password for `shoehorn_user` (migration, BYPASSRLS) |
| `db_password` | Any string, **different from above** | Password for `app_user` (runtime, NOBYPASSRLS enforces RLS) |
| `jwt_secret` | Hex string, min 32 chars | HMAC signing key for JWT tokens |
| `auth_encryption_key` | **Base64-encoded 32 bytes** | AES-256-GCM encryption for auth credentials |
| `session_encryption_key` | Any string, min 32 chars | Session cookie encryption |
| `valkey_password` | Any string | Valkey/Redis authentication |
| `meilisearch_master_key` | Hex string | Meilisearch API master key |

#### Auth Provider (one set required)

**Okta:**

| Credential key | Source | Used for |
|---|---|---|
| `okta_client_secret` | Okta app → General → Client Credentials | OAuth2 OIDC client secret |
| `okta_api_token` | Okta → Security → API → Tokens | User/group sync (orgdata) |

Drop the keys into the `credentials` map. The module wires
`auth.okta.clientSecretRef.key` and `auth.okta.apiTokenSecretRef.key`
automatically. Enable orgdata with:

```hcl
helm_set = {
  "auth.orgdata.enabled"          = "true"
  "auth.orgdata.providers[0]"     = "okta"
  "auth.orgdata.primaryProvider"  = "okta"
}
```

**Zitadel:**

| Credential key | Source | Used for |
|---|---|---|
| `zitadel_service_user_pat` | Zitadel → Service Users → Personal Access Token | Service-to-service auth |

Same pattern: drop the key in `credentials`. The module wires
`auth.zitadel.serviceUserPatSecretRef.key` automatically. Enable orgdata with:

```hcl
helm_set = {
  "auth.orgdata.enabled"          = "true"
  "auth.orgdata.providers[0]"     = "zitadel"
  "auth.orgdata.primaryProvider"  = "zitadel"
}
```

#### GitHub Integration (optional, for repo crawling + workflow engine)

GitHub requires two separate GitHub Apps: one for **Crawler** (repo discovery) and one for **Forge** (workflow execution). Each app has an App ID, Installation ID, and a private key (PEM file).

| Secret | Source | Description |
|---|---|---|
| `github_app_id` | GitHub → Settings → Developer Settings → GitHub Apps | Crawler app ID |
| `github_app_installation_id` | GitHub → Settings → Installations | Crawler installation ID |
| `github_forge_app_id` | Separate GitHub App for Forge | Forge app ID |
| `github_forge_installation_id` | Forge app installation | Forge installation ID |

**Private keys** are file-based (PEM), not stored in the credentials map. Mount them via `extraVolumes`:

```hcl
helm_values = [yamlencode({
  extraVolumes = [
    {
      name = "github-private-key"
      secret = {
        secretName = "github-app-credentials"
        items = [{ key = "github_app_private_key", path = "private-key" }]
      }
    },
    {
      name = "github-forge-private-key"
      secret = {
        secretName = "github-forge-credentials"
        optional = true
        items = [{ key = "github_forge_private_key", path = "private-key" }]
      }
    }
  ]
  extraVolumeMounts = [
    { name = "github-private-key",       mountPath = "/var/secrets/github" },
    { name = "github-forge-private-key", mountPath = "/var/secrets/github-forge" }
  ]
})]
```

Create the K8s secrets separately:
```bash
kubectl create secret generic github-app-credentials -n shoehorn \
  --from-file=github_app_private_key=crawler-app.pem

kubectl create secret generic github-forge-credentials -n shoehorn \
  --from-file=github_forge_private_key=forge-app.pem
```

#### Optional Services

| Secret | When needed | Description |
|---|---|---|
| `smtp_password` | Email notifications | SMTP server password |
| `argocd_token` | ArgoCD GitOps integration | ArgoCD API bearer token |
| `upcloud_token` | UpCloud cloud resource discovery | UpCloud API token |

Drop the keys above into the `credentials` map; the module wires the matching
`*SecretRef` paths in the chart automatically.

### Important Notes

-> **`auth_encryption_key` and `session_encryption_key` must be base64 of 32 raw bytes.** Using `random_password { length = 32 }` will fail with _"encryption key must be 32 bytes (256 bits), got 24 bytes"_ because 32 ASCII chars decode to 24 bytes. Use `random_bytes { length = 32 }` and pass `.base64`.

-> **`postgres_password` and `db_password` must be different.** Same password defeats Row-Level Security: a compromised runtime app could authenticate as the migration user and bypass all tenant isolation.

-> **GitHub private keys are PEM files, not strings.** Mount them as volumes via `extraVolumes` (see the GitHub Integration section above).

-> **Numeric-string IDs need `helm_values`, not `helm_set`.** GitHub App IDs and installation IDs are numeric strings. The Helm provider's `--set` syntax coerces numeric values to integers and the chart schema rejects them as `expected: string, given: integer`. Pass these via `helm_values` (raw YAML) where types are preserved:

```hcl
helm_values = [yamlencode({
  auth = {
    github = {
      appId          = "1234567"
      installationId = "98765432"
    }
  }
})]
```

-> **The `shoehorn` Terraform provider must be configured even when `deploy_agent = false`.** The module declares the `shoehorn_k8s_agent` resource with `count = var.deploy_agent ? 1 : 0`, but Terraform still validates the provider block at init time. Add a stub provider block to your root module:

```hcl
provider "shoehorn" {
  host    = "https://${var.domain}"
  api_key = var.deploy_agent ? var.shoehorn_api_key : "stub-not-used"
}
```

## Auth Provider Configuration

### Okta

```hcl
module "shoehorn" {
  auth_provider = "okta"
  auth_config = {
    domain              = "dev-12345.okta.com"
    clientId            = "0oa..."
    issuer              = "https://dev-12345.okta.com/oauth2/default"
    authorizationServer = "default"
  }
  credentials = {
    okta_client_secret = var.okta_client_secret
    # ... other secrets
  }
}
```

**Okta App Requirements**:
- Type: Web Application
- Grant type: Authorization Code
- PKCE: Enabled
- Sign-in redirect URI: `https://<domain>/api/v1/auth/callback`
- Sign-out redirect URI: `https://<domain>`

### Zitadel

```hcl
module "shoehorn" {
  auth_provider = "zitadel"
  auth_config = {
    externalUrl = "https://auth.example.com"
    clientId    = "..."
    projectId   = "..."
  }
}

## Cloud Partner Example: UpCloud

```hcl
# 1. Partner creates their infrastructure
resource "upcloud_kubernetes_cluster" "main" { ... }
resource "upcloud_kubernetes_node_group" "workers" { ... }

# 2. Configure providers using cluster outputs
provider "kubernetes" {
  host                   = data.upcloud_kubernetes_cluster.creds.host
  client_certificate     = base64decode(data.upcloud_kubernetes_cluster.creds.client_certificate)
  client_key             = base64decode(data.upcloud_kubernetes_cluster.creds.client_key)
  cluster_ca_certificate = base64decode(data.upcloud_kubernetes_cluster.creds.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = data.upcloud_kubernetes_cluster.creds.host
    client_certificate     = base64decode(data.upcloud_kubernetes_cluster.creds.client_certificate)
    client_key             = base64decode(data.upcloud_kubernetes_cluster.creds.client_key)
    cluster_ca_certificate = base64decode(data.upcloud_kubernetes_cluster.creds.cluster_ca_certificate)
  }
}

# 3. Deploy Shoehorn
module "shoehorn" {
  source = "shoehorn-dev/kubernetes"

  domain            = "portal.customer.com"
  organization_name = "Customer Corp"
  organization_slug = "customer-corp"
  storage_class     = "upcloud-block-storage-maxiops"

  auth_provider = "okta"
  auth_config   = { ... }
  admin_email   = "admin@customer.com"
  credentials   = { ... }

  enable_bootstrap = true
  deploy_agent     = true
  cluster_id       = "customer-prod-fi-hel1"
  cluster_name     = "Customer Production (Finland)"

  depends_on = [upcloud_kubernetes_node_group.workers]
}
```

## Module Reference

### Required Variables

| Variable | Type | Description |
|---|---|---|
| `domain` | string | Public domain for Shoehorn |
| `credentials` | map(string) | Secret keys (see Credentials section) |

### Optional Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `auth_provider` | string | `"zitadel"` | Auth: `zitadel` or `okta`
| `auth_config` | map(string) | `{}` | Provider-specific auth config |
| `admin_email` | string | `""` | Initial tenant admin email |
| `database_host` | string | `""` | External DB host (empty = chart PostgreSQL) |
| `enable_bootstrap` | bool | `false` | Enable bootstrap API key for single-apply |
| `deploy_agent` | bool | `false` | Deploy K8s discovery agent |
| `ingress_type` | string | `"ingressRoute"` | `ingressRoute` (Traefik), `ingress`, or `httpRoute` |
| `replica_count` | number | `2` | Replicas per service |
| `image_tag` | string | `null` | Pin image version |
| `chart_path` | string | `""` | Local chart path (for development) |

### Outputs

| Output | Description |
|---|---|
| `url` | Shoehorn portal URL |
| `namespace` | Kubernetes namespace |
| `release_name` | Helm release name |
| `agent_deployed` | Whether agent was deployed |
| `agent_status` | Agent registration status |

# =============================================================================
# Full-stack Shoehorn deploy
#
# What this shows that the simpler examples don't:
#   - Single-apply platform + K8s agent via the bootstrap API key
#   - Okta OIDC + Okta user/group sync (orgdata)
#   - GitHub App for repo discovery
#   - GitHub App for Forge workflow execution (separate app)
#   - ArgoCD GitOps integration on the agent
#   - cert-manager installed separately, Issuer kind (namespace-scoped CA)
#   - Public Docker Hub registry (no pull secret needed)
#
# Drop any block you don't need. The module accepts every piece independently.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3.0"
    }
    shoehorn = {
      source  = "shoehorn-dev/shoehorn"
      version = ">= 0.2.0"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

# Bootstrap key on first apply, permanent key after the operator creates one
# in the UI and writes it back to terraform.tfvars.
provider "shoehorn" {
  host    = "https://${var.domain}"
  api_key = var.shoehorn_api_key != "" ? var.shoehorn_api_key : local.bootstrap_api_key
}

# =============================================================================
# Bootstrap API key derivation
# =============================================================================
# HMAC-SHA256 of JWT_SECRET with the fixed message "shoehorn-bootstrap-api-key-v1",
# base64 url-encoded, prefixed with "shp_svc_". The platform derives the same
# value on its end, so the two sides agree without coordination.

data "external" "bootstrap_key" {
  program = [
    "python3", "-c",
    "import hmac,hashlib,base64,json,sys; q=json.load(sys.stdin); key=q['secret']; mac=hmac.new(key.encode(),b'shoehorn-bootstrap-api-key-v1',hashlib.sha256).digest(); print(json.dumps({'key': 'shp_svc_' + base64.urlsafe_b64encode(mac).decode().rstrip('=')}))"
  ]

  query = {
    secret = random_password.jwt_secret.result
  }
}

locals {
  bootstrap_api_key = data.external.bootstrap_key.result["key"]
}

# =============================================================================
# Per-deploy secrets
# =============================================================================

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# 32 raw bytes -> base64. Using random_password (32 ASCII chars) decodes to
# 24 bytes and the platform rejects with "encryption key must be 32 bytes".
resource "random_bytes" "auth_encryption_key" {
  length = 32
}

resource "random_bytes" "session_encryption_key" {
  length = 32
}

resource "random_password" "valkey_password" {
  length  = 32
  special = false
}

resource "random_password" "meilisearch_master_key" {
  length  = 32
  special = false
}

resource "random_password" "github_webhook_secret" {
  length  = 32
  special = false
}

# =============================================================================
# Shoehorn platform + agent
# =============================================================================

module "shoehorn" {
  source = "../../"

  domain            = var.domain
  organization_name = var.organization_name
  organization_slug = var.organization_slug
  admin_email       = var.admin_email

  storage_class = var.storage_class
  ingress_type  = var.ingress_type
  replica_count = var.replica_count

  # Auth: Okta OIDC
  auth_provider = "okta"
  auth_config = {
    domain              = var.okta_domain
    clientId            = var.okta_client_id
    issuer              = var.okta_issuer
    authorizationServer = "default"
  }

  credentials = {
    postgres_password        = random_password.postgres_password.result
    db_password              = random_password.db_password.result
    jwt_secret               = random_password.jwt_secret.result
    auth_encryption_key      = random_bytes.auth_encryption_key.base64
    session_encryption_key   = random_bytes.session_encryption_key.base64
    valkey_password          = random_password.valkey_password.result
    meilisearch_master_key   = random_password.meilisearch_master_key.result
    okta_client_secret       = var.okta_client_secret
    okta_api_token           = var.okta_api_token
    github_webhook_secret    = random_password.github_webhook_secret.result
    github_app_private_key   = file(var.github_app_private_key_path)
    github_forge_private_key = file(var.github_forge_private_key_path)
  }

  # Single-apply platform + agent. enable_bootstrap flips off automatically
  # once you set shoehorn_api_key from the UI-issued key.
  enable_bootstrap = var.shoehorn_api_key == ""
  deploy_agent     = true
  cluster_id       = var.cluster_id
  cluster_name     = var.cluster_name

  # ArgoCD GitOps integration on the agent. Token enables Sync/Refresh
  # buttons in the Shoehorn UI; without it ArgoCD apps are read-only.
  agent_gitops_tool = "argocd"
  argocd_namespace  = var.argocd_namespace
  argocd_server_url = var.argocd_server_url
  argocd_token      = var.argocd_token

  helm_set = {
    # Public Docker Hub images. No pull secret needed.
    "api.image.repository"        = "shoehorned/shoehorn-api"
    "web.image.repository"        = "shoehorned/shoehorn-web"
    "eventbus.image.repository"   = "shoehorned/shoehorn-eventbus"
    "worker.image.repository"     = "shoehorned/shoehorn-worker"
    "crawler.image.repository"    = "shoehorned/shoehorn-crawler"
    "forge.image.repository"      = "shoehorned/shoehorn-forge"
    "cerbos.image.repository"     = "shoehorned/shoehorn-cerbos"
    "postgresql.image.repository" = "shoehorned/shoehorn-postgres"

    # cert-manager installed separately in cert-manager namespace.
    # Issuer (namespace-scoped) keeps the CA secret in the shoehorn namespace.
    "certManager.install"     = "false"
    "certManager.issuer.kind" = "Issuer"
    "global.mtls.issuerKind"  = "Issuer"
    "global.mtls.enabled"     = "true"

    # Okta orgdata sync. The module wires apiTokenSecretRef for you from
    # credentials.okta_api_token.
    "auth.orgdata.enabled"         = "true"
    "auth.orgdata.providers[0]"    = "okta"
    "auth.orgdata.primaryProvider" = "okta"

    "api.env.GITHUB_ORGANIZATIONS" = var.github_organization
  }

  # GitHub App config. The numeric IDs go through helm_values, not helm_set
  # because `--set` coerces numeric values to integers and the chart schema
  # rejects ints for these fields. Volumes mount the private keys onto the
  # api pod.
  helm_values = [
    yamlencode({
      auth = {
        github = {
          appId          = var.github_app_id
          installationId = var.github_installation_id
          forge = {
            appId          = var.github_forge_app_id
            installationId = var.github_forge_installation_id
            organization   = var.github_organization
          }
        }
      }
      extraVolumes = [
        {
          name = "github-private-key"
          secret = {
            secretName = "shoehorn-credentials"
            items      = [{ key = "github_app_private_key", path = "private-key" }]
          }
        },
        {
          name = "github-forge-private-key"
          secret = {
            secretName = "shoehorn-credentials"
            items      = [{ key = "github_forge_private_key", path = "private-key" }]
          }
        },
      ]
      extraVolumeMounts = [
        { name = "github-private-key", mountPath = "/var/secrets/github", readOnly = true },
        { name = "github-forge-private-key", mountPath = "/var/secrets/github-forge", readOnly = true },
      ]
    })
  ]

  health_check_protocol = "https"
}

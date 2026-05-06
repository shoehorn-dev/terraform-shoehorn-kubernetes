# Shoehorn Terraform Modules

**Partner-only** — Terraform modules for deploying Shoehorn onto Kubernetes clusters.

These modules are used by cloud partners (UpCloud etc.) to offer automated Shoehorn deployments on their platforms.

## Modules

### `modules/kubernetes`

Deploys Shoehorn Internal Developer Portal onto any existing Kubernetes cluster.

```hcl
module "shoehorn" {
  source = "github.com/shoehorn-dev/terraform-shoehorn-modules//modules/kubernetes"

  domain            = "portal.customer.com"
  auth_provider     = "okta"
  auth_config       = { domain = "...", clientId = "...", issuer = "..." }
  admin_email       = "admin@customer.com"
  credentials       = { ... }

  enable_bootstrap  = true
  deploy_agent      = true
  cluster_id        = "prod-eu"
  cluster_name      = "Production EU"
}
```

Features:
- Single `terraform apply` deploys platform + K8s agent
- Bootstrap API key for initial deployment (auto-expires, no manual steps)
- Supports Okta, Zitadel authentication
- Chart-deployed or external managed PostgreSQL
- Traefik, nginx, or Envoy Gateway ingress

## Examples

- [`examples/basic`](examples/basic) — Shoehorn with Okta auth, chart-deployed PostgreSQL, no agent
- [`examples/okta-with-agent`](examples/okta-with-agent) — Full deployment with Okta + user/group sync + K8s agent (single-apply bootstrap)

## Gotchas

A few things that have tripped up partner deploys.

**Numeric-string IDs need `helm_values`, not `helm_set`.** GitHub App IDs and
installation IDs are numeric strings. Helm's `--set` syntax (which `helm_set`
maps to) coerces numeric values to integers, and the chart schema rejects
them. Pass these via `helm_values` (raw YAML strings):

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

**The `shoehorn` provider must be configured even when `deploy_agent = false`.**
The `shoehorn_k8s_agent` resource is gated `count = 0` when the agent is
disabled, but Terraform still validates the provider config at init. Add a
stub provider block:

```hcl
provider "shoehorn" {
  host    = "https://${var.domain}"
  api_key = var.deploy_agent ? var.shoehorn_api_key : "stub-not-used"
}
```

**`session_encryption_key` and `auth_encryption_key` must be base64 of 32
raw bytes.** Use `random_bytes { length = 32 }.base64`, not
`random_password { length = 32 }`. `random_password` produces 32 ASCII chars
which decode to 24 bytes and the platform rejects with `encryption key must
be 32 bytes (256 bits), got 24 bytes`.

## Documentation

- [Cloud Partner Integration Guide](docs/guides/cloud-partner-integration.md) — full setup guide with secrets, auth, and deployment lifecycle

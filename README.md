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

## Documentation

- [Cloud Partner Integration Guide](docs/guides/cloud-partner-integration.md) — full setup guide with secrets, auth, and deployment lifecycle

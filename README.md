# Shoehorn Terraform Module

A Terraform module for deploying Shoehorn, the Intelligent Developer Platform, onto Kubernetes clusters.

Run a single `terraform apply` to deploy the platform plus an optional Kubernetes discovery agent. Works on any cluster you can reach with `kubectl`: managed Kubernetes, on-prem, or k3s on a laptop.

## Usage

```hcl
module "shoehorn" {
  source  = "shoehorn-dev/kubernetes/shoehorn"
  version = "~> 0.1"

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

- [`examples/basic`](examples/basic): Okta auth, chart-deployed PostgreSQL, no agent. The smallest thing that runs.
- [`examples/okta-with-agent`](examples/okta-with-agent): platform + K8s discovery agent in a single apply, plus Okta user/group sync.
- [`examples/full-stack-okta-github`](examples/full-stack-okta-github): everything in `okta-with-agent`, plus a GitHub App for repo discovery, a second GitHub App for Forge workflows, ArgoCD GitOps on the agent, and a namespace-scoped cert-manager `Issuer`. Mirrors what runs on `demo.shoehorn.dev`.

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

## Data lifecycle

PostgreSQL data survives both platform upgrades and `terraform destroy`.

**`terraform apply` doesn't restart the database.** The postgres StatefulSet uses `updateStrategy: OnDelete`. Chart-template changes don't roll the postgres pod. Roll it when needed:

```bash
kubectl delete pod -n shoehorn shoehorn-postgresql-0
```

**`terraform destroy` doesn't drop the database.** The postgres StatefulSet carries `helm.sh/resource-policy: keep`, so the underlying `helm uninstall` leaves the StatefulSet and its PVC in place. A later `terraform apply` reattaches the same data.

To drop the database explicitly:

```bash
kubectl delete sts -n shoehorn shoehorn-postgresql
kubectl delete pvc -n shoehorn data-shoehorn-postgresql-0
```

**The postgres image tag is pinned** (e.g. `v18.3-pgaudit-1.0`). It follows postgres releases, not platform releases. Bumping `chart_version` upgrades platform services but leaves postgres alone unless that chart release moved the pin.

## Documentation

- [Deployment Guide](docs/guides/deployment-guide.md): full setup with secrets, auth providers, the bootstrap mechanism, and the day-2 lifecycle.

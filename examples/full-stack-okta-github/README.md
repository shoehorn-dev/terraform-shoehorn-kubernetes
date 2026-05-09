# Full-stack Shoehorn deploy

What this example covers that `basic` and `okta-with-agent` don't:

- Single-apply platform + K8s agent via the bootstrap API key
- Okta OIDC + Okta user/group sync
- GitHub App for repo discovery
- Second GitHub App for Forge workflow execution
- ArgoCD GitOps integration on the agent
- cert-manager already installed in the cluster, used via a namespace-scoped `Issuer`
- Public Docker Hub registry, no pull secret

It's the closest example to what we run on `demo.shoehorn.dev`. Drop any block you don't need. The module accepts every piece independently.

## Prerequisites

- A Kubernetes cluster, `kubectl` access, and a storage class for stateful workloads
- An ingress controller (Traefik / nginx / Envoy Gateway) and a DNS record pointing at it
- cert-manager installed in `cert-manager` namespace, with a configured `Issuer` or `ClusterIssuer`
- `python3` on the machine running `terraform apply` (used to derive the bootstrap key)
- An Okta OIDC app + Okta API token
- A GitHub App for repo discovery, with a private-key PEM
- A second GitHub App for Forge workflow execution, with its own PEM
- ArgoCD running in the cluster and an API token (optional; drop the GitOps block if you don't use ArgoCD)

## Use it

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in your values
terraform init
terraform apply
```

Two-phase API key flow:

1. First apply: `shoehorn_api_key = ""`. The module derives a bootstrap key from `JWT_SECRET`, runs the seeder Job, and the agent registers.
2. Log into the UI at `https://${domain}` with your Okta account.
3. Create a permanent key in **Settings → API Keys**.
4. Set `shoehorn_api_key` in `terraform.tfvars` and `terraform apply` again. Bootstrap turns off automatically.

Expected first-apply duration: 3-5 minutes.

## Verify

```bash
kubectl -n shoehorn get pods                    # all Running
kubectl -n shoehorn get certificate             # Ready=True
curl -I https://${DOMAIN}/health                # 200 with a valid cert
```

Then browse to `https://${DOMAIN}` and complete Okta login.

## Tear down

```bash
terraform destroy
```

Postgres data survives `destroy` on purpose. The StatefulSet carries `helm.sh/resource-policy: keep`. To drop it explicitly:

```bash
kubectl delete sts -n shoehorn shoehorn-postgresql
kubectl delete pvc -n shoehorn data-shoehorn-postgresql-0
```

## Common adjustments

**No GitHub.** Delete the `github_*` variables, the `github_*` keys in `credentials`, the `helm_values` block, and `api.env.GITHUB_ORGANIZATIONS` from `helm_set`.

**No agent.** Set `deploy_agent = false` and drop the `cluster_id`, `cluster_name`, and `agent_*` / `argocd_*` vars.

**No Okta orgdata sync.** Drop the three `auth.orgdata.*` keys from `helm_set` and `okta_api_token` from `credentials`.

**Tight cluster.** `replica_count = 1` and `redpanda.replicas = "1"` (already in `helm_set` if you uncomment it). The example targets a 2-node cluster comfortably; below that, single-replica everything.

**cert-manager not installed yet.** Set `certManager.install = "true"` in `helm_set` (chart installs it) and remove the `Issuer`-kind overrides. The chart defaults to `ClusterIssuer`.

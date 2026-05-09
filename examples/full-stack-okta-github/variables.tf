# =============================================================================
# Cluster
# =============================================================================

variable "kubeconfig_path" {
  description = "Path to kubeconfig"
  type        = string
  default     = "~/.kube/config"
}

variable "domain" {
  description = "Public domain for Shoehorn (e.g. portal.acme.com)"
  type        = string
}

variable "storage_class" {
  description = "Kubernetes storage class for stateful workloads (postgres, valkey, meilisearch)"
  type        = string
}

variable "ingress_type" {
  description = "Ingress type: ingressRoute (Traefik), ingress (standard), or httpRoute (Envoy Gateway)"
  type        = string
  default     = "ingressRoute"
}

variable "replica_count" {
  description = "Replica count for application services. Set to 1 on small clusters with no headroom for 2x of every service."
  type        = number
  default     = 2
}

# =============================================================================
# Tenant
# =============================================================================

variable "organization_name" {
  description = "Organization display name shown in the Shoehorn UI"
  type        = string
}

variable "organization_slug" {
  description = "URL-safe organization identifier"
  type        = string
}

variable "admin_email" {
  description = "Email of the initial tenant admin"
  type        = string
}

variable "cluster_id" {
  description = "Stable identifier for this Kubernetes cluster (used by the agent)"
  type        = string
}

variable "cluster_name" {
  description = "Human-readable cluster name shown in the Shoehorn UI"
  type        = string
}

# =============================================================================
# Auth (Okta)
# =============================================================================

variable "okta_domain" {
  description = "Okta tenant domain (e.g. acme.okta.com)"
  type        = string
}

variable "okta_client_id" {
  description = "Okta OIDC application client ID"
  type        = string
}

variable "okta_issuer" {
  description = "Okta OIDC issuer URL"
  type        = string
}

variable "okta_client_secret" {
  description = "Okta OIDC client secret"
  type        = string
  sensitive   = true
}

variable "okta_api_token" {
  description = "Okta API token for orgdata user/group sync"
  type        = string
  sensitive   = true
}

# =============================================================================
# GitHub App (repo discovery + Forge workflows)
# =============================================================================

variable "github_organization" {
  description = "GitHub organization slug the apps are installed on"
  type        = string
}

variable "github_app_id" {
  description = "GitHub App ID for repository discovery (numeric, passed as a string)"
  type        = string
}

variable "github_installation_id" {
  description = "GitHub App installation ID (numeric, passed as a string)"
  type        = string
}

variable "github_app_private_key_path" {
  description = "Path to the discovery GitHub App private key PEM file"
  type        = string
}

variable "github_forge_app_id" {
  description = "GitHub App ID used by Forge to execute workflows (numeric, passed as a string)"
  type        = string
}

variable "github_forge_installation_id" {
  description = "Forge GitHub App installation ID (numeric, passed as a string)"
  type        = string
}

variable "github_forge_private_key_path" {
  description = "Path to the Forge GitHub App private key PEM file"
  type        = string
}

# =============================================================================
# ArgoCD GitOps
# =============================================================================

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "argocd_server_url" {
  description = "Public ArgoCD server URL. Required for the Sync/Refresh buttons in the Shoehorn UI."
  type        = string
}

variable "argocd_token" {
  description = "ArgoCD API token. Generate with `argocd account generate-token --account shoehorn`. Empty disables Sync/Refresh; apps still display read-only."
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# API key (set after first apply)
# =============================================================================

variable "shoehorn_api_key" {
  description = "Permanent API key. Empty on first apply (bootstrap derives one). Set after the operator creates a real key in the UI, then re-apply."
  type        = string
  sensitive   = true
  default     = ""
}

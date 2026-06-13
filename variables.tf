# =============================================================================
# Core
# =============================================================================

variable "domain" {
  description = "Public domain for Shoehorn (e.g., portal.acme.com)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Shoehorn"
  type        = string
  default     = "shoehorn"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "shoehorn"
}

variable "organization_name" {
  description = "Organization display name shown in UI"
  type        = string
  default     = ""
}

variable "organization_slug" {
  description = "URL-safe organization identifier"
  type        = string
  default     = ""
}

# =============================================================================
# Helm Chart
# =============================================================================

variable "chart_repository" {
  description = "Helm chart repository URL (empty string when using chart_path for local charts)"
  type        = string
  default     = "oci://ghcr.io/shoehorn-dev/helm-charts"
}

variable "chart_path" {
  description = "Local path to the shoehorn Helm chart directory (overrides chart_repository when set)"
  type        = string
  default     = ""
}

variable "agent_chart_path" {
  description = "Local path to the shoehorn-k8s-agent Helm chart directory (overrides chart_repository when set)"
  type        = string
  default     = ""
}

variable "chart_version" {
  description = "Shoehorn Helm chart version (null = latest)"
  type        = string
  default     = null
}

variable "helm_timeout" {
  description = "Timeout in seconds for Helm operations"
  type        = number
  default     = 600
}

variable "image_tag" {
  description = "Docker image tag for Shoehorn services (null = chart default)"
  type        = string
  default     = null
}

# =============================================================================
# Database (external managed PostgreSQL)
# =============================================================================

variable "database_host" {
  description = "PostgreSQL host for external managed DB. Empty = use chart's built-in PostgreSQL."
  type        = string
  default     = ""
}

variable "database_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "shoehorn"
}

variable "database_user" {
  description = "PostgreSQL admin/migration user"
  type        = string
  default     = "shoehorn_user"
}

# =============================================================================
# Authentication
# =============================================================================

variable "auth_provider" {
  description = "Authentication provider: zitadel, okta, or entra-id"
  type        = string
  default     = "zitadel"

  validation {
    condition     = contains(["zitadel", "okta", "entra-id"], var.auth_provider)
    error_message = "auth_provider must be one of: zitadel, okta, entra-id"
  }
}

variable "auth_config" {
  description = "Auth provider configuration (passed as Helm set values under auth.<provider>.*)"
  type        = map(string)
  default     = {}
}

variable "admin_email" {
  description = "Email of the initial tenant admin user"
  type        = string
  default     = ""
}

# =============================================================================
# Credentials (the keys here become the K8s secret referenced by secret.defaultName).
# The module auto-wires per-credential *SecretRef paths from key names below.
# =============================================================================

variable "credentials" {
  description = <<-EOT
    Map of secret keys for the shoehorn-credentials K8s secret. Keys present
    here are wired into the chart's per-credential *SecretRef blocks
    automatically (e.g. okta_client_secret -> auth.okta.clientSecretRef.key).

    Required keys:
      postgres_password, db_password, jwt_secret, auth_encryption_key,
      session_encryption_key

    Optional keys (provide when the corresponding feature is in use):
      valkey_password, meilisearch_master_key,
      okta_client_secret, okta_api_token,
      entra_client_secret, zitadel_service_user_pat,
      github_app_private_key, github_forge_private_key,
      smtp_password, argocd_token, upcloud_token

    Note: session_encryption_key and auth_encryption_key must be base64 of 32
    raw bytes (use `random_bytes { length = 32 }.base64`, not random_password).
  EOT
  type        = map(string)
  sensitive   = true

  validation {
    condition = alltrue([
      contains(keys(var.credentials), "postgres_password"),
      contains(keys(var.credentials), "db_password"),
      contains(keys(var.credentials), "jwt_secret"),
      contains(keys(var.credentials), "session_encryption_key"),
    ])
    error_message = "credentials must contain: postgres_password, db_password, jwt_secret, session_encryption_key"
  }
}

variable "image_pull_secrets" {
  description = "List of image pull secret objects for private registries"
  type        = list(map(string))
  default     = []
}

# =============================================================================
# Infrastructure
# =============================================================================

variable "storage_class" {
  description = "Kubernetes storage class name"
  type        = string
  default     = ""
}

variable "ingress_type" {
  description = "Ingress type: ingressRoute (Traefik), ingress (standard), or httpRoute (Envoy Gateway)"
  type        = string
  default     = "ingressRoute"

  validation {
    condition     = contains(["ingressRoute", "ingress", "httpRoute"], var.ingress_type)
    error_message = "ingress_type must be one of: ingressRoute, ingress, httpRoute"
  }
}

variable "ingress_class" {
  description = "Ingress class name (only used when ingress_type = ingress)"
  type        = string
  default     = ""
}

variable "replica_count" {
  description = "Replica count for application services"
  type        = number
  default     = 2
}

# =============================================================================
# Bootstrap API Key (for single-apply agent deployment)
# =============================================================================

variable "enable_bootstrap" {
  description = "Enable bootstrap API key seeding via K8s Job for single-apply agent deployment. The key is derived deterministically from JWT_SECRET — no key value is needed."
  type        = bool
  default     = false
}

variable "bootstrap_image" {
  description = "Container image for the bootstrap API key Job. Empty means derive from image_tag as shoehorned/shoehorn-api:<image_tag>."
  type        = string
  default     = ""
}

variable "bootstrap_wait_db_image" {
  description = "Image for the bootstrap Job's wait-for-db init container. Needs pg_isready."
  type        = string
  default     = "shoehorned/shoehorn-postgres:v18.3-pgaudit-1.0"
}

variable "bootstrap_environment" {
  description = "ENVIRONMENT value for the bootstrap Job (must be a non-production environment)"
  type        = string
  default     = "staging"
}

variable "database_sslmode" {
  description = "PostgreSQL sslmode for external database connections (require, verify-full, etc.)"
  type        = string
  default     = "require"
}

# =============================================================================
# K8s Agent (Phase 2 - requires shoehorn_api_key to be configured on provider)
# =============================================================================

variable "deploy_agent" {
  description = "Deploy the Shoehorn K8s discovery agent"
  type        = bool
  default     = false
}

variable "cluster_id" {
  description = "Unique identifier for this Kubernetes cluster"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Human-readable cluster name"
  type        = string
  default     = ""
}

variable "agent_chart_version" {
  description = "K8s agent Helm chart version (null = latest)"
  type        = string
  default     = null
}

variable "agent_image_tag" {
  description = "Docker image tag for the K8s agent (null = chart default). Independent from the platform image_tag."
  type        = string
  default     = null
}

variable "agent_gitops_tool" {
  description = "GitOps tool to monitor: argocd, fluxcd, or empty string"
  type        = string
  default     = ""
}

variable "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed (when agent_gitops_tool = argocd)"
  type        = string
  default     = "argocd"
}

variable "argocd_server_url" {
  description = "Public ArgoCD server URL. Required to enable Sync/Refresh buttons in the Shoehorn UI."
  type        = string
  default     = ""
}

variable "argocd_token" {
  description = "ArgoCD API token used by the agent for sync/refresh commands. Generate with `argocd account generate-token --account shoehorn`. Empty disables Sync/Refresh; ArgoCD apps still display read-only."
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_helm_enabled" {
  description = "Detect Helm releases in the cluster and report each release with the resources it manages. Grants the agent read (list) access to Secrets, which is where Helm stores release data. Off by default."
  type        = bool
  default     = false
}

variable "agent_helm_namespace" {
  description = "Namespace the agent scans for Helm releases, or empty to scan all namespaces (used when agent_helm_enabled = true)."
  type        = string
  default     = ""
}

variable "agent_helm_interval" {
  description = "How often the agent rescans for Helm releases, between 30s and 1h (used when agent_helm_enabled = true)."
  type        = string
  default     = "5m"
}

# =============================================================================
# Helm Value Overrides
# =============================================================================

variable "helm_values" {
  description = "List of raw YAML strings to pass as additional Helm values (applied in order)"
  type        = list(string)
  default     = []
}

variable "helm_set" {
  description = "Map of individual Helm value overrides (key = Helm value path, value = string value)"
  type        = map(string)
  default     = {}
}

variable "helm_set_sensitive" {
  description = "Map of sensitive Helm value overrides"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "agent_helm_values" {
  description = "List of YAML strings with extra values for the shoehorn-k8s-agent chart, e.g. [file(\"values-large-cluster.yaml\")]. Applied after module-generated values."
  type        = list(string)
  default     = []
}

variable "agent_helm_set" {
  description = "Map of extra Helm value overrides for the shoehorn-k8s-agent chart (highest priority), e.g. { \"agent.kubernetes.scopeMode\" = \"namespaces\" }"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Health Check
# =============================================================================

variable "health_check_protocol" {
  description = "Protocol for health check (https or http)"
  type        = string
  default     = "https"
}

variable "health_check_attempts" {
  description = "Number of health check retry attempts"
  type        = number
  default     = 30
}

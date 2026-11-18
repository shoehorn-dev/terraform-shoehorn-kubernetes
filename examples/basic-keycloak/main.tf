# =============================================================================
# Basic Shoehorn Deployment (Keycloak)
#
# Deploys Shoehorn with chart-deployed PostgreSQL and Keycloak for both auth
# (OIDC) and orgdata sync (admin REST API). No K8s agent, no bootstrap.
#
# Unlike Okta/Zitadel/Entra ID, Keycloak does NOT default a token's audience
# to the client_id, so auth_audience must be set explicitly (via a dedicated
# Audience protocol mapper on the login client). Orgdata sync needs a SEPARATE
# service-account client - that's why there are two client secrets here, not
# one like the Entra ID example.
#
# Prerequisites:
#   - Kubernetes cluster with kubectl access
#   - A Keycloak realm with: a confidential login client (standard flow,
#     PKCE S256, an Audience protocol mapper pointing at itself, a Group
#     Membership mapper), and a second confidential client with service
#     accounts enabled and the realm-management roles (manage-users,
#     view-users, query-groups, query-users). On Keycloak 26.8.2+ that second
#     client also needs `kc-admin-api` as a DEFAULT client scope.
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

# =============================================================================
# Secrets
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

# 32 raw bytes → base64. The platform decodes the value and requires 32 bytes;
# `random_password { length = 32, special = false }` would produce 32 ASCII chars
# which decode to 24 bytes and fail with "encryption key must be 32 bytes".
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

# =============================================================================
# Shoehorn
# =============================================================================

module "shoehorn" {
  source = "../../"

  domain            = var.domain
  organization_name = var.organization_name
  organization_slug = var.organization_slug
  admin_email       = var.admin_email

  auth_provider = "keycloak"
  auth_audience = var.keycloak_client_id
  auth_config = {
    url      = var.keycloak_url
    realm    = var.keycloak_realm
    clientId = var.keycloak_client_id
    # Service-account client for orgdata sync. Defaults to "shoehorn-api" in
    # the chart if left unset; set explicitly here for clarity.
    adminClientId = var.keycloak_admin_client_id
  }

  credentials = {
    postgres_password            = random_password.postgres_password.result
    db_password                  = random_password.db_password.result
    jwt_secret                   = random_password.jwt_secret.result
    auth_encryption_key          = random_bytes.auth_encryption_key.base64
    session_encryption_key       = random_bytes.session_encryption_key.base64
    valkey_password              = random_password.valkey_password.result
    meilisearch_master_key       = random_password.meilisearch_master_key.result
    keycloak_client_secret       = var.keycloak_client_secret
    keycloak_admin_client_secret = var.keycloak_admin_client_secret
  }

  # The module wires `auth.keycloak.clientSecretRef.key` and
  # `auth.keycloak.adminClientSecretRef.key` automatically from the
  # `keycloak_client_secret`/`keycloak_admin_client_secret` keys above.

  helm_set = {
    "auth.orgdata.enabled"         = "true"
    "auth.orgdata.providers[0]"    = "keycloak"
    "auth.orgdata.primaryProvider" = "keycloak"
  }

  health_check_protocol = "https"
}

# =============================================================================
# Variables
# =============================================================================

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "domain" {
  type = string
}

variable "organization_name" {
  type = string
}

variable "organization_slug" {
  type = string
}

variable "admin_email" {
  type = string
}

variable "keycloak_url" {
  description = "Base Keycloak URL, no trailing slash, no /realms path."
  type        = string
}

variable "keycloak_realm" {
  type = string
}

variable "keycloak_client_id" {
  description = "The login client's ID. Also used as auth_audience - see the Audience protocol mapper requirement above."
  type        = string
}

variable "keycloak_client_secret" {
  type      = string
  sensitive = true
}

variable "keycloak_admin_client_id" {
  description = "Service-account client ID used for directory sync. Separate from the login client above."
  type        = string
  default     = "shoehorn-api"
}

variable "keycloak_admin_client_secret" {
  type      = string
  sensitive = true
}

# =============================================================================
# Outputs
# =============================================================================

output "url" {
  value = module.shoehorn.url
}

output "namespace" {
  value = module.shoehorn.namespace
}

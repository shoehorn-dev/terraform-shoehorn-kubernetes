# =============================================================================
# Basic Shoehorn Deployment (Microsoft Entra ID)
#
# Deploys Shoehorn with chart-deployed PostgreSQL and Entra ID for both auth
# (OIDC) and orgdata sync (Microsoft Graph). No K8s agent, no bootstrap.
#
# Entra orgdata reuses the same app registration and client secret as auth, so
# there's a single credential (entra_client_secret), no separate API token.
#
# Prerequisites:
#   - Kubernetes cluster with kubectl access
#   - A single-tenant Entra app registration: exposed API (scope
#     access_as_user), groups claim, and Graph permissions User.Read.All +
#     GroupMember.Read.All granted with admin consent.
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

  auth_provider = "entra-id"
  auth_config = {
    tenantId = var.entra_tenant_id
    clientId = var.entra_client_id
  }

  credentials = {
    postgres_password      = random_password.postgres_password.result
    db_password            = random_password.db_password.result
    jwt_secret             = random_password.jwt_secret.result
    auth_encryption_key    = random_bytes.auth_encryption_key.base64
    session_encryption_key = random_bytes.session_encryption_key.base64
    valkey_password        = random_password.valkey_password.result
    meilisearch_master_key = random_password.meilisearch_master_key.result
    entra_client_secret    = var.entra_client_secret
  }

  # The module wires `auth.entraId.clientSecretRef.key` automatically from the
  # `entra_client_secret` key in `credentials`, no helm_set needed.

  # Entra orgdata sync reuses the same app registration and client secret.
  helm_set = {
    "auth.orgdata.enabled"         = "true"
    "auth.orgdata.providers[0]"    = "entra-id"
    "auth.orgdata.primaryProvider" = "entra-id"
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

variable "entra_tenant_id" {
  type = string
}

variable "entra_client_id" {
  type = string
}

variable "entra_client_secret" {
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

# =============================================================================
# Basic Shoehorn Deployment
#
# Deploys Shoehorn with chart-deployed PostgreSQL and Okta auth.
# No K8s agent, no bootstrap — simplest possible setup.
#
# Prerequisites:
#   - Kubernetes cluster with kubectl access
#   - Okta OIDC application configured
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

resource "random_bytes" "auth_encryption_key" {
  length = 32
}

resource "random_password" "session_encryption_key" {
  length  = 32
  special = false
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
  source = "../../modules/kubernetes"

  domain            = var.domain
  organization_name = var.organization_name
  organization_slug = var.organization_slug
  admin_email       = var.admin_email

  auth_provider = "okta"
  auth_config = {
    domain              = var.okta_domain
    clientId            = var.okta_client_id
    issuer              = var.okta_issuer
    authorizationServer = "default"
  }

  credentials = {
    postgres_password      = random_password.postgres_password.result
    db_password            = random_password.db_password.result
    jwt_secret             = random_password.jwt_secret.result
    auth_encryption_key    = random_bytes.auth_encryption_key.base64
    session_encryption_key = random_password.session_encryption_key.result
    valkey_password        = random_password.valkey_password.result
    meilisearch_master_key = random_password.meilisearch_master_key.result
    okta_client_secret     = var.okta_client_secret
  }

  helm_set = {
    "secret.mappings.OKTA_CLIENT_SECRET" = "okta_client_secret"
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

variable "okta_domain" {
  type = string
}

variable "okta_client_id" {
  type = string
}

variable "okta_issuer" {
  type = string
}

variable "okta_client_secret" {
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

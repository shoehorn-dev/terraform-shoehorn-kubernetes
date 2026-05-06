# =============================================================================
# Shoehorn + K8s Agent (Single-Apply Bootstrap)
#
# Deploys Shoehorn with Okta auth, user/group sync, and K8s discovery agent
# in a single terraform apply using the bootstrap API key mechanism.
#
# Prerequisites:
#   - Kubernetes cluster with kubectl access
#   - python3 (for HMAC key derivation)
#   - Okta OIDC application + API token
#
# After deploy:
#   1. Log into the Shoehorn UI
#   2. Create a permanent API key (Settings → API Keys)
#   3. Set shoehorn_api_key in terraform.tfvars
#   4. Run terraform apply again (switches from bootstrap to permanent key)
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
    shoehorn = {
      source  = "shoehorn-dev/shoehorn"
      version = ">= 0.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3.0"
    }
  }
}

# =============================================================================
# Providers
# =============================================================================

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

# Automatically uses bootstrap key for initial deploy, permanent key after.
provider "shoehorn" {
  host    = "https://${var.domain}"
  api_key = var.shoehorn_api_key != "" ? var.shoehorn_api_key : local.bootstrap_api_key
}

# =============================================================================
# Bootstrap API Key (initial deploy only)
# =============================================================================

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
# Shoehorn + Agent
# =============================================================================

module "shoehorn" {
  source = "../../modules/kubernetes"

  domain            = var.domain
  organization_name = var.organization_name
  organization_slug = var.organization_slug
  admin_email       = var.admin_email

  # Auth
  auth_provider = "okta"
  auth_config = {
    domain              = var.okta_domain
    clientId            = var.okta_client_id
    issuer              = var.okta_issuer
    authorizationServer = "default"
  }

  # Credentials
  credentials = {
    postgres_password      = random_password.postgres_password.result
    db_password            = random_password.db_password.result
    jwt_secret             = random_password.jwt_secret.result
    auth_encryption_key    = random_bytes.auth_encryption_key.base64
    session_encryption_key = random_bytes.session_encryption_key.base64
    valkey_password        = random_password.valkey_password.result
    meilisearch_master_key = random_password.meilisearch_master_key.result
    okta_client_secret     = var.okta_client_secret
    okta_api_token         = var.okta_api_token
  }

  # Bootstrap + Agent
  enable_bootstrap = var.shoehorn_api_key == ""
  deploy_agent     = true
  cluster_id       = var.cluster_id
  cluster_name     = var.cluster_name

  # Okta user/group sync. The module wires `auth.okta.clientSecretRef.key` and
  # `auth.okta.apiTokenSecretRef.key` automatically from the matching keys in
  # the `credentials` map above — no helm_set entry needed for those.
  helm_set = {
    "auth.orgdata.enabled"          = "true"
    "auth.orgdata.providers[0]"     = "okta"
    "auth.orgdata.primaryProvider"  = "okta"
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
  description = "Public domain for Shoehorn"
  type        = string
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

variable "cluster_id" {
  description = "Unique cluster identifier for agent registration"
  type        = string
}

variable "cluster_name" {
  description = "Human-readable cluster name"
  type        = string
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

variable "okta_api_token" {
  description = "Okta API token for user/group sync"
  type        = string
  sensitive   = true
  default     = ""
}

variable "shoehorn_api_key" {
  description = "Permanent API key (set after initial deploy, leave empty for bootstrap)"
  type        = string
  sensitive   = true
  default     = ""
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

output "agent_deployed" {
  value = module.shoehorn.agent_deployed
}

output "agent_status" {
  value = module.shoehorn.agent_status
}

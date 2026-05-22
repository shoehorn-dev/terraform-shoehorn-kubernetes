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
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.0"
    }
    shoehorn = {
      source  = "shoehorn-dev/shoehorn"
      version = ">= 0.2.0"
    }
  }
}

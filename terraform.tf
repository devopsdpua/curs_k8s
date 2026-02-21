terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# Подключение к кластеру: с jumpbox после az aks get-credentials или задайте var.kube_config_path.
provider "kubernetes" {
  config_path = var.kube_config_path != "" ? var.kube_config_path : null
}

provider "helm" {
  kubernetes {
    config_path = var.kube_config_path != "" ? var.kube_config_path : null
  }
}

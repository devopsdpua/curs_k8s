terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# Kubernetes/Helm не используются в Terraform (private cluster доступен только из VNet).
# Управление кластером (Argo CD, манифесты) — с jumpbox или через Фазу 2 (GitOps).

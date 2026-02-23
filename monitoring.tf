# ---------------------------------------------------------------------------
# Azure Storage for Mimir (TSDB blocks, ruler, alertmanager state)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "mimir" {
  count                    = var.manage_monitoring ? 1 : 0
  name                     = var.mimir_storage_account_name
  resource_group_name      = azurerm_resource_group.aks_rg.name
  location                 = azurerm_resource_group.aks_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.common_tags
}

resource "azurerm_storage_container" "mimir" {
  count                 = var.manage_monitoring ? 1 : 0
  name                  = "mimir-data"
  storage_account_id    = azurerm_storage_account.mimir[0].id
  container_access_type = "private"
}

resource "azurerm_storage_container" "loki" {
  count                 = var.manage_monitoring ? 1 : 0
  name                  = "loki-data"
  storage_account_id    = azurerm_storage_account.mimir[0].id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Workload Identity for Mimir — allows pods to access Blob Storage via
# Azure AD federated token without storing any credentials.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "mimir" {
  count               = var.manage_monitoring ? 1 : 0
  name                = "id-aks-mimir"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

resource "azurerm_federated_identity_credential" "mimir" {
  count     = var.manage_monitoring ? 1 : 0
  name      = "fed-aks-mimir"
  parent_id = azurerm_user_assigned_identity.mimir[0].id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject   = "system:serviceaccount:mimir:mimir"
}

resource "azurerm_role_assignment" "mimir_blob_contributor" {
  count                = var.manage_monitoring ? 1 : 0
  scope                = azurerm_storage_account.mimir[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mimir[0].principal_id
}

# ---------------------------------------------------------------------------
# Workload Identity for Loki — separate identity from Mimir for least-privilege
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "loki" {
  count               = var.manage_monitoring ? 1 : 0
  name                = "id-aks-loki"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

resource "azurerm_federated_identity_credential" "loki" {
  count     = var.manage_monitoring ? 1 : 0
  name      = "fed-aks-loki"
  parent_id = azurerm_user_assigned_identity.loki[0].id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject   = "system:serviceaccount:monitoring:loki"
}

resource "azurerm_role_assignment" "loki_blob_contributor" {
  count                = var.manage_monitoring ? 1 : 0
  scope                = azurerm_storage_account.mimir[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.loki[0].principal_id
}

# ---------------------------------------------------------------------------
# Namespace for Grafana — created by Terraform so the ReferenceGrant
# (gateway_api.tf) can be applied before ArgoCD finishes its first sync.
# ArgoCD's CreateNamespace=true is a no-op when the namespace already exists.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "monitoring" {
  count = var.kube_config_path != "" && var.manage_monitoring ? 1 : 0
  metadata {
    name = "monitoring"
  }
}

# ---------------------------------------------------------------------------
# ArgoCD Applications — each points to a Helm umbrella chart in this repo.
# Dynamic Azure values (storage account name, client ID) are injected via
# the Application's helm.values so the rest of the config lives in git.
# ---------------------------------------------------------------------------

locals {
  loki_helm_overrides = var.manage_monitoring ? yamlencode({
    loki = {
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.loki[0].client_id
        }
      }
      podLabels = {
        "azure.workload.identity/use" = "true"
      }
      loki = {
        storage = {
          azure = {
            accountName       = azurerm_storage_account.mimir[0].name
            containerName     = "loki-data"
            useFederatedToken = true
          }
        }
      }
    }
  }) : ""

  mimir_helm_overrides = var.manage_monitoring ? yamlencode({
    "mimir-distributed" = {
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.mimir[0].client_id
        }
      }
      global = {
        podLabels = {
          "azure.workload.identity/use" = "true"
        }
      }
      mimir = {
        structuredConfig = {
          common = {
            storage = {
              backend = "azure"
              azure = {
                account_name   = azurerm_storage_account.mimir[0].name
                container_name = "mimir-data"
              }
            }
          }
        }
      }
    }
  }) : ""
}

resource "kubernetes_manifest" "argocd_app_mimir" {
  count = var.kube_config_path != "" && var.manage_monitoring && var.manage_argocd ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "mimir"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = "HEAD"
        path           = "apps/monitoring/mimir"
        helm = {
          values = local.mimir_helm_overrides
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "mimir"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_app_alloy" {
  count = var.kube_config_path != "" && var.manage_monitoring && var.manage_argocd ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "alloy"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = "HEAD"
        path           = "apps/monitoring/alloy"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "alloy"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_app_grafana" {
  count = var.kube_config_path != "" && var.manage_monitoring && var.manage_argocd ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "grafana"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = "HEAD"
        path           = "apps/monitoring/grafana"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "monitoring"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_app_loki" {
  count = var.kube_config_path != "" && var.manage_monitoring && var.manage_argocd ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "loki"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = "HEAD"
        path           = "apps/monitoring/loki"
        helm = {
          values = local.loki_helm_overrides
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "monitoring"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}

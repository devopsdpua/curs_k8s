# =============================================================================
# Data sources
# =============================================================================

data "azurerm_client_config" "current" {}

# =============================================================================
# Locals
# =============================================================================

locals {
  aks_private_dns_zone_name = "privatelink.${replace(lower(var.resource_group_location), " ", "")}.azmk8s.io"
  create_jumpbox            = length(var.jumpbox_ssh_public_key) > 0 || length(var.jumpbox_admin_password) > 0
  common_tags               = { Environment = "Learning", ManagedBy = "Terraform" }

  # Gateway API manifests
  gateway_class_manifest = yamldecode(file("${path.module}/networking/gateway-api/gateway-class.yaml"))
  gateway_file           = yamldecode(file("${path.module}/networking/gateway-api/gateway.yaml"))
  envoy_proxy_azure_pip_file = templatefile("${path.module}/networking/gateway-api/envoy-proxy-azure-pip.yaml", {
    node_resource_group = azurerm_kubernetes_cluster.aks.node_resource_group
  })
  envoy_proxy_azure_pip_manifest = yamldecode(local.envoy_proxy_azure_pip_file)
  gateway_manifest = merge(local.gateway_file, {
    spec = merge(local.gateway_file.spec, {
      addresses = [{ type = "IPAddress", value = azurerm_public_ip.gateway.ip_address }]
      infrastructure = {
        parametersRef = {
          group = "gateway.envoyproxy.io"
          kind  = "EnvoyProxy"
          name  = "envoy-proxy-azure-pip"
        }
      }
    })
  })
  argocd_httproute_manifest        = yamldecode(file("${path.module}/networking/routes/argocd-httproute.yaml"))
  argocd_reference_grant_manifest  = yamldecode(file("${path.module}/networking/routes/argocd-reference-grant.yaml"))
  grafana_httproute_manifest       = yamldecode(file("${path.module}/networking/routes/grafana-httproute.yaml"))
  grafana_reference_grant_manifest = yamldecode(file("${path.module}/networking/routes/grafana-reference-grant.yaml"))

  # Monitoring helm overrides
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
            accountName       = azurerm_storage_account.monitoring[0].name
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
                account_name   = azurerm_storage_account.monitoring[0].name
                container_name = "mimir-data"
              }
            }
          }
        }
      }
    }
  }) : ""
}

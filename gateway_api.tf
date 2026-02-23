locals {
  gateway_class_manifest    = yamldecode(file("${path.module}/networking/gateway-api/gateway-class.yaml"))
  gateway_file              = yamldecode(file("${path.module}/networking/gateway-api/gateway.yaml"))
  envoy_proxy_azure_pip_file = templatefile("${path.module}/networking/gateway-api/envoy-proxy-azure-pip.yaml", {
    node_resource_group = azurerm_kubernetes_cluster.aks.node_resource_group
  })
  envoy_proxy_azure_pip_manifest = yamldecode(local.envoy_proxy_azure_pip_file)
  gateway_manifest = merge(local.gateway_file, {
    spec = merge(local.gateway_file.spec, {
      addresses = [{ type = "IPAddress", value = azurerm_public_ip.gateway.ip_address }]
      infrastructure = {
        parametersRef = {
          group     = "gateway.envoyproxy.io"
          kind      = "EnvoyProxy"
          name      = "envoy-proxy-azure-pip"
          namespace = "default"
        }
      }
    })
  })
  argocd_httproute_manifest     = yamldecode(file("${path.module}/networking/routes/argocd-httproute.yaml"))
  argocd_reference_grant_manifest = yamldecode(file("${path.module}/networking/routes/argocd-reference-grant.yaml"))
}

resource "kubernetes_manifest" "gateway_class" {
  count      = var.kube_config_path != "" && var.manage_gateway_api ? 1 : 0
  manifest   = local.gateway_class_manifest
  depends_on = [helm_release.eg]
}

# EnvoyProxy with Azure PIP annotations so the Envoy Service uses pip-envoy-gateway (static IP).
resource "kubernetes_manifest" "envoy_proxy_azure_pip" {
  count      = var.kube_config_path != "" && var.manage_gateway_api ? 1 : 0
  manifest   = local.envoy_proxy_azure_pip_manifest
  depends_on = [helm_release.eg]
}

resource "kubernetes_manifest" "gateway" {
  count      = var.kube_config_path != "" && var.manage_gateway_api ? 1 : 0
  manifest   = local.gateway_manifest
  depends_on = [helm_release.eg, kubernetes_manifest.envoy_proxy_azure_pip]
}

resource "kubernetes_manifest" "argocd_httproute" {
  count      = var.kube_config_path != "" && var.manage_gateway_api ? 1 : 0
  manifest   = local.argocd_httproute_manifest
  depends_on = [helm_release.eg]
}

# Required for HTTPRoute (default ns) to reference Service in argocd ns; without it the gateway returns 500.
resource "kubernetes_manifest" "argocd_reference_grant" {
  count      = var.kube_config_path != "" && var.manage_gateway_api && var.manage_argocd ? 1 : 0
  manifest   = local.argocd_reference_grant_manifest
  depends_on = [helm_release.argocd]
}

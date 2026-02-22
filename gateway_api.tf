locals {
  gateway_class_manifest = yamldecode(file("${path.module}/networking/gateway-api/gateway-class.yaml"))
  gateway_file           = yamldecode(file("${path.module}/networking/gateway-api/gateway.yaml"))
  gateway_manifest = merge(local.gateway_file, {
    spec = merge(local.gateway_file.spec, {
      addresses = [{ type = "IPAddress", value = azurerm_public_ip.gateway.ip_address }]
    })
  })
  argocd_httproute_manifest = yamldecode(file("${path.module}/networking/routes/argocd-httproute.yaml"))
}

resource "kubernetes_manifest" "gateway_class" {
  count      = var.kube_config_path != "" && var.manage_gateway_api ? 1 : 0
  manifest   = local.gateway_class_manifest
  depends_on = [helm_release.eg]
}

resource "kubernetes_manifest" "gateway" {
  count      = var.kube_config_path != "" && var.manage_gateway_api ? 1 : 0
  manifest   = local.gateway_manifest
  depends_on = [helm_release.eg]
}

resource "kubernetes_manifest" "argocd_httproute" {
  count      = var.kube_config_path != "" && var.manage_gateway_api ? 1 : 0
  manifest   = local.argocd_httproute_manifest
  depends_on = [helm_release.eg]
}

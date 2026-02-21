# Envoy Gateway — контроллер Gateway API (OCI Helm-чарт).
# Запускайте Terraform с машины, имеющей доступ к API кластера (например jumpbox после az aks get-credentials).
# Если release "eg" уже установлен вручную: terraform import 'helm_release.eg[0]' envoy-gateway-system/eg
resource "helm_release" "eg" {
  count = var.manage_gateway_api ? 1 : 0

  name             = "eg"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = var.envoy_gateway_helm_version
  namespace        = "envoy-gateway-system"
  create_namespace = true
}

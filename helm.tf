resource "helm_release" "eg" {
  count            = var.kube_config_path != "" ? 1 : 0
  name             = "eg"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = var.envoy_gateway_helm_version
  namespace        = "envoy-gateway-system"
  create_namespace = true
}

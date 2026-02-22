resource "helm_release" "argocd" {
  count            = var.kube_config_path != "" && var.manage_argocd ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_helm_version
  namespace        = "argocd"
  create_namespace = true

  # Accept HTTP when TLS is terminated at the gateway (required for HTTPRoute backend on port 80)
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
}

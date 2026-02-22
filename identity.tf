resource "azurerm_user_assigned_identity" "kv_csi" {
  name                = "id-aks-kv-csi"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

resource "azurerm_federated_identity_credential" "kv_csi" {
  name       = "fed-aks-kv-csi"
  parent_id  = azurerm_user_assigned_identity.kv_csi.id
  audience   = ["api://AzureADTokenExchange"]
  issuer     = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject    = "system:serviceaccount:kube-system:secrets-store-csi-driver"
}

resource "azurerm_federated_identity_credential" "kv_csi_default_sa" {
  name       = "fed-aks-kv-csi-default"
  parent_id  = azurerm_user_assigned_identity.kv_csi.id
  audience   = ["api://AzureADTokenExchange"]
  issuer     = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject    = "system:serviceaccount:default:default"
}

resource "azurerm_role_assignment" "kv_csi_reader" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.kv_csi.principal_id
}

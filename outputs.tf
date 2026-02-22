output "resource_group_name" {
  value = azurerm_resource_group.aks_rg.name
}

output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "kv_csi_client_id" {
  value = azurerm_user_assigned_identity.kv_csi.client_id
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "key_vault_id" {
  value = azurerm_key_vault.kv.id
}

output "gateway_public_ip" {
  value = azurerm_public_ip.gateway.ip_address
}

output "jumpbox_public_ip" {
  value     = local.create_jumpbox ? azurerm_public_ip.jumpbox[0].ip_address : null
  sensitive = true
}

output "jumpbox_private_ip" {
  value     = local.create_jumpbox ? azurerm_network_interface.jumpbox[0].private_ip_address : null
  sensitive = true
}

output "bastion_host_name" {
  value     = local.create_bastion ? azurerm_bastion_host.main[0].name : null
  sensitive = true
}

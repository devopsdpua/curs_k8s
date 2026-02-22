data "azurerm_client_config" "current" {}

locals {
  aks_private_dns_zone_name = "privatelink.${replace(lower(var.resource_group_location), " ", "")}.azmk8s.io"
  create_jumpbox            = length(var.jumpbox_ssh_public_key) > 0 || length(var.jumpbox_admin_password) > 0
  create_bastion            = var.create_bastion && local.create_jumpbox
  common_tags               = { Environment = "Learning", ManagedBy = "Terraform" }
}

resource "azurerm_resource_group" "aks_rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_resource_group" "kv_rg" {
  name     = var.key_vault_resource_group_name
  location = var.resource_group_location
}

resource "azurerm_virtual_network" "aks_vnet" {
  name                = "vnet-aks-study"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  address_space       = ["10.0.0.0/8"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.240.0.0/16"]
}

resource "azurerm_private_dns_zone" "aks_api" {
  name                = local.aks_private_dns_zone_name
  resource_group_name = azurerm_resource_group.aks_rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks_api_aks" {
  name                  = "link-aks-vnet"
  resource_group_name   = azurerm_resource_group.aks_rg.name
  private_dns_zone_name  = azurerm_private_dns_zone.aks_api.name
  virtual_network_id    = azurerm_virtual_network.aks_vnet.id
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-cluster"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-study-cluster"
  location             = azurerm_resource_group.aks_rg.location
  resource_group_name  = azurerm_resource_group.aks_rg.name
  dns_prefix           = "aksstudy"
  kubernetes_version   = "1.32.10"

  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled  = false
  private_dns_zone_id                 = azurerm_private_dns_zone.aks_api.id

  default_node_pool {
    name           = "systempool"
    node_count     = 1
    vm_size        = "Standard_D2s_v3"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
    os_sku         = "AzureLinux"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled  = true

  key_vault_secrets_provider {
    secret_rotation_enabled   = true
    secret_rotation_interval = "2m"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    load_balancer_sku   = "standard"
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      default_node_pool[0].upgrade_settings,
      kubernetes_version,
    ]
  }
}

resource "azurerm_role_assignment" "aks_dns_contributor" {
  scope                = azurerm_private_dns_zone.aks_api.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_key_vault" "kv" {
  name                        = var.key_vault_name
  location                    = azurerm_resource_group.kv_rg.location
  resource_group_name         = azurerm_resource_group.kv_rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 90
  purge_protection_enabled    = false
  rbac_authorization_enabled  = true
  tags                        = local.common_tags
}

resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_virtual_network" "mgmt_vnet" {
  name                = "vnet-mgmt-study"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  address_space       = var.mgmt_vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "jumpbox" {
  name                 = "snet-jumpbox"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.mgmt_vnet.name
  address_prefixes     = [var.jumpbox_subnet_prefix]
}

resource "azurerm_subnet" "bastion" {
  count                = local.create_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.mgmt_vnet.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

resource "azurerm_virtual_network_peering" "aks_to_mgmt" {
  name                         = "peer-aks-to-mgmt"
  resource_group_name          = azurerm_resource_group.aks_rg.name
  virtual_network_name         = azurerm_virtual_network.aks_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.mgmt_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}

resource "azurerm_virtual_network_peering" "mgmt_to_aks" {
  name                         = "peer-mgmt-to-aks"
  resource_group_name          = azurerm_resource_group.aks_rg.name
  virtual_network_name         = azurerm_virtual_network.mgmt_vnet.name
  remote_virtual_network_id     = azurerm_virtual_network.aks_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks_api_mgmt" {
  name                  = "link-mgmt-vnet"
  resource_group_name   = azurerm_resource_group.aks_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.aks_api.name
  virtual_network_id    = azurerm_virtual_network.mgmt_vnet.id
}

resource "azurerm_network_security_group" "jumpbox" {
  count               = local.create_jumpbox ? 1 : 0
  name                = "nsg-jumpbox"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name

  security_rule {
    name                       = "AllowSSHFromInternet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.jumpbox_ssh_source_prefix
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = local.create_bastion ? [1] : []
    content {
      name                       = "AllowSSHFromBastion"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.bastion_subnet_prefix
      destination_address_prefix = "*"
    }
  }

  tags = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "jumpbox" {
  count                    = local.create_jumpbox ? 1 : 0
  subnet_id                = azurerm_subnet.jumpbox.id
  network_security_group_id = azurerm_network_security_group.jumpbox[0].id
}

resource "azurerm_public_ip" "jumpbox" {
  count               = local.create_jumpbox ? 1 : 0
  name                = "pip-jumpbox"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_public_ip" "bastion" {
  count               = local.create_bastion ? 1 : 0
  name                = "pip-bastion"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_bastion_host" "main" {
  count               = local.create_bastion ? 1 : 0
  name                = "bastion-study"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name

  ip_configuration {
    name                 = "config"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
  tags = local.common_tags
}

resource "azurerm_network_interface" "jumpbox" {
  count               = local.create_jumpbox ? 1 : 0
  name                = "nic-jumpbox"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jumpbox.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.jumpbox_private_ip
    public_ip_address_id          = azurerm_public_ip.jumpbox[0].id
  }
  tags = local.common_tags
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  count                 = local.create_jumpbox ? 1 : 0
  name                  = "vm-jumpbox"
  location              = azurerm_resource_group.aks_rg.location
  resource_group_name   = azurerm_resource_group.aks_rg.name
  size                  = var.jumpbox_vm_size
  admin_username        = var.jumpbox_admin_username
  admin_password        = length(var.jumpbox_ssh_public_key) == 0 ? var.jumpbox_admin_password : null
  network_interface_ids = [azurerm_network_interface.jumpbox[0].id]
  disable_password_authentication = length(var.jumpbox_ssh_public_key) > 0

  dynamic "admin_ssh_key" {
    for_each = length(var.jumpbox_ssh_public_key) > 0 ? [1] : []
    content {
      username   = var.jumpbox_admin_username
      public_key = var.jumpbox_ssh_public_key
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  tags = local.common_tags
}

resource "azurerm_public_ip" "gateway" {
  name                = "pip-envoy-gateway"
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  location            = azurerm_kubernetes_cluster.aks.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

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
  value       = local.create_jumpbox ? azurerm_public_ip.jumpbox[0].ip_address : null
  sensitive   = true
}

output "jumpbox_private_ip" {
  value       = local.create_jumpbox ? azurerm_network_interface.jumpbox[0].private_ip_address : null
  sensitive   = true
}

output "bastion_host_name" {
  value       = local.create_bastion ? azurerm_bastion_host.main[0].name : null
  sensitive   = true
}

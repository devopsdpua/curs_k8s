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

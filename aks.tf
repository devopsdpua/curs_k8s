resource "azurerm_resource_group" "aks_rg" {
  name     = var.resource_group_name
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
    name                         = "systempool"
    node_count                   = 1
    vm_size                      = "Standard_D2s_v3"
    vnet_subnet_id               = azurerm_subnet.aks_subnet.id
    os_sku                       = "AzureLinux"
    only_critical_addons_enabled = true
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

resource "azurerm_kubernetes_cluster_node_pool" "infrastructure" {
  count                 = (var.manage_argocd || var.manage_monitoring) ? 1 : 0
  name                  = "infra"
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.aks.id
  vm_size                = var.monitoring_node_vm_size
  node_count             = 1
  vnet_subnet_id         = azurerm_subnet.aks_subnet.id
  os_sku                 = "AzureLinux"

  node_labels = {
    "workload" = "infrastructure"
  }

  node_taints = ["workload=infrastructure:NoSchedule"]

  tags = local.common_tags
}

resource "azurerm_role_assignment" "aks_dns_contributor" {
  scope                = azurerm_private_dns_zone.aks_api.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_public_ip" "gateway" {
  name                = "pip-envoy-gateway"
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  location            = azurerm_kubernetes_cluster.aks.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

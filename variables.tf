variable "subscription_id" {
  type    = string
  default = ""
}

variable "resource_group_name" {
  type    = string
  default = "rg-learning-aks"
}

variable "resource_group_location" {
  type    = string
  default = "West Europe"
}

variable "key_vault_resource_group_name" {
  type    = string
  default = "rg-learning-kv"
}

variable "key_vault_name" {
  type    = string
  default = "kv-curs-k8s"
}

variable "tls_cert_name" {
  type    = string
  default = ""
}

variable "mgmt_vnet_address_space" {
  type    = list(string)
  default = ["192.168.0.0/16"]
}

variable "jumpbox_subnet_prefix" {
  type    = string
  default = "192.168.1.0/24"
}

variable "jumpbox_private_ip" {
  type    = string
  default = "192.168.1.4"
}

variable "jumpbox_admin_username" {
  type    = string
  default = "azureuser"
}

variable "jumpbox_ssh_public_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "jumpbox_admin_password" {
  type      = string
  default   = "ChangeMe123!"
  sensitive = true
}

variable "jumpbox_vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "jumpbox_ssh_source_prefix" {
  type    = string
  default = "0.0.0.0/0"
}

variable "create_bastion" {
  type    = bool
  default = false
}

variable "bastion_subnet_prefix" {
  type    = string
  default = "192.168.2.0/26"
}

variable "kube_config_path" {
  type    = string
  default = ""
}

variable "envoy_gateway_helm_version" {
  type    = string
  default = "1.7.0"
}

variable "manage_gateway_api" {
  type    = bool
  default = true
}

variable "argocd_helm_version" {
  type    = string
  default = "7.7.0"
}

variable "manage_argocd" {
  type    = bool
  default = true
}

variable "manage_monitoring" {
  type    = bool
  default = false
}

variable "monitoring_node_vm_size" {
  type    = string
  default = "Standard_D4s_v3"
}

variable "monitoring_node_count" {
  type    = number
  default = 1
}

variable "mimir_storage_account_name" {
  type        = string
  description = "Globally unique name for the Azure Storage Account used by Mimir (3-24 lowercase letters/numbers). Required when manage_monitoring = true."
  default     = ""

  validation {
    condition     = var.mimir_storage_account_name == "" || (length(var.mimir_storage_account_name) >= 3 && length(var.mimir_storage_account_name) <= 24 && can(regex("^[a-z0-9]+$", var.mimir_storage_account_name)))
    error_message = "mimir_storage_account_name must be 3-24 lowercase letters/numbers."
  }
}

variable "git_repo_url" {
  type        = string
  description = "Git repository URL for ArgoCD Applications (SSH or HTTPS)."
  default     = ""
}

variable "subscription_id" {
  type        = string
  default     = ""
  description = "Azure Subscription ID. Можно передать через ARM_SUBSCRIPTION_ID env или tfvars."
}

variable "resource_group_location" {
  type    = string
  default = "West Europe"
}

variable "resource_group_name" {
  type    = string
  default = "rg-learning-aks"
}

variable "key_vault_resource_group_name" {
  type        = string
  default     = "rg-learning-kv"
  description = "Имя отдельной ресурс-группы для Key Vault"
}

variable "key_vault_name" {
  type        = string
  default     = "kv-curs-k8s"
  description = "Имя Key Vault (глобально уникальное, 3–24 символа). После apply загрузите сюда wildcard-сертификат."
}

variable "tls_cert_name" {
  type        = string
  default     = ""
  description = "Имя Certificate или Secret в Key Vault (wildcard-сертификат)"
}

# --- Management VNet + Jumpbox ---
variable "mgmt_vnet_address_space" {
  type        = list(string)
  default     = ["192.168.0.0/16"]
  description = "Address space для management VNet (jumpbox, Bastion)"
}

variable "jumpbox_subnet_prefix" {
  type        = string
  default     = "192.168.1.0/24"
  description = "Подсеть для jumpbox VM"
}

variable "jumpbox_private_ip" {
  type        = string
  default     = "192.168.1.4"
  description = "Статический private IP для jumpbox (из диапазона jumpbox_subnet_prefix)"
}

variable "bastion_subnet_prefix" {
  type        = string
  default     = "192.168.2.0/26"
  description = "Подсеть для Azure Bastion (минимум /26)"
}

variable "jumpbox_admin_username" {
  type        = string
  default     = "azureuser"
  description = "Логин для входа на jumpbox по SSH"
}

variable "jumpbox_ssh_public_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "SSH public key для доступа к jumpbox. Если пусто — используется jumpbox_admin_password."
}

variable "jumpbox_admin_password" {
  type        = string
  default     = "ChangeMe123!"
  sensitive   = true
  description = "Пароль для входа на jumpbox (если не задан jumpbox_ssh_public_key). Смените после первого входа."
}

variable "jumpbox_vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "SKU jumpbox VM"
}

variable "jumpbox_ssh_source_prefix" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR, с которого разрешён SSH на jumpbox (0.0.0.0/0 = отовсюду; для безопасности укажите свой IP, например x.x.x.x/32)"
}

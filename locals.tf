locals {
  aks_private_dns_zone_name = "privatelink.${replace(lower(var.resource_group_location), " ", "")}.azmk8s.io"
  create_jumpbox            = length(var.jumpbox_ssh_public_key) > 0 || length(var.jumpbox_admin_password) > 0
  create_bastion            = var.create_bastion && local.create_jumpbox
  common_tags               = { Environment = "Learning", ManagedBy = "Terraform" }
}

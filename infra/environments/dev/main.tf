module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-${local.name_prefix}-${var.location_short}"
  location = var.location
  tags     = local.common_tags
}

module "network" {
  source = "../../modules/network"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = module.resource_group.name

  vnet_address_space             = var.vnet_address_space
  aks_subnet_prefix              = var.aks_subnet_prefix
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix

  tags = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name = module.resource_group.name
  location            = var.location
  workspace_name      = "law-${local.name_prefix}-${var.location_short}"
  retention_in_days   = 30
  tags                = local.common_tags
}

module "acr" {
  source = "../../modules/acr"

  resource_group_name = module.resource_group.name
  location            = var.location
  acr_name            = var.acr_name
  sku                 = var.acr_sku
  tags                = local.common_tags
}

module "identities" {
  source = "../../modules/identities"

  resource_group_name = module.resource_group.name
  location            = var.location
  identity_name       = "id-nordic-api-${var.environment}-${var.location_short}"
  tags                = local.common_tags
}

module "aks" {
  source = "../../modules/aks"

  aks_name            = "aks-${local.name_prefix}-${var.location_short}"
  location            = var.location
  resource_group_name = module.resource_group.name
  dns_prefix          = local.name_prefix
  kubernetes_version  = var.aks_kubernetes_version

  system_node_vm_size = var.aks_system_node_vm_size
  system_node_count   = var.aks_system_node_count

  aks_subnet_id = module.network.aks_subnet_id

  pod_cidr       = var.aks_pod_cidr
  service_cidr   = var.aks_service_cidr
  dns_service_ip = var.aks_dns_service_ip

  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags
}

module "acr_pull_rbac" {
  source = "../../modules/rbac"

  principal_id         = module.aks.kubelet_identity_object_id
  scope                = module.acr.acr_id
  role_definition_name = "AcrPull"
}

module "key_vault" {
  source = "../../modules/key-vault"

  name                = "kv-${local.name_prefix}-${var.location_short}"
  resource_group_name = module.resource_group.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.common_tags
}

module "key_vault_secrets_rbac" {
  source = "../../modules/rbac"

  principal_id         = module.identities.principal_id
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
}
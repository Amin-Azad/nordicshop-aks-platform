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


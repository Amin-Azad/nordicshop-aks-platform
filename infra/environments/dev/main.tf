module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-${local.name_prefix}-${var.location_short}"
  location = var.location
  tags     = local.common_tags
}
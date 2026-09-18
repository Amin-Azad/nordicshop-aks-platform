resource "azurerm_monitor_action_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  short_name          = var.short_name

  enabled = true

  email_receiver {
    name                    = "nordicshop-alert-email"
    email_address           = var.email_address
    use_common_alert_schema = true
  }

  tags = var.tags
}

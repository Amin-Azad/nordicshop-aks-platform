resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.diagnostic_settings

  name                           = each.value.name
  target_resource_id             = each.value.target_resource_id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = each.value.log_analytics_destination_type

  dynamic "enabled_log" {
    for_each = each.value.log_categories

    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = each.value.metric_categories

    content {
      category = enabled_metric.value
    }
  }
}

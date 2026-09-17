output "data_collection_rule_id" {
  description = "Resource ID of the Container Insights data collection rule."
  value       = azurerm_monitor_data_collection_rule.this.id
}

output "data_collection_rule_name" {
  description = "Name of the Container Insights data collection rule."
  value       = azurerm_monitor_data_collection_rule.this.name
}

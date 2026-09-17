output "monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor Workspace."
  value       = azurerm_monitor_workspace.this.id
}

output "monitor_workspace_name" {
  description = "Name of the Azure Monitor Workspace."
  value       = azurerm_monitor_workspace.this.name
}

output "monitor_workspace_query_endpoint" {
  description = "Prometheus query endpoint of the Azure Monitor Workspace."
  value       = azurerm_monitor_workspace.this.query_endpoint
}

output "data_collection_rule_id" {
  description = "Resource ID of the Managed Prometheus data collection rule."
  value       = azurerm_monitor_data_collection_rule.this.id
}

output "data_collection_rule_name" {
  description = "Name of the Managed Prometheus data collection rule."
  value       = azurerm_monitor_data_collection_rule.this.name
}

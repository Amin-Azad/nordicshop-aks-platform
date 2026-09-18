output "id" {
  description = "Resource ID of the Azure Monitor Action Group."
  value       = azurerm_monitor_action_group.this.id
}

output "name" {
  description = "Name of the Azure Monitor Action Group."
  value       = azurerm_monitor_action_group.this.name
}

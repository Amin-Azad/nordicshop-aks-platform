output "id" {
  description = "Resource ID of the Azure Managed Grafana workspace."
  value       = azurerm_dashboard_grafana.this.id
}

output "name" {
  description = "Name of the Azure Managed Grafana workspace."
  value       = azurerm_dashboard_grafana.this.name
}

output "endpoint" {
  description = "URL endpoint of the Azure Managed Grafana workspace."
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "principal_id" {
  description = "Principal ID of the Grafana system-assigned managed identity."
  value       = azurerm_dashboard_grafana.this.identity[0].principal_id
}

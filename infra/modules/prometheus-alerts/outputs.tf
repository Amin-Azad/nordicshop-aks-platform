output "id" {
  description = "Resource ID of the Managed Prometheus alert rule group."
  value       = azurerm_monitor_alert_prometheus_rule_group.this.id
}

output "name" {
  description = "Name of the Managed Prometheus alert rule group."
  value       = azurerm_monitor_alert_prometheus_rule_group.this.name
}

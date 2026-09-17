resource "azurerm_dashboard_grafana" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  grafana_major_version = "13"
  sku                   = "Standard"

  api_key_enabled                   = false
  deterministic_outbound_ip_enabled = false
  public_network_access_enabled     = true
  zone_redundancy_enabled           = false

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = var.azure_monitor_workspace_id
  }

  tags = var.tags
}

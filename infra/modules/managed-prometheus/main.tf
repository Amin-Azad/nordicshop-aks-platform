resource "azurerm_monitor_workspace" "this" {
  name                = var.workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

resource "azurerm_monitor_data_collection_rule" "this" {
  name                = var.dcr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.this.id
      name               = "managed-prometheus"
    }
  }

  data_flow {
    streams = [
      "Microsoft-PrometheusMetrics"
    ]

    destinations = [
      "managed-prometheus"
    ]
  }

  data_sources {
    prometheus_forwarder {
      name = "prometheus-forwarder"

      streams = [
        "Microsoft-PrometheusMetrics"
      ]
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "this" {
  name                    = "managed-prometheus"
  target_resource_id      = var.aks_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.this.id
}

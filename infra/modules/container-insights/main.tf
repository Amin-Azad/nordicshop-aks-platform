resource "azurerm_monitor_data_collection_rule" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "container-insights"
    }
  }

  data_flow {
    streams = [
      "Microsoft-ContainerInsights-Group-Default"
    ]

    destinations = [
      "container-insights"
    ]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"

      streams = [
        "Microsoft-ContainerInsights-Group-Default"
      ]

      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          namespaces             = []
          enableContainerLogV2   = true
        }
      })
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "this" {
  name                    = "container-insights"
  target_resource_id      = var.aks_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.this.id
}

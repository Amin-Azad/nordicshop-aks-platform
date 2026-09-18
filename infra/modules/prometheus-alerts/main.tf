resource "azurerm_monitor_alert_prometheus_rule_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  cluster_name       = var.cluster_name
  scopes             = [var.monitor_workspace_id]
  rule_group_enabled = true
  interval           = "PT1M"

  description = "NordicShop Managed Prometheus alert rules"

  rule {
    alert      = "NordicShopAPIUnavailable"
    enabled    = true
    severity   = 1
    for        = "PT5M"
    expression = <<-EOT
      (
        sum(
          up{
            job="kubernetes-pods",
            kubernetes_namespace="nordicshop",
            app="nordicshop-api"
          }
        )
        or vector(0)
      ) < 1
    EOT

    action {
      action_group_id = var.action_group_id
    }

    annotations = {
      summary     = "NordicShop API unavailable"
      description = "No NordicShop API Prometheus targets have been available for 5 minutes."
    }

    labels = {
      service  = "nordicshop-api"
      severity = "critical"
      category = "availability"
    }

    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT5M"
    }
  }

  rule {
    alert      = "NordicShopReplicaAvailabilityDegraded"
    enabled    = true
    severity   = 2
    for        = "PT5M"
    expression = <<-EOT
      100 *
      sum(
        kube_deployment_status_replicas_available{
          namespace="nordicshop"
        }
      )
      /
      sum(
        kube_deployment_spec_replicas{
          namespace="nordicshop"
        }
      )
      < 100
    EOT

    action {
      action_group_id = var.action_group_id
    }

    annotations = {
      summary     = "NordicShop deployment replicas degraded"
      description = "Available deployment replicas have been below the desired count for 5 minutes."
    }

    labels = {
      service  = "nordicshop"
      severity = "warning"
      category = "kubernetes"
    }

    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT5M"
    }
  }

  rule {
    alert      = "NordicShopArgoCDUnhealthy"
    enabled    = true
    severity   = 2
    for        = "PT5M"
    expression = <<-EOT
      absent(
        argocd_app_info{
          name="nordicshop",
          sync_status="synced",
          health_status="healthy"
        }
      )
    EOT

    action {
      action_group_id = var.action_group_id
    }

    annotations = {
      summary     = "NordicShop Argo CD application is not healthy"
      description = "The NordicShop Argo CD application has not been both Synced and Healthy for 5 minutes."
    }

    labels = {
      service  = "argocd"
      severity = "warning"
      category = "gitops"
    }

    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT5M"
    }
  }

  rule {
    alert      = "NordicShopHigh5xxErrorRate"
    enabled    = true
    severity   = 1
    for        = "PT5M"
    expression = <<-EOT
      100 *
      (
        sum(
          rate(
            http_requests_total{
              status=~"5.."
            }[5m]
          )
        )
        or vector(0)
      )
      /
      sum(
        rate(
          http_requests_total[5m]
        )
      )
      > 5
    EOT

    action {
      action_group_id = var.action_group_id
    }

    annotations = {
      summary     = "NordicShop API 5xx error rate is high"
      description = "More than 5 percent of NordicShop API requests have returned HTTP 5xx responses for 5 minutes."
    }

    labels = {
      service  = "nordicshop-api"
      severity = "critical"
      category = "application"
    }

    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT5M"
    }
  }

  tags = var.tags
}

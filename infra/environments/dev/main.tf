module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-${local.name_prefix}-${var.location_short}"
  location = var.location
  tags     = local.common_tags
}

module "network" {
  source = "../../modules/network"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = module.resource_group.name

  vnet_address_space             = var.vnet_address_space
  aks_subnet_prefix              = var.aks_subnet_prefix
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix

  tags = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name = module.resource_group.name
  location            = var.location
  workspace_name      = "law-${local.name_prefix}-${var.location_short}"
  retention_in_days   = 30
  tags                = local.common_tags
}

module "acr" {
  source = "../../modules/acr"

  resource_group_name = module.resource_group.name
  location            = var.location
  acr_name            = var.acr_name
  sku                 = var.acr_sku
  tags                = local.common_tags
}

module "identities" {
  source = "../../modules/identities"

  resource_group_name = module.resource_group.name
  location            = var.location
  identity_name       = "id-nordic-api-${var.environment}-${var.location_short}"
  tags                = local.common_tags
}

module "github_actions_identity" {
  source = "../../modules/identities"

  resource_group_name = module.resource_group.name
  location            = var.location
  identity_name       = "id-github-actions-${var.environment}-${var.location_short}"

  tags = merge(local.common_tags, {
    purpose = "github-actions"
  })
}

module "aks" {
  source = "../../modules/aks"

  aks_name            = "aks-${local.name_prefix}-${var.location_short}"
  location            = var.location
  resource_group_name = module.resource_group.name
  dns_prefix          = local.name_prefix
  kubernetes_version  = var.aks_kubernetes_version

  system_node_vm_size = var.aks_system_node_vm_size
  system_node_count   = var.aks_system_node_count

  aks_subnet_id = module.network.aks_subnet_id

  pod_cidr       = var.aks_pod_cidr
  service_cidr   = var.aks_service_cidr
  dns_service_ip = var.aks_dns_service_ip

  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags
}

module "container_insights" {
  source = "../../modules/container-insights"

  name = "MSCI-${local.name_prefix}-${var.location_short}"

  resource_group_name = module.resource_group.name
  location            = var.location

  aks_id                     = module.aks.aks_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags
}

module "managed_prometheus" {
  source = "../../modules/managed-prometheus"

  workspace_name      = "amw-${local.name_prefix}-${var.location_short}"
  dcr_name            = "MSProm-${local.name_prefix}-${var.location_short}"
  resource_group_name = module.resource_group.name
  location            = var.location

  aks_id = module.aks.aks_id

  tags = local.common_tags
}

module "prometheus_alerts" {
  source = "../../modules/prometheus-alerts"

  name                = "amprg-${local.name_prefix}-${var.location_short}"
  resource_group_name = module.resource_group.name
  location            = var.location

  monitor_workspace_id = module.managed_prometheus.monitor_workspace_id
  cluster_name         = module.aks.aks_name
  action_group_id      = module.monitoring_action_group.id

  tags = local.common_tags
}

module "monitoring_action_group" {
  source = "../../modules/action-group"

  name                = "ag-${local.name_prefix}-${var.location_short}"
  short_name          = "nordicshop"
  resource_group_name = module.resource_group.name

  email_address = var.alert_email_address

  tags = local.common_tags
}

module "managed_grafana" {
  source = "../../modules/managed-grafana"

  name                = "amg-${local.name_prefix}-${var.location_short}"
  resource_group_name = module.resource_group.name
  location            = var.location

  azure_monitor_workspace_id = module.managed_prometheus.monitor_workspace_id

  tags = local.common_tags
}

module "prometheus_query_rbac" {
  source = "../../modules/rbac"

  principal_id         = data.azurerm_client_config.current.object_id
  scope                = module.managed_prometheus.monitor_workspace_id
  role_definition_name = "Monitoring Data Reader"
}

module "grafana_prometheus_rbac" {
  source = "../../modules/rbac"

  principal_id         = module.managed_grafana.principal_id
  scope                = module.managed_prometheus.monitor_workspace_id
  role_definition_name = "Monitoring Data Reader"
}

module "grafana_admin_rbac" {
  source = "../../modules/rbac"

  principal_id         = data.azurerm_client_config.current.object_id
  scope                = module.managed_grafana.id
  role_definition_name = "Grafana Admin"
}

module "acr_pull_rbac" {
  source = "../../modules/rbac"

  principal_id         = module.aks.kubelet_identity_object_id
  scope                = module.acr.acr_id
  role_definition_name = "AcrPull"
}

module "github_actions_acr_push_rbac" {
  source = "../../modules/rbac"

  principal_id         = module.github_actions_identity.principal_id
  scope                = module.acr.acr_id
  role_definition_name = "AcrPush"
}

module "key_vault" {
  source = "../../modules/key-vault"

  name                = "kv-${local.name_prefix}-${var.location_short}"
  resource_group_name = module.resource_group.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.common_tags
}

module "key_vault_secrets_rbac" {
  source = "../../modules/rbac"

  principal_id         = module.identities.principal_id
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
}

module "federation" {
  source = "../../modules/federation"

  name                = "fic-nordic-api-dev"
  managed_identity_id = module.identities.identity_id
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:nordicshop:nordic-api"
  audiences = [
    "api://AzureADTokenExchange"
  ]
}

module "github_actions_federation" {
  source = "../../modules/federation"

  name                = "fic-github-main"
  managed_identity_id = module.github_actions_identity.identity_id

  issuer = "https://token.actions.githubusercontent.com"

  subject = "repo:Amin-Azad@41924091/nordicshop-aks-platform@1348846402:ref:refs/heads/main"

  audiences = [
    "api://AzureADTokenExchange"
  ]
}

module "diagnostics" {
  source = "../../modules/diagnostics"

  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  diagnostic_settings = {
    aks = {
      name                           = "diag-aks-nordicshop-dev-weu"
      target_resource_id             = module.aks.aks_id
      log_analytics_destination_type = "Dedicated"

      log_categories = [
        "kube-apiserver",
        "kube-audit-admin",
        "kube-controller-manager",
        "kube-scheduler",
        "cluster-autoscaler"
      ]
    }

    key_vault = {
      name                           = "diag-kv-nordicshop-dev-weu"
      target_resource_id             = module.key_vault.key_vault_id
      log_analytics_destination_type = "Dedicated"

      log_categories = [
        "AuditEvent"
      ]
    }

    acr = {
      name               = "diag-acr-nordicshop-dev-weu"
      target_resource_id = module.acr.acr_id

      log_categories = [
        "ContainerRegistryLoginEvents",
        "ContainerRegistryRepositoryEvents"
      ]
    }
  }
}

module "budget" {
  source = "../../modules/budget"

  name              = "budget-${local.name_prefix}-${var.location_short}"
  resource_group_id = module.resource_group.id

  amount     = 3000
  time_grain = "Monthly"

  start_date = "2026-09-01T00:00:00Z"
  end_date   = "2027-09-01T00:00:00Z"

  notification_emails = var.budget_notification_emails
}
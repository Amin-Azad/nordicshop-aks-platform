output "resource_group_id" {
  description = "ID of the NordicShop development Resource Group."
  value       = module.resource_group.id
}

output "resource_group_name" {
  description = "Name of the NordicShop development Resource Group."
  value       = module.resource_group.name
}

output "vnet_id" {
  description = "ID of the NordicShop virtual network."
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "Name of the NordicShop virtual network."
  value       = module.network.vnet_name
}

output "aks_subnet_id" {
  description = "ID of the subnet reserved for AKS."
  value       = module.network.aks_subnet_id
}

output "private_endpoint_subnet_id" {
  description = "ID of the subnet reserved for future Private Endpoints."
  value       = module.network.private_endpoint_subnet_id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace."
  value       = module.monitoring.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace."
  value       = module.monitoring.log_analytics_workspace_name
}

output "acr_id" {
  description = "ID of the Azure Container Registry."
  value       = module.acr.acr_id
}

output "acr_name" {
  description = "Name of the Azure Container Registry."
  value       = module.acr.acr_name
}

output "acr_login_server" {
  description = "Login server of the Azure Container Registry."
  value       = module.acr.acr_login_server
}

output "nordic_api_identity_id" {
  description = "Azure resource ID of the Nordic API managed identity"
  value       = module.identities.identity_id
}

output "nordic_api_identity_client_id" {
  description = "Client ID of the Nordic API managed identity"
  value       = module.identities.client_id
}

output "nordic_api_identity_principal_id" {
  description = "Principal ID of the Nordic API managed identity"
  value       = module.identities.principal_id
}
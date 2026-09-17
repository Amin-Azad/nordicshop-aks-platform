variable "name" {
  description = "Name of the Container Insights data collection rule."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the monitoring resources."
  type        = string
}

variable "location" {
  description = "Azure region for the data collection rule."
  type        = string
}

variable "aks_id" {
  description = "Resource ID of the AKS cluster associated with the data collection rule."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving Container Insights data."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Container Insights resources."
  type        = map(string)
}

variable "name" {
  description = "Name of the Azure Managed Grafana workspace."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the Grafana workspace."
  type        = string
}

variable "location" {
  description = "Azure region for the Grafana workspace."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Grafana workspace."
  type        = map(string)
  default     = {}
}
variable "azure_monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor Workspace used for Managed Prometheus."
  type        = string
}

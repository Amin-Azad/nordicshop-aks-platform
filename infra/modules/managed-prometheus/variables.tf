variable "workspace_name" {
  description = "Name of the Azure Monitor Workspace storing Managed Prometheus metrics."
  type        = string
}

variable "dcr_name" {
  description = "Name of the Managed Prometheus data collection rule."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the Managed Prometheus resources."
  type        = string
}

variable "location" {
  description = "Azure region for the Managed Prometheus resources."
  type        = string
}

variable "aks_id" {
  description = "Resource ID of the AKS cluster associated with Managed Prometheus."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Managed Prometheus resources."
  type        = map(string)
}

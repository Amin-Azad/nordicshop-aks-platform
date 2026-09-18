variable "name" {
  description = "Name of the Managed Prometheus alert rule group."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the Prometheus rule group."
  type        = string
}

variable "location" {
  description = "Azure region for the Prometheus rule group."
  type        = string
}

variable "monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor Workspace."
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name used to scope Prometheus rules."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Prometheus rule group."
  type        = map(string)
  default     = {}
}
variable "action_group_id" {
  description = "Azure Monitor Action Group resource ID used for alert notifications."
  type        = string
}

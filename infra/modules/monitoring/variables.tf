variable "resource_group_name" {
  description = "Name of the resource group where monitoring resources will be created."
  type        = string
}

variable "location" {
  description = "Azure region for the monitoring resources."
  type        = string
}

variable "workspace_name" {
  description = "Name of the Log Analytics Workspace."
  type        = string
}

variable "retention_in_days" {
  description = "Number of days Log Analytics data is retained."
  type        = number
}

variable "tags" {
  description = "Tags applied to monitoring resources."
  type        = map(string)
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace that receives diagnostic data."
  type        = string
}

variable "diagnostic_settings" {
  description = "Diagnostic settings to create for Azure resources."

  type = map(object({
    name                           = string
    target_resource_id             = string
    log_categories                 = set(string)
    metric_categories              = optional(set(string), [])
    log_analytics_destination_type = optional(string)
  }))
}
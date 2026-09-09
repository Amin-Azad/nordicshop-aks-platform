variable "project_name" {
  type        = string
  description = "Short project name used for resource naming and tags."
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  type        = string
  description = "Primary Azure region for NordicShop resources."
}

variable "location_short" {
  type        = string
  description = "Short region code used in Azure resource names."
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to NordicShop resources."
  default     = {}
}
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

variable "vnet_address_space" {
  description = "Address space assigned to the NordicShop virtual network."
  type        = list(string)
}

variable "aks_subnet_prefix" {
  description = "CIDR range assigned to the AKS subnet."
  type        = string
}

variable "private_endpoint_subnet_prefix" {
  description = "CIDR range reserved for future Azure Private Endpoints."
  type        = string
}
variable "resource_group_name" {
  description = "Name of the resource group where the Azure Container Registry will be created."
  type        = string
}

variable "location" {
  description = "Azure region for the Azure Container Registry."
  type        = string
}

variable "acr_name" {
  description = "Name of the Azure Container Registry."
  type        = string
}

variable "sku" {
  description = "SKU of the Azure Container Registry. Valid values are 'Basic', 'Standard', or 'Premium'."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Azure Container Registry."
  type        = map(string)
}
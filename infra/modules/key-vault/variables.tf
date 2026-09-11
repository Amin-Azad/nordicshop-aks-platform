variable "name" {
  description = "The name of the Azure Key Vault."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group where the Key Vault will be created."
  type        = string
}

variable "location" {
  description = "The Azure region where the Key Vault will be created."
  type        = string
}

variable "tenant_id" {
  description = "The Microsoft Entra tenant ID associated with the Key Vault."
  type        = string
}

variable "sku_name" {
  description = "The SKU used by the Azure Key Vault."
  type        = string
  default     = "standard"
}

variable "tags" {
  description = "Tags applied to the Azure Key Vault."
  type        = map(string)
  default     = {}
}
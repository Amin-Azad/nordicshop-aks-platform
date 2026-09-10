variable "resource_group_name" {
  description = "Name of the resource group where the managed identity will be created."
  type        = string
}

variable "location" {
  description = "Azure region where the managed identity will be created."
  type        = string
}

variable "identity_name" {
  description = "Name of the user-assigned managed identity."
  type        = string
}

variable "tags" {
  description = "Tags applied to the managed identity."
  type        = map(string)
  default     = {}
}
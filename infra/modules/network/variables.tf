variable "resource_group_name" {
  description = "Name of the resource group where the network resources will be created."
  type        = string
}

variable "location" {
  description = "Azure region where the network resources will be created."
  type        = string
}

variable "name_prefix" {
  description = "Common naming prefix used for NordicShop Azure resources."
  type        = string
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

variable "tags" {
  description = "Common Azure tags applied to network resources."
  type        = map(string)
}
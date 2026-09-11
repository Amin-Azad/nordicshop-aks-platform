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

variable "acr_name" {
  description = "Globally unique name of the Azure Container Registry."
  type        = string
}

variable "acr_sku" {
  description = "SKU of the Azure Container Registry."
  type        = string

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard, or Premium."
  }
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version used by the AKS cluster."
  type        = string
}

variable "aks_system_node_vm_size" {
  description = "Azure VM size used by the AKS system node pool."
  type        = string
}

variable "aks_system_node_count" {
  description = "Number of nodes in the AKS system node pool."
  type        = number

  validation {
    condition     = var.aks_system_node_count >= 1
    error_message = "The AKS system node pool must contain at least one node."
  }
}

variable "aks_pod_cidr" {
  description = "CIDR range used for AKS pods with Azure CNI Overlay."
  type        = string
}

variable "aks_service_cidr" {
  description = "CIDR range used for Kubernetes services inside AKS."
  type        = string
}

variable "aks_dns_service_ip" {
  description = "IP address used by Kubernetes DNS inside the AKS service CIDR."
  type        = string
}

variable "budget_notification_emails" {
  description = "Email addresses that receive Azure Cost Management budget notifications."
  type        = list(string)

  validation {
    condition     = length(var.budget_notification_emails) > 0
    error_message = "At least one budget notification email address must be provided."
  }
}
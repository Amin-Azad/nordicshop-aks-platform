variable "resource_group_name" {
  description = "Name of the resource group where the AKS cluster will be created."
  type        = string
}

variable "location" {
  description = "Azure region where the AKS cluster will be created."
  type        = string
}

variable "aks_name" {
  description = "Name of the AKS cluster."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix used by the AKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version used by the AKS cluster."
  type        = string
}

variable "aks_subnet_id" {
  description = "Resource ID of the existing subnet used by AKS nodes."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the existing Log Analytics workspace used by AKS monitoring."
  type        = string
}

variable "system_node_vm_size" {
  description = "Azure VM size used by the AKS system node pool."
  type        = string
}

variable "system_node_count" {
  description = "Number of nodes in the AKS system node pool."
  type        = number

  validation {
    condition     = var.system_node_count >= 1
    error_message = "The AKS system node pool must contain at least one node."
  }
}

variable "pod_cidr" {
  description = "CIDR range used for Kubernetes pods with Azure CNI Overlay."
  type        = string
}

variable "service_cidr" {
  description = "CIDR range used for Kubernetes ClusterIP services."
  type        = string
}

variable "dns_service_ip" {
  description = "IP address used by Kubernetes DNS inside the service CIDR."
  type        = string
}

variable "tags" {
  description = "Tags applied to the AKS cluster."
  type        = map(string)
}
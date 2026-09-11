variable "name" {
  description = "Name of the federated identity credential."
  type        = string
}

variable "managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity that the Kubernetes workload will use."
  type        = string
}

variable "issuer" {
  description = "OIDC issuer URL of the AKS cluster."
  type        = string
}

variable "subject" {
  description = "OIDC subject identifying the Kubernetes ServiceAccount allowed to use the managed identity."
  type        = string
}

variable "audiences" {
  description = "Audiences expected by Microsoft Entra ID when exchanging the Kubernetes OIDC token."
  type        = list(string)
}

variable "name" {
  description = "Name of the federated identity credential."
  type        = string
}

variable "managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity that trusts the external OIDC identity."
  type        = string
}

variable "issuer" {
  description = "OIDC issuer URL trusted by Microsoft Entra ID."
  type        = string
}

variable "subject" {
  description = "OIDC subject identifying the external workload allowed to use the managed identity."
  type        = string
}

variable "audiences" {
  description = "Audiences accepted by Microsoft Entra ID for the OIDC token exchange."
  type        = list(string)
}

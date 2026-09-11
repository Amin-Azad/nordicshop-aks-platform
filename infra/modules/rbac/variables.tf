variable "principal_id" {
  description = "The Microsoft Entra principal object ID that receives the Azure role assignment."
  type        = string
}

variable "scope" {
  description = "The Azure resource ID that defines where the role assignment applies."
  type        = string
}

variable "role_definition_name" {
  description = "The built-in Azure role to assign to the principal."
  type        = string
  default     = "AcrPull"
}

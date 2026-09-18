variable "name" {
  description = "Name of the Azure Monitor Action Group."
  type        = string
}

variable "short_name" {
  description = "Short name of the Action Group."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the Action Group."
  type        = string
}

variable "email_address" {
  description = "Email address that receives NordicShop monitoring alerts."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Action Group."
  type        = map(string)
  default     = {}
}

variable "name" {
  type        = string
  description = "Name of the Azure Resource Group."
}

variable "location" {
  type        = string
  description = "Azure region for the Resource Group."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the Resource Group."
  default     = {}
}
variable "name" {
  description = "Name of the Azure Consumption Budget."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the Azure resource group scoped by the budget."
  type        = string
}

variable "amount" {
  description = "Monthly budget amount in the billing currency of the Azure subscription."
  type        = number

  validation {
    condition     = var.amount > 0
    error_message = "Budget amount must be greater than zero."
  }
}
variable "time_grain" {
  description = "Time period over which Azure evaluates and resets budget tracking."
  type        = string
  default     = "Monthly"

  validation {
    condition     = var.time_grain == "Monthly"
    error_message = "time_grain must be Monthly for the NordicShop development budget."
  }
}

variable "start_date" {
  description = "Budget start date in RFC3339 format."
  type        = string
}

variable "end_date" {
  description = "Budget end date in RFC3339 format."
  type        = string
}

variable "notification_emails" {
  description = "Email addresses that receive Azure budget notifications."
  type        = list(string)
}

variable "notification_thresholds" {
  description = "Percentage thresholds that trigger actual-cost budget notifications."
  type        = list(number)
  default     = [50, 80, 100]

  validation {
    condition = alltrue([
      for threshold in var.notification_thresholds :
      threshold > 0 && threshold <= 1000
    ])

    error_message = "Each budget notification threshold must be greater than 0 and no more than 1000 percent."
  }
}

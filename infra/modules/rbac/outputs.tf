output "role_assignment_id" {
  description = "the azure resource id of role assignment"
  value       = azurerm_role_assignment.this.id
}
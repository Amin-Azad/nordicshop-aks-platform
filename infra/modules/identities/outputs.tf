output "identity_id" {
  description = "The Azure resource ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.this.id
}

output "client_id" {
  description = "The client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "The principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.this.principal_id
}

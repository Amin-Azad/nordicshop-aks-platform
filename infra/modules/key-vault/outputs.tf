output "key_vault_id" {
  description = "The Azure resource ID of the Key Vault."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "The name of the Key Vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "The URI used to access the Key Vault."
  value       = azurerm_key_vault.this.vault_uri
}

resource "azurerm_federated_identity_credential" "this" {
  name                      = var.name
  user_assigned_identity_id = var.managed_identity_id
  audience                  = var.audiences
  issuer                    = var.issuer
  subject                   = var.subject
}

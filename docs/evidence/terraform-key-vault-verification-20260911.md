# Terraform Key Vault Verification

Date: 2026-09-11

## Purpose

Create and verify the NordicShop Azure Key Vault and grant the Nordic API managed identity least-privilege access to read secrets.

## Key Vault

Name:

`kv-nordicshop-dev-weu`

Resource Group:

`rg-nordicshop-dev-weu`

Region:

`westeurope`

SKU:

`standard`

Configuration verified:

* Azure RBAC authorization enabled
* Soft delete retention set to 7 days
* Purge protection enabled
* Public network access enabled for the current project design
* No Private Endpoint configured
* No secrets stored in Terraform

Vault URI:

`https://kv-nordicshop-dev-weu.vault.azure.net/`

## Nordic API access

Principal:

Nordic API user-assigned managed identity

Principal ID:

`c285a017-a750-4378-ba4d-ae08165cec74`

Role:

`Key Vault Secrets User`

Scope:

NordicShop Key Vault only

Azure CLI verification confirmed that the Nordic API managed identity has the `Key Vault Secrets User` role directly on `kv-nordicshop-dev-weu`.

## Identity boundary

This phase does not configure workload identity federation.

The current relationship is only:

Nordic API managed identity
→ Key Vault Secrets User
→ NordicShop Key Vault

The Kubernetes ServiceAccount and AKS OIDC federation will be configured separately in the federation phase.

## Terraform verification

Terraform validation completed successfully.

Final Terraform plan result:

`No changes. Your infrastructure matches the configuration.`

## Result

Key Vault creation and Nordic API Key Vault RBAC access are verified.

The Key Vault phase is complete and the environment is ready for workload identity federation.

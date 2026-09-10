# Azure Container Registry Verification — 2026-09-10

## Module

`infra/modules/acr`

## Resource

- Name: `acrnordicshopazaddevweu`
- Resource Group: `rg-nordicshop-dev-weu`
- Region: `westeurope`
- SKU: `Basic`
- Login Server: `acrnordicshopazaddevweu.azurecr.io`

## Security decisions

- ACR admin account disabled
- Public network access enabled for the current development phase
- No Private Link / Private Endpoint configured yet
- No registry username/password used
- AKS `AcrPull` will be configured later through Azure RBAC
- GitHub Actions push permissions will also be configured later through identity/RBAC

## Terraform result

Initial `terraform apply` failed because the subscription was not registered for the `Microsoft.ContainerRegistry` resource provider.

After registering the provider, the second apply completed successfully:

```text
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

```

## Azure CLI verification

adminEnabled: false
location: westeurope
loginServer: acrnordicshopazaddevweu.azurecr.io
name: acrnordicshopazaddevweu
provisioningState: Succeeded
publicNetworkAccess: Enabled
sku: Basic

## Final Terraform verificaton

No changes. Your infrastructure matches the configuration.

## Result

Azure Container Registry is created, verified directly in Azure, and fully managed by Terraform.

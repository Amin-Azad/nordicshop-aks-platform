````md
# Terraform Managed Identity Verification

Date: 2026-09-10

## Module

`infra/modules/identities`

## What I created

Created one user-assigned managed identity for the Nordic API.

Name:

`id-nordic-api-dev-weu`

Resource group:

`rg-nordicshop-dev-weu`

Location:

`westeurope`

## Why this identity exists

This identity will later be used by the Nordic API through AKS Workload Identity.

For now, only the Azure managed identity was created.

No RBAC role assignments, Key Vault permissions, federation or Kubernetes ServiceAccount were added yet.

## Terraform Plan

Before apply:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
````

Terraform planned only the new managed identity.

## Terraform Apply

Apply result:

```text
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

## Terraform Outputs

Client ID:

```text
14d8802c-2b2f-4b6d-91cf-2709930ea2e4
```

Principal ID:

```text
c285a017-a750-4378-ba4d-ae08165cec74
```

Resource ID:

```text
/subscriptions/.../resourceGroups/rg-nordicshop-dev-weu/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-nordic-api-dev-weu
```

## Azure CLI Verification

Command used:

```bash
az identity show \
  --name id-nordic-api-dev-weu \
  --resource-group rg-nordicshop-dev-weu \
  --query "{name:name, location:location, clientId:clientId, principalId:principalId, id:id}" \
  -o json
```

Azure CLI confirmed:

* identity name is correct
* location is `westeurope`
* client ID matches Terraform
* principal ID matches Terraform
* resource ID matches Terraform

## What the IDs mean

* Client ID: used later when the workload authenticates as this identity
* Principal ID: used later for Azure RBAC permissions
* Resource ID: identifies the managed identity resource in Azure

## Final Terraform Check

Final command:

```bash
terraform plan
```

Result:

```text
No changes. Your infrastructure matches the configuration.
```

## Status

Module 05 - Managed Identities: complete and verified.

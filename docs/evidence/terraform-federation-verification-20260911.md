# NordicShop Terraform Federation Verification

**Date:** 2026-09-11
**Environment:** dev
**Phase:** Terraform 09 — Workload Identity Federation

## Purpose

Create the Azure-side trust relationship that will later allow the Nordic API Kubernetes ServiceAccount to use the existing Nordic API user-assigned managed identity without storing Azure credentials.

Terraform owns the Azure federated identity credential.

The Kubernetes ServiceAccount will remain owned by Helm and is not created in this Terraform phase.

## Federated identity credential

Terraform created:

```text
fic-nordic-api-dev
```

Attached managed identity:

```text
id-nordic-api-dev-weu
```

Trust configuration:

```text
Issuer:
AKS OIDC issuer for aks-nordicshop-dev-weu

Subject:
system:serviceaccount:nordicshop:nordic-api

Audience:
api://AzureADTokenExchange
```

## Terraform result

The reviewed Terraform plan showed:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

Only the following resource was created:

```text
module.federation.azurerm_federated_identity_credential.this
```

Terraform apply completed successfully:

```text
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

## Azure CLI verification

The federated identity credential was independently verified with Azure CLI.

```bash
az identity federated-credential show \
  --resource-group rg-nordicshop-dev-weu \
  --identity-name id-nordic-api-dev-weu \
  --name fic-nordic-api-dev \
  --query "{name:name,issuer:issuer,subject:subject,audiences:audiences}" \
  -o json
```

Verified values:

```text
name:
fic-nordic-api-dev

subject:
system:serviceaccount:nordicshop:nordic-api

audience:
api://AzureADTokenExchange

issuer:
AKS OIDC issuer for aks-nordicshop-dev-weu
```

The credential was also listed directly from the managed identity:

```bash
az identity federated-credential list \
  --resource-group rg-nordicshop-dev-weu \
  --identity-name id-nordic-api-dev-weu \
  -o table
```

The expected `fic-nordic-api-dev` credential was present.

## Final Terraform verification

A second Terraform plan was run after the apply.

Result:

```text
No changes. Your infrastructure matches the configuration.
```

This confirms that Azure and Terraform state match.

## Identity boundary

The current trust path is:

```text
Kubernetes ServiceAccount
        ↓
projected OIDC token
        ↓
AKS OIDC issuer
        ↓
federated identity credential
        ↓
Nordic API user-assigned managed identity
        ↓
Key Vault Secrets User
        ↓
Azure Key Vault
```

The Key Vault RBAC assignment controls what the managed identity is allowed to do.

The federated identity credential controls which Kubernetes identity is allowed to act as that managed identity.

## Current limitation

The Azure side of Workload Identity federation is complete.

The full runtime flow cannot be tested yet because the Helm-managed `nordic-api` Kubernetes ServiceAccount has not been created and configured for Workload Identity.

That will be completed later in the Kubernetes/Helm workload identity phase.

## Status

```text
Terraform Federation: COMPLETE

Terraform plan:       Clean
Azure verification:   Passed
ServiceAccount:       Deferred to Helm
```

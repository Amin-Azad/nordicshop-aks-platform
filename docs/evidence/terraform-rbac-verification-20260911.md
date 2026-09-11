# Terraform RBAC Verification

Date: 2026-09-11

## Purpose

Grant the AKS kubelet identity least-privilege permission to pull NordicShop container images from Azure Container Registry.

## Terraform relationship

Principal:
AKS kubelet managed identity

Role:
AcrPull

Scope:
acrnordicshopazaddevweu

## Azure verification

Azure CLI confirmed:

- Role: AcrPull
- Principal type: ServicePrincipal
- Principal ID: de327958-05e9-4c3e-9f17-0f79d6210a3b
- Scope: NordicShop Azure Container Registry

## Terraform reconciliation

Final terraform plan:

No changes. Your infrastructure matches the configuration.

## Result

RBAC phase verified successfully.

No Key Vault, GitHub Actions, workload identity federation, Kubernetes ServiceAccount, or other RBAC relationships were added in this phase.

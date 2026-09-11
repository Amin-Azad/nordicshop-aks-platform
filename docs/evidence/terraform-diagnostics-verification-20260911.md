# Terraform Diagnostics Verification

Date: 2026-09-11

## Scope

Implemented Azure Diagnostic Settings for:

- AKS
- Azure Key Vault
- Azure Container Registry

All diagnostics send selected platform logs to the existing Log Analytics Workspace:

`law-nordicshop-dev-weu`

## Terraform module

Module:

`infra/modules/diagnostics`

The module accepts:

- Log Analytics Workspace resource ID
- target resource IDs
- selected log categories
- optional metric categories
- optional Log Analytics destination type

## AKS diagnostics

Diagnostic setting:

`diag-aks-nordicshop-dev-weu`

Enabled log categories:

- `kube-apiserver`
- `kube-audit-admin`
- `kube-controller-manager`
- `kube-scheduler`
- `cluster-autoscaler`

Not enabled:

- full `kube-audit`
- CSI controller logs
- cloud controller manager logs
- other unused AKS diagnostic categories
- `AllMetrics`

`Dedicated` Log Analytics destination mode is enabled.

## Key Vault diagnostics

Diagnostic setting:

`diag-kv-nordicshop-dev-weu`

Enabled:

- `AuditEvent`

Not enabled:

- `AzurePolicyEvaluationDetails`
- `AllMetrics`

`Dedicated` Log Analytics destination mode is enabled.

## ACR diagnostics

Diagnostic setting:

`diag-acr-nordicshop-dev-weu`

Enabled:

- `ContainerRegistryLoginEvents`
- `ContainerRegistryRepositoryEvents`

Not enabled:

- `AllMetrics`

Azure returns the ACR Log Analytics destination type as `null`, so the module allows destination type to be optional for each diagnostic setting. This prevents permanent Terraform drift while keeping the intended ACR log collection.

## Apply result

Terraform apply:

`3 added, 0 changed, 0 destroyed`

Azure CLI verification confirmed:

- correct diagnostic setting names
- correct resource targets
- correct Log Analytics Workspace
- intended log categories enabled
- unneeded categories disabled
- platform metrics not exported to Log Analytics

## Final Terraform plan

Final result:

`No changes. Your infrastructure matches the configuration.`

## Cost decision

Only useful platform logs are sent to Log Analytics.

Full AKS audit logging and duplicated platform metrics were intentionally not enabled to reduce unnecessary Log Analytics ingestion and noise.

## Result

Diagnostics phase complete.

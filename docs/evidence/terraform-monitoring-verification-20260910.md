# Terraform Monitoring Verification

## Module

`infra/modules/monitoring`

## Purpose

Create the Log Analytics Workspace that will act as the Azure monitoring destination for NordicShop.

## Terraform configuration

Created:

- Log Analytics Workspace
- SKU: `PerGB2018`
- Retention: `30` days
- Region: `West Europe`
- Common NordicShop tags

Managed Prometheus and Azure Managed Grafana are intentionally not enabled at this stage.

## Terraform validation

```text
Success! The configuration is valid.

```

## Reviewed plan

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

The only planned Azure resource was:

```text
module.monitoring.azurerm_log_analytics_workspace.this
```

## Apply result

```text
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Created workspace:

```text
law-nordicshop-dev-weu
```

## Azure CLI verification

Command:

```bash
az monitor log-analytics workspace show \
  --resource-group rg-nordicshop-dev-weu \
  --workspace-name law-nordicshop-dev-weu \
  --query "{name:name, location:location, sku:sku.name, retention:retentionInDays, provisioningState:provisioningState, tags:tags}" \
  -o json
```

Verified:

```text
name              = law-nordicshop-dev-weu
location          = westeurope
sku               = PerGB2018
retention         = 30
provisioningState = Succeeded
```

Tags:

```text
environment = dev
managed_by  = terraform
owner       = platform
project     = nordicshop
purpose     = nordicshop-aks-platform
```

## Final Terraform verification

```text
No changes. Your infrastructure matches the configuration.
```

## Learning summary

The Log Analytics Workspace is created before AKS so later platform monitoring and diagnostic settings have an existing destination.

Terraform owns the Azure monitoring resource. Helm continues to own Kubernetes application objects, while Argo CD will later reconcile Helm/Git desired state.

The workspace ID is exposed as a Terraform output so later modules such as AKS and diagnostics can reference it directly without manually rebuilding Azure resource IDs.

# Terraform Budget Verification — 2026-09-11

## Purpose

This evidence records the implementation and verification of the Azure Cost Management budget for the NordicShop development environment.

The budget is the final Terraform module in the current Azure foundation sequence.

The budget is used as a cost-governance and alerting control only. It does not automatically stop, scale down, or delete Azure resources when the configured amount is reached.

---

## Design decision

The budget is scoped to the NordicShop development resource group:

```text
rg-nordicshop-dev-weu
```

This keeps NordicShop workload costs separate from the Terraform backend resource group and other unrelated Azure resources.

Terraform resource:

```text
azurerm_consumption_budget_resource_group
```

Configured budget:

```text
Name:
budget-nordicshop-dev-weu

Scope:
rg-nordicshop-dev-weu

Amount:
3000 DKK

Time grain:
Monthly

Start date:
2026-09-01T00:00:00Z

End date:
2027-09-01T00:00:00Z
```

Actual-cost notification thresholds:

```text
50%
80%
100%
```

The configured notification recipient is supplied through the development environment variable rather than hard-coded inside the reusable Budget module.

No Action Groups or automatic shutdown actions were added.

The main expected cost driver for the current development platform is the AKS node pool:

```text
VM size:
Standard_D4s_v4

Node count:
2

Autoscaling:
Disabled
```

Other possible costs include managed disks, Log Analytics ingestion, ACR, public IP/load-balancer resources, and Key Vault operations.

---

## Terraform implementation

Budget module:

```text
infra/modules/budget/
├── main.tf
└── variables.tf
```

The module receives:

```text
name
resource_group_id
amount
time_grain
start_date
end_date
notification_emails
notification_thresholds
```

The resource-group dependency is passed through the existing Terraform module output rather than using an explicit `depends_on`.

---

## Terraform plan review

Before apply, Terraform proposed only the new budget resource.

Plan result:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

Terraform planned:

```text
Resource:
module.budget.azurerm_consumption_budget_resource_group.this

Name:
budget-nordicshop-dev-weu

Amount:
3000

Time grain:
Monthly

Scope:
rg-nordicshop-dev-weu
```

Notifications:

```text
50% Actual
80% Actual
100% Actual
```

All notification blocks used:

```text
operator       = GreaterThanOrEqualTo
threshold_type = Actual
enabled        = true
```

No existing AKS, ACR, Key Vault, RBAC, Federation, Diagnostics, Network, Monitoring, or identity resources were changed or destroyed.

---

## Terraform apply result

The reviewed plan was applied successfully.

Result:

```text
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Terraform created:

```text
/subscriptions/.../resourceGroups/rg-nordicshop-dev-weu/providers/Microsoft.Consumption/budgets/budget-nordicshop-dev-weu
```

No existing platform resource was modified or destroyed during the Budget apply.

---

## Azure CLI verification

The deployed budget was verified independently using Azure CLI:

```bash
az consumption budget show \
  --resource-group rg-nordicshop-dev-weu \
  --budget-name budget-nordicshop-dev-weu \
  -o json
```

Azure returned:

```text
Name:
budget-nordicshop-dev-weu

Amount:
3000.0

Currency:
DKK

Current spend:
0.0 DKK

Time grain:
Monthly

Start:
2026-09-01T00:00:00Z

End:
2027-09-01T00:00:00Z
```

Azure also confirmed three enabled Actual-cost notifications:

```text
50%  → GreaterThanOrEqualTo
80%  → GreaterThanOrEqualTo
100% → GreaterThanOrEqualTo
```

The configured notification email was present on all three thresholds.

---

## Final Terraform drift check

After Azure CLI verification, another Terraform plan was executed.

Result:

```text
No changes. Your infrastructure matches the configuration.
```

Terraform successfully refreshed the Budget together with the existing NordicShop platform resources and detected no configuration drift.

---

## Result

Budget implementation status:

```text
Design reviewed        ✅
Module created         ✅
Dev root connected     ✅
Terraform validate     ✅
Terraform plan reviewed ✅
Terraform apply        ✅
Azure CLI verification ✅
Final clean plan       ✅
```

The NordicShop development environment now has a Terraform-managed monthly Azure cost budget of 3000 DKK with Actual-cost alerts at 50%, 80%, and 100%.

The budget is an alerting and governance control, not a hard spending cap. Cost control still depends on operating the development environment responsibly, especially the AKS worker nodes.

## Exit status

```text
Terraform Budget phase: COMPLETE
```

The next step is to commit and push the Budget implementation and evidence, then review the complete Terraform foundation before deciding whether the Terraform phase is officially finished.

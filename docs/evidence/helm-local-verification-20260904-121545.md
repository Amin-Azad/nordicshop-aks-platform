# NordicShop Helm Local Verification

- Date: 2026-09-04T12:16:46+02:00
- Release: `nordicshop`
- Namespace: `nordicshop`
- Chart: `helm/nordicshop`
- Result: **PASSED**
- Passed checks: **48**
- Failed checks: **0**
- Raw log: `helm-local-verification-20260904-121545.log`

## Scope verified

- Helm release namespace and Helm ownership
- `.Release.Namespace` chart behavior
- Helm lint and render
- Kubernetes client dry-run
- Six workload readiness
- Secret and ConfigMap references
- PostgreSQL PVC/PV binding
- Customer, Vendor and Admin Ingress routes
- API health and readiness
- Customer catalog, Redis cart and checkout
- Vendor tenant isolation and cross-tenant denial
- Admin authorization
- Nordic API Pod self-healing
- PostgreSQL Pod recreation using the same PV
- Order persistence after PostgreSQL recovery
- Local secret values file not tracked by Git

## Notes

This verification intentionally creates one demonstration order and deletes/recreates the Nordic API and PostgreSQL Pods to prove reconciliation and persistence. It does not uninstall the Helm release or delete the PVC.

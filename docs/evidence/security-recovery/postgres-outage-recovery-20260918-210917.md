# NordicShop - PostgreSQL Outage Recovery Evidence

**Started:** 2026-09-18T21:09:17Z  
**Completed:** 2026-09-18T21:10:41Z  
**Environment:** AKS  
**Kubernetes context:** aks-nordicshop-dev-weu  
**Result:** **PASS**

## Baseline

- Argo: Synced/Healthy
- PostgreSQL replicas: 1
- PVC: postgres-pvc
- PVC status: Bound
- API readiness: 200
- Order count: 3
- Maximum order ID: 3
- Latest order: 3|rls-test@example.com|placed

## Controlled outage

- PostgreSQL scaled to: 0
- Outage started: 2026-09-18T21:09:30Z
- PVC during outage: Bound
- API readiness during outage: 500
- PVC deleted: no

## Recovery

- Restore started: 2026-09-18T21:09:36Z
- PostgreSQL replicas restored to: 1
- PVC after recovery: Bound
- API readiness after recovery: 200
- Order count after recovery: 3
- Maximum order ID after recovery: 3
- Latest order after recovery: 3|rls-test@example.com|placed
- Final Argo state: Synced/Healthy

## Acceptance

- Passed checks: 16
- Failed checks: 0

**Result: PASS**

The PostgreSQL StatefulSet was scaled down without deleting or modifying its PVC.
The same persistent data was verified after PostgreSQL and the API recovered.

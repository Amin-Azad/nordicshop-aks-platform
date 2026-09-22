# NordicShop Security and Recovery Acceptance

## Purpose

This document records the final security and recovery checks completed for the NordicShop AKS platform.

The goal was to prove that tenant data is protected at both the API and PostgreSQL layers, and that the platform can recover safely from controlled application and database failures.

---

## 1. PostgreSQL Row-Level Security

NordicShop originally relied mainly on API filtering for vendor isolation. PostgreSQL was then hardened so that the database also enforces tenant boundaries.

The production design now uses a restricted runtime role called `nordicshop_app`.

The role is configured with:

- `NOSUPERUSER`
- `NOBYPASSRLS`
- limited table permissions
- limited update permissions on product stock

RLS is enabled and forced on:

- `products`
- `order_lines`

The API sets PostgreSQL session context for three access modes:

- customer
- vendor
- admin

Vendor requests include the tenant ID, while customer checkout also sets the current order ID when required.

### RLS lab result

The policy was first tested in an isolated disposable PostgreSQL lab before production rollout.

Result:

- PASS: 18
- FAIL: 0

The lab verified customer, vendor and admin behavior, including cross-tenant update prevention and order-line visibility.

Evidence:

`docs/evidence/security-recovery/postgres-rls-lab-20260921-110351.md`

---

## 2. AKS Tenant Isolation

After the RLS changes were deployed to AKS, vendor isolation was tested again against the live Nordic API.

The test verified:

- API health and readiness
- Vendor A can only see tenant 1 products
- Vendor B can only see tenant 2 products
- requests without identity are rejected
- vendor access to admin endpoints is denied
- admin access works
- Vendor A cannot modify Vendor B products
- Vendor B cannot modify Vendor A products
- blocked cross-tenant attempts do not change stock

Final result:

- PASS: 11
- FAIL: 0

The final post-merge verification on `main` also passed:

- PASS: 11
- FAIL: 0

Evidence:

- initial AKS verification: `docs/evidence/security-recovery/tenant-isolation-20260918-205107.md`
- final post-hardening verification: `docs/evidence/security-recovery/tenant-isolation-20260922-093626.md`

---

## 3. Workload Identity and Secret Separation

The final hardening pass separated the API and database-administration secret paths.

The Nordic API uses:

- ServiceAccount: `nordic-api`
- managed identity: Nordic API identity
- Key Vault access: `nordicshop-app-database-url` only

PostgreSQL and the database security Job use:

- ServiceAccount: `nordicshop-db-admin`
- separate DB-admin managed identity
- Key Vault access: `postgres-password` and `postgres-app-password`

The old vault-wide `Key Vault Secrets User` assignment for the API identity was removed and replaced with per-secret RBAC.

The old shared Kubernetes Secret `nordicshop-runtime-secret` was checked for references and deleted after the new split was live.

Final tenant-isolation verification after this change:

- PASS: 11
- FAIL: 0

---

## 4. Customer Cross-Vendor Checkout

The customer checkout path was tested after RLS was enabled.

A cart was created with products from both vendors:

- product 1 from tenant 1
- product 5 from tenant 2

The cart total was calculated correctly and checkout succeeded.

The resulting order was:

- order ID: 3
- status: placed
- items: 2

This confirmed that customer checkout can work across multiple vendors while vendor isolation remains enforced.

The same order was later used during the PostgreSQL recovery test to confirm data persistence.

---

## 5. GitOps Invalid Image Recovery

A controlled GitOps failure was created by changing the Nordic API image in Git to a deliberately invalid image tag.

The recovery flow was:

1. commit invalid API image to Git
2. Argo CD detects the desired-state change
3. AKS attempts the new rollout
4. image pull failure is detected
5. the bad Git commit is reverted
6. Argo CD reconciles the cluster
7. the original immutable API image is restored
8. the application returns to a healthy state

The failure was introduced and recovered only through Git. The Deployment was not manually repaired with `kubectl set image`.

Result:

- failure detected: yes
- recovered: yes
- original API image restored: yes
- final Argo state: healthy
- result: PASS

Evidence:

`docs/evidence/security-recovery/invalid-api-image-recovery-20260918-205937.md`

---

## 6. PostgreSQL Outage and Recovery

A controlled PostgreSQL outage was created by scaling the PostgreSQL StatefulSet from 1 replica to 0.

The PVC was not deleted or modified.

Before the outage:

- PostgreSQL replicas: 1
- PVC `postgres-pvc`: Bound
- API readiness: 200
- order count: 3
- maximum order ID: 3
- latest order: order 3, `rls-test@example.com`, placed

During the outage:

- PostgreSQL Pod was stopped
- PVC remained Bound
- API readiness returned 500

After restoration:

- PostgreSQL returned to Ready
- PVC remained Bound
- order count remained 3
- maximum order ID remained 3
- latest order data was unchanged
- API readiness recovered to 200
- Argo CD returned to Synced / Healthy

Final result:

- PASS: 16
- FAIL: 0

Evidence:

`docs/evidence/security-recovery/postgres-outage-recovery-20260918-210917.md`

---

## 7. Final Platform State

After all security and recovery tests were completed, the final platform state was checked again.

Final state:

- Git branch: `main`
- Git working tree: clean
- Argo CD: Synced / Healthy
- PostgreSQL Pod: 1/1 Running
- PostgreSQL PVC: Bound
- API tenant isolation: PASS
- API / DB-admin workload identities: separated
- old shared runtime Secret: removed
- PostgreSQL RLS: active
- GitOps rollback: PASS
- PostgreSQL recovery: PASS

The PostgreSQL PVC remained the same persistent volume during the database outage test.

---

## Final Result

The NordicShop platform passed the planned security and recovery acceptance checks.

The platform now demonstrates:

- API-level tenant authorization
- PostgreSQL row-level security
- restricted database runtime permissions
- separate API and DB-admin workload identities
- secret-scoped Key Vault RBAC
- cleanup of the old shared runtime Secret
- vendor cross-tenant protection
- working multi-vendor customer checkout
- GitOps-controlled rollback and recovery
- StatefulSet recovery without PVC loss
- persistent order data after PostgreSQL outage
- final healthy reconciliation through Argo CD

**Overall result: PASS**

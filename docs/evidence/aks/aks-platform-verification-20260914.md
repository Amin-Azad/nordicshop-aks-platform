# NordicShop AKS Platform Verification

Date: 2026-09-14

This document summarizes the functional, isolation, recovery, persistence, and Gateway API verification completed against the NordicShop development AKS environment.

## Environment

- Kubernetes namespace: `nordicshop`
- Helm release: `nordicshop`
- Helm chart version: `0.1.0`
- Final verified Helm revision: `7`
- Gateway controller: AKS Application Routing / Istio
- Public IP: `20.73.231.149`

## Customer Journey

Result: **PASS**

Verified:

- API health endpoint
- API readiness endpoint
- seeded product catalogue
- cart creation
- multiple cart items
- order checkout
- generated order ID
- cart empty after checkout
- order persisted to PostgreSQL
- order lines persisted for products belonging to different vendor tenants

Test order:

- Order ID: `1`
- Customer: `AKS Customer Test`
- Product 1: Harbour Wool Throw x1
- Product 6: Forest Notebook x2
- Total: `947 DKK`

## Vendor Isolation

Result: **PASS — 16 PASS / 0 FAIL**

Verified:

- Vendor A resolves to tenant 1
- Vendor B resolves to tenant 2
- each vendor sees only its own products
- vendor product sets are disjoint
- vendors see only their own order lines
- Vendor A can update its own stock
- Vendor A cannot update Vendor B stock
- Vendor B cannot update Vendor A stock
- cross-tenant stock operations returned HTTP 404
- stock was restored after testing

The browser vendor portal uses seeded Vendor A for the demo user experience. Vendor B isolation remains verified through the automated test suite.

## Admin Authorization

Result: **PASS — 15 PASS / 0 FAIL**

Verified:

- seeded admin can access marketplace summary
- seeded admin can access vendors
- seeded admin can access orders
- test order 1 is visible to admin
- Vendor A receives HTTP 403 for admin endpoints
- Vendor B receives HTTP 403 for admin endpoints
- requests without identity receive HTTP 401

## API Self-Healing

Result: **PASS — 11 PASS / 0 FAIL**

Verified:

- running API Pod was identified
- API Pod was deliberately deleted
- Kubernetes created a replacement Pod
- replacement Pod had a different UID
- Deployment returned to Ready state
- public health endpoint remained functional
- public readiness endpoint remained functional

## Redis Cart Persistence

Result: **PASS — 13 PASS / 0 FAIL**

Verified:

- cart created through the API
- cart stored product quantity and total
- API Pod was deliberately deleted
- Kubernetes created a replacement API Pod
- the same cart remained available after the API restart
- cart total remained unchanged

A first test-script run incorrectly expected HTTP 200 from the cart-create operation. The API correctly returns HTTP 201. The test was corrected and rerun successfully.

## PostgreSQL Persistence

Result: **PASS — 14 PASS / 0 FAIL**

Verified:

- PostgreSQL Pod `postgres-0` was identified
- existing order 1 and its order lines were confirmed
- PostgreSQL Pod was deleted
- StatefulSet recreated the PostgreSQL Pod
- new Pod had a different UID
- PVC name remained unchanged
- PVC UID remained unchanged
- PersistentVolume remained unchanged
- PVC remained Bound
- order 1 remained available
- associated order lines remained available

The PostgreSQL PVC was never deleted during the persistence test.

## PostgreSQL Startup Observation

During the first cold deployment, the API restarted several times while PostgreSQL was still starting.

Kubernetes recovered automatically once PostgreSQL became available.

This identifies a startup dependency/race condition that may later be improved with stronger startup handling, but it did not prevent successful platform recovery.

## Gateway API

Result: **PASS**

Gateway:

- `nordicshop-gateway`

HTTPRoute:

- `nordicshop-routes`
- `Accepted=True`
- `ResolvedRefs=True`
- no route events/errors

Verified public routing:

- `/` -> HTTP 200
- `/vendor` -> HTTP 308 -> `/vendor/`
- `/vendor/` -> HTTP 200
- `/admin` -> HTTP 308 -> `/admin/`
- `/admin/` -> HTTP 200
- `/api/health` -> healthy
- `/api/ready` -> ready

The Vendor and Admin exact paths are redirected by Gateway API before prefix rewriting.

## Ingress Cleanup

Result: **PASS**

The legacy Kubernetes Ingress resources were removed after Gateway API verification.

Final check:

```text
kubectl get ingress -n nordicshop
No resources found in nordicshop namespace.
```

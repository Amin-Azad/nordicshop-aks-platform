# NordicShop Kubernetes Production Controls Verification

Date: 2026-09-16

## Scope

This verification covered the production Kubernetes controls added to the NordicShop AKS deployment:

- CPU and memory requests/limits
- readiness and liveness probes
- PostgreSQL readiness
- API startup dependency handling
- API Horizontal Pod Autoscaler
- API PodDisruptionBudget
- runtime application verification
- Workload Identity / Key Vault sanity checks
- NetworkPolicy design and current enforcement limitation

## Helm release

Final verified release:

- Release: nordicshop
- Namespace: nordicshop
- Revision: 15
- Status: deployed

## Resource requests and limits

Verified live pod resources:

| Workload | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---|---:|---:|---:|---:|
| Admin Portal | 25m | 32Mi | 100m | 128Mi |
| Nordic API | 100m | 128Mi | 500m | 512Mi |
| Customer Web | 25m | 32Mi | 100m | 128Mi |
| Vendor Portal | 25m | 32Mi | 100m | 128Mi |
| PostgreSQL | 100m | 256Mi | 500m | 512Mi |
| Redis | 50m | 64Mi | 250m | 256Mi |

The two API replicas were both running with the expected resource settings.

## Health probes

### Nordic API

- readiness: `/api/ready`
- liveness: `/api/health`

### Customer / Vendor / Admin

- readiness: HTTP `/`
- liveness: HTTP `/`

### Redis

- readiness: `redis-cli ping`
- liveness: `redis-cli ping`

### PostgreSQL

- readiness: `pg_isready`

## API startup dependency

During revision 14 rollout, one Nordic API Pod restarted because the application started before PostgreSQL was accepting connections.

The failure was confirmed from previous container logs as a PostgreSQL connection refused error during FastAPI startup.

A `wait-for-postgres` init container was added to the API Deployment.

The init container uses `pg_isready` and prevents the API container from starting until PostgreSQL is available.

Revision 15 verification:

- API replicas: 2
- both Running
- both Ready
- both with 0 restarts

## Horizontal Pod Autoscaler

Nordic API HPA:

- minimum replicas: 2
- maximum replicas: 4
- CPU target: 70%
- current replicas: 2
- HPA metric successfully calculated from CPU request

The HPA reported `ScalingActive=True` and `ValidMetricFound`.

## PodDisruptionBudget

Nordic API PDB:

- `minAvailable: 1`
- current allowed disruptions: 1

The PDB is meaningful because the API runs with a minimum of two replicas.

## Application runtime verification

The AKS Gateway public address successfully returned:

- Customer storefront: HTTP 200
- Vendor Portal: HTTP 200
- Admin Portal: HTTP 200

`/api/products` also returned the seeded NordicShop product list through the public request path.

This verifies:

Gateway -> Frontend -> Nordic API -> PostgreSQL

## Redis and PostgreSQL connectivity

From a running Nordic API Pod:

- Redis TCP connection to `redis:6379`: successful
- PostgreSQL DNS resolution: successful
- PostgreSQL TCP connection to `postgres:5432`: successful

## Rollout verification

Successful rollout status was confirmed for:

- Nordic API
- Customer Web
- Vendor Portal
- Admin Portal
- Redis
- PostgreSQL StatefulSet

## Workload Identity and Key Vault

Both API Pods showed:

- ServiceAccount: `nordic-api`
- `azure.workload.identity/use=true`
- Azure client ID injected
- `secretProviderClass=nordicshop-keyvault`

This confirms the API workload continued using the existing Workload Identity and Key Vault CSI integration after the production-control changes.

## NetworkPolicy

NetworkPolicy manifests were created for:

- Gateway -> frontends
- frontends -> Nordic API
- Nordic API -> PostgreSQL
- Nordic API -> Redis

The policies are currently gated by:

`networkPolicy.enabled: false`

Reason:

The current AKS cluster uses Azure CNI Overlay but does not have an active NetworkPolicy enforcement engine.

A migration to Cilium was attempted through Terraform.

The desired change was:

- network dataplane: Azure -> Cilium
- network policy: Cilium

Terraform showed an in-place AKS update with no cluster replacement.

The migration could not proceed because AKS required a temporary surge node and the subscription only had 2 remaining regional vCPUs while the Standard_D4s_v4 surge node required 4 vCPUs.

Quota increase for the DSv4 family was not available for this subscription.

The current cluster therefore remains unchanged and Terraform has been returned to the actual deployed state.

The NetworkPolicy manifests remain in the Helm chart but are intentionally disabled until the platform can enforce them.

## Final status

Verified:

- resources and limits
- workload probes
- API startup ordering
- API minimum two replicas
- HPA
- PDB
- application routing
- Redis/PostgreSQL connectivity
- Workload Identity / Key Vault continuity

Pending platform prerequisite:

- Cilium-enabled AKS
- NetworkPolicy runtime enforcement tests

# NordicShop AKS Platform

NordicShop is a small multi-tenant marketplace that I use to build and test an Azure Kubernetes platform end to end.

The application is intentionally simple. The main work in this repository is the platform around it: Terraform, AKS, Helm, GitHub Actions, Argo CD, Workload Identity, Key Vault, monitoring, tenant isolation and recovery testing.

The current development environment runs on Azure AKS in West Europe. Infrastructure is managed with Terraform, application workloads are packaged with Helm, and Argo CD keeps the cluster aligned with the desired state in Git.

## Architecture

![NordicShop platform architecture](docs/architecture/diagrams/01-full-platform-architecture.png)

The main request path is:

```text
Internet
   |
Azure Load Balancer / public entry point
   |
AKS Gateway / routing
   |
   +----------------+----------------+----------------+
   |                |                |
Customer Web    Vendor Portal    Admin Portal
   \                |                /
    \               |               /
             Nordic API
              /      \
             /        \
      PostgreSQL     Redis
```

The platform around the application includes:

```text
GitHub
  |
GitHub Actions
  |
Azure OIDC
  |
ACR
  |
image digest update in Git
  |
Argo CD
  |
Helm release
  |
AKS
```

Azure infrastructure is created separately with Terraform:

```text
Resource Group
├── VNet and subnets
├── AKS
├── Azure Container Registry
├── Key Vault
├── Managed Identities
├── Azure RBAC
├── Federated Identity Credentials
├── Log Analytics
├── Azure Monitor Workspace
├── Managed Grafana
├── diagnostics
└── budget controls
```

More detail is in [`docs/architecture/Architecture_Brief.md`](docs/architecture/Architecture_Brief.md).

## Application

NordicShop currently has six main workloads:

- `customer-web` — product catalogue, cart and checkout
- `vendor-portal` — tenant-scoped products, stock updates and order lines
- `admin-portal` — marketplace-wide admin views
- `nordic-api` — FastAPI backend
- `postgres` — persistent application data
- `redis` — cart and temporary shared state

The three frontends are small static applications served by Nginx. They call the shared FastAPI backend through `/api/*`.

The application is multi-tenant at the vendor layer. Vendor requests are scoped by tenant, and PostgreSQL Row-Level Security is also used so tenant isolation does not depend only on API filtering.

## What is implemented

At this point the repository contains the working platform rather than placeholders for future work.

### Azure and Terraform

The development environment is built from reusable Terraform modules under `infra/`.

The current Terraform layer covers:

- resource group
- networking
- AKS
- Azure Container Registry
- managed identities
- Azure RBAC
- Key Vault
- GitHub OIDC federation
- monitoring and diagnostics
- budget controls

Terraform state is kept outside the workload resource group in a separate Azure Storage backend.

### Kubernetes and Helm

The application is packaged as a Helm chart under:

```text
helm/nordicshop/
```

The chart manages the application Deployments and Services together with PostgreSQL, Redis, configuration, security objects and routing-related resources.

The earlier hand-written local Kubernetes manifests are still under `kubernetes/local/`. I kept them because they show the progression from direct Kubernetes YAML to the Helm-based deployment used by the AKS environment.

### Cilium NetworkPolicy status

NordicShop is designed to use Cilium-backed Kubernetes NetworkPolicies to restrict application traffic between workloads.

The Helm chart already contains NetworkPolicy definitions for:

- Customer, Vendor and Admin frontends
- Nordic API
- PostgreSQL
- Redis

The policies are currently controlled through:

```yaml
networkPolicy:
  enabled: false
```

NetworkPolicy enforcement is intentionally disabled at the moment.

The planned AKS migration to Cilium could not be completed because the Azure subscription did not have enough available regional vCPU quota for the additional node capacity required during the AKS networking upgrade.

The existing AKS cluster was therefore left on its current networking configuration instead of forcing a partial or unsafe migration.

Because the Cilium migration is not complete, NordicShop does not currently claim active Kubernetes NetworkPolicy enforcement.

The existing NetworkPolicy templates are retained as the intended production-style configuration and should only be enabled after the AKS networking migration has completed successfully.

Before chainging:  

```yaml
networkPolicy:
  enabled: true
  ```

all of the following conditions must be met:

AKS has been successfully migrated to Cilium.
Sufficient Azure regional vCPU quota and capacity are available to complete the required node-pool upgrade safely.
The Cilium networking configuration is healthy.
Gateway-to-frontend traffic works correctly.
Gateway-to-API routing works correctly where required.
Customer, Vendor and Admin application flows continue to work.
Nordic API can reach PostgreSQL.
Nordic API can reach Redis.
Required database security or migration jobs can reach PostgreSQL.
Allowed pod-to-pod traffic paths are verified.
Explicit denied-path tests confirm that unwanted traffic is blocked.
The full NordicShop smoke tests and tenant-isolation tests pass after enforcement is enabled.

Until these checks pass, networkPolicy.enabled must remain false.

This is a known platform limitation caused by Azure quota constraints, not an indication that NetworkPolicy was removed from the architecture.

### CI/CD and GitOps

GitHub Actions is used to build and publish the four custom application images.

The image workflow:

```text
source change
   |
GitHub Actions
   |
test and build
   |
Azure login with OIDC
   |
push images to ACR
   |
capture immutable digests
   |
update Helm values
   |
Git change / review
   |
Argo CD reconciliation
```

The AKS deployment uses immutable ACR digests rather than relying only on mutable tags.

Argo CD watches Git and reconciles the NordicShop Helm release. I intentionally keep image publishing and cluster reconciliation as separate responsibilities: GitHub Actions publishes artifacts, while Argo CD deploys the desired state from Git.

## Identity and secrets

I did not use one Azure identity for everything.

The main identity boundaries are:

- local Terraform identity
- GitHub Actions managed identity
- AKS cluster identity
- AKS kubelet identity
- Nordic API workload identity

GitHub Actions authenticates to Azure through OIDC instead of a stored Azure client secret.

The Nordic API uses AKS Workload Identity to reach Azure Key Vault:

```text
Nordic API Pod
   |
Kubernetes ServiceAccount
   |
projected service account token
   |
AKS OIDC issuer
   |
federated identity credential
   |
Nordic API managed identity
   |
Azure Key Vault
```

The kubelet identity has the ACR pull permission needed by the cluster. Application workloads do not reuse the kubelet or cluster identity for Key Vault access.

## PostgreSQL tenant isolation

Vendor isolation is enforced in two places.

The API performs authorization and tenant checks, and PostgreSQL independently applies Row-Level Security.

The API performs role, tenant and object-level authorization before database access.

PostgreSQL Row-Level Security provides an additional defence-in-depth layer for the vendor-owned `products` and `order_lines` tables. The API sets transaction-local PostgreSQL context such as `app.access_mode`, `app.tenant_id` and `app.order_id`, and the RLS policies use that context to restrict the rows available to the current request.

The application runtime database role, `nordicshop_app`, is intentionally restricted. It is not a superuser, cannot bypass RLS and receives only the table and column privileges required by the application.

RLS in this project is intended to protect against application query mistakes, such as a missing tenant filter. It is not treated as an independent authentication boundary against a compromised application process or an attacker who already possesses the runtime database credentials, because the trusted API is responsible for setting the PostgreSQL request context.

Customer checkout is allowed to decrement the `stock` column for products from multiple vendors because one order may contain items from more than one vendor. The runtime role has column-level permission only for `products.stock`; it cannot use this permission to modify protected product fields such as the product name or tenant ownership.

Production user authentication is intentionally outside the scope of this portfolio application. `X-Demo-User` selects seeded demonstration identities so the project can exercise vendor authorization, tenant isolation, administrator access and the surrounding AKS platform without building a production identity system.

## Monitoring

The AKS environment uses Azure Managed Prometheus and Azure Managed Grafana.

The repository includes three Grafana dashboards:

```text
monitoring/grafana/dashboards/
├── nordicshop-application.json
├── nordicshop-namespace-health.json
└── nordicshop-gitops-delivery.json
```

The current alert rules include:

- NordicShop API unavailable
- replica availability degraded
- Argo CD unhealthy
- high 5xx error rate

Alerts are connected to an Azure Monitor Action Group.

I also tested the alert path by creating a controlled GitOps drift condition. The Argo CD alert fired through Managed Prometheus and Azure Monitor and reached the configured email receiver.

## Verification

I keep the detailed evidence under `docs/evidence/`, but these are the main results that matter.

| Check | Result |
| --- | --- |
| PostgreSQL RLS lab | 18 passed / 0 failed |
| AKS tenant isolation | 11 passed / 0 failed |
| Cross-vendor customer checkout | Passed |
| PostgreSQL outage recovery | 16 passed / 0 failed |
| Invalid API image GitOps recovery | Passed |
| PostgreSQL PVC persistence | Passed |
| Argo CD final state | Synced / Healthy |
| Managed alert delivery | Passed |

The final security and recovery summary is here:

[`docs/evidence/security-recovery/NordicShop_Security_and_Recovery_Acceptance.md`](docs/evidence/security-recovery/NordicShop_Security_and_Recovery_Acceptance.md)

## Recovery tests

I wanted the project to show what happens when something actually fails, not only that the happy path works.

### Invalid API image

For the image recovery test I committed a deliberately invalid Nordic API image reference.

The flow was:

```text
bad image in Git
   |
Argo CD detects the change
   |
AKS starts a new rollout
   |
image pull fails
   |
failure is detected
   |
Git revert
   |
Argo CD reconciles again
   |
original image is restored
```

The Deployment was not repaired manually with `kubectl set image`. Recovery happened through the Git desired state.

### PostgreSQL outage

For the database recovery test I scaled the PostgreSQL StatefulSet from `1` to `0`.

During the outage:

- the PostgreSQL Pod stopped
- the PVC stayed `Bound`
- API readiness returned `500`

After restoring PostgreSQL:

- `postgres-0` returned to `Ready`
- the same PVC remained attached
- order count stayed unchanged
- the latest order was still present
- API readiness returned to `200`
- Argo CD returned to `Synced / Healthy`

No PVC was deleted during the test.

## Repository layout

The main directories are:

```text
.
├── .github/workflows/          GitHub Actions
├── application/
│   ├── apps/                   three frontend applications
│   ├── database/               PostgreSQL security SQL
│   ├── services/nordic-api/    FastAPI backend
│   └── tests/                  application tests
├── docs/
│   ├── architecture/           architecture brief and diagrams
│   └── evidence/               verification records
├── gitops/                     Argo CD configuration
├── helm/nordicshop/            Helm chart used by AKS
├── infra/
│   ├── bootstrap/              Terraform backend bootstrap
│   ├── environments/dev/       development root module
│   └── modules/                reusable Azure modules
├── kubernetes/local/           earlier local Kubernetes manifests
├── monitoring/                 Grafana dashboards and alert notes
├── scripts/                    verification/helper scripts
└── tests/
    ├── aks/                    AKS functional and recovery tests
    └── security/               RLS, tenant isolation and recovery tests
```

## Running the application locally

The full local stack can be started with Docker Compose:

```bash
docker compose up -d
```

Check the services:

```bash
docker compose ps
```

Useful local endpoints are:

```text
Customer Web   http://localhost:8081
Vendor Portal  http://localhost:8082
Admin Portal   http://localhost:8083
Nordic API     http://localhost:8000
API docs       http://localhost:8000/docs
```

Stop the stack with:

```bash
docker compose down
```

The PostgreSQL named volume is intentionally kept unless volumes are explicitly removed.

## Running application tests

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate

python -m pip install -r application/services/nordic-api/requirements.txt
python -m pytest -q application/tests
```

## Helm checks

Validate the chart:

```bash
helm lint helm/nordicshop
```

Render the development configuration:

```bash
helm template nordicshop helm/nordicshop \
  --namespace nordicshop \
  -f helm/nordicshop/values-dev.yaml
```

There is also a local verification script:

```bash
./scripts/verify-helm-local.sh
```

## Terraform

The development environment is under:

```text
infra/environments/dev/
```

A normal validation flow is:

```bash
cd infra/environments/dev

terraform fmt -recursive ../../
terraform validate
terraform plan
```

I do not keep `terraform.tfvars`, state files or plan files in Git.

The Terraform modules are intentionally split by responsibility rather than putting all Azure resources into one large file.

## AKS checks I use most often

Connect to the cluster first, then:

```bash
kubectl get nodes
kubectl get pods -n nordicshop
kubectl get pvc -n nordicshop
kubectl get application nordicshop -n argocd
```

For the current healthy environment I expect the Argo CD application to end at:

```text
Synced   Healthy
```

The security and recovery tests are under:

```text
tests/security/
```

For example:

```bash
./tests/security/tenant-isolation-aks.sh
./tests/security/invalid-api-image-recovery.sh
./tests/security/postgres-outage-recovery.sh
```

The recovery scripts intentionally make changes to the live development environment. I only run them against the dev cluster and with a clean baseline.

## Design choices

A few decisions in this repository are deliberate compromises because this is a single-engineer project and a learning environment.

PostgreSQL and Redis are currently inside AKS. That gives me direct experience with StatefulSets, PVCs, service discovery and dependency recovery. For a commercial production system I would seriously consider Azure Database for PostgreSQL and a managed Redis service instead.

The AKS environment is not designed as a fully private enterprise platform. The network layout keeps room for future private endpoints, but I did not add Private Link everywhere just to make the diagram more complicated.

I also kept the application small on purpose. Splitting the backend into many microservices would add operational work without helping the main goal of this repository, which is learning and proving the platform layer.

The project has changed a lot while I built it, so some older local manifests and test assets remain in the repository when they still explain the path to the current design. I remove intermediate notes and duplicate evidence when they no longer add anything useful.

## Current state

The main development platform is working end to end:

```text
Terraform
   |
Azure infrastructure
   |
AKS
   |
Helm
   |
Argo CD
   |
NordicShop workloads
   |
Managed Prometheus / Grafana
```

The main security and recovery checks have also been completed.

There is still more I can harden later—backup strategy, stricter production networking, branch protection, additional policy controls and a fuller production-readiness review—but I prefer to keep those as explicit next steps rather than claim they are already solved.

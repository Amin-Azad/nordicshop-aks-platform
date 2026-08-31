# NordicShop AKS Platform

NordicShop is a small multi-tenant marketplace workload built for a learning-led Azure Kubernetes Service platform project.

The repository separates the application workload from the platform implementation so each learning phase is easy to understand.

## Current application baseline

The application lives under `application/`:

- Customer Web: catalogue, cart and demonstration checkout
- Vendor Portal: tenant-scoped products, stock updates and order lines
- Admin Portal: marketplace overview and vendor status control
- Nordic API: Python FastAPI backend
- SQLite development database with deterministic seed data
- PostgreSQL Row-Level Security policy prepared for the later PostgreSQL environment
- In-memory development cart adapter, ready to be replaced by Redis
- API, journey and tenant-isolation tests

PostgreSQL and Redis official images have now been tested separately, but they are not connected to Nordic API yet. That will happen in the Docker Compose phase.

## Application architecture

NordicShop has three frontend applications and one shared backend API. It is not split into business microservices.

```text
Customer Web ──┐
Vendor Portal ─┼── HTTP /api/* ──> Nordic API
Admin Portal ──┘                     │
                                     ├── SQLite now → PostgreSQL later
                                     └── In-memory cart now → Redis later
```

### Components

- **Customer Web** provides product browsing, cart and demonstration checkout.
- **Vendor Portal** uses the same API but only receives data for the signed-in vendor's `tenant_id`.
- **Admin Portal** uses admin API routes for marketplace-wide demonstration data.
- **Nordic API** contains the FastAPI routes, authorization checks, business logic and database access.
- **SQLite** is still the current development database.
- **CartStore** still keeps cart data in Python memory.

The three frontends and Nordic API are now separate container images. Nordic API no longer serves the frontend folders itself.

## Container images

The current container phase has verified these images individually:

- `nordicshop-api:prod`
- `nordicshop-customer-web:prod`
- `nordicshop-vendor-portal:prod`
- `nordicshop-admin-portal:prod`
- `postgres:18.6-alpine`
- `redis:8.10.1-alpine`

The custom images run as non-root users. PostgreSQL and Redis were also checked at runtime to confirm their actual server processes run as restricted users.

A short record of the checks is in `docs/evidence/container-images.md`.

## Repository structure

```text
application/
  apps/
    customer-web/
    vendor-portal/
    admin-portal/
  services/
    nordic-api/
  database/
  shared/
  tests/
infra/
  bootstrap/
  environments/dev/
  modules/
helm/nordicshop/
gitops/argocd/
monitoring/
tests/security/
docs/
  adr/
  evidence/
  runbooks/
.github/workflows/
```

The root `tests/security/` directory is reserved for later platform-level security acceptance tests. The current application tests live under `application/tests/`.

The empty platform folders are deliberate placeholders for later phases. Terraform, Kubernetes, Helm, Argo CD and monitoring have not been implemented yet.

## Run Nordic API locally

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r application/services/nordic-api/requirements.txt
python -m uvicorn --app-dir application/services/nordic-api app.main:app --reload --port 8000
```

Useful endpoints:

- API root: `http://127.0.0.1:8000/`
- Health: `http://127.0.0.1:8000/api/health`
- Readiness: `http://127.0.0.1:8000/api/ready`
- API documentation: `http://127.0.0.1:8000/docs`

The frontends are now separate from the API. Their full local integration will be added with Docker Compose rather than being served by FastAPI.

## Run tests

```bash
python -m pytest -q application/tests
```

Current result: `7 passed`.

## Current boundary

Production Dockerfiles for the four custom application images are complete and individually verified. Docker Compose, Kubernetes, Helm, Terraform, GitHub deployment workflows and Argo CD are still future phases.

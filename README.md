# NordicShop AKS Platform

NordicShop is a small multi-tenant marketplace workload built for a learning-led Azure Kubernetes Service platform project.

The repository separates the application workload from the platform implementation so each learning phase is easy to understand.

## Current application baseline

The tested local application baseline lives under `application/`:

- Customer Web: catalogue, cart and demonstration checkout
- Vendor Portal: tenant-scoped products, stock updates and order lines
- Admin Portal: marketplace overview and vendor status control
- Nordic API: Python FastAPI backend
- SQLite development database with deterministic seed data
- PostgreSQL Row-Level Security policy for the later PostgreSQL environment
- In-memory development cart adapter, ready to be replaced by Redis during the Docker phase
- API, journey and tenant-isolation tests

PostgreSQL and Redis are not yet the active local runtime dependencies. They are introduced during the container-learning phase. The included PostgreSQL RLS SQL is therefore a planned database control, not something the current SQLite tests claim to execute.

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
- **SQLite** is the current local persistent database. PostgreSQL will replace it in the container environment.
- **CartStore** currently keeps cart data in Python memory. Redis will replace it so cart state can be shared across API replicas.

In the current local baseline, FastAPI also serves the three frontend folders as static files. During containerization the frontends will become separate containers and Nordic API will remain the shared backend service.

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

## Run locally

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r application/services/nordic-api/requirements.txt
python -m uvicorn --app-dir application/services/nordic-api app.main:app --reload --port 8000
```

Open:

- Customer Web: http://127.0.0.1:8000/
- Vendor Portal: http://127.0.0.1:8000/vendor/
- Admin Portal: http://127.0.0.1:8000/admin/
- API documentation: http://127.0.0.1:8000/docs

Demo identities are selected inside the Vendor and Admin interfaces. They are development identities only, not production authentication.

## Run tests

```bash
python -m pytest -q application/tests
```

The repository-layout version of the application was retested after moving the files into their planned folders: `7 passed`.

## Current boundary

There are no production Dockerfiles, final Docker Compose environment, Kubernetes manifests, Helm implementation, Terraform modules, GitHub deployment workflow or Argo CD configuration yet. Those will be created step by step during the platform learning work.
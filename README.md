# NordicShop AKS Platform

NordicShop is a small multi-tenant marketplace workload built for a learning-led Azure Kubernetes Service platform project.

The application is intentionally limited so the main project can focus on Docker, Terraform, AKS, Kubernetes, Helm, identity, GitOps, observability and recovery.

## Current application baseline

The repository currently contains the tested local application baseline:

- Customer Web: catalogue, cart and demonstration checkout
- Vendor Portal: tenant-scoped products, stock updates and order lines
- Admin Portal: marketplace overview and vendor status control
- Nordic API: Python FastAPI backend
- SQLite development database with deterministic seed data
- PostgreSQL Row-Level Security policy for the later PostgreSQL environment
- In-memory development cart adapter, ready to be replaced by Redis during the Docker phase
- API, journey and tenant-isolation tests

PostgreSQL and Redis are not yet the active local runtime dependencies. They are introduced during the container-learning phase. The included PostgreSQL RLS SQL is therefore a planned database control, not something the current SQLite tests claim to execute.

## Repository structure

```text
apps/
  customer-web/
  vendor-portal/
  admin-portal/
services/
  nordic-api/
database/
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

The empty platform folders are deliberate placeholders for later phases. Terraform, Kubernetes, Helm, Argo CD and monitoring have not been implemented yet.

## Run locally

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r services/nordic-api/requirements.txt
python -m uvicorn --app-dir services/nordic-api app.main:app --reload --port 8000
```

Open:

- Customer Web: http://127.0.0.1:8000/
- Vendor Portal: http://127.0.0.1:8000/vendor/
- Admin Portal: http://127.0.0.1:8000/admin/
- API documentation: http://127.0.0.1:8000/docs

Demo identities are selected inside the Vendor and Admin interfaces. They are development identities only, not production authentication.

## Run tests

```bash
python -m pytest -q
```

The repository-layout version of the application was retested after moving the files into their planned folders: `7 passed`.

## Current boundary

There are no production Dockerfiles, final Docker Compose environment, Kubernetes manifests, Helm implementation, Terraform modules, GitHub deployment workflow or Argo CD configuration yet. Those will be created step by step during the platform learning work.

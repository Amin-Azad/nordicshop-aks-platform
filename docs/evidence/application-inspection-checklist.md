# NordicShop Application Inspection Checklist

**Project:** NordicShop AKS Platform  
**Purpose:** Record the application handover inspection completed before Docker/container work.

**Method:** Inspect → verify → explain → then containerize.

---

## 1. What application components were handed over?

```bash
find application -maxdepth 4 -type d | sort
find application -maxdepth 4 -type f | sort
tree application -L 4 -a -I '__pycache__|*.pyc'
```

### output

```text
application/apps/admin-portal
application/apps/customer-web
application/apps/vendor-portal
application/database/postgresql_rls.sql
application/services/nordic-api/app
application/services/nordic-api/requirements.txt
application/shared
application/tests/test_api.py
```

NordicShop contains three thin browser interfaces, one FastAPI backend, database/RLS preparation, shared frontend assets and application tests.

---

## 2. Which component calls which?

```bash
grep -Rni "fetch(" application/apps
grep -Rni "/api/" application/apps
grep -Rni '@app\.' application/services/nordic-api
sed -n '1,220p' application/services/nordic-api/app/main.py
```

### output

```text
Customer Web:
  /api/products
  /api/cart/...
  /api/orders

Vendor Portal:
  /api/vendor/me
  /api/vendor/products
  /api/vendor/orders

Admin Portal:
  /api/admin/summary
  /api/admin/vendors
  /api/admin/orders
```

```text
@app.get("/api/products")
@app.get("/api/vendor/products")
@app.get("/api/admin/vendors")
```

The three browser interfaces call Nordic API over HTTP using `/api/...` routes. Nordic API then uses its database layer and cart store.

---

## 3. What port does NordicShop use?

```bash
grep -Rni "8000" README.md application
ss -lntp | grep 8000
```

### output

```text
README.md:62:python -m uvicorn --app-dir application/services/nordic-api app.main:app --reload --port 8000
README.md:67:- Customer Web: http://127.0.0.1:8000/
README.md:68:- Vendor Portal: http://127.0.0.1:8000/vendor/
README.md:69:- Admin Portal: http://127.0.0.1:8000/admin/
README.md:70:- API documentation: http://127.0.0.1:8000/docs
```

```text
LISTEN ... 127.0.0.1:8000 ...
```

Nordic API listens locally on TCP port `8000`.

---

## 4. What command starts the application?

```bash
grep -Rni "uvicorn" .
grep -n -A12 -B5 "Run locally" README.md
```

### output

```text
python -m uvicorn --app-dir application/services/nordic-api app.main:app --reload --port 8000
```

Uvicorn runs the FastAPI application. `--reload` is used only for local development.

---

## 5. What are the health and readiness endpoints?

```bash
curl http://127.0.0.1:8000/api/health
curl http://127.0.0.1:8000/api/ready
```

### output

```text
{"status":"ok","service":"nordic-api"}
```

```text
{"status":"ready"}
```

Relevant code:

```python
@app.get("/api/health")
def health():
    return {"status": "ok", "service": "nordic-api"}

@app.get("/api/ready")
def ready(db: Session = Depends(get_db)):
    db.scalar(select(func.count(Tenant.id)))
    return {"status": "ready"}
```

`/api/health` proves the API process can answer HTTP. `/api/ready` also performs a database query, so it proves the application can currently reach its database.

---

## 6. What runtime dependencies are required?

```bash
cat application/services/nordic-api/requirements.txt
grep -R '^import\|^from' application/services/nordic-api/app
python -m pip list
```

### output

```text
fastapi==0.141.1
uvicorn==0.52.4
sqlalchemy==2.0.52
psycopg[binary]==3.3.4
redis==8.1.0
httpx==0.28.1
pytest==9.1.1
email-validator==2.3.0
```

FastAPI, Uvicorn, SQLAlchemy and email validation are active application dependencies. Psycopg and Redis are installed for later PostgreSQL/Redis work; httpx and pytest support testing.

---

## 7. What environment variables does the application use?

```bash
grep -Rni "os.getenv" application
grep -RniE 'getenv|environ|process\.env|ENV\[' application
cat application/services/nordic-api/app/database.py
```

### output

```text
DATABASE_URL = os.getenv("NORDICSHOP_DATABASE_URL", "sqlite:///./nordicshop.db")
```

Test override:

```text
os.environ["NORDICSHOP_DATABASE_URL"] = f"sqlite:///{TEST_DB}"
```

`NORDICSHOP_DATABASE_URL` controls the database connection. If it is not supplied, NordicShop defaults to a local SQLite database.

---

## 8. What secrets are required now?

```bash
grep -RniE 'password|secret|token|api_key|apikey|credential|private_key' application
find . -name '.env*' -o -iname '*secret*' -o -iname '*credential*'
git grep -iE 'password|secret|token|api[_-]?key'
```

### output

```text
No application password/secret/token matches found.
No committed .env or credential files found.
No Git-tracked secret-like values found.
```

No real runtime secrets are required by the current local baseline. Later PostgreSQL/Redis credentials and Azure secrets must be injected externally rather than committed.

---

## 9. What database is used now?

```bash
grep -RniE 'sqlite|postgres|psycopg|DATABASE_URL|create_engine' application
find . -type f \( -name '*.db' -o -name '*.sqlite*' \)
```

### output

```text
DATABASE_URL = os.getenv("NORDICSHOP_DATABASE_URL", "sqlite:///./nordicshop.db")
```

```text
./nordicshop.db
```

The current local application uses SQLite. PostgreSQL support is prepared for the later container phase.

---

## 10. How is the database connection changed?

```bash
grep -Rni "DATABASE_URL" application
```

### output

```text
NORDICSHOP_DATABASE_URL
```

The database can be changed without modifying source code by supplying `NORDICSHOP_DATABASE_URL`.

---

## 11. Is Redis active now?

```bash
grep -Rni "redis" application
cat application/services/nordic-api/app/cart.py
```

### output

```python
class CartStore:
    """Development cart store. Redis will replace this adapter in the Docker phase."""
```

```python
self._carts: dict[str, dict[int, int]] = defaultdict(dict)
```

Redis is not active yet. Cart state is currently stored in Python memory and Redis is the planned shared replacement.

---

## 12. Which data is persistent and which is temporary?

```bash
cat application/services/nordic-api/app/database.py
cat application/services/nordic-api/app/cart.py
find . -type f \( -name '*.db' -o -name '*.sqlite*' \)
```

### output

Before restart:

```text
Two products were added to the cart.
Existing orders were visible in Vendor and Admin portals.
```

After API restart:

```text
Cart: empty
Vendor orders: still present
Admin orders: still present
```

Database-backed products, vendors, inventory and orders persist in SQLite. In-memory cart contents disappear when the API process stops.

---

## 13. How does authentication work?

```bash
cat application/services/nordic-api/app/auth.py
grep -Rni "Header" application/services/nordic-api/app
```

### output

```python
x_demo_user: str | None = Header(default=None)
```

```python
user_id = int(x_demo_user)
user = db.get(User, user_id)
```

The development baseline identifies the current user through the `X-Demo-User` HTTP header and then looks that user up in the database.

---

## 14. How does authorization and tenant isolation work?

```bash
grep -Rni "Depends(vendor_user)" application/services/nordic-api
grep -Rni "tenant_id" application/services/nordic-api/app/main.py
```

### output

```python
Product.tenant_id == user.tenant_id
```

```python
select(Product).where(
    Product.id == product_id,
    Product.tenant_id == user.tenant_id
)
```

```python
OrderLine.tenant_id == user.tenant_id
```

Vendor access is scoped using the authenticated user's own `tenant_id`. The browser does not choose the effective tenant; API queries enforce ownership.

---

## 15. Does NordicShop call external APIs?

```bash
grep -RniE 'httpx|requests|aiohttp|fetch\(|https?://' application
grep -Rni "http" application/apps
```

### output

```text
Frontend fetch calls use relative /api/... paths.
No external http:// or https:// runtime targets were found.
```

No external API or third-party runtime dependency was discovered in the current baseline.

---

## 16. How is the database schema created or migrated?

```bash
find application -iname '*migration*' -o -iname 'alembic*' -o -iname '*.sql'
grep -RniE 'alembic|migration|create_all' application
```

### output

```text
application/database/postgresql_rls.sql
```

```python
Base.metadata.create_all(bind=engine)
```

There is no full migration framework yet. SQLAlchemy `create_all()` creates missing tables at startup; the PostgreSQL RLS SQL file is prepared for later use.

---

## 17. How does a clean database get seed data?

```bash
cat application/services/nordic-api/app/seed.py
grep -Rni "seed" application
```

### output

```python
if db.scalar(select(Tenant.id).limit(1)):
    return
```

Seeded identities:

```text
User 1: Anna Lind - vendor - tenant 1
User 2: Erik Dahl - vendor - tenant 2
User 3: Maja Holm - admin
```

Seeded tenants:

```text
North Harbour Goods
Fjell & Form
```

On an empty database, startup seeds two vendors, two vendor users, one admin user and eight demo products. Existing tenant data prevents duplicate seeding.

---

## 18. How does the application log?

```bash
grep -RniE 'logging|logger|print\(' application/services
curl http://127.0.0.1:8000/api/products
```

### output

Application logging search:

```text
No custom logging statements found.
```

Uvicorn terminal:

```text
"GET /api/products HTTP/1.1" 200 OK
```

NordicShop currently relies on Uvicorn runtime/access logs written to stdout/stderr. No custom application logging exists yet.

---

## 19. Does NordicShop expose metrics?

```bash
grep -RniE 'metrics|prometheus|opentelemetry|instrument' application
```

### output

```text
No matches.
```

Application metrics are not implemented yet. Prometheus/OpenTelemetry instrumentation is future work.

---

## 20. Does the application write files locally?

```bash
grep -RniE 'open\(.*w|write\(|mkdir|Path\(' application/services
find application -type f | sort
```

### output

```python
ROOT = Path(__file__).resolve().parents[3]
```

And separately:

```text
./nordicshop.db
```

The application does not write normal local files itself, but SQLite creates `nordicshop.db` in local development. Static application files are only read from disk.

---

## 21. What CPU and memory does the API need?

```bash
ps aux | grep uvicorn
pgrep -af uvicorn
ps -o pid,%cpu,%mem,rss,cmd -p $(pgrep -f uvicorn | head -1)
ps -ef --forest | grep -A5 -B2 '[u]vicorn'
ps --ppid 122237 -o pid,ppid,%cpu,%mem,rss,cmd
top -b -n 1 -p 122237 | head -12
grep -RniE 'cpu|memory|resource|limit|request' README.md docs application
```

### output

Development reload parent:

```text
RES ≈ 29084 KB
```

Spawned application worker:

```text
RSS ≈ 67936 KB
CPU ≈ 0.3% at the inspected moment
```

CPU/memory requirements are not formally documented or load-tested. Development measurements are only observations and must not be used directly as Kubernetes requests/limits.

---

## 22. Can Nordic API safely run multiple replicas today?

```bash
grep -RniE 'global|defaultdict|dict\[' application/services/nordic-api/app
cat application/services/nordic-api/app/cart.py
```

### output

```python
self._carts: dict[str, dict[int, int]] = defaultdict(dict)
```

```python
cart_store = CartStore()
```

Not fully. Each API process has its own cart memory, so multiple replicas would not share cart state. Redis/shared state is required before cart behavior is safe across replicas.

---

## 23. Does the application shut down gracefully?

```bash
grep -RniE 'lifespan|shutdown|signal|SIGTERM|SIGINT' application/services
pgrep -af uvicorn
kill -TERM 122237
pgrep -af uvicorn
ss -lntp | grep 8000
```

### output

```text
INFO: Shutting down
INFO: Waiting for application shutdown.
INFO: Application shutdown complete.
INFO: Finished server process [122239]
INFO: Stopping reloader process [122237]
```

After shutdown:

```text
No uvicorn process found.
No listener on port 8000.
```

Uvicorn handles SIGTERM cleanly. The FastAPI application completes shutdown and releases port 8000.

---

## 24. What happens when the database dependency fails?

```bash
pkill -f uvicorn
mv nordicshop.db nordicshop.db.bak
python -m uvicorn --app-dir application/services/nordic-api app.main:app --reload --port 8000
curl -i http://127.0.0.1:8000/api/health
curl -i http://127.0.0.1:8000/api/ready
ls -lh nordicshop.db
```

### output

```text
/api/health → HTTP/1.1 200 OK
/api/ready  → HTTP/1.1 200 OK
```

```text
A new nordicshop.db file was created automatically.
```

Removing the SQLite file did not simulate a real database outage because startup recreated and reseeded it. Proper dependency-failure testing must be done later with PostgreSQL running as a separate service.

---

## 25. What automated tests exist?

```bash
find application/tests -maxdepth 3 -type f -print
grep -n '^def test_' application/tests/*.py
python -m pytest -q
python -m pytest -v
```

### output

```text
application/tests/test_api.py
```

Tests:

```text
test_health_and_seeded_catalog
test_customer_cart_and_checkout_journey
test_vendor_lists_are_tenant_scoped
test_vendor_a_cannot_change_vendor_b_product
test_vendor_cannot_use_admin_routes_and_admin_can
test_missing_identity_is_rejected
test_three_portal_entry_points_render
```

Final result:

```text
7 passed, 1 warning
```

Seven automated tests currently prove the main API, customer journey, vendor isolation, admin authorization, missing-identity behavior and all three portal entry points.

---

## 26. Are security and tenant-isolation controls actually tested?

```bash
grep -RniE 'tenant|vendor|forbidden|unauthorized|403|404' application/tests
find tests/security -maxdepth 3 -type f -print
```

### output

```python
assert {p["tenant_id"] for p in a} == {1}
assert {p["tenant_id"] for p in b} == {2}
```

```python
response = client.patch(
    "/api/vendor/products/5/stock",
    headers=VENDOR_A,
    json={"stock": 999}
)
assert response.status_code == 404
```

```python
assert client.get("/api/admin/summary", headers=VENDOR_A).status_code == 403
```

Platform security directory:

```text
tests/security/.gitkeep
```

Application-level tenant isolation and authorization are genuinely tested. Platform-level security tests are intentionally still future work.

---

## Inspection summary

The current NordicShop local baseline is understood well enough to begin the Docker learning phase.

Verified current architecture:

```text
Customer Web ──┐
Vendor Portal ─┼── HTTP /api/* ──> Nordic API
Admin Portal ──┘                     │
                                     ├── SQLite
                                     └── In-memory CartStore
```

Important findings before containerization:

```text
SQLite                 → PostgreSQL later
In-memory CartStore    → Redis later
Development --reload   → production runtime command later
Local DB file          → separate persistent database service later
No metrics             → observability work later
No custom app logging  → improve during operations phase
```

## Exit status

**Application inspection: COMPLETE**

The next phase is Docker fundamentals and containerization, starting from first principles rather than copying a prepared Dockerfile.

## Status update: 

This checklist records the application state before containerization. Since this inspection, the three frontends have been separated from FastAPI, four custom container images have been built and verified, and PostgreSQL and Redis official images have been tested separately. The current container state is recorded in docs/evidence/container-images.md.

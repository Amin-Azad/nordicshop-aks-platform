# Docker Compose Learning Notes

## 1. What did we build?

We connected the complete NordicShop application using Docker Compose.

The stack now contains six services:

```text
customer-web
vendor-portal
admin-portal
api
postgres
redis
```

The three frontend applications run with Nginx. They send `/api/...` requests to the Nordic API through an Nginx reverse proxy.

The API stores persistent business data in PostgreSQL and cart data in Redis.

---

## 2. Why Docker Compose?

Before Compose, each container had to be started manually with separate `docker run` commands, environment variables, networks, ports and volumes.

Docker Compose puts those definitions into one file:

```text
compose.yml
```

The complete application can now be started with:

```bash
docker compose up -d
```

and stopped with:

```bash
docker compose down
```

---

## 3. How do containers communicate?

Docker Compose creates a default network automatically.

The services can reach each other using their Compose service names.

For example:

```text
postgres:5432
redis:6379
api:8000
```

The API database connection therefore uses:

```text
postgresql+psycopg://nordicshop:nordicshop-dev@postgres:5432/nordicshop
```

and Redis uses:

```text
redis://redis:6379/0
```

We do not need to know container IP addresses.

---

## 4. PostgreSQL

PostgreSQL runs from:

```text
postgres:18.6-alpine
```

The Compose service creates:

```text
database: nordicshop
user: nordicshop
```

The API now connects to PostgreSQL instead of the local SQLite database when running in Compose.

PostgreSQL uses the named volume:

```text
nordicshop-postgres-data
```

This means database data survives container deletion and recreation.

We proved this by:

1. Creating an order.
2. Running `docker compose down`.
3. Starting the stack again with `docker compose up -d`.
4. Querying the Admin API.
5. Confirming the previous order still existed.

---

## 5. Redis

Redis runs from:

```text
redis:8.10.1-alpine
```

The old Python in-memory `CartStore` was replaced with Redis.

A cart is stored as a Redis hash.

Example:

```text
cart:compose-test
```

with product ID and quantity stored as hash fields.

We verified the Redis content directly with:

```bash
docker compose exec redis redis-cli HGETALL cart:compose-test
```

The cart also survived an API container restart because the state lives in Redis rather than inside the API process.

Redis currently has no named volume. Cart data is treated as temporary application state.

---

## 6. API database connection recovery

SQLAlchemy connection pooling was configured with:

```python
pool_pre_ping=True
```

This helps detect stale database connections before SQLAlchemy reuses them.

We tested this by restarting PostgreSQL while leaving the API running.

After PostgreSQL returned, the API successfully queried the database without requiring an API restart.

---

## 7. Nginx reverse proxy

Each frontend runs in its own Nginx container.

The frontend JavaScript uses relative API paths such as:

```text
/api/products
/api/orders
/api/vendor/products
/api/admin/orders
```

The Nginx configuration contains:

```nginx
location /api/ {
    proxy_pass http://api:8000;
}
```

Therefore a browser request such as:

```text
localhost:8081/api/products
```

follows this path:

```text
Browser
  ↓
Customer Web Nginx
  ↓
api:8000
  ↓
Nordic API
  ↓
PostgreSQL
```

---

## 8. Host ports

The services are exposed locally as:

```text
API            localhost:8000
Customer Web   localhost:8081
Vendor Portal  localhost:8082
Admin Portal   localhost:8083
PostgreSQL     localhost:5432
Redis          localhost:6379
```

Inside the Compose network, containers use service names and container ports instead of these host ports.

---

## 9. Health checks

PostgreSQL health is checked with:

```bash
pg_isready -U nordicshop -d nordicshop
```

Redis health is checked with:

```bash
redis-cli ping
```

The API health check calls:

```text
http://localhost:8000/api/ready
```

from inside the API container.

The API waits for PostgreSQL and Redis to become healthy.

The frontend containers wait for the API to become healthy.

The startup dependency is therefore:

```text
PostgreSQL healthy ─┐
                    ├──> API healthy ───> Customer Web
Redis healthy ──────┘                 ├──> Vendor Portal
                                      └──> Admin Portal
```

---

## 10. Customer flow tested

We added a product to a cart through:

```text
localhost:8081
```

The request travelled through:

```text
Customer Nginx
  ↓
Nordic API
  ↓
Redis
```

The Redis key was inspected directly and contained the expected quantity.

The API was restarted and the cart remained available because the cart was stored in Redis rather than API memory.

---

## 11. Order flow tested

The customer cart was checked out and created an order in PostgreSQL.

The order was then visible through:

```text
Admin Portal → Admin API
Vendor Portal → Vendor API
```

Vendor A saw only its own product/order information.

This verified the complete flow:

```text
Customer
   ↓
Customer Web
   ↓
API
   ↓
PostgreSQL
   ↓
Vendor/Admin views
```

---

## 12. Clean startup test

We removed all Compose containers and the Compose network with:

```bash
docker compose down
```

The PostgreSQL named volume remained.

We then started the complete environment using only:

```bash
docker compose up -d
```

All six services started successfully.

The three backend/data services reached healthy state:

```text
postgres  healthy
redis     healthy
api       healthy
```

The frontend endpoints returned:

```text
HTTP/1.1 200 OK
```

for Customer, Vendor and Admin.

The previously created PostgreSQL order was still available.

---

## 13. Useful commands learned

Validate the Compose file:

```bash
docker compose config
docker compose config --quiet
```

List services:

```bash
docker compose config --services
```

Start the stack:

```bash
docker compose up -d
```

Check containers:

```bash
docker compose ps
```

Restart one service:

```bash
docker compose restart api
```

Run a command inside a service:

```bash
docker compose exec redis redis-cli ping
```

View logs:

```bash
docker compose logs api
```

Stop and remove Compose containers:

```bash
docker compose down
```

Check volumes:

```bash
docker volume ls
```

---

## 14. Final verification

The final application test result was:

```text
7 passed, 1 warning
```

The remaining warning is a Starlette TestClient deprecation warning and does not cause a test failure.

At the end of this phase NordicShop can be started locally as a complete multi-container application using Docker Compose.

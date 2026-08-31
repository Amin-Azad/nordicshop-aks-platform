# Container image checks

This note records the container work completed before Docker Compose.

## Custom images

### Nordic API

- Image: `nordicshop-api:prod`
- Size: 71.9 MB
- Port: 8000
- Runtime user: `nordicshop` (UID 10001)
- `/api/health`: passed
- `/api/ready`: passed
- Graceful shutdown: passed
- Digest: `sha256:05d385d5dfcd26b150b2dbe0176a72624c8e3ce7c5e8ed34485c94373b74c746`

The API image contains only the backend files. The frontend folders are no longer served by FastAPI.

### Customer Web

- Image: `nordicshop-customer-web:prod`
- Size: 25.8 MB
- Port: 8080
- Runtime user: `nginx` (UID 101)
- HTML, JavaScript, CSS and WebP asset: passed
- Graceful shutdown: passed
- Digest: `sha256:80bea12144b4244cc67b1f2c6679489833c668d49819ad450bfb80a44b4531f0`

### Vendor Portal

- Image: `nordicshop-vendor-portal:prod`
- Size: 25.7 MB
- Port: 8080
- Runtime user: `nginx` (UID 101)
- HTML, JavaScript and CSS: passed
- Graceful shutdown: passed
- Digest: `sha256:09d56bff103275920a0d1783d4c47b827f21cda743e11b9a6c1b7b0e4712d387`

### Admin Portal

- Image: `nordicshop-admin-portal:prod`
- Size: 25.7 MB
- Port: 8080
- Runtime user: `nginx` (UID 101)
- HTML, JavaScript and CSS: passed
- Graceful shutdown: passed
- Digest: `sha256:4471398e6d6f9f80bb3406624a78f209d13ba28f983f1231d41d236a851ec6b5`

## Official service images

### PostgreSQL

- Image: `postgres:18.6-alpine`
- Size: about 121 MB
- Port: 5432
- `pg_isready`: passed
- SQL connection: passed
- PostgreSQL server process runs as a restricted user
- Named volume: `nordicshop-postgres-data`
- Data survived container deletion and recreation
- Graceful shutdown: passed
- Digest: `sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2`

The persistence test created a small table, removed the PostgreSQL container, recreated it with the same volume and confirmed the row was still there.

### Redis

- Image: `redis:8.10.1-alpine`
- Size: about 39.0 MB
- Port: 6379
- `PING` returned `PONG`
- `SET` and `GET`: passed
- Redis server process runs as a restricted user
- No named volume was attached for this test
- Data did not survive container deletion and recreation
- Graceful shutdown: passed
- Digest: `sha256:becdda6c7f4b3fb42e42fd7f120bbf5c54c4caaaf16f26da24e4563d2c1f0576`

## What this phase proved

- The four NordicShop application components can run as separate images.
- The custom images run as non-root users.
- PostgreSQL data can be kept outside the container with a named volume.
- Redis can be used for temporary shared state.
- Container shutdown was checked instead of only checking startup.
- Docker Compose has not been created yet.

Next step: connect the six services with Docker Compose and replace SQLite/in-memory cart behavior with PostgreSQL and Redis step by step.

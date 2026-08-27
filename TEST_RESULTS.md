# Test results

## Automated baseline

Command:

```bash
python -m pytest -q
```

Result at packaging time:

```text
7 passed
```

Covered behavior:

- API health and deterministic eight-product catalogue
- Customer cart and demonstration checkout
- Vendor A and Vendor B product-list tenant scoping
- Vendor A denied when attempting to change a Vendor B product
- Vendor denied from administrator routes
- Administrator marketplace summary access
- Missing demo identity rejected
- Customer, Vendor and Admin entry pages returned successfully

## Static checks

- Python modules compile successfully.
- Customer, Vendor and Admin JavaScript files pass syntax checks.
- Required local assets are included in the package.

## Honest pre-Docker limitation

The initial baseline uses SQLite and an in-memory cart adapter so it runs before the Docker lesson. `database/postgresql_rls.sql` defines the intended PostgreSQL policies, but those policies are not reported as runtime-tested yet. PostgreSQL and Redis runtime verification belongs to the Docker Compose learning phase.

## Manual review after download

Run the application and review these pages:

- `/shop/`
- `/vendor/`
- `/admin/`

Then place an order, switch between both vendor identities and confirm each vendor sees only its own product and order-line data.

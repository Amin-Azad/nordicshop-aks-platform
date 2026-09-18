# NordicShop PostgreSQL RLS Disposable Lab

This is an isolated Kubernetes/PostgreSQL acceptance lab. It does not modify the `nordicshop` namespace, PVCs, Helm release, Key Vault, or application.

It validates a restricted `nordicshop_app` role and PostgreSQL RLS for customer, vendor and admin database contexts.

Important v2 detail: customer checkout sets `app.order_id` after the order is created. The customer may then insert and read only the order lines belonging to that current order. This supports PostgreSQL/ORM `INSERT ... RETURNING` without exposing other order lines.

Run from the repository root:

```bash
chmod +x tests/security/postgres-rls-lab/run.sh
./tests/security/postgres-rls-lab/run.sh
```

The temporary namespace is deleted automatically at exit.

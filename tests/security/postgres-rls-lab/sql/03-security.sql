\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nordicshop_app') THEN
    CREATE ROLE nordicshop_app NOLOGIN;
  END IF;
END
$$;

ALTER ROLE nordicshop_app
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  NOBYPASSRLS;

GRANT USAGE ON SCHEMA public TO nordicshop_app;
GRANT SELECT ON tenants, users, products, orders, order_lines TO nordicshop_app;
GRANT INSERT ON orders, order_lines TO nordicshop_app;
GRANT UPDATE (stock) ON products TO nordicshop_app;
GRANT UPDATE (active) ON tenants TO nordicshop_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO nordicshop_app;

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
ALTER TABLE order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_lines FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS products_select_policy ON products;
DROP POLICY IF EXISTS products_update_policy ON products;
DROP POLICY IF EXISTS order_lines_select_policy ON order_lines;
DROP POLICY IF EXISTS order_lines_insert_policy ON order_lines;

CREATE POLICY products_select_policy
ON products
FOR SELECT
TO nordicshop_app
USING (
  current_setting('app.access_mode', true) IN ('customer', 'admin')
  OR (
    current_setting('app.access_mode', true) = 'vendor'
    AND tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::integer
  )
);

CREATE POLICY products_update_policy
ON products
FOR UPDATE
TO nordicshop_app
USING (
  current_setting('app.access_mode', true) IN ('customer', 'admin')
  OR (
    current_setting('app.access_mode', true) = 'vendor'
    AND tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::integer
  )
)
WITH CHECK (
  current_setting('app.access_mode', true) IN ('customer', 'admin')
  OR (
    current_setting('app.access_mode', true) = 'vendor'
    AND tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::integer
  )
);

-- Customers may only see the order lines for the order currently being built.
-- This is required for INSERT ... RETURNING while preventing access to other
-- customers' or vendors' order lines.
CREATE POLICY order_lines_select_policy
ON order_lines
FOR SELECT
TO nordicshop_app
USING (
  current_setting('app.access_mode', true) = 'admin'
  OR (
    current_setting('app.access_mode', true) = 'vendor'
    AND tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::integer
  )
  OR (
    current_setting('app.access_mode', true) = 'customer'
    AND order_id = NULLIF(current_setting('app.order_id', true), '')::integer
  )
);

CREATE POLICY order_lines_insert_policy
ON order_lines
FOR INSERT
TO nordicshop_app
WITH CHECK (
  current_setting('app.access_mode', true) = 'admin'
  OR (
    current_setting('app.access_mode', true) = 'customer'
    AND order_id = NULLIF(current_setting('app.order_id', true), '')::integer
  )
);

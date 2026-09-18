-- NordicShop PostgreSQL row-level security.
-- This policy is based on the disposable RLS lab that passed the customer,
-- vendor A, vendor B and administrator acceptance matrix.
--
-- API transaction context:
--   customer: app.access_mode='customer' and, during checkout, app.order_id
--   vendor:   app.access_mode='vendor' + app.tenant_id
--   admin:    app.access_mode='admin'

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
ALTER TABLE order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_lines FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS products_tenant_isolation ON products;
DROP POLICY IF EXISTS order_lines_tenant_isolation ON order_lines;
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

-- Customers may only see lines for the checkout order currently being built.
-- This permits ORM INSERT ... RETURNING without exposing other customers' lines.
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

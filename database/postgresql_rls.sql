-- Apply after creating the equivalent PostgreSQL tables in the Docker phase.
-- The API transaction must set: SET LOCAL app.tenant_id = '<tenant id>';

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
ALTER TABLE order_lines FORCE ROW LEVEL SECURITY;

CREATE POLICY products_tenant_isolation ON products
  USING (tenant_id = current_setting('app.tenant_id', true)::integer)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::integer);

CREATE POLICY order_lines_tenant_isolation ON order_lines
  USING (tenant_id = current_setting('app.tenant_id', true)::integer)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::integer);

-- A separate migration role owns tables. The runtime role must not have
-- BYPASSRLS and must not be a superuser.

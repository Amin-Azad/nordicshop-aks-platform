-- NordicShop restricted application runtime role permissions.
-- Role creation/password is performed by the Kubernetes database-security Job.

ALTER ROLE nordicshop_app
  LOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  NOBYPASSRLS;

GRANT CONNECT ON DATABASE nordicshop TO nordicshop_app;
GRANT USAGE ON SCHEMA public TO nordicshop_app;

GRANT SELECT ON TABLE tenants, users, products, orders, order_lines TO nordicshop_app;
GRANT INSERT ON TABLE orders, order_lines TO nordicshop_app;
GRANT UPDATE (stock) ON TABLE products TO nordicshop_app;
GRANT UPDATE (active) ON TABLE tenants TO nordicshop_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO nordicshop_app;

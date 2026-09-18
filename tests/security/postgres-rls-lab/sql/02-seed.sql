\set ON_ERROR_STOP on

INSERT INTO tenants (id, name, slug, active) VALUES
  (1, 'North Harbour Goods', 'north-harbour', true),
  (2, 'Fjell & Form',        'fjell-form',   true);

INSERT INTO users (id, email, name, role, tenant_id) VALUES
  (1, 'vendor.a@nordicshop.local', 'Anna Lind',  'vendor', 1),
  (2, 'vendor.b@nordicshop.local', 'Erik Dahl',  'vendor', 2),
  (3, 'admin@nordicshop.local',    'Maja Holm',  'admin',  NULL);

INSERT INTO products
  (id, tenant_id, name, description, category, price, stock, accent, active)
VALUES
  (1, 1, 'Harbour Wool Throw', 'Lab product A1', 'Home',      649.00, 18, 'fjord',  true),
  (2, 1, 'Oak Desk Tray',      'Lab product A2', 'Workspace', 329.00, 24, 'oak',    true),
  (3, 2, 'Birch Table Lamp',   'Lab product B1', 'Lighting',  799.00, 12, 'birch',  true),
  (4, 2, 'Forest Notebook',    'Lab product B2', 'Workspace', 149.00, 65, 'forest', true);

INSERT INTO orders (id, customer_name, customer_email, status)
OVERRIDING SYSTEM VALUE
VALUES (100, 'Existing Customer', 'existing@example.com', 'placed');

INSERT INTO order_lines
  (order_id, tenant_id, product_id, product_name, quantity, unit_price)
VALUES
  (100, 1, 1, 'Harbour Wool Throw', 1, 649.00),
  (100, 2, 3, 'Birch Table Lamp',   1, 799.00);

SELECT setval(pg_get_serial_sequence('orders','id'), 100, true);
SELECT setval(pg_get_serial_sequence('order_lines','id'), 2, true);

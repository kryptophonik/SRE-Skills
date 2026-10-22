-- Run as shop in database shop by setup.sh. Deterministic data (no random()).
CREATE TABLE customers (id int PRIMARY KEY, name text NOT NULL);
INSERT INTO customers SELECT g, 'customer-' || g FROM generate_series(1, 500) g;

CREATE TABLE orders (
  id          int PRIMARY KEY,
  customer_id int NOT NULL REFERENCES customers(id),
  status      text NOT NULL,
  total       numeric(10,2) NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO orders (id, customer_id, status, total)
  SELECT g, g % 500 + 1, 'paid', (g % 97) + 0.99 FROM generate_series(1, 50000) g;
ANALYZE customers;
ANALYZE orders;

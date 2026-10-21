-- The safe patterns. Expect no blockers and no warnings.
SET lock_timeout = '5s';
CREATE INDEX CONCURRENTLY orders_created_idx ON orders (created_at);
ALTER TABLE orders ADD COLUMN note text;
ALTER TABLE orders ADD COLUMN priority int DEFAULT 0;
ALTER TABLE orders ADD COLUMN created_on timestamptz DEFAULT now();
ALTER TABLE orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;
ALTER TABLE orders ADD CONSTRAINT orders_cid_nn CHECK (customer_id IS NOT NULL) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_cid_nn;
CREATE UNIQUE INDEX CONCURRENTLY orders_ref_uq_idx ON orders (ref);
ALTER TABLE orders ADD CONSTRAINT orders_ref_uq UNIQUE USING INDEX orders_ref_uq_idx;
UPDATE orders SET status = 'new' WHERE id BETWEEN 1 AND 5000;
INSERT INTO schema_note (body) VALUES ('semicolon; inside a string; is fine');
CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $$ SELECT 1; $$;
DROP INDEX CONCURRENTLY orders_old_idx;
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_totals;

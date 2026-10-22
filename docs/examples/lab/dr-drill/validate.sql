-- Validation for docs/examples/08: run on the source and on the restore, compare the lines.
-- Counts, newest updated_at, md5 over every backed-up order (id <= 50000), and one known record.
SELECT 'orders=' || (SELECT count(*) FROM orders)
    || ' customers=' || (SELECT count(*) FROM customers)
    || ' max_updated_at=' || (SELECT max(updated_at) FROM orders)
    || ' orders_md5=' || (SELECT md5(string_agg(id || ':' || customer_id || ':' || status || ':' || total, ',' ORDER BY id))
                          FROM orders WHERE id <= 50000)
    || ' order42=' || (SELECT status FROM orders WHERE id = 42);

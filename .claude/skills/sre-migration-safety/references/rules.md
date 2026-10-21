# Rules and blind spots

Each rule ID matches the checker output and, where a lab proof exists, the line in `scripts/proof-pg.sh` or `scripts/proof-mysql.sh` that tests it.

## PostgreSQL

| Rule | Pattern | Why | Safe pattern | Lab proof |
|---|---|---|---|---|
| PG-IDX-LOCK | `CREATE INDEX` without `CONCURRENTLY` | SHARE lock blocks writes for the whole build | `CREATE INDEX CONCURRENTLY`, outside a transaction | yes |
| PG-CONC-IN-TXN | `CONCURRENTLY` inside `BEGIN` | Statement errors | Own non-transactional migration | yes |
| PG-ADDCOL-REWRITE | `ADD COLUMN` with a volatile default or serial | Rewrites every row under ACCESS EXCLUSIVE | Add with no default, backfill in batches, `SET DEFAULT` | yes |
| PG-ADDCOL-NOTNULL | `ADD COLUMN ... NOT NULL` with no default | Fails on a non-empty table | Nullable, backfill, then the NOT NULL steps | yes |
| PG-ALTER-TYPE | `ALTER COLUMN ... TYPE` | Usually rewrites and reindexes. Reported as a warning, not a blocker, when the new type is `varchar` or `text`, because widening a varchar or going from varchar to text doesn't rewrite | New column, backfill, swap | yes (int to bigint rewrites; varchar widening and varchar to text don't) |
| PG-SET-NOTNULL | `SET NOT NULL` | Full scan under ACCESS EXCLUSIVE | `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE`, `SET NOT NULL` (12+ skips the scan) | yes |
| PG-FK-VALIDATE | `ADD FOREIGN KEY` without `NOT VALID` | Scans and blocks writes on both tables | `NOT VALID`, then `VALIDATE CONSTRAINT` (SHARE UPDATE EXCLUSIVE) | yes |
| PG-CHECK-VALIDATE | `ADD CHECK` without `NOT VALID` | Scans under ACCESS EXCLUSIVE | `NOT VALID`, then `VALIDATE` | same mechanism as FK |
| PG-UNIQUE-BUILD | `ADD UNIQUE` / `PRIMARY KEY` without `USING INDEX` | Builds the index under the lock | `CREATE UNIQUE INDEX CONCURRENTLY`, then `ADD CONSTRAINT ... USING INDEX` | rule only |
| PG-NO-LOCK-TIMEOUT | ALTER with no `lock_timeout` | A waiting ACCESS EXCLUSIVE request queues every later query on the table | `SET lock_timeout = '5s'` and retry | yes (reads queue behind the waiting ALTER) |
| PG-DROPIDX-LOCK, PG-REINDEX-LOCK, PG-MATVIEW-LOCK | non-concurrent variants | Block reads and/or writes | `CONCURRENTLY` variants | rule only |
| PG-REWRITE-CMD, PG-REWRITE-ALTER | `VACUUM FULL`, `CLUSTER`, `SET LOGGED/UNLOGGED`, `SET TABLESPACE` | Full rewrite under ACCESS EXCLUSIVE | Not in a migration; `pg_repack` behind a gate | rule only |
| PG-DROP, PG-DROP-TABLE, PG-RENAME | destructive or breaking | Running app versions break; no undo | Expand and contract; gate with a tested backup | rule only |
| PG-DML-ALL-ROWS | `UPDATE`/`DELETE` with no `WHERE` | One long transaction, bloat, replica lag | Batches by primary key | rule only |

Sources: [ALTER TABLE](https://www.postgresql.org/docs/current/sql-altertable.html), [explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html), [CREATE INDEX CONCURRENTLY](https://www.postgresql.org/docs/current/sql-createindex.html).

## MySQL and MariaDB (InnoDB)

| Rule | Pattern | Why | Safe pattern | Lab proof |
|---|---|---|---|---|
| MY-NO-LOCK-WAIT-TIMEOUT | any DDL with no `lock_wait_timeout` | Pending exclusive metadata lock queues every later query; the default wait is one year on MySQL (31536000 s) and one day on MariaDB (86400 s) | `SET SESSION lock_wait_timeout = 5` and retry | yes |
| MY-ADDCOL-ALGO | `ADD COLUMN` with no algorithm | Falls back to a rebuild when INSTANT isn't possible | `ALGORITHM=INSTANT` so it fails instead. Any position from MySQL 8.0.29 (last column only in 8.0.12 to 8.0.28). Cap of 64 instant row versions per table (255 from 9.1); check `INFORMATION_SCHEMA.INNODB_TABLES.TOTAL_ROW_VERSIONS`, and a rebuild resets it | yes (cap hit at op 65 on 8.4.11, error 4092) |
| MY-COLUMN-TYPE | `MODIFY`/`CHANGE` | Type changes need COPY | `ALGORITHM=INPLACE, LOCK=NONE` to fail fast; else `gh-ost` or `pt-online-schema-change` | yes (INT to BIGINT refused INPLACE; VARCHAR widening allowed) |
| MY-CHARSET | `CONVERT TO CHARACTER SET` | COPY | online schema change tool | yes |
| MY-PK | `DROP`/`ADD PRIMARY KEY` | Rebuild; drop-only needs COPY | online schema change tool | yes |
| MY-FTS | `ADD FULLTEXT`/`SPATIAL` | No concurrent writes | Off-peak or `gh-ost` | yes |
| MY-FK-COPY | `ADD FOREIGN KEY` with `foreign_key_checks=1` | Needs COPY | Orphan check first, then `foreign_key_checks=0`, the `ALTER`, and `foreign_key_checks=1` in one gated session (see below). `gh-ost` doesn't support foreign keys | yes |
| MY-ALG-COPY, MY-OPTIMIZE | explicit copy, `OPTIMIZE TABLE` | Full rebuild | Off-peak, not in an automatic migration | rule only |
| MY-DROP-COLUMN, MY-DROP-TABLE, MY-RENAME | destructive or breaking | As PostgreSQL | As PostgreSQL | rule only |
| MY-DML-ALL-ROWS | `UPDATE`/`DELETE` with no `WHERE` | Undo growth, replica lag | Batches with `LIMIT` | rule only |

Sources: [MySQL 8.4 online DDL operations](https://dev.mysql.com/doc/refman/8.4/en/innodb-online-ddl-operations.html), [MySQL metadata locking](https://dev.mysql.com/doc/refman/8.4/en/metadata-locking.html).

## Blind spots: review these by hand

- Triggers, rules and views that a change touches.
- Partitioned tables: locks on the parent can cascade to every partition.
- PostgreSQL `ALTER TYPE ... ADD VALUE` for enums, and anything inside `DO` blocks or functions.
- Migration tools that wrap every file in a transaction, which breaks `CONCURRENTLY`.
- Table size and traffic: the checker can't see them.
- Versions older than PostgreSQL 13 or MySQL 8.0; the lab doesn't cover them.

## MySQL: adding a foreign key without a table copy

With `foreign_key_checks = 0`, MySQL creates the constraint without checking existing rows, so orphan rows would go unnoticed. Check first. This is a read; run it on a replica if the table is large. Stop if it returns a row.

```sql
SELECT 1 FROM child c LEFT JOIN parent p ON p.id = c.parent_id WHERE c.parent_id IS NOT NULL AND p.id IS NULL LIMIT 1;
```

Then run the change as one step in one session, so the setting goes back on before anything else uses that session.

**Gate: approval required.**
```sql
SET SESSION lock_wait_timeout = 5; SET SESSION foreign_key_checks = 0; ALTER TABLE child ADD CONSTRAINT fk_child_parent FOREIGN KEY (parent_id) REFERENCES parent (id), ALGORITHM=INPLACE, LOCK=NONE; SET SESSION foreign_key_checks = 1;
```

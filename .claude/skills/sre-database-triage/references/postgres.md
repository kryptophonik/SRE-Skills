# PostgreSQL triage (read-only)

Versions: community-supported PostgreSQL 14–18 (the current docs are 18). Queries were verified live on 13–17; PG18 is checked against the docs only. Queries also run on 13 unless a row says otherwise. Last reviewed: 2026-10-17. Sources: SOURCES in [../SKILL.md](../SKILL.md).

Every query goes through the wrapper. It passes `default_transaction_read_only=on`, `statement_timeout` (5 s), `lock_timeout` (1 s) and `idle_in_transaction_session_timeout` (10 s) in the connection string's `options=`, which beats `PGOPTIONS` and a `pg_service.conf` `options=` line, and it refuses to run if `PGOPTIONS` is set. It caps output and refuses anything that is not a single one-line `SELECT`/`WITH`/`SHOW`/`EXPLAIN` ending in `LIMIT n`. The same settings also go on the role (Access, below), so they hold even where startup options are lost (PgBouncer):

```bash
PGHOST=<host> PGPORT=5432 PGDATABASE=<db> PGUSER=<ro-role> PGPASSFILE=~/.pgpass bash scripts/db-ro.sh pg -- "SELECT version() LIMIT 1"
```

## Version differences that change the queries

| Feature | Since | If older |
|---|---|---|
| `pg_stat_replication.write_lag/flush_lag/replay_lag` | 10 | compare LSNs with `pg_wal_lsn_diff` |
| `pg_blocking_pids()` | 9.6 | n/a (all supported versions have it) |
| `pg_stat_activity.leader_pid` (parallel workers) | 13 | parallel workers show as separate rows |
| `pg_replication_slots.wal_status`, `safe_wal_size` | 13 | only `restart_lsn` |
| `pg_stat_statements.total_exec_time`, `mean_exec_time` | 13 | `total_time`, `mean_time` |
| `pg_stat_activity.query_id` | 14 | join `pg_stat_statements` by text only |
| `pg_terminate_backend(pid, timeout)` | 14 | `pg_terminate_backend(pid)` only (separate gated blocks below) |
| `vacuum_failsafe_age` | 14 | n/a |
| `pg_stat_io`, `reserved_connections` + `pg_use_reserved_connections` | 16 | only `superuser_reserved_connections` |
| `pg_stat_checkpointer` (checkpoint stats moved out of `pg_stat_bgwriter`), `transaction_timeout` | 17 | `pg_stat_bgwriter` |
| `pg_replication_slots.inactive_since` | 17 | n/a |

## Access (one-time setup by the database owner; it is a change, so it goes through normal review, not the incident)

- Triage role: a login role that is a member of `pg_monitor` (reads all `pg_stat_*` views, `pg_ls_waldir()`, and other sessions' query text). Never a superuser. Put the session guards on the role too, so they still apply behind PgBouncer and for clients other than the wrapper, and cap its connections so triage cannot add to an exhaustion incident:

```sql
-- one-time setup by the DB owner, through change review (not an incident action)
CREATE ROLE sre_ro LOGIN CONNECTION LIMIT 3;
GRANT pg_monitor TO sre_ro;
ALTER ROLE sre_ro SET default_transaction_read_only = on;
ALTER ROLE sre_ro SET statement_timeout = '5s';
ALTER ROLE sre_ro SET lock_timeout = '1s';
ALTER ROLE sre_ro SET idle_in_transaction_session_timeout = '10s';
```

PG16+ only (the role does not exist before 16, where only superusers get reserved slots), so triage can log in during exhaustion:

```sql
GRANT pg_use_reserved_connections TO sre_ro;
```

- Role settings are session **defaults**: a client that sends its own startup options (for example `PGOPTIONS='-c default_transaction_read_only=off'` outside the wrapper) overrides them (lab: Database Reviewer re-run). The wrapper refuses a preset `PGOPTIONS` and sets its guards in the connection string; the role settings cover PgBouncer and other clients, not a hostile environment.

- Set the password with psql `\password sre_ro`, which sends it encrypted. A literal `CREATE/ALTER ROLE ... PASSWORD '...'` is stored in clear in `pg_stat_statements` (utility statements are tracked by default) and can reach the server log.
- PG16+ `reserved_connections` (e.g. 2–3) is a server-start setting: changing it needs a **restart**, so set it ahead of time, never mid-incident. Its slots come out of `max_connections`, on top of `superuser_reserved_connections`.
- Cloud SQL: create the role **with SQL** as above, not with `gcloud sql users create` or the console: users created that way are made members of `cloudsqlsuperuser`. Verify that the role belongs to nothing beyond `pg_monitor` (which itself includes `pg_read_all_settings`, `pg_read_all_stats` and `pg_stat_scan_tables`) and, on PG16+, `pg_use_reserved_connections`. The query lists anything else, so a correct setup returns **0 rows**:

```bash
bash scripts/db-ro.sh pg -- "SELECT rolname FROM pg_roles WHERE pg_has_role('sre_ro', oid, 'member') AND rolname NOT IN ('sre_ro', 'pg_monitor', 'pg_read_all_settings', 'pg_read_all_stats', 'pg_stat_scan_tables', 'pg_use_reserved_connections') LIMIT 20"
```
- Cancel/terminate rights (`pg_signal_backend`) belong to a separate operator role that a human uses after approval, not to the triage role. `pg_signal_backend` cannot signal superuser backends.
- Secrets: `~/.pgpass` (`chmod 0600`, libpq ignores it otherwise) or `PGPASSFILE`, or `PGSERVICE` with `pg_service.conf`. Never `PGPASSWORD`, never a password in a conninfo string or on the command line.
- Connect to the database itself, not through PgBouncer: during exhaustion the pooler is often the bottleneck, and PgBouncer only accepts the startup parameters it tracks: with the default config the wrapper's `options` make it fail at connect (`unsupported startup parameter in options: default_transaction_read_only`, lab with PgBouncer 1.24.1). Only if the pooler's `ignore_startup_parameters` includes `options` does the connection go through, and then the wrapper's guards are silently ignored: the role settings above are what still hold.
- `EXPLAIN` needs `SELECT` on the tables involved, which this role does not have. Use a separate read-only account with `SELECT` on the app schema only (on PG14+ avoid the cluster-wide `pg_read_all_data`), or hand the statement to the DB owner.
- Managed services: see "Managed services" at the end (RDS/Aurora, Cloud SQL, Azure).

## 1. Connection exhaustion ("too many clients", "remaining connection slots are reserved", pool timeouts)

Read:

```bash
bash scripts/db-ro.sh pg -- "SELECT (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend') AS client_conns, current_setting('max_connections')::int AS max_connections, current_setting('superuser_reserved_connections')::int AS su_reserved, current_setting('reserved_connections', true) AS reserved_pg16 LIMIT 1"
bash scripts/db-ro.sh pg -- "SELECT state, wait_event_type, usename, application_name, count(*) AS n FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1, 2, 3, 4 ORDER BY n DESC LIMIT 50"
bash scripts/db-ro.sh pg -- "SELECT application_name, client_addr, count(*) AS n, max(now() - state_change) AS longest_in_state FROM pg_stat_activity WHERE state = 'idle in transaction' GROUP BY 1, 2 ORDER BY n DESC LIMIT 20"
```

Interpret:

- One `application_name`/`client_addr` holding most slots right after a deploy: the new version's pool size or a connection leak. The fix is on the app side: roll back the deploy or lower its pool size (`sre-change-safety`, `sre-k8s-safe-remediation`). That is faster and safer than killing sessions, because a leaking app refills the slots within seconds.
- Many `idle in transaction`: the app opens a transaction and waits on something else (an HTTP call, a lock). These sessions also hold locks and stop vacuum.
- Mostly `active` with `wait_event_type = Lock`: go to section 2. Mostly `active` on `IO` or `LWLock`: saturation, go to section 6.

Proposal: end idle-in-transaction sessions of one application. Run only after evidence capture (`bash scripts/db-snapshot.sh pg <outdir>`), a proposal naming the app, the row count from this preview, risk high, not reversible (each open transaction rolls back), and the app-side fix already in flight. Filter on both the database user and `application_name`: many drivers send a generic name (the PostgreSQL JDBC driver sends `PostgreSQL JDBC Driver`) unless the app sets one, so the name alone can match other services. There is no cancel step here: an idle-in-transaction session has no running statement to cancel. Preview (read-only):

```bash
bash scripts/db-ro.sh pg -- "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend' AND pid <> pg_backend_pid() AND usename = '<app-db-user>' AND application_name = '<app>' AND state = 'idle in transaction' AND now() - state_change > interval '5 minutes' LIMIT 1"
```

PG14 and later (waits up to 5 s for each session to exit):

**Gate: approval required.**
```sql
-- operator role with pg_signal_backend, NOT through scripts/db-ro.sh; the approval names <app> and the previewed count
SELECT pid, pg_terminate_backend(pid, 5000) FROM pg_stat_activity WHERE backend_type = 'client backend' AND pid <> pg_backend_pid() AND usename = '<app-db-user>' AND application_name = '<app>' AND state = 'idle in transaction' AND now() - state_change > interval '5 minutes';
```

PG13 (no timeout argument):

**Gate: approval required.**
```sql
-- PG13 only; same filter, same approval
SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE backend_type = 'client backend' AND pid <> pg_backend_pid() AND usename = '<app-db-user>' AND application_name = '<app>' AND state = 'idle in transaction' AND now() - state_change > interval '5 minutes';
```

Verify: re-run the first read; `client_conns` falls and stays down; the app's error rate drops. If the count climbs back within a minute, stop: the leak is still deployed.

## 2. Locks, blocking chains and deadlocks

Use `pg_blocking_pids()` with `pg_stat_activity`, not a self-join of `pg_locks`. The docs warn that each call needs exclusive access to the lock manager's shared state for a short time, so filter to sessions waiting on a lock first and do not poll in a tight loop.

```bash
bash scripts/db-ro.sh pg -- "SELECT pid, blocked_by, usename, application_name, wait_event, now() - query_start AS waiting, CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 200) END AS query FROM (SELECT a.*, pg_blocking_pids(a.pid) AS blocked_by FROM pg_stat_activity a WHERE a.wait_event_type = 'Lock') w ORDER BY query_start LIMIT 50"
bash scripts/db-ro.sh pg -- "SELECT pid, usename, application_name, state, now() - xact_start AS xact_age, CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 200) END AS query FROM pg_stat_activity WHERE pid IN (SELECT unnest(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE wait_event_type = 'Lock') LIMIT 20"
bash scripts/db-ro.sh pg -- "SELECT datname, deadlocks FROM pg_stat_database WHERE datname IS NOT NULL ORDER BY deadlocks DESC LIMIT 10"
```

- The head of the chain is the blocker that is not itself blocked. `idle in transaction` at the head means the app forgot to commit. A DDL statement (`ALTER TABLE`, `CREATE INDEX` without `CONCURRENTLY`) in the chain is usually a migration from the deploy. If the fix is an index, `CREATE INDEX CONCURRENTLY` and `DROP INDEX CONCURRENTLY` fail inside a transaction block, so run them outside `BEGIN` and outside any migration-tool transaction (see `sre-diagnostics`).
- `blocked_by` containing `0` means a prepared transaction holds the lock: check `pg_prepared_xacts` and escalate to the DB owner; do not cancel anything.
- Deadlocks are resolved by the server (one transaction errors). A rising `deadlocks` count is an access-order bug in the app; the server log has the details (`log_lock_waits`, deadlock reports).

Proposal: cancel, then terminate, the head blocker. Evidence captured, proposal with pid, query, transaction age and who owns the app; one pid at a time.

**Gate: approval required.**
```sql
-- 1) cancel first: stops the current statement, keeps the session (an idle-in-transaction blocker has no statement to cancel, go to 2)
SELECT pg_cancel_backend(<pid>);
```

Wait 10 s and re-run the blocking query. Only if the same pid still blocks, and the approval covers terminate:

PG14 and later:

**Gate: approval required.**
```sql
-- 2) terminate: ends the session and rolls back its transaction; waits up to 5 s for it to exit
SELECT pg_terminate_backend(<pid>, 5000);
```

PG13 (no timeout argument):

**Gate: approval required.**
```sql
-- 2) terminate, PG13 only: ends the session and rolls back its transaction
SELECT pg_terminate_backend(<pid>);
```

Verify: the blocked list empties; the waiting queries complete; error rate recovers.

## 3. Long-running queries and transactions

```bash
bash scripts/db-ro.sh pg -- "SELECT pid, usename, application_name, client_addr, state, wait_event_type, wait_event, now() - xact_start AS xact_age, now() - query_start AS query_age, CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 200) END AS query FROM pg_stat_activity WHERE backend_type = 'client backend' AND xact_start IS NOT NULL ORDER BY xact_start LIMIT 20"
bash scripts/db-ro.sh pg -- "SELECT pid, state, backend_xid, backend_xmin, greatest(age(backend_xid), age(backend_xmin)) AS horizon_age, now() - xact_start AS xact_age, CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 120) END AS query FROM pg_stat_activity WHERE backend_xid IS NOT NULL OR backend_xmin IS NOT NULL ORDER BY horizon_age DESC LIMIT 10"
```

- An old `backend_xid` or `backend_xmin` stops vacuum from removing dead rows anywhere in the cluster (bloat, section 5). A session idle in a transaction after a write has `backend_xid` set and `backend_xmin` empty, which is why both are checked. Replication slots and `hot_standby_feedback` replicas hold the horizon back too.
- The query text is truncated at `track_activity_query_size` (1024 bytes by default) and can contain customer data: redact before sharing. Text containing "password" is replaced by a marker in these queries.
- Cancel/terminate: same gated blocks as section 2.

## 4. Replication lag

On the primary (PG10+):

```bash
bash scripts/db-ro.sh pg -- "SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag, CASE WHEN pg_is_in_recovery() THEN NULL ELSE pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) END AS replay_bytes_behind FROM pg_stat_replication LIMIT 20"
bash scripts/db-ro.sh pg -- "SELECT slot_name, slot_type, active, wal_status, pg_size_pretty(safe_wal_size) AS safe_wal_size FROM pg_replication_slots ORDER BY restart_lsn LIMIT 20"
```

On a replica:

```bash
bash scripts/db-ro.sh pg -- "SELECT pg_is_in_recovery() AS is_replica, CASE WHEN NOT pg_is_in_recovery() THEN 'n/a (primary)' ELSE COALESCE(r.status, 'not connected') END AS receiver, now() - r.last_msg_receipt_time AS since_last_msg, now() - pg_last_xact_replay_timestamp() AS since_last_replayed_xact, CASE WHEN r.status = 'streaming' AND now() - r.last_msg_receipt_time < greatest(interval '60 seconds', current_setting('wal_receiver_timeout')::interval) THEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() END AS replay_caught_up FROM (SELECT 1) one LEFT JOIN pg_stat_wal_receiver r ON true LIMIT 1"
bash scripts/db-ro.sh pg -- "SELECT status, sender_host, last_msg_receipt_time, latest_end_time FROM pg_stat_wal_receiver LIMIT 1"
```

- `replay_caught_up` only compares what the replica **received** with what it replayed. It is shown only while `receiver = streaming` and the last message from the primary is younger than `greatest(60 s, wal_receiver_timeout)`; otherwise it is empty. On an idle but healthy link the standby asks the primary for a reply at about half of `wal_receiver_timeout` (default 60 s), so `since_last_msg` stays under that (lab: peak 30.6 s with the default; 99 s with 150 s). `wal_receiver_status_interval` governs standby-to-primary reports and does not refresh this column. On a primary `receiver` reads `n/a (primary)`. `receiver = not connected` means the replica is cut off and falling behind, even though its own LSNs look equal: check the primary's `pg_stat_replication` (no row for this replica) and the replica's log.
- The primary is the authority on lag. Prefer `replay_bytes_behind`: `replay_lag` can stay at a small, stale value while replay is paused or stuck.
- `since_last_replayed_xact` grows on an idle primary even when the replica is fully caught up: there is simply nothing new to replay.
- `*_lag` columns are NULL when the standby has caught up and nothing is being sent; that is not an error.
- `safe_wal_size` is NULL when `max_slot_wal_keep_size = -1` (the default: slots may retain unlimited WAL).
- A replica that is far behind is not a failover target (data loss). Long queries on a replica can pause replay (`max_standby_streaming_delay`); check `pg_stat_database_conflicts` on the replica.

## 5. Disk, WAL growth and bloat

```bash
bash scripts/db-ro.sh pg -- "SELECT slot_name, active, wal_status, pg_size_pretty(pg_wal_lsn_diff(CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_lsn() END, restart_lsn)) AS retained_wal FROM pg_replication_slots ORDER BY restart_lsn LIMIT 20"
bash scripts/db-ro.sh pg -- "SELECT archived_count, failed_count, last_failed_wal, last_failed_time FROM pg_stat_archiver LIMIT 1"
bash scripts/db-ro.sh pg -- "SELECT count(*) AS files, pg_size_pretty(sum(size)) AS total FROM pg_ls_waldir() LIMIT 1"
bash scripts/db-ro.sh pg -- "SELECT datname, pg_size_pretty(sz) AS size, temp_bytes FROM (SELECT datname, pg_database_size(datname) AS sz, temp_bytes FROM pg_stat_database WHERE datname IS NOT NULL) s ORDER BY sz DESC LIMIT 20"
bash scripts/db-ro.sh pg -- "SELECT schemaname, relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 20"
bash scripts/db-ro.sh pg -- "SELECT datname, age(datfrozenxid) AS xid_age, mxid_age(datminmxid) AS mxid_age FROM pg_database ORDER BY 2 DESC LIMIT 10"
bash scripts/db-ro.sh pg -- "SELECT pid, datname, relid::regclass AS rel, phase FROM pg_stat_progress_vacuum LIMIT 20"
```

WAL keeps growing for three reasons: an inactive replication slot (`active = f`, large `retained_wal`), failing archiving (`failed_count` rising), or a checkpoint/replication backlog. Bloat grows when old transactions (section 3) or slots hold back vacuum.

Wraparound: anti-wraparound autovacuum starts when a table's age passes `autovacuum_freeze_max_age` (default 200 million). `xid_age` above that and still rising means it is not keeping up: look for the blockers in section 3 and the slots above. Escalate to the DB owner now above about 1.5 billion, or on any `must be vacuumed within N transactions` warning in the log. For reference, the PG14+ vacuum failsafe triggers at `vacuum_failsafe_age` (default 1.6 billion); the server starts warning 40 million transactions before wraparound and stops assigning new XIDs with 3 million left. The same applies to `mxid_age`.

`pg_ls_waldir()` and `pg_database_size()` need `pg_monitor`; managed services may hide `pg_ls_waldir()`. `pg_database_size()` reads every file of the database, so it is computed once per row in the query above.

Proposal: drop an inactive slot only with the consumer's owner on the call, after evidence capture; the consumer (replica, CDC pipeline) must be rebuilt afterwards. Replication slot functions are restricted to superusers and roles with the `REPLICATION` attribute (not `pg_signal_backend` or `pg_monitor`), so the operator role needs `REPLICATION` (on a managed service, use the provider's admin role).

**Gate: approval required.**
```sql
-- operator role; only a slot that shows active = f, named in the approval
SELECT pg_drop_replication_slot('<slot_name>');
```

Disk-reclaiming maintenance (rewrites, `pg_repack`) is a change-window job, not triage: see the never-run list in [destructive-commands.md](destructive-commands.md).

## 6. Slow queries and CPU

```bash
bash scripts/db-ro.sh pg -- "SELECT queryid, calls, round(total_exec_time::numeric, 1) AS total_ms, round(mean_exec_time::numeric, 1) AS mean_ms, rows, CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 200) END AS query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 15"
bash scripts/db-ro.sh pg -- "SELECT wait_event_type, wait_event, count(*) AS n FROM pg_stat_activity WHERE state = 'active' GROUP BY 1, 2 ORDER BY n DESC LIMIT 20"
bash scripts/db-ro.sh pg -- "EXPLAIN SELECT <columns> FROM <table> WHERE <predicate>"
```

- `pg_stat_statements` needs the extension in `shared_preload_libraries` and `CREATE EXTENSION` in the database; if it is missing, use the managed query view (below) or the slow query log (`log_min_duration_statement`).
- Its counters are cumulative since the last reset. Compare two snapshots a few minutes apart instead of reading totals (the delta procedure is in [../SKILL.md](../SKILL.md), "Latency up, cause unknown").
- Query text that contains "password" (for example `ALTER ROLE ... PASSWORD '...'`, which it stores unnormalised) is replaced by a marker. Keep that `CASE` when you adapt the query.
- `EXPLAIN` needs `SELECT` on the tables (see Access); the triage role gets "permission denied".
- Many active sessions with no wait event = CPU-bound; `IO` waits = disk; `LWLock` = internal contention (buffer mapping, WAL insert).
- Plain `EXPLAIN` only. `EXPLAIN ANALYZE` executes the statement, including any write in it: run it on a replica or staging, with approval if it must touch prod.

## Managed services

| | Amazon RDS / Aurora PostgreSQL | Cloud SQL for PostgreSQL | Azure Database for PostgreSQL flexible server |
|---|---|---|---|
| Admin role | `rds_superuser` (not a real superuser) | `cloudsqlsuperuser` (no superuser attribute) | `azure_pg_admin` (`azuresu` is Microsoft's) |
| Triage role | grant `pg_monitor` to a dedicated login | create it **in SQL** (Access above); console/gcloud users get `cloudsqlsuperuser` | grant `pg_monitor` to a dedicated login |
| Query/load view | CloudWatch Database Insights (the Performance Insights console reached end of life 2026-07-31 and was migrated to it; the `aws pi get-resource-metrics` API still works) | Query insights | Query Store (`query_store.qs_view`) and Query Performance Insight |
| Cancel/terminate | same functions; the admin role cannot signal the provider's own sessions (confirm live) | same | same |
| Failover | `aws rds failover-db-cluster` (Aurora, Multi-AZ DB cluster) or `aws rds reboot-db-instance --force-failover` (Multi-AZ instance) | `gcloud sql instances failover` (HA instances) | `az postgres flexible-server restart --failover Planned` (or `Forced`), HA servers only |

Failover is never done in SQL on a managed service. Before proposing one, check replica lag (section 4), confirm the incident is the database host and not the app, and expect clients to reconnect (DNS/endpoint flip, 30–120 s of errors).

Proposal: managed failover. Evidence captured, IC and DB owner approve, lag checked, rollback is "fail back" (another failover). Use only the one block for your platform; each is a separate approval.

Aurora PostgreSQL or a Multi-AZ DB cluster:

**Gate: approval required.**
```bash
aws rds failover-db-cluster --profile <profile> --region <region> --db-cluster-identifier <cluster>
```

RDS Multi-AZ DB instance:

**Gate: approval required.**
```bash
aws rds reboot-db-instance --profile <profile> --region <region> --db-instance-identifier <db> --force-failover
```

Cloud SQL (HA instances):

**Gate: approval required.**
```bash
gcloud sql instances failover <instance> --project=<PROJECT_ID>
```

Azure flexible server (HA servers). `--failover Forced` brings the primary down first (Azure's mode for testing or an unresponsive primary) and needs its own approval:

**Gate: approval required.**
```bash
az postgres flexible-server restart --subscription <subscription-id> --resource-group <rg> --name <server> --failover Planned
```

Verify: the new writer is healthy (`aws rds describe-db-clusters`, `gcloud sql instances describe`, `az postgres flexible-server show`), connections recover, replica lag returns to normal.

---
name: sre-database-triage
description: "Use when Postgres, MySQL/MariaDB or Redis is slow or failing: connection exhaustion, locks, long or slow queries, replication lag, disk/WAL/bloat, Redis memory/eviction, DB CPU. Read-only; kill and failover are gated."
---

# Database triage

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-incident-command` (roles, severity), `sre-engineer` / `sre-diagnostics` (the wider investigation), `sre-change-safety` (the deploy that preceded it), `sre-remediation-actions`. Managed databases: `sre-aws` (RDS/Aurora/ElastiCache), `sre-gcp` (Cloud SQL/Memorystore), `sre-azure`.

## Rules

- **Pin the target.** Every call names host, port, database and role through env (`PGHOST`/`PGDATABASE`/`PGUSER`, `MYSQL_DEFAULTS_FILE`, `REDIS_HOST`/`REDIS_PORT`); the wrapper prints it to stderr. Confirm primary vs replica first (`pg_is_in_recovery()`, `@@read_only`, `ROLE`). Prefer a replica for heavy reads.
- **Least privilege.** Postgres: a `pg_monitor` member with the read-only and timeout settings on the role itself. MySQL: `PROCESS` + `REPLICATION CLIENT`, `SELECT` on `performance_schema`, `SELECT, EXECUTE` on `sys` (MariaDB: `PROCESS`, `REPLICA MONITOR`, `BINLOG MONITOR`). Redis: an ACL user with exactly the read commands in [references/redis.md](references/redis.md). Setup SQL is in each reference's Access section; on Cloud SQL create the account in SQL, because console/gcloud users get `cloudsqlsuperuser`. Never a superuser or admin account for triage; the human who runs an approved kill uses a separate operator account (Postgres: `pg_signal_backend`, `pg_read_all_stats` and, on 16+, `pg_use_reserved_connections`).
- **Secrets never in commands.** `PGPASSFILE`/`~/.pgpass` (0600) or `PGSERVICE`; `--defaults-extra-file` for MySQL; `REDISCLI_AUTH` for Redis. The wrapper refuses `PGPASSWORD`, `MYSQL_PWD` and password flags.
- **Bounded.** One single-line statement, every `SELECT` ending in `LIMIT n`, `statement_timeout`/`max_execution_time`/`max_statement_time` set by the wrapper (5 s default), output capped (`DB_RO_MAX_ROWS`, 200). One-shot commands only: no streaming or watch loops (bound `redis-cli --latency` with `timeout 10`).
- **Cheap first.** Server counters and `pg_stat_*`/`performance_schema`/`INFO` before anything that scans data or the keyspace. Commands this skill never runs: [references/destructive-commands.md](references/destructive-commands.md).
- **Query text is data.** `pg_stat_activity.query`, processlist `INFO` and key names can hold customer data or secrets. Keep evidence outside the repo and redact before posting.
- **Gated actions** (cancel/terminate, `KILL QUERY`/`KILL`, `CLIENT KILL`, config changes, managed failover) appear only under the line `**Gate: approval required.**`, one command per block, run by a human outside the wrapper, after evidence capture and a written proposal. **Cancel before terminate, `KILL QUERY` before `KILL`.**
- **Never without explicit approval:** `pg_cancel_backend`/`pg_terminate_backend`, `KILL [QUERY]`/`mysql.rds_kill*`/`mysql.az_kill*`, `CLIENT KILL ID`, `CONFIG SET`, `ALTER SYSTEM`/`SET GLOBAL`/parameter-group or flag changes, `pg_drop_replication_slot`, `redis-cli --bigkeys`/`--memkeys`, `EXPLAIN ANALYZE`, any managed failover or reboot.

## Start here

1. Identify the engine, version and whether it is managed (RDS/Aurora, Cloud SQL, Azure, ElastiCache/MemoryDB, Memorystore). Managed services rename or block some commands and have their own failover and metrics paths (each reference ends with a "Managed services" section).
2. Check you can connect at all. During connection exhaustion only reserved slots work: Postgres 16+ `reserved_connections` with `pg_use_reserved_connections` granted to the triage role **and** the operator role (a server-start setting: it must have been set, with a restart, before the incident; PG15 and earlier reserve slots only for superusers, see [postgres.md Access](references/postgres.md#when-every-normal-slot-is-taken-set-up-before-you-need-it)), MySQL's one extra `CONNECTION_ADMIN` connection. If you cannot connect, use the provider's metrics and the app's pool metrics, and give the human the commands to run from a session they already hold.

   ```bash
   bash scripts/db-ro.sh pg -- "SELECT version(), current_user, pg_is_in_recovery() AS is_replica LIMIT 1"
   ```

   When you cannot get in, read the connection count from the provider (read-only):

   ```bash
   aws cloudwatch get-metric-statistics --profile <profile> --region <region> --namespace AWS/RDS --metric-name DatabaseConnections --dimensions Name=DBInstanceIdentifier,Value=<db> --start-time <start-ISO8601> --end-time <end-ISO8601> --period 60 --statistics Maximum
   az monitor metrics list --subscription <subscription-id> --resource <server-resource-id> --metric active_connections --interval PT1M --offset 1h
   ```

   Cloud SQL: Metrics Explorer, `cloudsql.googleapis.com/database/postgresql/num_backends` (MySQL: `database/network/connections`). ElastiCache `CurrConnections`, Memorystore `clients/connected`. ElastiCache **serverless** blocks `SLOWLOG`, `LATENCY`, `MEMORY` and `CLIENT LIST`, so use CloudWatch there from the start (`ElastiCacheProcessingUnits`, `BytesUsedForCache`, `SuccessfulReadRequestLatency`, `CurrConnections`). On RDS/Aurora the Performance Insights API (`aws pi get-resource-metrics`) still works for CLI users after the console moved to Database Insights.

3. Capture evidence once, before any proposal (bounded, read-only, 0700 directory outside any git work tree; the script refuses a path inside one, and replaces query text that contains "password" with a marker; other query text is still customer data. It does not capture `SHOW ENGINE INNODB STATUS`, whose statement text cannot be redacted reliably; lock waits come from the redacted `sys.x$` / `information_schema` queries):

   ```bash
   bash scripts/db-snapshot.sh pg ~/incidents/<id>/db-t0        # or mysql | mariadb | redis
   ```

4. Follow the symptom table, then the section in the engine reference.

| Symptom | Postgres | MySQL / MariaDB | Redis |
|---|---|---|---|
| "too many connections", pool timeouts | [postgres.md §1](references/postgres.md#1-connection-exhaustion-too-many-clients-remaining-connection-slots-are-reserved-pool-timeouts) | [mysql.md §1](references/mysql.md#1-connection-exhaustion-too-many-connections-error-1040) | [redis.md §3](references/redis.md#3-connections-and-clients) |
| Requests hang, lock waits, deadlocks | [§2](references/postgres.md#2-locks-blocking-chains-and-deadlocks) | [§2](references/mysql.md#2-locks-blocking-and-deadlocks) | n/a (single-threaded: see §1 latency) |
| One query runs for minutes | [§3](references/postgres.md#3-long-running-queries-and-transactions) | [§3](references/mysql.md#3-long-running-queries) | [§1](references/redis.md#1-latency-and-slow-commands) |
| Replica behind / stale reads | [§4](references/postgres.md#4-replication-lag) | [§4](references/mysql.md#4-replication-lag) | [§4](references/redis.md#4-replication-and-persistence) |
| Disk full, WAL/binlog growth, bloat | [§5](references/postgres.md#5-disk-wal-growth-and-bloat) | [§5](references/mysql.md#5-slow-queries-cpu-disk) | [§4](references/redis.md#4-replication-and-persistence) (RDB/AOF) |
| Slow queries, high CPU | [§6](references/postgres.md#6-slow-queries-and-cpu) | [§5](references/mysql.md#5-slow-queries-cpu-disk) | [§5](references/redis.md#5-cpu) |
| Memory full, evictions, OOM errors | (OS / `work_mem` sizing: escalate) | (buffer pool sizing: escalate) | [§2](references/redis.md#2-memory-and-eviction) |
| Latency up, cause unknown ("is it the DB?") | [below](#latency-up-cause-unknown-is-it-the-db), then [§6](references/postgres.md#6-slow-queries-and-cpu), §2/§3 | [below](#latency-up-cause-unknown-is-it-the-db), then [§5](references/mysql.md#5-slow-queries-cpu-disk), §2/§3 | [below](#latency-up-cause-unknown-is-it-the-db), then [§1](references/redis.md#1-latency-and-slow-commands) |

### Latency up, cause unknown (is it the DB?)

Counters (`pg_stat_statements`, digests, `INFO commandstats`) are cumulative, so one snapshot cannot show what changed. Read-only route:

1. Managed: open the load view for the incident window and for the same window a day earlier (Database Insights top SQL and waits, Cloud SQL Query insights, Azure Query Store / Query Performance Insight).
2. Take two snapshots 3–5 minutes apart and compare them:

   ```bash
   bash scripts/db-snapshot.sh <engine> ~/incidents/<id>/db-t0
   bash scripts/db-snapshot.sh <engine> ~/incidents/<id>/db-t1
   ```

   Delta = t1 − t0 per statement (`top-statements` / `top-digests`: calls and total time, so mean time per call over the window), plus wait events, lock waits, replica lag and, for Redis, `INFO stats`/`commandstats` and the slow log.
3. Decide:
   - A statement whose mean time in the window doubled: a plan or data change (check `last_autoanalyze`, row growth, `EXPLAIN` with an account that may read the tables).
   - Lock waits: §2. CPU or I/O saturation: Postgres §6, MySQL §5, Redis §5.
   - None of these, and the database's own latency and load are flat: **stop, the database is not the cause.** Hand back to `sre-diagnostics` with both snapshots as evidence.

## Fix order when the database is the symptom, not the cause

Most database pages during an incident are caused by a client: a deploy that raised the pool size, leaked connections, or shipped a query without an index. In that case the fastest safe fix is on the app side (roll back or lower the pool, via `sre-change-safety` / `sre-k8s-safe-remediation`), and database-side kills only buy minutes. Order:

1. App-side rollback or pool change (gated in its own skill).
2. Cancel the specific statement (`pg_cancel_backend`, `KILL QUERY` / `mysql.rds_kill_query` / `mysql.az_kill_query`).
3. Terminate the specific session (`pg_terminate_backend`, `KILL` / `mysql.rds_kill` / `mysql.az_kill`, `CLIENT KILL ID`).
4. Config change (parameter group / flags / `CONFIG SET`), propose only, usually after the incident. Some settings need a restart (Postgres `reserved_connections`, `max_connections`).
5. Managed failover: last resort, replica lag checked first, IC and DB owner approve.

Each gated block in the references states its evidence, risk and verification. Approval names the exact target (pid, thread id, client id, instance); a new pid needs a new approval.

## Bundled scripts and references

```bash
bash scripts/db-ro.sh <pg|mysql|mariadb|redis> -- <statement>   # read-only allowlist guard; timeouts, LIMIT, capped output; exit 1 = error, 3 = refused
bash scripts/db-snapshot.sh <pg|mysql|mariadb|redis> <outdir>  # evidence bundle before any gated action
bash tests/run-tests.sh                                       # offline tests (no database needed)
```

- [references/postgres.md](references/postgres.md) · [references/mysql.md](references/mysql.md) · [references/redis.md](references/redis.md)
- [references/destructive-commands.md](references/destructive-commands.md): never-run list (machine-read by the tests) and every gated action with risk and reversibility.

The wrapper is a guard against mistakes, not a security boundary: the read-only role is what actually protects production. If neither a database client nor an MCP server is available, give the human the exact commands and stop.

## Output

- Target (engine, version, host, primary/replica, managed or not), evidence path, findings with the queries used, likely cause and confidence, proposed actions in fix order with risk/reversibility and the approver, verification result.

## Stop and escalate

- Transaction ID wraparound warnings, a replica that is not caught up when failover is on the table, a blocker that is a prepared transaction, or any data-loss risk: escalate to the DB owner and IC.
- A gated action did not help, or metrics got worse: stop, do not try the next kill on your own, report.

Last reviewed: 2026-10-17

## SOURCES

Fetched and checked 2026-10-17 (current versions: PostgreSQL 18 docs, MySQL 8.4, MariaDB current, Redis 8 docs).

PostgreSQL
- Statistics views (`pg_stat_activity`, `pg_stat_replication`, `pg_stat_wal_receiver`, `pg_stat_database`, `pg_stat_user_tables`, `pg_stat_progress_vacuum`, `pg_stat_archiver`, `pg_stat_io`, `pg_stat_checkpointer`): https://www.postgresql.org/docs/current/monitoring-stats.html (version boundaries checked against /docs/10, /13, /14, /15, /16, /17)
- `pg_blocking_pids` and its lock-manager cost: https://www.postgresql.org/docs/current/functions-info.html
- `pg_terminate_backend(pid)` only on 13: https://www.postgresql.org/docs/13/functions-admin.html · timeout argument from 14: https://www.postgresql.org/docs/14/functions-admin.html
- `pg_cancel_backend`, `pg_terminate_backend(pid, timeout)`, `pg_last_xact_replay_timestamp`, `pg_wal_lsn_diff`, `pg_ls_waldir`, `pg_database_size`, `pg_drop_replication_slot`: https://www.postgresql.org/docs/current/functions-admin.html
- `pg_monitor`, `pg_signal_backend`, `pg_use_reserved_connections`: https://www.postgresql.org/docs/current/predefined-roles.html
- `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`, `transaction_timeout` (17+), `default_transaction_read_only`: https://www.postgresql.org/docs/current/runtime-config-client.html
- `max_connections`, `superuser_reserved_connections`, `reserved_connections` (16+; "can only be set at server start"): https://www.postgresql.org/docs/current/runtime-config-connection.html
- Role-level settings and `CONNECTION LIMIT` (`ALTER ROLE ... SET`): https://www.postgresql.org/docs/current/sql-alterrole.html · https://www.postgresql.org/docs/current/sql-createrole.html
- psql `\password` sends the password encrypted (not in clear in history or logs): https://www.postgresql.org/docs/current/app-psql.html
- Connection `options` parameter; conninfo values beat environment variables: https://www.postgresql.org/docs/current/libpq-connect.html · service file: https://www.postgresql.org/docs/current/libpq-pgservice.html
- `log_lock_waits`, `log_min_duration_statement`: https://www.postgresql.org/docs/current/runtime-config-logging.html
- `max_standby_streaming_delay`, `hot_standby_feedback`, `wal_sender_timeout` and `wal_receiver_timeout` (both default 60 s), `wal_receiver_status_interval` (10 s): https://www.postgresql.org/docs/current/runtime-config-replication.html · idle-link `since_last_msg` peaks at about `wal_receiver_timeout`/2 (lab: Database Reviewer re-run, PG16 replica)
- `pg_monitor` includes `pg_read_all_settings`, `pg_read_all_stats`, `pg_stat_scan_tables`: https://www.postgresql.org/docs/current/predefined-roles.html
- Replication slot functions are restricted to superusers and roles with `REPLICATION`: https://www.postgresql.org/docs/current/functions-admin.html (Replication Management Functions)
- `ALTER ROLE ... SET` and `PGOPTIONS` both set session defaults: https://www.postgresql.org/docs/current/config-setting.html · client startup options beat role settings (lab: Database Reviewer re-run)
- psql `-w` / `--no-password` (never prompt): https://www.postgresql.org/docs/current/app-psql.html
- `pg_stat_wal_receiver` `status`, `last_msg_receipt_time`; `pg_stat_activity.backend_xid`/`backend_xmin`: https://www.postgresql.org/docs/current/monitoring-stats.html
- `pg_replication_slots` (`wal_status`, `safe_wal_size` 13+, `inactive_since` 17+): https://www.postgresql.org/docs/current/view-pg-replication-slots.html
- `pg_stat_statements` (`total_exec_time` 13+; `track_utility` on by default, so utility statements such as `ALTER ROLE` are recorded): https://www.postgresql.org/docs/current/pgstatstatements.html
- Wraparound, `age(datfrozenxid)`, `autovacuum_freeze_max_age` default 200 M, warnings at 40 M before wraparound, XID assignment stops at 3 M left: https://www.postgresql.org/docs/current/routine-vacuuming.html · `vacuum_failsafe_age` default 1.6 B: https://www.postgresql.org/docs/current/runtime-config-vacuum.html
- `EXPLAIN` as the `pg_monitor` role fails with "permission denied for table" (lab, PG 13–17; Database Reviewer live results #28)
- `VACUUM FULL` lock and disk: https://www.postgresql.org/docs/current/sql-vacuum.html · `EXPLAIN ANALYZE` executes: https://www.postgresql.org/docs/current/sql-explain.html
- `.pgpass` 0600, `PGPASSFILE`, `PGOPTIONS`, `PGCONNECT_TIMEOUT`: https://www.postgresql.org/docs/current/libpq-pgpass.html · https://www.postgresql.org/docs/current/libpq-envars.html
- `psql -X`, `ON_ERROR_STOP`: https://www.postgresql.org/docs/current/app-psql.html
- PostgreSQL JDBC `ApplicationName` default (`PostgreSQL JDBC Driver`): https://jdbc.postgresql.org/documentation/use/
- PgBouncer startup parameters (only tracked parameters are allowed, others raise an error unless listed in `ignore_startup_parameters`, which may include `options`): https://www.pgbouncer.org/config.html#ignore_startup_parameters · 1.24.1 rejects the wrapper's `options` (lab: Database Reviewer re-run)

MySQL 8.4 (8.0 where noted)
- `SHOW REPLICA STATUS` (REPLICATION CLIENT): https://dev.mysql.com/doc/refman/8.4/en/show-replica-status.html · 8.0.22 rename: https://dev.mysql.com/doc/refman/8.0/en/show-replica-status.html · `SHOW SLAVE STATUS` removed in 8.4: https://dev.mysql.com/doc/refman/8.4/en/mysql-nutshell.html
- `INNODB_LOCK_WAITS` removed in 8.0: https://dev.mysql.com/doc/refman/8.0/en/mysql-nutshell.html · `sys.innodb_lock_waits`: https://dev.mysql.com/doc/refman/8.4/en/sys-innodb-lock-waits.html · `data_lock_waits`: https://dev.mysql.com/doc/refman/8.4/en/performance-schema-data-lock-waits-table.html
- `performance_schema.processlist`: https://dev.mysql.com/doc/refman/8.4/en/performance-schema-processlist-table.html · `sys.processlist` / `sys.x$processlist`: https://dev.mysql.com/doc/refman/8.4/en/sys-processlist.html · `INNODB_TRX`: https://dev.mysql.com/doc/refman/8.4/en/information-schema-innodb-trx-table.html
- Plain sys views shorten statements with `format_statement()`, which replaces the **middle** with an ellipsis at `statement_truncate_len` (default 64); `x$` views show raw values: https://dev.mysql.com/doc/refman/8.4/en/sys-format-statement.html · https://dev.mysql.com/doc/refman/8.4/en/sys-sys-config.html · https://dev.mysql.com/doc/refman/8.4/en/sys-schema-usage.html
- `SHOW ENGINE INNODB STATUS` prints transaction SQL without password rewriting, a line filter can be defeated by statement text that imitates monitor markers, and MariaDB `SHOW GRANTS` prints the password hash (lab: Database Reviewer re-run, rounds 2 and 3)
- `max_execution_time` (SELECT only): https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html · `MAX_EXECUTION_TIME` hint: https://dev.mysql.com/doc/refman/8.4/en/optimizer-hints.html
- Extra `CONNECTION_ADMIN` connection: https://dev.mysql.com/doc/refman/8.4/en/too-many-connections.html · status variables: https://dev.mysql.com/doc/refman/8.4/en/server-status-variables.html
- `KILL` / `KILL QUERY`, PROCESS and CONNECTION_ADMIN: https://dev.mysql.com/doc/refman/8.4/en/kill.html · privileges: https://dev.mysql.com/doc/refman/8.4/en/privileges-provided.html
- `SHOW ENGINE INNODB STATUS`: https://dev.mysql.com/doc/refman/8.4/en/show-engine.html · digests: https://dev.mysql.com/doc/refman/8.4/en/performance-schema-statement-summary-tables.html · `sys.statement_analysis`: https://dev.mysql.com/doc/refman/8.4/en/sys-statement-analysis.html
- Applier lag columns: https://dev.mysql.com/doc/refman/8.4/en/performance-schema-replication-applier-status-by-worker-table.html · `information_schema.TABLES`: https://dev.mysql.com/doc/refman/8.4/en/information-schema-tables-table.html · `SHOW BINARY LOGS`: https://dev.mysql.com/doc/refman/8.4/en/show-binary-logs.html · `binlog_expire_logs_seconds`: https://dev.mysql.com/doc/refman/8.4/en/replication-options-binary-log.html
- `--defaults-extra-file` must be first: https://dev.mysql.com/doc/refman/8.4/en/option-file-options.html · client options: https://dev.mysql.com/doc/refman/8.4/en/mysql-command-options.html (`--init-command` is a single SQL statement)
- `SHOW GRANTS` (own account needs no extra privilege; other accounts need `SELECT` on `mysql`): https://dev.mysql.com/doc/refman/8.4/en/show-grants.html
- `sys` needs `SELECT` and `EXECUTE`: https://dev.mysql.com/doc/refman/8.4/en/sys-schema-prerequisites.html
- `INNODB_TABLESPACES` (needs `PROCESS`; `FILE_SIZE`, `ALLOCATED_SIZE`): https://dev.mysql.com/doc/refman/8.4/en/information-schema-innodb-tablespaces-table.html
- `EXPLAIN` needs the privileges of the explained statement: https://dev.mysql.com/doc/refman/8.4/en/explain.html
- `CREATE USER ... REQUIRE SSL WITH MAX_USER_CONNECTIONS`: https://dev.mysql.com/doc/refman/8.4/en/create-user.html
- `--ssl-mode=VERIFY_IDENTITY` verifies against the configured CA: https://dev.mysql.com/doc/refman/8.4/en/connection-options.html
- Administrative connection interface (`admin_port` 33062, `SERVICE_CONNECTION_ADMIN`, not limited by `max_connections`): https://dev.mysql.com/doc/refman/8.4/en/administrative-connection-interface.html

MariaDB
- `SHOW REPLICA STATUS` / `SHOW SLAVE STATUS`, REPLICA MONITOR, `Seconds_Behind_Master` with parallel replication: https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/show/show-replica-status
- `INFORMATION_SCHEMA.INNODB_LOCK_WAITS` (current in MariaDB): https://mariadb.com/docs/server/reference/system-tables/information-schema/information-schema-tables/information-schema-innodb-tables/information-schema-innodb_lock_waits-table
- `max_statement_time` (seconds): https://mariadb.com/docs/server/ha-and-performance/optimization-and-tuning/query-optimizations/aborting-statements
- `KILL [QUERY] [ID]`: https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/kill
- `BINLOG MONITOR`, `REPLICA MONITOR`, `REPLICATION CLIENT` alias: https://mariadb.com/docs/server/reference/sql-statements/account-management-sql-statements/grant
- sys schema: https://mariadb.com/docs/server/reference/system-tables/sys-schema
- `INNODB_SYS_TABLESPACES` (`FILE_SIZE`, `ALLOCATED_SIZE`): https://mariadb.com/docs/server/reference/system-tables/information-schema/information-schema-tables/information-schema-innodb-tables/information-schema-innodb_sys_tablespaces-table
- Client TLS options (`--ssl-ca`, `--ssl-verify-server-cert`; no `ssl-mode`), option groups: https://mariadb.com/docs/server/clients-and-utilities/mariadb-client/mariadb-command-line-client
- `CREATE USER ... MAX_USER_CONNECTIONS`, `MAX_STATEMENT_TIME` (seconds): https://mariadb.com/docs/server/reference/sql-statements/account-management-sql-statements/create-user
- `tx_read_only` deprecated: Warning 1287 on 11.8, and 10.11 has no `transaction_read_only` (lab, Database Reviewer live results F17); 11.1 made `transaction_*` system variables (MDEV-21921): https://mariadb.com/docs/release-notes/community-server/old-releases/11.1/11.1.1

Redis
- `INFO` fields (`evicted_keys`, `maxmemory_policy`, `mem_fragmentation_ratio`, `allocator_frag_ratio`, `master_link_status`): https://redis.io/docs/latest/commands/info/
- `SLOWLOG GET` (times in microseconds; entries hold the arguments): https://redis.io/docs/latest/commands/slowlog-get/ · `LATENCY DOCTOR`: https://redis.io/docs/latest/commands/latency-doctor/ · latency monitor (`latency-monitor-threshold` off by default): https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency-monitor/
- `MEMORY DOCTOR`: https://redis.io/docs/latest/commands/memory-doctor/ · `MEMORY USAGE` (`SAMPLES 0` samples every nested value): https://redis.io/docs/latest/commands/memory-usage/ · `CONFIG GET` (glob patterns, returns any parameter): https://redis.io/docs/latest/commands/config-get/ · eviction policies: https://redis.io/docs/latest/develop/reference/eviction/
- `SCAN` and `COUNT`: https://redis.io/docs/latest/commands/scan/ · `CLIENT LIST`: https://redis.io/docs/latest/commands/client-list/ · `CLIENT KILL`: https://redis.io/docs/latest/commands/client-kill/ · `FAILOVER`: https://redis.io/docs/latest/commands/failover/
- Never-run evidence: https://redis.io/docs/latest/commands/keys/ · https://redis.io/docs/latest/commands/monitor/
- ACL categories and selectors (`%R~`): https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/ (per-command categories from each command page)
- `redis-cli` `--bigkeys`/`--memkeys` (`-i 0.1`), `--latency`, `REDISCLI_AUTH`, `-t <timeout>`: https://redis.io/docs/latest/develop/tools/cli/ · `-t` is new in redis-cli 7.4 (#10609), so the wrapper feature-detects it from `redis-cli --help`: https://raw.githubusercontent.com/redis/redis/7.4.0/00-RELEASENOTES
- redis-cli exits 0 on `NOPERM`/`WRONGPASS`/`ERR`, and redis-cli 8 sends `READONLY` before `--bigkeys`/`--memkeys` (lab, Database Reviewer live results F10, F12)

Managed services
- Reserved connections on managed PostgreSQL 16+ (checked 2026-10-22): RDS `reserved_connections` replaces `rds.rds_superuser_reserved_connections`, `rds_superuser` is a member of `pg_use_reserved_connections`: https://docs.aws.amazon.com/AmazonRDS/latest/PostgreSQLReleaseNotes/postgresql-versions.html · Aurora, same wording: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraPostgreSQLReleaseNotes/AuroraPostgreSQL.Updates.html · `rds_superuser` holds it with ADMIN: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Roles.View.html · `rds.rds_superuser_reserved_connections` only up to 15 (static): https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Parameters.html · Cloud SQL flag `reserved_connections` (16+, restart required): https://docs.cloud.google.com/sql/docs/postgres/flags · Azure `reserved_connections` read-only 5: https://learn.microsoft.com/en-us/azure/postgresql/server-parameters/param-connections-authentication-connection-settings · Azure grant of `pg_use_reserved_connections` (March 2026 maintenance): https://learn.microsoft.com/en-us/azure/postgresql/release-notes-maintenance/2026-march
- RDS PostgreSQL `rds_superuser`: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Roles.html · `mysql.rds_kill`/`rds_kill_query`: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/mysql-stored-proc-ending.html · `mysql.rds_show_configuration` (`binlog retention hours`): https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/mysql-stored-proc-configuring.html
- Performance Insights end of life (2026-07-31) and CloudWatch Database Insights: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Database-Insights.html · https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html · "The Performance Insights API will continue to exist with no changes": https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Overview.Engines.html
- `aws rds failover-db-cluster`: https://docs.aws.amazon.com/cli/latest/reference/rds/failover-db-cluster.html · `aws rds reboot-db-instance --force-failover`: https://docs.aws.amazon.com/cli/latest/reference/rds/reboot-db-instance.html
- ElastiCache restricted commands, including the serverless-only list (`slowlog`, `latency`, `memory`, `object`, `client list/info/kill`, `lastsave`): https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/SupportedCommands.html · serverless metrics (`ElastiCacheProcessingUnits`, `BytesUsedForCache`): https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/serverless-metrics-events-redis.html · `test-failover` (testing API, may be blocked, 15 node groups per rolling 24 h) · metrics: https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html https://docs.aws.amazon.com/cli/latest/reference/elasticache/test-failover.html · MemoryDB: https://docs.aws.amazon.com/memorydb/latest/devguide/restrictedcommands.html · `aws memorydb failover-shard`: https://docs.aws.amazon.com/cli/latest/reference/memorydb/failover-shard.html
- Cloud SQL `cloudsqlsuperuser` (users created through Cloud SQL get it; users created with the SQL client get only what you grant): https://cloud.google.com/sql/docs/postgres/users · https://cloud.google.com/sql/docs/mysql/users · Query insights: https://cloud.google.com/sql/docs/postgres/using-query-insights · `gcloud sql instances failover`: https://cloud.google.com/sdk/gcloud/reference/sql/instances/failover
- Memorystore blocked commands (including `ACL`): https://cloud.google.com/memorystore/docs/redis/supported-commands · config: https://cloud.google.com/memorystore/docs/redis/configure-redis · metrics: https://cloud.google.com/memorystore/docs/redis/supported-monitoring-metrics · `gcloud redis instances failover` (`--data-protection-mode`): https://cloud.google.com/sdk/gcloud/reference/redis/instances/failover
- Connection metrics: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html · https://cloud.google.com/sql/docs/postgres/admin-api/metrics · https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-dbforpostgresql-flexibleservers-metrics
- Azure PostgreSQL `azure_pg_admin`: https://learn.microsoft.com/azure/postgresql/security/security-manage-database-users · Query Store: https://learn.microsoft.com/azure/postgresql/monitor/concepts-query-store · `az postgres flexible-server restart --failover`: https://learn.microsoft.com/cli/azure/postgres/flexible-server · `az mysql flexible-server restart --failover Forced`: https://learn.microsoft.com/cli/azure/mysql/flexible-server
- Azure Cache for Redis disabled commands: https://learn.microsoft.com/azure/azure-cache-for-redis/cache-configure · metrics: https://learn.microsoft.com/azure/azure-cache-for-redis/monitor-cache-reference · `az redis force-reboot --reboot-type PrimaryNode`: https://learn.microsoft.com/cli/azure/redis · retirement (Basic/Standard/Premium 2028-09-30, Enterprise 2027-03-31): https://learn.microsoft.com/azure/azure-cache-for-redis/retirement-faq
- Azure MySQL flexible server `mysql.az_kill` / `mysql.az_kill_query`: https://learn.microsoft.com/azure/mysql/flexible-server/concept-servers · forced failover semantics (Azure PostgreSQL HA): https://learn.microsoft.com/azure/postgresql/high-availability/concepts-high-availability

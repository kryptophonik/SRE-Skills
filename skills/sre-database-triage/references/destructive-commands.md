# Database commands: never run, and gated

This is the only file in `sre-database-triage` that names never-run commands. The triage references never show them. Gated commands appear in the triage steps only directly under the `**Gate: approval required.**` line, after evidence capture (`bash scripts/db-snapshot.sh <engine> <outdir>`) and a written proposal.

Last reviewed: 2026-10-17. Sources are in the SOURCES section of [../SKILL.md](../SKILL.md).

## Never run (this skill never proposes these, not even with approval)

The table is machine-read by `tests/run-tests.sh`: column 1 is the engine, column 2 is the command exactly as the wrapper would receive it.

| Engine | Command | Why | Use instead |
|---|---|---|---|
| redis | `KEYS *` | O(N) over the whole keyspace and blocks the single command thread; the docs warn it "may ruin performance" on large databases | `SCAN 0 MATCH <pattern> COUNT 100`, or `redis-cli --bigkeys` / `--memkeys` off-peak on a replica |
| redis | `KEYS <pattern>` | Same full scan; a pattern does not make it cheaper | `SCAN` with `MATCH` and `COUNT` |
| redis | `MONITOR` | One MONITOR client can cut throughput by more than 50% (redis.io); it also streams every command, including values | `SLOWLOG GET 25`, `LATENCY DOCTOR`, `INFO commandstats` |
| redis | `FLUSHALL` | Deletes every key in every database | Nothing in triage needs it |
| redis | `FLUSHDB` | Deletes every key in the selected database | Nothing in triage needs it |
| redis | `DEBUG SLEEP 0` | `DEBUG` can block, crash or reload the server (`DEBUG SEGFAULT`, `DEBUG RELOAD`); blocked on ElastiCache, MemoryDB and Memorystore anyway | `LATENCY DOCTOR`, `MEMORY DOCTOR` |
| redis | `SHUTDOWN` | Stops the server; with `NOSAVE` data since the last snapshot is lost | Managed failover (gated) or escalate |
| redis | `CONFIG GET *` | Returns every parameter, including `requirepass` and `masterauth` (names match case-insensitively and as globs) | `INFO memory` (`maxmemory_policy`), `INFO server` |
| redis | `CONFIG GET requirepass` | Prints the password | Nothing in triage needs it |
| redis | `CONFIG RESETSTAT` | Wipes `INFO stats`/`commandstats` counters (evidence) | Snapshot; compare deltas |
| redis | `CONFIG REWRITE` | Rewrites `redis.conf` on disk with the running config | Config through IaC / parameter groups |
| redis | `SLOWLOG RESET` | Wipes the slow log (evidence) | `SLOWLOG GET 25` into the snapshot |
| redis | `LATENCY RESET` | Wipes latency history (evidence) | `LATENCY LATEST`, `LATENCY DOCTOR` |
| redis | `DEBUG OBJECT <key>` | Walks the value on the main thread; `DEBUG` is blocked on managed services | `MEMORY USAGE <key>`, `OBJECT ENCODING <key>` |
| redis | `SAVE` | Synchronous snapshot: blocks every client until the dump finishes | Escalate; persistence is the owner's change |
| redis | `BGSAVE` | Forks the server (copy-on-write memory, fork stall); at peak it can trigger OOM | `INFO persistence` |
| redis | `BGREWRITEAOF` | Same fork cost as `BGSAVE` | `INFO persistence` |
| redis | `CLIENT PAUSE 10000` | Stops serving clients for the timeout | Nothing in triage needs it |
| redis | `CLIENT KILL TYPE normal` | Disconnects every application client at once | Gated `CLIENT KILL ID <id>` for one client |
| pgbouncer | `KILL <db>` | Drops every client and server connection for that database at once; clients see errors | `PAUSE <db>` (transaction pooling) or gated `RECONNECT <db>` (session pooling) in sre-remediation-actions |
| redis | `SCRIPT FLUSH` | Removes cached Lua scripts; clients relying on `EVALSHA` start failing | Escalate to the app owner |
| redis | `FUNCTION FLUSH` | Deletes every loaded function library | Escalate to the app owner |
| redis | `REPLICAOF NO ONE` | Promotes a replica by hand: split brain, the old primary keeps taking writes | Managed failover (gated) or the owner's Sentinel/Cluster procedure |
| redis | `FAILOVER` | Manual primary/replica switch outside the managed or Sentinel/Cluster process | Managed failover (gated) or escalate |
| redis | `SWAPDB 0 1` | Swaps two databases: every client of either sees the other's data | Nothing in triage needs it |
| redis | `DEL <big-key>` | Deletes data; freeing a huge key blocks the main thread | Escalate to the data owner |
| redis | `UNLINK <big-key>` | Deletes data (freed in the background, still data loss) | Escalate to the data owner |
| pg | `VACUUM FULL` | Rewrites the table under an ACCESS EXCLUSIVE lock (blocks reads and writes) and needs free disk equal to the table size, during an incident usually the thing that is short | Find why autovacuum is behind (long transactions, slots); plain `VACUUM` or `pg_repack` in a change window |
| pg | `SELECT pg_stat_reset()` | Wipes the statistics that are your evidence | Snapshot first; never reset during an incident |
| pg | `SELECT pg_stat_statements_reset()` | Wipes query history (evidence) | Snapshot; compare deltas instead |
| pg | `SELECT pg_stat_reset_shared('bgwriter')` | Wipes cluster-wide statistics (evidence); every `pg_stat_reset*` variant is refused | Snapshot first |
| pg | `SELECT pg_stat_reset_single_table_counters(16384)` | Wipes one table's statistics, which autovacuum also uses | Snapshot first |
| pg | `CLUSTER <table>` | Rewrites the table under an ACCESS EXCLUSIVE lock | Change window |
| pg | `REINDEX TABLE <table>` | Non-concurrent `REINDEX` blocks writes to the table (and reads that use the index) | `REINDEX ... CONCURRENTLY` in a change window, via `sre-diagnostics` |
| pg | `LOCK TABLE <table>` | Takes an explicit lock that queues every other session behind it | Nothing in triage needs it |
| pg | `ANALYZE <huge-table>` | Heavy I/O at peak; can change plans mid-incident | Propose it for a change window |
| pg | `SELECT pg_promote()` | Promotes a standby by hand: split brain if the old primary is alive; on managed services there is no such path | Managed failover (gated) or the owner's HA tooling (Patroni etc.) |
| os | `kill -9 <backend-pid>` | SIGKILL of any backend makes the postmaster restart every session and run crash recovery | Gated `pg_cancel_backend` / `pg_terminate_backend` |
| mysql | `FLUSH TABLES WITH READ LOCK` | Blocks every write on the server until released; waits behind long queries and stalls everything queued behind it | Read-only diagnostics; backups use their own tooling |
| mysql | `RESET REPLICA ALL` | Erases the replica's connection and position metadata | Escalate to the DB owner |
| mysql | `SET GLOBAL innodb_deadlock_detect = OFF` | Turns deadlocks into lock-wait timeouts server-wide | Fix the access order in the app |
| mysql | `FLUSH STATUS` | Resets session and global status counters (evidence) | Snapshot; compare deltas |
| mysql | `TRUNCATE TABLE performance_schema.events_statements_summary_by_digest` | Wipes the digest history (evidence) | Snapshot; compare deltas |
| mysql | `CALL sys.ps_truncate_all_tables(FALSE)` | Wipes every Performance Schema summary table (evidence) | Snapshot first |
| mysql | `PURGE BINARY LOGS BEFORE NOW()` | Removes binary logs a replica, CDC pipeline or point-in-time recovery may still need | DB owner: retention settings (`binlog_expire_logs_seconds`; RDS `binlog retention hours`) through change review |
| mysql | `RESET BINARY LOGS AND GTIDS` | Deletes every binary log and resets GTID history (MySQL 8.4) | Escalate to the DB owner |
| mysql | `RESET MASTER` | Same as above, pre-8.4 name (MariaDB too) | Escalate to the DB owner |
| mysql | `STOP REPLICA` | Stops replication; lag grows and a later restart can fail on purged logs | Read `SHOW REPLICA STATUS`; escalate |
| mysql | `OPTIMIZE TABLE <table>` | Rebuilds the table (InnoDB: recreate + analyze), heavy I/O and metadata locks | Change window |
| mysql | `ALTER TABLE <table> ENGINE=InnoDB` | Same rebuild | Change window |
| mysql | `ANALYZE TABLE <table>` | Takes locks and can change plans mid-incident | Propose it for a change window |
| mysql | `SET GLOBAL read_only = ON` | Makes the whole server refuse writes | Managed failover or escalate |

## Gated (copy-paste blocks live in the triage steps, under the gate line)

Order rule: **cancel before terminate**, always. Cancel stops the statement and keeps the session. Terminate ends the session and rolls back its open transaction.

| Action | Engine | Where the gated block is | Risk | Reversible | Notes |
|---|---|---|---|---|---|
| `pg_cancel_backend(<pid>)` | pg | [postgres.md](postgres.md) Locks, Long-running queries | med | no (statement is lost; client may retry) | Needs `pg_signal_backend` or the same role; never superuser backends |
| `pg_terminate_backend(<pid>, 5000)` (PG14+) / `pg_terminate_backend(<pid>)` (PG13) | pg | [postgres.md](postgres.md) Locks, Connection exhaustion | high | no (open transaction rolls back) | Only after a cancel failed or the session is idle in transaction |
| Bulk terminate by `application_name` + idle age | pg | [postgres.md](postgres.md) Connection exhaustion | high | no | Run the identical read-only preview first; approval names the row count |
| `KILL QUERY <id>` / `CALL mysql.rds_kill_query(<id>)` / `CALL mysql.az_kill_query(<id>)` | mysql | [mysql.md](mysql.md) Locks, Long-running queries (one block per platform) | med | no | MariaDB also has `KILL QUERY ID <query_id>` |
| `KILL <id>` / `CALL mysql.rds_kill(<id>)` / `CALL mysql.az_kill(<id>)` | mysql | [mysql.md](mysql.md) Locks (one block per platform) | high | no (transaction rolls back; large rollbacks take long) | Only after `KILL QUERY` failed |
| `CLIENT KILL ID <client-id>` | redis | [redis.md](redis.md) Connections | med | no | By ID, never by `ADDR` pattern or `TYPE normal` |
| `CONFIG SET <param> <value>` | redis | [redis.md](redis.md) Memory/eviction | med | yes (set back; lost on restart unless rewritten) | Blocked on ElastiCache/MemoryDB/Memorystore: use the parameter group / `gcloud redis instances update --update-redis-config` |
| `ALTER SYSTEM SET ...` + `pg_reload_conf()`, `SET GLOBAL ...` | pg / mysql | Propose only; config belongs in IaC/parameter groups | med | yes | Managed services: parameter group / database flags / server parameters, often needs a restart |
| `pg_drop_replication_slot('<slot>')` | pg | [postgres.md](postgres.md) Disk/WAL | high | no (the consumer must be rebuilt) | Only an inactive slot, with the consumer's owner on the call |
| Managed failover (`aws rds failover-db-cluster`, `aws rds reboot-db-instance --force-failover`, `gcloud sql instances failover`, `az postgres flexible-server restart --failover`, `az mysql flexible-server restart --failover`, `aws elasticache test-failover`, `aws memorydb failover-shard`, `gcloud redis instances failover`, `az redis force-reboot --reboot-type PrimaryNode`) | all | Each reference, "Managed services" (one block per platform) | high | no | Last resort. Check replica lag first; failover via SQL is never used. ElastiCache/MemoryDB failover APIs are testing APIs (rate-limited, may be blocked) |
| `redis-cli --bigkeys` / `--memkeys` on a primary at peak | redis | [redis.md](redis.md) Memory | med | n/a | Full SCAN of the keyspace; off-peak, on a replica, with `-i 0.1` |
| `EXPLAIN ANALYZE` on production | pg / mysql | [postgres.md](postgres.md) Slow queries | med | n/a | It executes the statement (and DML inside it); plain `EXPLAIN` first |
| `CONFIG SET latency-monitor-threshold 100` | redis | [redis.md](redis.md) Latency | low | yes | Needed before `LATENCY DOCTOR` has data; not settable on Memorystore |

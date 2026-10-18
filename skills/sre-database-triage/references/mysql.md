# MySQL and MariaDB triage (read-only)

Versions: MySQL 8.0 and 8.4 LTS (current docs: 8.4), MariaDB 10.6/10.11/11.x LTS. Last reviewed: 2026-10-17. Sources: SOURCES in [../SKILL.md](../SKILL.md).

The wrapper sets the session read-only and adds a timeout (MySQL `max_execution_time`, milliseconds, applies to read-only `SELECT` only; MariaDB `max_statement_time`, seconds, applies to all statements), refuses anything but one single-line `SELECT`/`WITH`/`SHOW`/`EXPLAIN`, requires every `SELECT` to end in `LIMIT n`, and caps output. Use `mysql` with the MySQL option file and `mariadb` with the MariaDB one (Access, below):

```bash
MYSQL_DEFAULTS_FILE=~/.sre-ro-mysql.cnf bash scripts/db-ro.sh mysql -- "SELECT VERSION(), CURRENT_USER(), @@read_only LIMIT 1"
MYSQL_DEFAULTS_FILE=~/.sre-ro-mariadb.cnf bash scripts/db-ro.sh mariadb -- "SELECT VERSION(), CURRENT_USER(), @@read_only LIMIT 1"
```

## Version differences that change the queries

| Topic | MySQL 8.0 / 8.4 | MariaDB |
|---|---|---|
| Replica status | `SHOW REPLICA STATUS` from 8.0.22. `SHOW SLAVE STATUS` was deprecated in 8.0.22 and **removed in 8.4**. Before 8.0.22 only `SHOW SLAVE STATUS` exists | `SHOW SLAVE STATUS` and `SHOW REPLICA STATUS` are both accepted (current docs); very old releases only know `SLAVE` |
| Lag column | `Seconds_Behind_Source` (8.0.22+), `Seconds_Behind_Master` before | `Seconds_Behind_Master` |
| Lock waits | `sys.innodb_lock_waits` or `performance_schema.data_lock_waits`. `information_schema.INNODB_LOCK_WAITS`/`INNODB_LOCKS` were **removed in 8.0** | `information_schema.INNODB_LOCK_WAITS` + `INNODB_TRX` (still present) |
| Process list | `performance_schema.processlist` (preferred; the `information_schema` one takes a global mutex) | `information_schema.PROCESSLIST` |
| `performance_schema` | on by default | **off by default**; digest queries return nothing until enabled (restart) |
| `sys` schema | bundled | present in recent releases; check `SHOW DATABASES` before relying on it |
| Privileges | `PROCESS`, `REPLICATION CLIENT`, `SELECT` on `performance_schema`, `SELECT, EXECUTE` on `sys` | `PROCESS`, `REPLICA MONITOR` (for `SHOW REPLICA STATUS`), `BINLOG MONITOR` (new name for `REPLICATION CLIENT`) |
| Kill | `KILL QUERY <id>`, `KILL <id>` (`CONNECTION_ADMIN` to kill others' threads); RDS `mysql.rds_kill*`, Azure `mysql.az_kill*` | also `KILL QUERY ID <query_id>` |
| Table sizes the triage role can see | `information_schema.INNODB_TABLESPACES` (needs `PROCESS`) | `information_schema.INNODB_SYS_TABLESPACES` (needs `PROCESS`) |
| `Max_used_connections_time` status | yes | absent on 10.11 (the row is just missing) |
| `sys.processlist` | full | latency and transaction columns are NULL |
| Session read-only variable used by the wrapper | `transaction_read_only` | `tx_read_only` (10.11 has no `transaction_read_only`; 11.8 warns that `tx_read_only` is deprecated) |
| TLS client options | `ssl-mode`, `ssl-ca` | no `ssl-mode` (the client fails on it); `ssl-ca`, `ssl-verify-server-cert` |

## Access (one-time setup by the database owner, through normal change review)

- Triage account with only `PROCESS` and `REPLICATION CLIENT` (MySQL) or `PROCESS`, `REPLICA MONITOR`, `BINLOG MONITOR` (MariaDB), plus `SELECT` on `performance_schema` and `SELECT, EXECUTE` on `sys`. The `sys` views run with the caller's rights and call `sys` functions, so without `EXECUTE` they fail with error 1356. The `sys` procedures that change settings still fail (they need write rights on `performance_schema`), and the wrapper refuses `CALL`. No `SUPER`, no `CONNECTION_ADMIN`: killing is done by a human with a separate account after approval.

```sql
-- one-time setup by the DB owner, through change review (not an incident action). MySQL 8.0/8.4:
CREATE USER 'sre_ro'@'<cidr>' IDENTIFIED BY '<from-secret-store>' REQUIRE SSL WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'sre_ro'@'<cidr>';
GRANT SELECT ON performance_schema.* TO 'sre_ro'@'<cidr>';
GRANT SELECT, EXECUTE ON sys.* TO 'sre_ro'@'<cidr>';
-- MySQL has no per-account statement timeout (max_execution_time covers read-only SELECT only).
-- MariaDB: also a server-side statement timeout (seconds); grant sys only if SHOW DATABASES lists it
CREATE USER 'sre_ro'@'<cidr>' IDENTIFIED BY '<from-secret-store>' REQUIRE SSL WITH MAX_USER_CONNECTIONS 3 MAX_STATEMENT_TIME 5;
GRANT PROCESS, REPLICA MONITOR, BINLOG MONITOR ON *.* TO 'sre_ro'@'<cidr>';
GRANT SELECT ON performance_schema.* TO 'sre_ro'@'<cidr>';
GRANT SELECT, EXECUTE ON sys.* TO 'sre_ro'@'<cidr>';
```

- Type the password from the secret store at the prompt of an interactive session; do not keep it in shell history or a script.
- Cloud SQL: create the account **with SQL** as above, not with `gcloud sql users create` or the console: those accounts get the `cloudsqlsuperuser` role, which includes `CONNECTION_ADMIN`. Verify, connected as the triage account, that its grants are exactly the ones above (no `cloudsqlsuperuser` line):

```bash
bash scripts/db-ro.sh mysql -- "SHOW GRANTS"
```
- On MariaDB, `SHOW GRANTS` also prints the account's password hash (`IDENTIFIED BY PASSWORD '*...'`, lab: Database Reviewer re-run). Read it on screen; never paste the output into a ticket or chat. MySQL does not print it.

- `EXPLAIN` needs the same privileges as the statement it explains, so `SELECT` on the app tables, which this account does not have (error 1142). Use a separate read-only account with `SELECT` on the app schema, or hand the statement to the DB owner.
- Secrets: an option file passed as `--defaults-extra-file` (the wrapper reads `MYSQL_DEFAULTS_FILE`; it must be the first option, which the wrapper handles), `chmod 600`, outside the repo. Never `-p<password>` on the command line and never `MYSQL_PWD`.
- Use one option file per client. The `mariadb` client has no `ssl-mode` and stops with "unknown variable" if it finds one, and `VERIFY_IDENTITY` needs the CA bundle (`ssl-ca`, e.g. the RDS global bundle or the Cloud SQL / Azure server CA).

```ini
# ~/.sre-ro-mysql.cnf  (chmod 600), MySQL 8.0/8.4 client
[client]
host=<host>
port=3306
user=<ro-user>
password=<from your secret store>
ssl-mode=VERIFY_IDENTITY
ssl-ca=<absolute path to the CA bundle>
```

```ini
# ~/.sre-ro-mariadb.cnf  (chmod 600), MariaDB client
[client]
host=<host>
port=3306
user=<ro-user>
password=<from your secret store>
[client-mariadb]
ssl-ca=<absolute path to the CA bundle>
ssl-verify-server-cert
```

## 1. Connection exhaustion ("Too many connections", error 1040)

```bash
bash scripts/db-ro.sh mysql -- "SHOW GLOBAL STATUS WHERE Variable_name IN ('Threads_connected', 'Threads_running', 'Max_used_connections', 'Max_used_connections_time', 'Connection_errors_max_connections', 'Aborted_connects')"
bash scripts/db-ro.sh mysql -- "SHOW GLOBAL VARIABLES WHERE Variable_name IN ('max_connections', 'max_user_connections', 'wait_timeout')"
bash scripts/db-ro.sh mysql -- "SELECT USER, SUBSTRING_INDEX(HOST, ':', 1) AS client, DB, COMMAND, COUNT(*) AS n FROM performance_schema.processlist GROUP BY 1, 2, 3, 4 ORDER BY n DESC LIMIT 30"
```

MariaDB: same `SHOW` statements (10.11 has no `Max_used_connections_time`); replace `performance_schema.processlist` with `information_schema.PROCESSLIST`.

- MySQL keeps one extra connection for accounts with `CONNECTION_ADMIN`/`SUPER`, so the triage account is locked out with everyone else. Use the managed metrics (below) or an admin session that a human already holds. Self-managed MySQL can also have an administrative interface (`admin_address`/`admin_port`, default port 33062) that `max_connections` does not limit, for accounts with `SERVICE_CONNECTION_ADMIN`; MariaDB has `extra_port` with the thread pool. Managed services usually offer neither.
- Many `Sleep` connections from one client after a deploy: app pool size or leak. Fix it in the app (roll back, lower the pool) before killing anything.
- `Threads_running` high: the server is busy, go to sections 2 and 5.

## 2. Locks, blocking and deadlocks

MySQL 8.0/8.4:

```bash
bash scripts/db-ro.sh mysql -- "SELECT wait_started, wait_age, locked_table, locked_type, waiting_pid, IF(UPPER(waiting_query) LIKE '%PASSWORD%' OR UPPER(waiting_query) LIKE '%IDENTIFIED%', '<redacted: contains password>', LEFT(waiting_query, 200)) AS waiting_query, blocking_pid, IF(UPPER(blocking_query) LIKE '%PASSWORD%' OR UPPER(blocking_query) LIKE '%IDENTIFIED%', '<redacted: contains password>', LEFT(blocking_query, 200)) AS blocking_query, blocking_trx_age FROM sys.x\$innodb_lock_waits ORDER BY wait_started LIMIT 20"
bash scripts/db-ro.sh mysql -- "SELECT trx_id, trx_state, trx_started, TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_s, trx_mysql_thread_id, trx_rows_locked, trx_rows_modified, IF(UPPER(trx_query) LIKE '%PASSWORD%' OR UPPER(trx_query) LIKE '%IDENTIFIED%', '<redacted: contains password>', LEFT(trx_query, 200)) AS q FROM information_schema.INNODB_TRX ORDER BY trx_started LIMIT 20"
```

Deadlock detail (MySQL and MariaDB), **interactive only**. Read it on screen; never paste it into a ticket, chat or the evidence bundle (db-snapshot.sh does not capture it):

```bash
DB_RO_MAX_ROWS=400 bash scripts/db-ro.sh mysql -- "SHOW ENGINE INNODB STATUS"
```

MariaDB (this table is current in MariaDB; it is only the MySQL 8 copy that was removed):

```bash
bash scripts/db-ro.sh mariadb -- "SELECT r.trx_mysql_thread_id AS waiting_thread, IF(UPPER(r.trx_query) LIKE '%PASSWORD%' OR UPPER(r.trx_query) LIKE '%IDENTIFIED%', '<redacted: contains password>', LEFT(r.trx_query, 200)) AS waiting_query, b.trx_mysql_thread_id AS blocking_thread, IF(UPPER(b.trx_query) LIKE '%PASSWORD%' OR UPPER(b.trx_query) LIKE '%IDENTIFIED%', '<redacted: contains password>', LEFT(b.trx_query, 200)) AS blocking_query, TIMESTAMPDIFF(SECOND, b.trx_started, NOW()) AS blocking_age_s FROM information_schema.INNODB_LOCK_WAITS w JOIN information_schema.INNODB_TRX r ON r.trx_id = w.requesting_trx_id JOIN information_schema.INNODB_TRX b ON b.trx_id = w.blocking_trx_id LIMIT 20"
```

- `sys.x$innodb_lock_waits` needs `EXECUTE` on `sys` (Access). Statement text that contains `PASSWORD` or `IDENTIFIED` is replaced by a marker; keep the `IF(...)` when you adapt a query. Always redact the **full** text first and shorten after (`IF(UPPER(x) LIKE ..., marker, LEFT(x, 200))`), and use the `x$` sys views: the plain ones cut out the middle of statements, which can drop the keyword but keep the password.
- `sys.innodb_lock_waits` also has `sql_kill_blocking_query`/`sql_kill_blocking_connection` columns that print ready-made kill statements. The query above leaves them out on purpose: a kill is gated, not copied from output.
- `SHOW ENGINE INNODB STATUS` (needs `PROCESS`) has a "LATEST DETECTED DEADLOCK" section; the output is long, so the cap is raised for it. **The output may still contain passwords and row values.** It prints each transaction's SQL verbatim (the server does not rewrite passwords there), and the record-lock dumps (`hex ...; asc ...;`) show row values. The wrapper pipes every `SHOW ENGINE ...` output through `scripts/innodb-redact.awk`, but that is **best-effort defence in depth, not a guarantee**: it redacts lines containing `PASSWORD`/`IDENTIFIED` and the lines after them up to the next genuine monitor marker, and statement text that contains an exact copy of such a marker (for example a line `---TRANSACTION 999`) ends the redaction early. If the filter fails, the output is withheld (exit 1). So run it interactively only, through the wrapper, never with the bare `mysql` client, and never paste the output into tickets, chat or the evidence bundle. For evidence, use the redacted lock-wait and processlist queries above and in section 3.
- A blocker with `trx_state = RUNNING` and no current query is an idle open transaction (the app did not commit).

Proposal: kill the query first, the connection only if that fails. Evidence captured (`bash scripts/db-snapshot.sh mysql <outdir>`), proposal with the thread id, its query and transaction age, risk, and the owning app. One id at a time, admin account (not the triage account), and only the block for your platform.

1) Statement only; the connection and its transaction stay.

Self-managed MySQL/MariaDB and Cloud SQL (an admin with `CONNECTION_ADMIN`; Cloud SQL's `cloudsqlsuperuser` has it):

**Gate: approval required.**
```sql
KILL QUERY <thread_id>;
```

Amazon RDS / Aurora MySQL (no `SUPER`/`CONNECTION_ADMIN` there):

**Gate: approval required.**
```sql
CALL mysql.rds_kill_query(<thread_id>);
```

Azure Database for MySQL flexible server (no `SUPER` there):

**Gate: approval required.**
```sql
CALL mysql.az_kill_query(<thread_id>);
```

Re-run the lock query after 10 s. Only if the same thread still blocks, and the approval covers it:

2) Ends the connection and rolls back its transaction; a big transaction can take as long to roll back as it ran.

Self-managed MySQL/MariaDB and Cloud SQL:

**Gate: approval required.**
```sql
KILL <thread_id>;
```

Amazon RDS / Aurora MySQL:

**Gate: approval required.**
```sql
CALL mysql.rds_kill(<thread_id>);
```

Azure Database for MySQL flexible server:

**Gate: approval required.**
```sql
CALL mysql.az_kill(<thread_id>);
```

Verify: the lock-wait list empties, `Innodb_row_lock_current_waits` drops, error rate recovers. A killed connection shows `Killed` in the process list until its rollback finishes; do not kill it again.

## 3. Long-running queries

```bash
bash scripts/db-ro.sh mysql -- "SELECT ID, USER, DB, COMMAND, TIME, STATE, IF(UPPER(INFO) LIKE '%PASSWORD%' OR UPPER(INFO) LIKE '%IDENTIFIED%', '<redacted: contains password>', LEFT(INFO, 200)) AS info FROM performance_schema.processlist WHERE COMMAND <> 'Sleep' ORDER BY TIME DESC LIMIT 20"
bash scripts/db-ro.sh mysql -- "SELECT thd_id, conn_id, user, db, command, time, IF(UPPER(current_statement) LIKE '%PASSWORD%' OR UPPER(current_statement) LIKE '%IDENTIFIED%', '<redacted: may contain a password>', LEFT(current_statement, 200)) AS current_statement, statement_latency AS statement_latency_ps, trx_state, lock_latency AS lock_latency_ps FROM sys.x\$processlist WHERE conn_id IS NOT NULL ORDER BY time DESC LIMIT 20"
```

`sys.x$processlist` needs `EXECUTE` on `sys`. Use the `x$` view: the plain `sys.processlist` shortens `current_statement` by cutting out the **middle** (`sys.format_statement`, `statement_truncate_len` 64), which can remove `IDENTIFIED` and keep the password after it, so a filter on the shortened text misses it (lab: a MariaDB `ALTER USER ... IDENTIFIED BY` leaked this way). Redact the full text, then shorten it. The `x$` latencies are raw picoseconds (hence `_ps`). MariaDB: the first query against `information_schema.PROCESSLIST`; in MariaDB's `sys.processlist` the latency and transaction columns are NULL. `INFO` holds the statement text and can include customer data: redact before sharing. Kill: the gated blocks in section 2.

## 4. Replication lag

```bash
bash scripts/db-ro.sh mysql -- "SHOW REPLICA STATUS"
bash scripts/db-ro.sh mysql -- "SELECT CHANNEL_NAME, WORKER_ID, SERVICE_STATE, LAST_ERROR_MESSAGE, TIMESTAMPDIFF(MICROSECOND, LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP, LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP) / 1000000 AS last_apply_lag_s, IF(APPLYING_TRANSACTION = '', NULL, TIMESTAMPDIFF(MICROSECOND, APPLYING_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP, NOW(6)) / 1000000) AS applying_lag_s FROM performance_schema.replication_applier_status_by_worker LIMIT 20"
```

MySQL before 8.0.22 and old MariaDB: `bash scripts/db-ro.sh mysql -- "SHOW SLAVE STATUS"` (removed in MySQL 8.4).

- Check `Replica_IO_Running`/`Replica_SQL_Running` (`Slave_*` on MariaDB and before 8.0.22) first: a stopped thread with `Last_*_Error` is a broken replica, not a slow one.
- `Seconds_Behind_Source` is NULL when the SQL thread is not running, and 0 when the replica is idle even if the IO thread is behind.
- `last_apply_lag_s` describes the last transaction a worker **finished**; a worker stuck on one big transaction keeps showing the old, small value. `applying_lag_s` growing means exactly that. Both compare the source's clock with the replica's, so clock skew shows up as lag.
- MariaDB updates `Seconds_Behind_Master` differently with parallel replication (after commit): compare GTID positions (`gtid_slave_pos` vs the primary's `gtid_binlog_pos`) if the number looks odd.

## 5. Slow queries, CPU, disk

```bash
bash scripts/db-ro.sh mysql -- "SELECT SCHEMA_NAME, LEFT(DIGEST_TEXT, 200) AS digest, COUNT_STAR, ROUND(SUM_TIMER_WAIT / 1000000000000, 1) AS total_s, ROUND(AVG_TIMER_WAIT / 1000000000, 1) AS avg_ms, SUM_ROWS_EXAMINED, SUM_NO_INDEX_USED FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 15"
bash scripts/db-ro.sh mysql -- "EXPLAIN SELECT <columns> FROM <table> WHERE <predicate>"
bash scripts/db-ro.sh mysql -- "SELECT NAME, ROUND(FILE_SIZE / 1048576) AS file_mb, ROUND(ALLOCATED_SIZE / 1048576) AS alloc_mb FROM information_schema.INNODB_TABLESPACES ORDER BY FILE_SIZE DESC LIMIT 20"
bash scripts/db-ro.sh mysql -- "SHOW BINARY LOGS"
```

MariaDB table sizes:

```bash
bash scripts/db-ro.sh mariadb -- "SELECT NAME, ROUND(FILE_SIZE / 1048576) AS file_mb, ROUND(ALLOCATED_SIZE / 1048576) AS alloc_mb FROM information_schema.INNODB_SYS_TABLESPACES ORDER BY FILE_SIZE DESC LIMIT 20"
```

- Timer columns are picoseconds. Digest counters are cumulative: compare two snapshots.
- High `SUM_NO_INDEX_USED` on a digest that appeared with the deploy: a missing index or a changed query; the fix is a reviewed migration or a rollback, not an online `ALTER`.
- The tablespace views show InnoDB file sizes (one row per table with file-per-table, plus the system and undo tablespaces) and need only `PROCESS`. `information_schema.TABLES` is not used because it hides tables the account has no privileges on, so it returns nothing for the triage account; its sizes are also estimates, up to 24 h stale on MySQL 8 (`information_schema_stats_expiry`). Disk truth is the provider's free-storage metric or the filesystem.
- `EXPLAIN` needs `SELECT` on the tables (Access); the triage account gets error 1142. `EXPLAIN ANALYZE` executes the statement: plain `EXPLAIN` only on prod.
- Binary logs filling the disk: check `binlog_expire_logs_seconds` and a replica that stopped reading. On RDS, `CALL mysql.rds_show_configuration` (admin account) shows `binlog retention hours`; changing it is a gated config change for the DB owner. Removing binary logs by hand is not a triage action (see [destructive-commands.md](destructive-commands.md)).

## Managed services

| | Amazon RDS / Aurora MySQL | Cloud SQL for MySQL | Azure Database for MySQL flexible server |
|---|---|---|---|
| Admin role | master user (no `SUPER`) | `cloudsqlsuperuser` role | server admin login |
| Triage account | dedicated account (Access) | create it **in SQL**; console/gcloud users get `cloudsqlsuperuser` | dedicated account (Access) |
| Kill | `CALL mysql.rds_kill_query(<id>)`, `CALL mysql.rds_kill(<id>)` | `KILL QUERY` / `KILL` (`cloudsqlsuperuser` has `CONNECTION_ADMIN`) | `CALL mysql.az_kill_query(<id>)`, `CALL mysql.az_kill(<id>)` |
| Load view | CloudWatch Database Insights (Performance Insights console end of life 2026-07-31; the `aws pi get-resource-metrics` API still works) | Query insights | Query Performance Insight / slow query log in Azure Monitor |
| Failover | `aws rds failover-db-cluster` (Aurora) / `aws rds reboot-db-instance --force-failover` (Multi-AZ) | `gcloud sql instances failover` | `az mysql flexible-server restart --failover Forced` (HA only) |

Proposal: managed failover. Same rules as Postgres: last resort, lag checked, IC and DB owner approve, evidence captured. Use only the one block for your platform; each is a separate approval.

Aurora MySQL or a Multi-AZ DB cluster:

**Gate: approval required.**
```bash
aws rds failover-db-cluster --profile <profile> --region <region> --db-cluster-identifier <cluster> --target-db-instance-identifier <replica-instance>
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

Azure flexible server (HA servers only):

**Gate: approval required.**
```bash
az mysql flexible-server restart --subscription <subscription-id> --resource-group <rg> --name <server> --failover Forced
```

Verify: the new writer accepts connections, `SHOW REPLICA STATUS` on the remaining replicas is healthy, app errors recover.

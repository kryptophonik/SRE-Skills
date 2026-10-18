#!/usr/bin/env bash
# db-snapshot.sh: bounded, read-only evidence bundle BEFORE any gated action (cancel/kill/failover/config).
# Usage: bash scripts/db-snapshot.sh <pg|mysql|mariadb|redis> <outdir>
# Same target env as db-ro.sh. Every item runs through db-ro.sh (allowlist, timeouts, LIMIT, capped output).
# A failing item (missing extension, managed-service block, wrong role) is recorded and skipped.
# Output can hold query text with customer data: keep <outdir> outside the repo, redact before sharing.
# Query text that contains "password" (CREATE/ALTER ROLE|USER ... PASSWORD/IDENTIFIED BY) is replaced by a marker
# in every query-text column (redacted on the full text, then shortened). Other query text is still customer data.
# InnoDB monitor output is deliberately NOT captured: its statement text is free-form and cannot be redacted
# reliably. Lock-wait evidence comes from the redacted lock-wait and processlist queries below.
# For "is it the DB?" (P3) take two snapshots 3-5 min apart and compare deltas (SKILL.md).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -eq 2 ]] || { echo "usage: bash scripts/db-snapshot.sh <pg|mysql|mariadb|redis> <outdir>" >&2; exit 2; }
engine="$1"; out="$2"
d="$(dirname "$out")"; while [[ ! -d "$d" ]]; do d="$(dirname "$d")"; done   # nearest existing parent
if [[ "$(git -C "$d" rev-parse --is-inside-work-tree 2>/dev/null || true)" == true ]]; then
  echo "refusing: $out is inside a git work tree; evidence can hold customer data, keep it outside repos" >&2; exit 2
fi
umask 077; mkdir -p "$out"; chmod 700 "$out"
ok=0; failed=0; n=0
item() { # item <name> <db-ro args...>
  local name="$1"; shift; n=$((n+1))
  local f; f="$(printf '%s/%02d-%s.txt' "$out" "$n" "$name")"
  if bash "$here/db-ro.sh" "$engine" -- "$@" >"$f" 2>&1; then ok=$((ok+1)); else failed=$((failed+1)); echo "[skipped: $name failed, see $f]" >&2; fi
}
date -u '+captured_utc: %Y-%m-%dT%H:%M:%SZ' >"$out/00-README.txt"
echo "engine: $engine" >>"$out/00-README.txt"

case "$engine" in
  pg)
    Q="CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 200) END AS query"
    item identity "SELECT version(), current_user, current_database(), pg_is_in_recovery() AS is_replica, now() LIMIT 1"
    item conn-limits "SELECT (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend') AS client_conns, current_setting('max_connections')::int AS max_connections, current_setting('superuser_reserved_connections')::int AS su_reserved, current_setting('reserved_connections', true) AS reserved_pg16 LIMIT 1"
    item conn-by-state "SELECT state, wait_event_type, usename, application_name, count(*) AS n FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1, 2, 3, 4 ORDER BY n DESC LIMIT 50"
    item oldest-xacts "SELECT pid, usename, application_name, client_addr, state, wait_event_type, wait_event, now() - xact_start AS xact_age, now() - state_change AS in_state, $Q FROM pg_stat_activity WHERE backend_type = 'client backend' AND xact_start IS NOT NULL ORDER BY xact_start LIMIT 20"
    item blocked "SELECT pid, blocked_by, usename, application_name, wait_event, now() - query_start AS waiting, $Q FROM (SELECT a.*, pg_blocking_pids(a.pid) AS blocked_by FROM pg_stat_activity a WHERE a.wait_event_type = 'Lock') w ORDER BY query_start LIMIT 50"
    item blockers "SELECT pid, usename, application_name, state, now() - xact_start AS xact_age, $Q FROM pg_stat_activity WHERE pid IN (SELECT unnest(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE wait_event_type = 'Lock') LIMIT 20"
    item replication-primary "SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag, CASE WHEN pg_is_in_recovery() THEN NULL ELSE pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) END AS replay_bytes_behind FROM pg_stat_replication LIMIT 20"
    item replication-replica "SELECT pg_is_in_recovery() AS is_replica, CASE WHEN NOT pg_is_in_recovery() THEN 'n/a (primary)' ELSE COALESCE(r.status, 'not connected') END AS receiver, now() - r.last_msg_receipt_time AS since_last_msg, now() - pg_last_xact_replay_timestamp() AS since_last_replayed_xact, CASE WHEN r.status = 'streaming' AND now() - r.last_msg_receipt_time < greatest(interval '60 seconds', current_setting('wal_receiver_timeout')::interval) THEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() END AS replay_caught_up FROM (SELECT 1) one LEFT JOIN pg_stat_wal_receiver r ON true LIMIT 1"
    item slots "SELECT slot_name, slot_type, active, wal_status, pg_size_pretty(safe_wal_size) AS safe_wal_size, pg_size_pretty(pg_wal_lsn_diff(CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_lsn() END, restart_lsn)) AS retained_wal FROM pg_replication_slots ORDER BY restart_lsn LIMIT 20"
    item databases "SELECT datname, numbackends, deadlocks, temp_bytes, conflicts, pg_size_pretty(sz) AS size FROM (SELECT datname, numbackends, deadlocks, temp_bytes, conflicts, pg_database_size(datname) AS sz FROM pg_stat_database WHERE datname IS NOT NULL) s ORDER BY sz DESC LIMIT 20"
    item xmin-horizon "SELECT pid, state, backend_xid, backend_xmin, greatest(age(backend_xid), age(backend_xmin)) AS horizon_age, now() - xact_start AS xact_age, CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 120) END AS query FROM pg_stat_activity WHERE backend_xid IS NOT NULL OR backend_xmin IS NOT NULL ORDER BY horizon_age DESC LIMIT 10"
    item wraparound "SELECT datname, age(datfrozenxid) AS xid_age, mxid_age(datminmxid) AS mxid_age FROM pg_database ORDER BY 2 DESC LIMIT 10"
    item dead-tuples "SELECT schemaname, relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 20"
    item vacuum-progress "SELECT pid, datname, relid::regclass AS rel, phase FROM pg_stat_progress_vacuum LIMIT 20"
    item archiver "SELECT archived_count, failed_count, last_failed_wal, last_failed_time FROM pg_stat_archiver LIMIT 1"
    item wal-dir "SELECT count(*) AS files, pg_size_pretty(sum(size)) AS total FROM pg_ls_waldir() LIMIT 1"
    item top-statements "SELECT queryid, calls, round(total_exec_time::numeric, 1) AS total_ms, round(mean_exec_time::numeric, 1) AS mean_ms, rows, $Q FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 15"
    ;;
  mysql|mariadb)
    if [[ "$engine" == mysql ]]; then PL=performance_schema.processlist; else PL=information_schema.PROCESSLIST; fi
    red() { printf "IF(UPPER(%s) LIKE '%%PASSWORD%%' OR UPPER(%s) LIKE '%%IDENTIFIED%%', '<redacted: contains password>', LEFT(%s, 200))" "$1" "$1" "$1"; }
    item identity "SELECT VERSION(), CURRENT_USER(), @@read_only, NOW() LIMIT 1"
    # Max_used_connections_time is MySQL-only (absent on MariaDB 10.11): it is simply missing from the output there.
    item status "SHOW GLOBAL STATUS WHERE Variable_name IN ('Threads_connected', 'Threads_running', 'Max_used_connections', 'Max_used_connections_time', 'Connection_errors_max_connections', 'Aborted_connects', 'Innodb_row_lock_current_waits', 'Innodb_row_lock_waits', 'Uptime')"
    item variables "SHOW GLOBAL VARIABLES WHERE Variable_name IN ('max_connections', 'max_user_connections', 'wait_timeout', 'innodb_lock_wait_timeout', 'max_execution_time', 'max_statement_time', 'performance_schema', 'innodb_deadlock_detect')"
    item conn-by-user "SELECT USER, SUBSTRING_INDEX(HOST, ':', 1) AS client, DB, COMMAND, COUNT(*) AS n FROM $PL GROUP BY 1, 2, 3, 4 ORDER BY n DESC LIMIT 30"
    item long-running "SELECT ID, USER, DB, COMMAND, TIME, STATE, $(red INFO) AS info FROM $PL WHERE COMMAND <> 'Sleep' ORDER BY TIME DESC LIMIT 20"
    item innodb-trx "SELECT trx_id, trx_state, trx_started, TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_s, trx_mysql_thread_id, trx_rows_locked, trx_rows_modified, $(red trx_query) AS q FROM information_schema.INNODB_TRX ORDER BY trx_started LIMIT 20"
    if [[ "$engine" == mysql ]]; then
      item lock-waits "SELECT wait_started, wait_age, locked_table, locked_type, waiting_pid, $(red waiting_query) AS waiting_query, blocking_pid, $(red blocking_query) AS blocking_query, blocking_trx_age FROM sys.x\$innodb_lock_waits ORDER BY wait_started LIMIT 20"
      item applier-lag "SELECT CHANNEL_NAME, WORKER_ID, SERVICE_STATE, LAST_ERROR_MESSAGE, TIMESTAMPDIFF(MICROSECOND, LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP, LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP) / 1000000 AS last_apply_lag_s, IF(APPLYING_TRANSACTION = '', NULL, TIMESTAMPDIFF(MICROSECOND, APPLYING_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP, NOW(6)) / 1000000) AS applying_lag_s FROM performance_schema.replication_applier_status_by_worker LIMIT 20"
    else
      item lock-waits "SELECT r.trx_mysql_thread_id AS waiting_thread, $(red r.trx_query) AS waiting_query, b.trx_mysql_thread_id AS blocking_thread, $(red b.trx_query) AS blocking_query, TIMESTAMPDIFF(SECOND, b.trx_started, NOW()) AS blocking_age_s FROM information_schema.INNODB_LOCK_WAITS w JOIN information_schema.INNODB_TRX r ON r.trx_id = w.requesting_trx_id JOIN information_schema.INNODB_TRX b ON b.trx_id = w.blocking_trx_id LIMIT 20"  # MariaDB only: this table was removed from MySQL 8.0
    fi
    item replica-status "SHOW REPLICA STATUS"
    item top-digests "SELECT SCHEMA_NAME, LEFT(DIGEST_TEXT, 200) AS digest, COUNT_STAR, ROUND(SUM_TIMER_WAIT / 1000000000000, 1) AS total_s, ROUND(AVG_TIMER_WAIT / 1000000000, 1) AS avg_ms, SUM_ROWS_EXAMINED, SUM_NO_INDEX_USED FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 15"
    item binary-logs "SHOW BINARY LOGS"
    # No InnoDB monitor output here (see the header): it can print passwords that no line filter reliably removes.
    ;;
  redis)
    item role ROLE
    for s in server clients memory stats replication persistence keyspace; do item "info-$s" INFO "$s"; done
    item slowlog-len SLOWLOG LEN
    item slowlog SLOWLOG GET 25
    item latency-latest LATENCY LATEST
    item latency-doctor LATENCY DOCTOR
    item memory-doctor MEMORY DOCTOR
    # maxmemory_policy is in INFO memory (CONFIG is not allowed: CONFIG GET can return secrets).
    DB_RO_MAX_ROWS=200 item client-list CLIENT LIST TYPE normal   # last: O(clients) on the main thread
    ;;
  *) echo "unknown engine: $engine" >&2; exit 2 ;;
esac
echo "items_ok: $ok  items_failed: $failed" >>"$out/00-README.txt"
echo "snapshot: $out ($ok ok, $failed skipped)" >&2
if [[ $ok -eq 0 ]]; then echo "no item succeeded: check the target env and role; during connection exhaustion retry once slots free up and use provider metrics meanwhile (SKILL.md, Start here step 2)" >&2; fi

#!/usr/bin/env bash
# Prove the linter's PostgreSQL claims on a real server: lock modes, rewrites, lock queues.
# Run ONLY against a throwaway or staging instance. It creates a scratch database,
# runs the risky patterns on a small table there, then drops that database.
# Connection comes from the usual libpq settings (PGHOST, PGPORT, PGUSER, PGPASSFILE).
# The role needs CREATEDB. Usage:  MIGPROOF_SCRATCH_OK=yes bash scripts/proof-pg.sh
set -uo pipefail
[ "${MIGPROOF_SCRATCH_OK:-}" = yes ] || { echo "refusing: set MIGPROOF_SCRATCH_OK=yes to confirm this is a throwaway or staging instance" >&2; exit 3; }
PSQL=${PSQL:-psql}
DB="migration_proof_$$"
pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 (want '$3', got '$2')"; fi; }
q(){ "$PSQL" -X -qAt -v ON_ERROR_STOP=1 -d "$DB" -c "$1" 2>&1; }
bg(){ "$PSQL" -X -qAt -d "$DB" -c "$1" >/dev/null 2>&1 & }
cleanup(){ wait 2>/dev/null; "$PSQL" -X -qAt -d postgres -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1; }
trap cleanup EXIT
"$PSQL" -X -qAt -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE $DB" >/dev/null || { echo "cannot create scratch database" >&2; exit 3; }
ver=$(q "SHOW server_version_num"); echo "server_version_num=$ver"
reset_t(){ q "DROP TABLE IF EXISTS t, p CASCADE; CREATE TABLE p (id int PRIMARY KEY); INSERT INTO p SELECT g FROM generate_series(1,100) g;
  CREATE TABLE t (id int PRIMARY KEY, a int, pid int, name varchar(10), note text); INSERT INTO t SELECT g, g, 1+g%100, 'x', 'y' FROM generate_series(1,20000) g; ANALYZE t" >/dev/null; }
# strongest lock mode this session holds on t
locks(){ q "BEGIN; $1; SELECT mode FROM pg_locks WHERE relation = 't'::regclass AND pid = pg_backend_pid() ORDER BY array_position(ARRAY['AccessShareLock','RowShareLock','RowExclusiveLock','ShareUpdateExclusiveLock','ShareLock','ShareRowExclusiveLock','ExclusiveLock','AccessExclusiveLock'], mode) DESC LIMIT 1; ROLLBACK" | tail -1; }
filenode(){ q "SELECT pg_relation_filenode('t')"; }
rewrites(){ reset_t; local b a; b=$(filenode); q "$1" >/dev/null; a=$(filenode); [ "$b" = "$a" ] && echo no || echo yes; }

reset_t
# Lock modes each statement takes on t (checked inside a rolled-back transaction).
ok "PG-IDX-LOCK: CREATE INDEX takes SHARE"                      "$(locks 'CREATE INDEX ON t (a)')" "ShareLock"
ok "PG-NO-LOCK-TIMEOUT: ADD COLUMN takes ACCESS EXCLUSIVE"       "$(locks 'ALTER TABLE t ADD COLUMN z int')" "AccessExclusiveLock"
ok "PG-FK-VALIDATE: ADD FOREIGN KEY ... NOT VALID takes SHARE ROW EXCLUSIVE" "$(locks 'ALTER TABLE t ADD CONSTRAINT t_p FOREIGN KEY (pid) REFERENCES p (id) NOT VALID')" "ShareRowExclusiveLock"
q "ALTER TABLE t ADD CONSTRAINT t_p FOREIGN KEY (pid) REFERENCES p (id) NOT VALID" >/dev/null
ok "PG-FK-VALIDATE: VALIDATE CONSTRAINT takes only SHARE UPDATE EXCLUSIVE (writes continue)" "$(locks 'ALTER TABLE t VALIDATE CONSTRAINT t_p')" "ShareUpdateExclusiveLock"

# Rewrites: does the table get a new file?
ok "ADD COLUMN DEFAULT 0 does not rewrite"                  "$(rewrites 'ALTER TABLE t ADD COLUMN z int DEFAULT 0')" "no"
ok "ADD COLUMN DEFAULT now() does not rewrite"              "$(rewrites 'ALTER TABLE t ADD COLUMN z timestamptz DEFAULT now()')" "no"
ok "PG-ADDCOL-REWRITE: DEFAULT clock_timestamp() rewrites"  "$(rewrites 'ALTER TABLE t ADD COLUMN z timestamptz DEFAULT clock_timestamp()')" "yes"
ok "PG-ADDCOL-REWRITE: bigserial rewrites"                  "$(rewrites 'ALTER TABLE t ADD COLUMN z bigserial')" "yes"
ok "PG-ALTER-TYPE: int to bigint rewrites"                  "$(rewrites 'ALTER TABLE t ALTER COLUMN a TYPE bigint')" "yes"
ok "varchar(10) to varchar(20) does not rewrite"            "$(rewrites 'ALTER TABLE t ALTER COLUMN name TYPE varchar(20)')" "no"
ok "varchar to text does not rewrite"                       "$(rewrites 'ALTER TABLE t ALTER COLUMN name TYPE text')" "no"
ok "PG-ADDCOL-NOTNULL: NOT NULL without default fails on a non-empty table" "$(reset_t; q 'ALTER TABLE t ADD COLUMN z int NOT NULL' | grep -c 'contains null values')" "1"

# SET NOT NULL skips the scan when a validated CHECK proves it (PostgreSQL 12+ logs this at DEBUG1).
reset_t
q "ALTER TABLE t ADD CONSTRAINT t_a_nn CHECK (a IS NOT NULL) NOT VALID; ALTER TABLE t VALIDATE CONSTRAINT t_a_nn" >/dev/null
msg=$(q "SET client_min_messages = debug1; ALTER TABLE t ALTER COLUMN a SET NOT NULL" | grep -c 'sufficient to prove')
ok "PG-SET-NOTNULL: validated CHECK lets SET NOT NULL skip the scan" "$msg" "1"

# CONCURRENTLY refuses to run in a transaction block.
ok "PG-CONC-IN-TXN: CREATE INDEX CONCURRENTLY inside BEGIN errors" "$(q 'BEGIN; CREATE INDEX CONCURRENTLY ON t (a); COMMIT' | grep -c 'cannot run inside a transaction block')" "1"

# Blocking behaviour with two live sessions.
reset_t
bg "BEGIN; CREATE INDEX t_a_idx ON t (a); SELECT pg_sleep(4); COMMIT"; sleep 1
ok "PG-IDX-LOCK: an INSERT waits behind a plain CREATE INDEX" "$(q "SET lock_timeout = '1s'; INSERT INTO t VALUES (99999, 1, 1, 'x', 'y')" | grep -c 'lock timeout')" "1"
wait
reset_t
bg "BEGIN; INSERT INTO t VALUES (99998, 1, 1, 'x', 'y'); SELECT pg_sleep(4); COMMIT"; sleep 1   # an open writer makes CIC wait
bg "CREATE INDEX CONCURRENTLY t_a_cidx ON t (a)"; sleep 1
ok "CREATE INDEX CONCURRENTLY is in progress" "$(q "SELECT count(*) FROM pg_stat_activity WHERE query LIKE 'CREATE INDEX CONCURRENTLY t_a_cidx%' AND datname = current_database()")" "1"
ok "an INSERT does not wait behind CREATE INDEX CONCURRENTLY" "$(q "SET lock_timeout = '1s'; INSERT INTO t VALUES (99997, 1, 1, 'x', 'y')" | grep -c 'lock timeout')" "0"
wait
reset_t
bg "BEGIN; SELECT count(*) FROM t; SELECT pg_sleep(5); COMMIT"; sleep 1   # a long read holds ACCESS SHARE
ok "PG-NO-LOCK-TIMEOUT: with lock_timeout the ALTER gives up instead of queueing" "$(q "SET lock_timeout = '1s'; ALTER TABLE t ADD COLUMN z int" | grep -c 'lock timeout')" "1"
bg "SET statement_timeout = '3s'; ALTER TABLE t ADD COLUMN z2 int"; sleep 1   # ALTER with no lock_timeout now waits in the queue
ok "PG-NO-LOCK-TIMEOUT: without it, plain SELECTs queue behind the waiting ALTER" "$(q "SET lock_timeout = '1s'; SELECT count(*) FROM t" | grep -c 'lock timeout')" "1"
wait

echo "$pass/$((pass+fail)) passed"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# Prove the linter's MySQL/MariaDB (InnoDB) claims on a real server: which ALTERs can run
# online, which need a table copy, and how a pending metadata lock queues other queries.
# Run ONLY against a throwaway or staging instance. It creates a scratch database,
# runs the patterns on a small table there, then drops that database.
# Credentials come from an option file, never the command line:
#   MIGPROOF_SCRATCH_OK=yes MYSQL_DEFAULTS=~/.my-staging.cnf bash scripts/proof-mysql.sh
# The account needs CREATE, DROP, ALTER, INDEX, REFERENCES, INSERT and SELECT on the scratch database.
set -uo pipefail
[ "${MIGPROOF_SCRATCH_OK:-}" = yes ] || { echo "refusing: set MIGPROOF_SCRATCH_OK=yes to confirm this is a throwaway or staging instance" >&2; exit 3; }
[ -r "${MYSQL_DEFAULTS:-}" ] || { echo "set MYSQL_DEFAULTS to a readable option file with the connection settings" >&2; exit 3; }
MYSQL=${MYSQL:-mysql}
DB="migration_proof_$$"
pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 (want '$3', got '$2')"; fi; }
m(){ "$MYSQL" --defaults-extra-file="$MYSQL_DEFAULTS" -N -B "$@"; }
q(){ m -D "$DB" -e "$1" 2>&1; }
works(){ local out; out=$(q "$1"); case $out in *ERROR*) echo refused;; *) echo ok;; esac; }
bg(){ m -D "$DB" -e "$1" >/dev/null 2>&1 & }
cleanup(){ wait 2>/dev/null; m -e "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1; }
trap cleanup EXIT
m -e "CREATE DATABASE $DB" || { echo "cannot create scratch database" >&2; exit 3; }
echo "version=$(m -e 'SELECT VERSION()')"
reset_t(){ q "DROP TABLE IF EXISTS t; DROP TABLE IF EXISTS p;
  CREATE TABLE p (id INT PRIMARY KEY) ENGINE=InnoDB; INSERT INTO p VALUES (1),(2),(3);
  CREATE TABLE t (id INT PRIMARY KEY, a INT, pid INT, name VARCHAR(10), note TEXT) ENGINE=InnoDB DEFAULT CHARSET=latin1;
  INSERT INTO t VALUES (1,1,1,'x','y'),(2,2,2,'x','y'),(3,3,3,'x','y')" >/dev/null; }

reset_t; ok "MY-ADDCOL-ALGO: ADD COLUMN at the end works with ALGORITHM=INSTANT" "$(works 'ALTER TABLE t ADD COLUMN z INT, ALGORITHM=INSTANT')" "ok"
reset_t; ok "MY-COLUMN-TYPE: INT to BIGINT is refused with ALGORITHM=INPLACE (needs a copy)" "$(works 'ALTER TABLE t MODIFY COLUMN a BIGINT, ALGORITHM=INPLACE, LOCK=NONE')" "refused"
reset_t; ok "VARCHAR(10) to VARCHAR(20) runs INPLACE, LOCK=NONE" "$(works 'ALTER TABLE t MODIFY COLUMN name VARCHAR(20), ALGORITHM=INPLACE, LOCK=NONE')" "ok"
reset_t; ok "MY-CHARSET: CONVERT TO CHARACTER SET is refused with ALGORITHM=INPLACE" "$(works 'ALTER TABLE t CONVERT TO CHARACTER SET utf8mb4, ALGORITHM=INPLACE, LOCK=NONE')" "refused"
reset_t; ok "MY-PK: dropping the primary key without adding one is refused INPLACE" "$(works 'ALTER TABLE t DROP PRIMARY KEY, ALGORITHM=INPLACE')" "refused"
reset_t; ok "MY-FTS: FULLTEXT index is refused with LOCK=NONE" "$(works 'ALTER TABLE t ADD FULLTEXT INDEX ft (note), ALGORITHM=INPLACE, LOCK=NONE')" "refused"
reset_t; ok "ADD INDEX runs INPLACE, LOCK=NONE" "$(works 'ALTER TABLE t ADD INDEX ia (a), ALGORITHM=INPLACE, LOCK=NONE')" "ok"
reset_t; ok "MY-FK-COPY: ADD FOREIGN KEY is refused INPLACE while foreign_key_checks=1" "$(works 'SET SESSION foreign_key_checks=1; ALTER TABLE t ADD CONSTRAINT fk FOREIGN KEY (pid) REFERENCES p (id), ALGORITHM=INPLACE')" "refused"
reset_t; ok "MY-FK-COPY: the same ALTER runs INPLACE with foreign_key_checks=0" "$(works 'SET SESSION foreign_key_checks=0; ALTER TABLE t ADD CONSTRAINT fk FOREIGN KEY (pid) REFERENCES p (id), ALGORITHM=INPLACE')" "ok"

# Metadata locks: an open transaction that has read t blocks any ALTER on t.
reset_t
bg "BEGIN; SELECT COUNT(*) FROM t; DO SLEEP(5); COMMIT"; sleep 1
ok "MY-NO-LOCK-WAIT-TIMEOUT: with lock_wait_timeout the ALTER gives up" "$(q 'SET SESSION lock_wait_timeout=1; ALTER TABLE t ADD COLUMN z INT, ALGORITHM=INSTANT' | grep -c 'Lock wait timeout')" "1"
bg "SET SESSION lock_wait_timeout=3; ALTER TABLE t ADD COLUMN z2 INT, ALGORITHM=INSTANT"; sleep 1
ok "MY-NO-LOCK-WAIT-TIMEOUT: without it, plain SELECTs queue behind the waiting ALTER" "$(q 'SET SESSION lock_wait_timeout=1; SELECT COUNT(*) FROM t' | grep -c 'Lock wait timeout')" "1"
wait

echo "$pass/$((pass+fail)) passed"
[ "$fail" -eq 0 ]

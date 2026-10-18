#!/usr/bin/env bash
# run-tests.sh: offline tests for scripts/db-ro.sh and scripts/db-snapshot.sh. No database needed:
# uses DB_RO_DRYRUN=1 and stub client binaries. Run with any bash, including macOS /bin/bash 3.2:
#   bash tests/run-tests.sh            (BASH_UNDER_TEST=/bin/bash to pick the shell running the scripts)
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
B="${BASH_UNDER_TEST:-bash}"; RO="$here/scripts/db-ro.sh"; SNAP="$here/scripts/db-snapshot.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/db-ro-test.XXXXXX")"; trap 'rm -rf -- "$W"' EXIT
pass=0 fail=0
ok()  { pass=$((pass+1)); printf 'PASS  %s\n' "$*"; }
bad() { fail=$((fail+1)); printf 'FAIL  %s\n' "$*"; }
expect() { # expect <rc> <name> -- cmd...
  local want="$1" name="$2"; shift 3; local rc=0
  "$@" >"$W/out" 2>&1 || rc=$?
  if [[ "$rc" == "$want" ]]; then ok "$name"; else bad "$name (exit $rc, want $want)"; sed 's/^/      /' "$W/out" | head -5; fi
}
PGT="PGHOST=db.example.invalid PGDATABASE=app PGUSER=sre_ro"
pg()    { env -u PGPASSWORD PGHOST=db.example.invalid PGDATABASE=app PGUSER=sre_ro DB_RO_DRYRUN=1 "$B" "$RO" pg -- "$@"; }
my()    { env -u MYSQL_PWD MYSQL_DEFAULTS_FILE="$W/my.cnf" DB_RO_DRYRUN=1 "$B" "$RO" "${ENGINE:-mysql}" -- "$@"; }
rd()    { env REDIS_HOST=cache.example.invalid REDIS_PORT=6379 DB_RO_DRYRUN=1 "$B" "$RO" redis -- "$@"; }
: "$PGT"

# 1. Every never-run command in references/destructive-commands.md is refused (single source of truth).
rows=0
while IFS='|' read -r _ eng cmd _; do
  eng="$(echo "$eng" | tr -d ' ')"; cmd="$(echo "$cmd" | sed 's/^ *`//; s/` *$//')"
  case "$eng" in
    redis) rows=$((rows+1)); set -f; # shellcheck disable=SC2086  # split the command into redis-cli words
           expect 3 "never-run refused: redis $cmd" -- rd $cmd; set +f ;;
    pg)    rows=$((rows+1)); expect 3 "never-run refused: pg $cmd" -- pg "$cmd" ;;
    mysql) rows=$((rows+1)); expect 3 "never-run refused: mysql $cmd" -- my "$cmd" ;;
  esac
done < <(awk '/^## Never run/{f=1;next} /^## /{f=0} f && /^\| (redis|pg|mysql) \|/' "$here/references/destructive-commands.md")
(( rows >= 50 )) && ok "parsed $rows never-run rows" || bad "parsed only $rows never-run rows"

# 2. Gated actions are refused by the read-only wrapper (they are run by a human, outside it).
expect 3 "gated: pg_cancel_backend"       -- pg "SELECT pg_cancel_backend(123) LIMIT 1"
expect 3 "gated: pg_terminate_backend"    -- pg "SELECT pg_terminate_backend(pid) FROM pg_stat_activity LIMIT 5"
expect 3 "gated: spaced/quoted terminate" -- pg 'SELECT pg_catalog."pg_terminate_backend" (42) LIMIT 1'
expect 3 "gated: pg_reload_conf"          -- pg "SELECT pg_reload_conf() LIMIT 1"
expect 3 "gated: pg_drop_replication_slot" -- pg "SELECT pg_drop_replication_slot('s') LIMIT 1"
expect 3 "gated: ALTER SYSTEM"            -- pg "ALTER SYSTEM SET max_connections = 500"
expect 3 "gated: KILL QUERY"              -- my "KILL QUERY 42"
expect 3 "gated: KILL"                    -- my "KILL 42"
expect 3 "gated: rds_kill"                -- my "CALL mysql.rds_kill(42)"
expect 3 "gated: rds_kill in SELECT"      -- my "SELECT mysql.rds_kill_query(42) LIMIT 1"
expect 3 "gated: az_kill"                 -- my "CALL mysql.az_kill(42)"
expect 3 "gated: az_kill_query in SELECT" -- my "SELECT mysql.az_kill_query(42) LIMIT 1"
expect 3 "gated: az_kill backtick-quoted" -- my 'SELECT `mysql`.`az_kill`(42) LIMIT 1'
expect 3 "gated: SET GLOBAL"              -- my "SET GLOBAL max_connections = 500"
expect 3 "gated: CLIENT KILL"             -- rd CLIENT KILL ID 7
expect 3 "gated: CONFIG SET"              -- rd CONFIG SET maxmemory-policy allkeys-lru
expect 3 "gated: FAILOVER"                -- rd FAILOVER
expect 3 "gated: REPLICAOF"               -- rd REPLICAOF NO ONE

# 3. Bypass attempts.
expect 3 "two statements"                 -- pg "SELECT 1 LIMIT 1; DROP TABLE t"
expect 3 "data-modifying CTE"             -- pg "WITH d AS (DELETE FROM t RETURNING *) SELECT * FROM d LIMIT 1"
expect 3 "EXPLAIN ANALYZE"                -- pg "EXPLAIN ANALYZE SELECT 1"
expect 3 "EXPLAIN (ANALYZE)"              -- pg "EXPLAIN (ANALYZE, BUFFERS) SELECT 1"
expect 3 "row lock FOR UPDATE"            -- pg "SELECT * FROM t FOR UPDATE LIMIT 1"
expect 3 "SELECT INTO creates a table"    -- pg "SELECT * INTO t2 FROM t LIMIT 1"
expect 3 "comment hides text"             -- pg "SELECT 1 /* x */ LIMIT 1"
expect 3 "psql meta-command"              -- pg '\! id'
expect 3 "missing LIMIT"                  -- pg "SELECT * FROM pg_stat_activity"
expect 3 "LIMIT too large"                -- pg "SELECT * FROM pg_stat_activity LIMIT 5000"
expect 3 "LIMIT not literal"              -- pg "SELECT * FROM pg_stat_activity LIMIT ALL"
expect 3 "pg_sleep"                       -- pg "SELECT pg_sleep(60) LIMIT 1"
expect 3 "advisory lock"                  -- pg "SELECT pg_advisory_lock(1) LIMIT 1"
expect 3 "nextval writes"                 -- pg "SELECT nextval('s') LIMIT 1"
expect 3 "mysql INTO OUTFILE"             -- my "SELECT * FROM t LIMIT 1 INTO OUTFILE '/tmp/x'"
expect 3 "mysql SLEEP"                    -- my "SELECT SLEEP(100) LIMIT 1"
expect 3 "mysql LOCK IN SHARE MODE"       -- my "SELECT * FROM t LIMIT 1 LOCK IN SHARE MODE"
expect 3 "mysql hash comment"             -- my "SELECT 1 LIMIT 1 # x"
expect 3 "redis SCAN without COUNT"       -- rd SCAN 0 MATCH 'user:*'
expect 3 "redis SCAN COUNT too big"       -- rd SCAN 0 COUNT 100000
expect 3 "redis CONFIG GET *"             -- rd CONFIG GET '*'
expect 3 "redis CONFIG GET requirepass"   -- rd CONFIG GET requirepass
expect 3 "redis CONFIG GET REQUIREPASS (upper case)" -- rd CONFIG GET REQUIREPASS
expect 3 "redis config get Requirepass (mixed case)" -- rd config get Requirepass
expect 3 "redis CONFIG GET MASTER*"       -- rd CONFIG GET 'MASTER*'
expect 3 "redis CONFIG GET TLS-KEY-FILE-PASS" -- rd CONFIG GET TLS-KEY-FILE-PASS
expect 3 "redis CONFIG GET maxmemory-policy (CONFIG removed; use INFO memory)" -- rd CONFIG GET maxmemory-policy
expect 3 "redis MEMORY USAGE SAMPLES 0"   -- rd MEMORY USAGE bigkey SAMPLES 0
expect 3 "redis MEMORY USAGE SAMPLES big" -- rd MEMORY USAGE bigkey SAMPLES 100000000
expect 3 "redis CLIENT PAUSE"             -- rd CLIENT PAUSE 1000
expect 3 "redis CONFIG RESETSTAT"         -- rd CONFIG RESETSTAT
# MySQL function blocklist: backtick quoting and other whitespace must not hide a call
expect 3 "mysql backtick sleep"           -- my 'SELECT `sleep`(1) LIMIT 1'
expect 3 "mysql backtick GET_LOCK"        -- my "SELECT \`GET_LOCK\`('x', 10) LIMIT 1"
expect 3 "mysql backtick benchmark"       -- my 'SELECT `benchmark`(1000000, md5(1)) LIMIT 1'
expect 3 "mysql tab before ("             -- my "$(printf 'SELECT SLEEP\t(1) LIMIT 1')"
expect 3 "mysql CR before ("              -- my "$(printf 'SELECT SLEEP\r(1) LIMIT 1')"
# PG: prefix families (reset variants, dblink, *_to_xml run a query string), logical message
expect 3 "pg_stat_reset_shared"           -- pg "SELECT pg_stat_reset_shared('bgwriter') LIMIT 1"
expect 3 "pg_stat_reset_slru"             -- pg "SELECT pg_stat_reset_slru() LIMIT 1"
expect 3 "pg_stat_reset_single_table_counters" -- pg "SELECT pg_stat_reset_single_table_counters(1) LIMIT 1"
expect 3 "dblink_connect"                 -- pg "SELECT dblink_connect('x') LIMIT 1"
expect 3 "dblink()"                       -- pg "SELECT * FROM dblink('x', 'select 1') AS t(a int) LIMIT 1"
expect 3 "query_to_xml"                   -- pg "SELECT query_to_xml('select 1', true, false, '') LIMIT 1"
expect 3 "table_to_xml"                   -- pg "SELECT table_to_xml('t', true, false, '') LIMIT 1"
expect 3 "pg_logical_emit_message"        -- pg "SELECT pg_logical_emit_message(true, 'p', 'x') LIMIT 1"
# LIMIT must be the final clause
expect 3 "LIMIT only in a subquery"       -- pg "SELECT * FROM pg_stat_activity WHERE pid IN (SELECT pid FROM pg_locks LIMIT 1)"
expect 3 "LIMIT before a trailing clause" -- pg "SELECT * FROM (SELECT * FROM pg_stat_activity LIMIT 5) s ORDER BY 1"
expect 3 "mysql LIMIT offset, count"      -- my "SELECT * FROM performance_schema.processlist LIMIT 0, 100000"
expect 3 "multi-line SQL (one line only)" -- pg "$(printf 'SELECT 1\nLIMIT 1')"
expect 3 "redis SLOWLOG GET 1000"         -- rd SLOWLOG GET 1000
expect 3 "redis SLOWLOG RESET"            -- rd SLOWLOG RESET
expect 3 "redis unknown command"          -- rd SET k v
expect 3 "redis inline -a password"       -- rd -a hunter2 INFO

# 4. Secrets and target pinning.
expect 3 "preset PGOPTIONS refused" -- env -u PGPASSWORD PGOPTIONS='-c default_transaction_read_only=off' PGHOST=h PGDATABASE=d PGUSER=u DB_RO_DRYRUN=1 "$B" "$RO" pg -- "SELECT 1 LIMIT 1"
expect 3 "preset PGOPTIONS timeout=0 refused" -- env -u PGPASSWORD PGOPTIONS='-c statement_timeout=0' PGSERVICE=svc DB_RO_DRYRUN=1 "$B" "$RO" pg -- "SELECT 1 LIMIT 1"
expect 3 "PGPASSWORD refused"  -- env PGPASSWORD=x PGHOST=h PGDATABASE=d PGUSER=u DB_RO_DRYRUN=1 "$B" "$RO" pg -- "SELECT 1 LIMIT 1"
expect 3 "MYSQL_PWD refused"   -- env MYSQL_PWD=x MYSQL_DEFAULTS_FILE="$W/my.cnf" DB_RO_DRYRUN=1 "$B" "$RO" mysql -- "SELECT 1 LIMIT 1"
expect 1 "pg needs PGHOST"     -- env -u PGHOST -u PGSERVICE PGDATABASE=d PGUSER=u DB_RO_DRYRUN=1 "$B" "$RO" pg -- "SELECT 1 LIMIT 1"
expect 1 "redis needs host"    -- env -u REDIS_HOST REDIS_PORT=1 DB_RO_DRYRUN=1 "$B" "$RO" redis -- INFO
expect 2 "usage without --"    -- "$B" "$RO" pg "SELECT 1"

# 5. Allowed reads.
expect 0 "pg SELECT with LIMIT"     -- pg "SELECT pid, state FROM pg_stat_activity WHERE wait_event_type = 'Lock' LIMIT 20"
expect 0 "string literal Sleep is not SLEEP()" -- my "SELECT ID FROM performance_schema.processlist WHERE COMMAND <> 'Sleep' LIMIT 5"
expect 0 "pg SHOW"                  -- pg "SHOW max_connections"
expect 0 "pg EXPLAIN"               -- pg "EXPLAIN SELECT * FROM t WHERE id = 1"
expect 0 "mysql SHOW REPLICA STATUS" -- my "SHOW REPLICA STATUS"
expect 0 "mysql SHOW CREATE TABLE"  -- my "SHOW CREATE TABLE t"
expect 0 "redis INFO memory"        -- rd INFO memory
expect 0 "redis SCAN COUNT"         -- rd SCAN 0 MATCH 'session:*' COUNT 100
expect 0 "redis MEMORY USAGE <key>" -- rd MEMORY USAGE 'session:1'
expect 0 "pg LIMIT n OFFSET m"      -- pg "SELECT pid FROM pg_stat_activity ORDER BY pid LIMIT 5 OFFSET 10"
expect 0 "pg LIMIT in subquery and at the end" -- pg "SELECT pid FROM pg_stat_activity WHERE pid IN (SELECT pid FROM pg_locks LIMIT 5) LIMIT 5"
expect 0 "pg redacted query text"   -- pg "SELECT CASE WHEN query ILIKE '%password%' THEN '<redacted: contains password>' ELSE left(query, 200) END AS query FROM pg_stat_statements LIMIT 15"
expect 0 "redis SLOWLOG GET 25"     -- rd SLOWLOG GET 25

# 6. Session guards are applied.
out="$(pg "SHOW max_connections" 2>&1)"
case "$out" in *default_transaction_read_only=on*statement_timeout=5000*lock_timeout=*) ok "pg PGOPTIONS read-only + timeouts";; *) bad "pg PGOPTIONS: $out";; esac
# Guards also go in the conninfo options=, which beats PGOPTIONS and a pg_service.conf options= line
case "$out" in *"-d options=\\'-c\\ default_transaction_read_only=on"*statement_timeout=5000*) ok "pg guards in conninfo options=";; *) bad "pg conninfo options missing: $out";; esac
out="$(env -u PGPASSWORD -u PGHOST PGSERVICE=prod-ro DB_RO_DRYRUN=1 "$B" "$RO" pg -- "SHOW max_connections" 2>&1)"
case "$out" in *"service=prod-ro"*"options=\\'-c\\ default_transaction_read_only=on"*) ok "PGSERVICE target line + conninfo guards";; *) bad "PGSERVICE: $out";; esac
# redis-cli -t only exists from 7.4: stub "--help" with and without it, so the result never depends on the host's redis-cli.
printf '#!/bin/sh\n[ "$1" = --help ] && { printf "  -p <port>          Server port (default: 6379).\\n  -t <timeout>       Server connection timeout in seconds (decimals allowed).\\n"; exit 0; }\necho PONG\n' >"$W/rc-help-t"
printf '#!/bin/sh\n[ "$1" = --help ] && { printf "  -p <port>          Server port (default: 6379).\\n  -s <socket>        Server socket (overrides hostname and port).\\n"; exit 0; }\ncase " $* " in *" -t "*) echo "Unrecognized option or bad number of args for: '"'"'-t'"'"'" >&2; exit 1;; esac\necho PONG\n' >"$W/rc-help-no-t"
chmod +x "$W/rc-help-t" "$W/rc-help-no-t"
case "$(DB_RO_REDIS_BIN="$W/rc-help-t" rd INFO 2>&1)" in *" -t 5 "*) ok "redis-cli >= 7.4 (--help lists -t): -t 5 added";; *) bad "redis -t missing with a -t capable client";; esac
case "$(DB_RO_REDIS_BIN="$W/rc-help-no-t" rd INFO 2>&1)" in *" -t "*) bad "redis -t passed to a 7.2-style client";; *DRYRUN:*) ok "redis-cli 7.2 (no -t in --help): -t omitted";; *) bad "redis dry-run output missing";; esac
case "$(DB_RO_REDIS_BIN="$W/does-not-exist" rd INFO 2>&1)" in *" -t "*) bad "redis -t passed when --help fails";; *DRYRUN:*) ok "redis-cli --help failing: -t omitted";; *) bad "redis dry-run output missing (no client)";; esac
expect 0 "redis 7.2-style client runs without -t (not dry-run)" -- env REDIS_HOST=h REDIS_PORT=1 DB_RO_REDIS_BIN="$W/rc-help-no-t" "$B" "$RO" redis -- PING
out="$(my "SHOW REPLICA STATUS" 2>&1)"
case "$out" in *--defaults-extra-file=*--init-command=SET\\\ SESSION\\\ transaction_read_only=ON*max_execution_time=5000*) ok "mysql read-only + max_execution_time";; *) bad "mysql init: $out";; esac
out="$(ENGINE=mariadb my "SHOW REPLICA STATUS" 2>&1)"
case "$out" in *mariadb*tx_read_only=1*max_statement_time=5*) ok "mariadb read-only + max_statement_time (s)";; *) bad "mariadb init: $out";; esac
case "$(my "SHOW REPLICA STATUS" 2>&1 | sed -n 's/^DRYRUN: //p' | awk '{print $2}')" in --defaults-extra-file=*) ok "defaults-extra-file is first option";; *) bad "defaults-extra-file not first";; esac

# 7. Output cap with a stub client (not dry-run).
printf '#!/bin/sh\necho "PGOPTIONS=$PGOPTIONS"\ni=0; while [ $i -lt 500 ]; do echo row$i; i=$((i+1)); done\n' >"$W/psql"; chmod +x "$W/psql"
out="$(env -u PGPASSWORD PGHOST=h PGDATABASE=d PGUSER=u DB_RO_PSQL_BIN="$W/psql" DB_RO_MAX_ROWS=50 "$B" "$RO" pg -- "SELECT 1 LIMIT 1" 2>/dev/null)"
[[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 56 ]] && ok "output capped at DB_RO_MAX_ROWS + 5 header/footer lines" || bad "cap: $(printf '%s\n' "$out" | wc -l) lines"
case "$out" in *"capped at 55 of 501"*) ok "cap notice printed";; *) bad "no cap notice";; esac
printf '#!/bin/sh\nhead -c 400000 /dev/zero | tr "\\0" x\n' >"$W/psql1"; chmod +x "$W/psql1"
out="$(env -u PGPASSWORD PGHOST=h PGDATABASE=d PGUSER=u DB_RO_PSQL_BIN="$W/psql1" "$B" "$RO" pg -- "SELECT 1 LIMIT 1" 2>/dev/null)"
[[ ${#out} -lt 263000 ]] && ok "one huge row is byte-capped" || bad "byte cap: ${#out} chars"
case "$out" in *"capped at 262144 of 400000 bytes"*) ok "byte cap notice printed";; *) bad "no byte cap notice";; esac

printf '#!/bin/sh\necho "psql: error: connection failed"\nexit 2\n' >"$W/psql2"; chmod +x "$W/psql2"
expect 1 "client exit 2 maps to 1" -- env -u PGPASSWORD PGHOST=h PGDATABASE=d PGUSER=u DB_RO_PSQL_BIN="$W/psql2" "$B" "$RO" pg -- "SELECT 1 LIMIT 1"

# 7b. redis-cli exits 0 on server errors: the wrapper must report them (stub client, not dry-run).
printf '#!/bin/sh\necho "NOPERM User sre-ro has no permissions to run the '"'"'pttl'"'"' command"\nexit 0\n' >"$W/rc-noperm"
printf '#!/bin/sh\necho "(error) WRONGPASS invalid username-password pair or user is disabled."\nexit 0\n' >"$W/rc-wrongpass"
printf '#!/bin/sh\necho "Could not connect to Redis at h:1: Connection refused"\nexit 0\n' >"$W/rc-noconn"
printf '#!/bin/sh\necho "# Memory"; echo "used_memory:1024"; echo "maxmemory_policy:noeviction"\nexit 0\n' >"$W/rc-ok"
chmod +x "$W"/rc-*
for st in noperm wrongpass noconn; do
  expect 1 "redis $st with exit 0 is reported as error" -- env REDIS_HOST=h REDIS_PORT=1 DB_RO_REDIS_BIN="$W/rc-$st" "$B" "$RO" redis -- PTTL k
done
expect 0 "redis normal output stays ok" -- env REDIS_HOST=h REDIS_PORT=1 DB_RO_REDIS_BIN="$W/rc-ok" "$B" "$RO" redis -- INFO memory
rm -rf "$W/snap-noperm"
env REDIS_HOST=h REDIS_PORT=1 DB_RO_REDIS_BIN="$W/rc-noperm" "$B" "$SNAP" redis "$W/snap-noperm" >/dev/null 2>&1 || true
case "$(grep items_ "$W/snap-noperm/00-README.txt" 2>/dev/null)" in *"items_ok: 0 "*) ok "snapshot with a denied redis user reports 0 ok";; *) bad "snapshot NOPERM: $(grep items_ "$W/snap-noperm/00-README.txt" 2>/dev/null)";; esac

# 8. Every snapshot item passes the wrapper (dry-run), for each engine.
for e in pg mysql mariadb redis; do
  rm -rf "$W/snap-$e"
  env -u PGPASSWORD -u MYSQL_PWD PGHOST=h PGDATABASE=d PGUSER=u MYSQL_DEFAULTS_FILE="$W/my.cnf" REDIS_HOST=h REDIS_PORT=1 \
    DB_RO_DRYRUN=1 "$B" "$SNAP" "$e" "$W/snap-$e" >/dev/null 2>&1
  r="$(grep items_ "$W/snap-$e/00-README.txt" 2>/dev/null)"
  case "$r" in *"items_failed: 0"*) ok "snapshot $e: $r";; *) bad "snapshot $e: ${r:-no README}"; grep -l REFUSED "$W/snap-$e"/*.txt 2>/dev/null | head -3;; esac
done
[[ "$(stat -c %a "$W/snap-pg" 2>/dev/null || stat -f %Lp "$W/snap-pg")" == 700 ]] && ok "snapshot dir is 0700" || bad "snapshot dir mode"
mkdir -p "$W/snap-exist"; chmod 755 "$W/snap-exist"
env -u PGPASSWORD PGHOST=h PGDATABASE=d PGUSER=u DB_RO_DRYRUN=1 "$B" "$SNAP" pg "$W/snap-exist" >/dev/null 2>&1 || true
[[ "$(stat -c %a "$W/snap-exist" 2>/dev/null || stat -f %Lp "$W/snap-exist")" == 700 ]] && ok "existing snapshot dir tightened to 0700" || bad "existing dir mode"
if command -v git >/dev/null 2>&1; then
  git init -q "$W/repo" 2>/dev/null
  expect 2 "snapshot refuses a path inside a git work tree" -- env -u PGPASSWORD PGHOST=h PGDATABASE=d PGUSER=u DB_RO_DRYRUN=1 "$B" "$SNAP" pg "$W/repo/incident/db-t0"
fi
# Redaction: every query-text column in the snapshot is wrapped (blocker: pg_stat_statements stores ALTER ROLE ... PASSWORD)
grep -q "pg_stat_statements" "$W"/snap-pg/*top-statements.txt && grep -qF "ILIKE\\ \\'%password%\\'" "$W"/snap-pg/*top-statements.txt \
  && ok "snapshot top-statements redacts password text" || bad "top-statements not redacted"
n_unred="$(grep -l 'query' "$W"/snap-pg/*.txt | xargs grep -L 'password' | grep -v -e identity -e README | wc -l | tr -d ' ')"
for f in "$W"/snap-pg/*.txt; do case "$f" in *oldest-xacts*|*blocked*|*blockers*|*xmin-horizon*|*top-statements*) grep -q 'password' "$f" || bad "unredacted query text in $(basename "$f")";; esac; done
[[ "$n_unred" == 0 ]] && ok "no pg snapshot item shows query text without redaction" || bad "$n_unred pg items show unredacted query text"
for f in "$W"/snap-mysql/*long-running.txt "$W"/snap-mysql/*innodb-trx.txt "$W"/snap-mysql/*lock-waits.txt "$W"/snap-mariadb/*lock-waits.txt; do
  grep -q 'PASSWORD' "$f" && ok "mysql redaction in $(basename "$f")" || bad "mysql unredacted: $f"
done
grep -q 'CONFIG' "$W"/snap-redis/*.txt && bad "redis snapshot still calls CONFIG" || ok "redis snapshot has no CONFIG call"
grep -q 'CLIENT LIST TYPE normal' "$W"/snap-redis/*client-list.txt && ok "redis snapshot uses CLIENT LIST TYPE normal" || bad "redis CLIENT LIST unfiltered"

# 9. Every db-ro.sh line in the references passes the wrapper (dry-run), so a documented read is never refused.
docs=0
while IFS= read -r line; do
  case "$line" in *'$('*|*'`'*) bad "unexpected substitution in reference line: $line"; continue ;; esac
  rest="$(printf '%s' "${line#bash scripts/db-ro.sh }" | sed 's/<[^>]*>/X/g')"; docs=$((docs+1))   # placeholders -> X
  eval "set -- $rest"; e="$1"; shift 2
  env -u PGPASSWORD -u MYSQL_PWD -u PGOPTIONS PGHOST=h PGDATABASE=d PGUSER=u MYSQL_DEFAULTS_FILE="$W/my.cnf" REDIS_HOST=h REDIS_PORT=1 \
    DB_RO_DRYRUN=1 "$B" "$RO" "$e" -- "$@" >"$W/out" 2>&1 && continue
  bad "reference read refused: $line"; sed 's/^/      /' "$W/out" | head -3
done < <(awk '/^[[:space:]]*```/{f=!f; next} f && /bash scripts\/db-ro\.sh (pg|mysql|mariadb|redis) --/' "$here"/references/*.md "$here"/SKILL.md | sed 's/^[[:space:]]*//; s/^\([A-Z_]*=[^ ]* \)*//' | grep '^bash scripts/db-ro.sh ')
(( docs >= 60 )) && ok "$docs reference db-ro.sh lines pass the wrapper" || bad "only $docs reference lines found"

# 10. Gate format: every gated block has exactly '**Gate: approval required.**' on the line directly above
#     its fence and holds ONE command (comments aside); every block with a gated command is such a block.
gates="$(awk '
  FNR==1 { prev="" }
  /^```/ { if (!inb) { inb=1; gated=(prev=="**Gate: approval required.**"); cmds=0; risky=0; start=FNR; next }
           inb=0
           if (gated && cmds != 1) print FILENAME ":" start ": gated block has " cmds " commands"
           if (risky && !gated) print FILENAME ":" start ": gated command without the gate line directly above"
           prev=$0; next }
  inb { if ($0 !~ /^[[:space:]]*(--|#)/ && $0 !~ /^[[:space:]]*$/) cmds++
        if ($0 ~ /pg_terminate_backend|pg_cancel_backend|pg_drop_replication_slot|^[[:space:]]*KILL|rds_kill|az_kill|CONFIG SET|CLIENT KILL|failover|force-reboot|--memkeys|--bigkeys/) risky=1
        next }
  { prev=$0 }' "$here"/references/postgres.md "$here"/references/mysql.md "$here"/references/redis.md "$here"/SKILL.md)"
nblocks="$(grep -c '^\*\*Gate: approval required\.\*\*$' "$here"/references/postgres.md "$here"/references/mysql.md "$here"/references/redis.md | awk -F: '{s+=$2} END{print s}')"
[[ -z "$gates" ]] && ok "gate format: $nblocks gated blocks, one command each, marker directly above" || { bad "gate format"; printf '      %s\n' "$gates"; }

# 11. SHOW ENGINE INNODB STATUS redaction (scripts/innodb-redact.awk), under every awk on this host.
#     Fixtures: synthetic batch (one row, literal \n) and raw (real newlines) with secrets split across
#     line boundaries, plus two lab captures (Database Reviewer re-run, fake leak marker only).
FX="$here/tests/fixtures"; AWKS=""
for a in awk gawk mawk original-awk nawk; do command -v "$a" >/dev/null 2>&1 && AWKS="$AWKS $a"; done
# busybox: DB_RO_AWK must be ONE path ("busybox awk" is two words and fails closed), so use a symlink named
# awk -> busybox (busybox dispatches on argv[0]) and prove busybox really runs behind it.
BBAWK=""
if command -v busybox >/dev/null 2>&1; then
  mkdir -p "$W/bb"; ln -sf "$(command -v busybox)" "$W/bb/awk"
  bbusage="$("$W/bb/awk" 2>&1 || true)"   # usage exits non-zero; capture first (pipefail)
  if [[ "$bbusage" == *BusyBox* && "$("$W/bb/awk" 'BEGIN{print "bb-ok"}')" == bb-ok ]]; then
    ok "busybox awk runs via symlink $W/bb/awk (single path)"; BBAWK="$W/bb/awk"; AWKS="$AWKS $BBAWK"
  else bad "busybox awk symlink does not run busybox"; fi
fi
nawks=0; for a in $AWKS; do nawks=$((nawks+1)); done
ok "awks under test ($nawks):$AWKS"
cnt() { grep -o "$1" | wc -l | tr -d ' '; }   # count occurrences on stdin
for a in $AWKS; do
  an="$(basename "$a")"; [[ "$a" == "$BBAWK" ]] && an="busybox-awk"
  for f in "$FX"/innodb-status-*.txt; do
    fn="$(basename "$f" .txt)"
    "$a" -f "$here/scripts/innodb-redact.awk" "$f" >"$W/red.out" 2>&1 || { bad "$an $fn: awk failed"; continue; }
    grep -q -e 'FIXTURE_SECRET' -e 'LEAKMARK' "$W/red.out" && bad "$an $fn: secret leaked" || ok "$an $fn: no secret"
    [[ "$(cnt '\\n' <"$f")" == "$(cnt '\\n' <"$W/red.out")" ]] && ok "$an $fn: escaped newlines preserved" || bad "$an $fn: escaped newline count changed"
    [[ "$(grep -c 'TRX HAS BEEN WAITING' "$W/red.out")" -ge 1 ]] && ok "$an $fn: lock-wait structure kept" || bad "$an $fn: structure lost"
    case "$fn" in *batch*|*lab*) [[ "$(grep -v '^\[db-ro:' "$W/red.out" | wc -l | tr -d ' ')" == "$(wc -l <"$f" | tr -d ' ')" ]] && ok "$an $fn: still one batch row" || bad "$an $fn: batch row count changed";; esac
    [[ -s "$W/red.out" ]] || bad "$an $fn: empty output"
    case "$fn" in *edge*)
      for k in EDGE_A EDGE_DASHES_B EDGE_STARS_C EDGE_PUREDASH_D; do grep -q "FIXTURE_SECRET_$k" "$W/red.out" && bad "$an $fn: $k leaked" || ok "$an $fn: $k redacted"; done
      grep -q 'SET v=2 WHERE id=1' "$W/red.out" && ok "$an $fn: next transaction's benign statement kept" || bad "$an $fn: over-redacted past a genuine marker";;
    esac
    case "$fn" in innodb-status-batch|innodb-status-raw)
      grep -q 'SET v=2 WHERE id=1' "$W/red.out" && ok "$an $fn: benign statement kept" || bad "$an $fn: benign statement redacted"
      grep -q "CHANGE REPLICATION SOURCE TO SOURCE_HOST='db2'," "$W/red.out" && ok "$an $fn: text before the keyword kept" || bad "$an $fn: over-redacted"
      grep -qF "keep" "$W/red.out" && ok "$an $fn: backslash literal kept" || bad "$an $fn: backslash literal lost";;
    esac
    case "$fn" in innodb-status-batch) grep -qF 'keep\\nthis' "$W/red.out" && ok "$an $fn: escaped backslash not split" || bad "$an $fn: escaped backslash mangled";; esac
    md5="$( (md5sum 2>/dev/null || md5 -q) <"$W/red.out" | awk '{print $1}')"
    eval "prev=\${H_$(printf '%s' "$fn" | tr -c 'a-zA-Z0-9' _):-}"
    if [[ -z "$prev" ]]; then eval "H_$(printf '%s' "$fn" | tr -c 'a-zA-Z0-9' _)=$md5"; elif [[ "$prev" == "$md5" ]]; then ok "$an $fn: output identical to the first awk"; else bad "$an $fn: output differs between awks"; fi
  done
done
# busybox byte-for-byte against gawk on every fixture (so a busybox that silently did nothing cannot pass).
if [[ -n "$BBAWK" ]] && command -v gawk >/dev/null 2>&1; then
  for f in "$FX"/innodb-status-*.txt; do
    "$BBAWK" -f "$here/scripts/innodb-redact.awk" "$f" >"$W/bb.out" 2>&1; gawk -f "$here/scripts/innodb-redact.awk" "$f" >"$W/gk.out" 2>&1
    [[ -s "$W/bb.out" ]] && cmp -s "$W/bb.out" "$W/gk.out" && ok "busybox == gawk byte-for-byte: $(basename "$f")" || bad "busybox differs from gawk: $(basename "$f")"
  done
fi
# Known limitation (documented in innodb-redact.awk and references/mysql.md): a statement that embeds an exact
# genuine marker ("---TRANSACTION 999") between keyword and secret ends redaction early. This test pins the
# limitation so the docs stay honest; the evidence bundle does not capture INNODB STATUS (checked below).
for a in $AWKS; do
  "$a" -f "$here/scripts/innodb-redact.awk" "$FX/innodb-limitation-embedded-trx.txt" 2>&1 | grep -q FIXTURE_LIMITATION_SECRET \
    && ok "$([[ "$a" == "$BBAWK" ]] && echo busybox-awk || basename "$a"): known limitation reproduced (embedded ---TRANSACTION; documented, interactive use only)" \
    || bad "$(basename "$a"): limitation no longer reproduces: update the docs in innodb-redact.awk and mysql.md"
done
# Through the wrapper (stub mysql prints the batch fixture for SHOW ENGINE, fixed text otherwise).
printf '#!/bin/sh\ncase "$*" in *"SHOW ENGINE"*) cat "%s";; *) printf "Variable_name\\tValue\\nUptime\\t5\\n";; esac\n' "$FX/innodb-status-batch.txt" >"$W/mysql-innodb"; chmod +x "$W/mysql-innodb"
: >"$W/my.cnf"
sed "s|innodb-status-batch.txt|innodb-status-edge-batch.txt|" "$W/mysql-innodb" >"$W/mysql-edge"; chmod +x "$W/mysql-edge"
for a in $AWKS; do
  an="$(basename "$a")"; [[ "$a" == "$BBAWK" ]] && an="busybox-awk"
  out="$(env -u MYSQL_PWD MYSQL_DEFAULTS_FILE="$W/my.cnf" DB_RO_MYSQL_BIN="$W/mysql-innodb" DB_RO_AWK="$a" DB_RO_MAX_ROWS=400 "$B" "$RO" mysql -- "SHOW ENGINE INNODB STATUS" 2>&1)"; rc=$?
  case "$out" in *FIXTURE_SECRET*|*LEAKMARK*) bad "wrapper ($an): INNODB STATUS leaked";; *"<redacted: may contain a password>"*) [[ $rc == 0 ]] && ok "wrapper ($an): INNODB STATUS redacted, exit 0" || bad "wrapper ($an): exit $rc";; *) bad "wrapper ($an): no marker";; esac
  out="$(env -u MYSQL_PWD MYSQL_DEFAULTS_FILE="$W/my.cnf" DB_RO_MYSQL_BIN="$W/mysql-edge" DB_RO_AWK="$a" DB_RO_MAX_ROWS=400 "$B" "$RO" mariadb -- "SHOW ENGINE INNODB STATUS" 2>&1)"; rc=$?
  case "$out" in *FIXTURE_SECRET*) bad "wrapper ($an): round-3 edge case leaked";; *"best-effort redaction only"*) [[ $rc == 0 ]] && ok "wrapper ($an): round-3 edge cases (---ticket, *** note, bare ---) redacted, best-effort notice shown" || bad "wrapper ($an) edge: exit $rc";; *) bad "wrapper ($an): edge output unexpected";; esac
done
out="$(env -u MYSQL_PWD MYSQL_DEFAULTS_FILE="$W/my.cnf" DB_RO_MYSQL_BIN="$W/mysql-innodb" DB_RO_AWK=false "$B" "$RO" mysql -- "show  engine innodb status" 2>&1)"; rc=$?
case "$out" in *FIXTURE_SECRET*|*LEAKMARK*) bad "redaction failure leaks output";; *"output withheld"*) [[ $rc == 1 ]] && ok "redaction failure: output withheld, exit 1" || bad "redaction failure exit $rc";; *) bad "redaction failure: $out";; esac
# The evidence bundle never captures INNODB STATUS: stub mysql prints the leaking limitation fixture for
# SHOW ENGINE and logs every call; the snapshot must never ask for it, and nothing may leak.
printf '#!/bin/sh\necho "$*" >>"%s"\ncase "$*" in *"SHOW ENGINE"*) cat "%s";; *) printf "Variable_name\\tValue\\nUptime\\t5\\n";; esac\n' "$W/mysql-calls" "$FX/innodb-limitation-embedded-trx.txt" >"$W/mysql-lim"; chmod +x "$W/mysql-lim"
for e in mysql mariadb; do
  rm -rf "$W/snap-innodb-$e"; : >"$W/mysql-calls"
  env -u MYSQL_PWD MYSQL_DEFAULTS_FILE="$W/my.cnf" DB_RO_MYSQL_BIN="$W/mysql-lim" "$B" "$SNAP" "$e" "$W/snap-innodb-$e" >/dev/null 2>&1 || true
  [[ -s "$W/mysql-calls" ]] || bad "$e snapshot stub was never called"
  grep -qi 'SHOW *ENGINE' "$W/mysql-calls" && bad "$e snapshot ran SHOW ENGINE" || ok "$e snapshot never runs SHOW ENGINE INNODB STATUS"
  hasinno=0; for x in "$W/snap-innodb-$e"/*innodb-status*; do [[ -e "$x" ]] && hasinno=1; done
  [[ $hasinno == 1 ]] && bad "$e snapshot has an innodb-status item" || ok "$e snapshot has no innodb-status item"
  grep -rq -e FIXTURE_LIMITATION_SECRET -e 'INNODB MONITOR OUTPUT' "$W/snap-innodb-$e" && bad "$e snapshot contains INNODB STATUS text" || ok "$e snapshot contains no INNODB STATUS text"
done
grep -qiE '^[^#]*item[^#]*SHOW[[:space:]]+ENGINE' "$SNAP" && bad "db-snapshot.sh still mentions SHOW ENGINE as an item" || ok "db-snapshot.sh has no SHOW ENGINE item"

# 12. Round 3: statement text is redacted on the FULL column (plain sys views cut out the middle), replica check, psql -w.
grep -h -e '^bash scripts/db-ro.sh' -e 'item ' "$here"/references/*.md "$here/scripts/db-snapshot.sh" | grep -E 'sys\.(processlist|innodb_lock_waits)' >"$W/plainsys"
[[ ! -s "$W/plainsys" ]] && ok "no runnable query uses the middle-truncating sys.processlist / sys.innodb_lock_waits" || { bad "plain sys view in a runnable query"; sed 's/^/      /' "$W/plainsys" | cut -c1-120; }
grep -qF "IF(UPPER(current_statement) LIKE '%PASSWORD%' OR UPPER(current_statement) LIKE '%IDENTIFIED%', '<redacted: may contain a password>', LEFT(current_statement, 200))" "$here/references/mysql.md" \
  && ok "mysql.md sys.x\$processlist redacts the full current_statement before LEFT()" || bad "row 53 redaction pattern missing"
# Any LEFT()/left() of a statement column in a runnable query must sit inside the redaction CASE/IF.
grep -h -e '^bash scripts/db-ro.sh' -e 'item ' "$here"/references/*.md "$here/scripts/db-snapshot.sh" \
  | grep -oiE "left\((query|info|trx_query|r\.trx_query|b\.trx_query|waiting_query|blocking_query|current_statement), [0-9]+\)" | sort -u >"$W/lefts"
nleft=0; while read -r l; do nleft=$((nleft+1)); col="$(printf '%s' "$l" | sed -E 's/^[lL][eE][fF][tT]\(([^,]*),.*/\1/')"
  grep -h -e '^bash scripts/db-ro.sh' -e 'item ' "$here"/references/*.md "$here/scripts/db-snapshot.sh" | grep -F "$l" | grep -viqF "$col) LIKE '%PASSWORD%'" && { grep -h -e '^bash scripts/db-ro.sh' -e 'item ' "$here"/references/*.md "$here/scripts/db-snapshot.sh" | grep -F "$l" | grep -vF "ILIKE '%password%'" | grep -vF '$(red ' | grep -viqF "$col) LIKE '%PASSWORD%'" && bad "unredacted $l"; }
done <"$W/lefts"; ok "checked $nleft truncated statement columns for redaction"
rq="$(grep -h 'pg_stat_wal_receiver r ON true' "$here/references/postgres.md" "$here/scripts/db-snapshot.sh")"
[[ "$(printf '%s\n' "$rq" | grep -cF "greatest(interval '60 seconds', current_setting('wal_receiver_timeout')::interval)")" == 2 ]] && ok "replica check: threshold greatest(60 s, wal_receiver_timeout) in reference and snapshot" || bad "replica threshold"
[[ "$(printf '%s\n' "$rq" | grep -cF "'n/a (primary)'")" == 2 ]] && ok "replica check: n/a (primary) in reference and snapshot" || bad "replica n/a (primary)"
grep -q "rolname NOT IN ('sre_ro', 'pg_monitor', 'pg_read_all_settings', 'pg_read_all_stats', 'pg_stat_scan_tables', 'pg_use_reserved_connections')" "$here/references/postgres.md" && ok "grants check lists only unexpected roles" || bad "grants check"
case "$(pg "SELECT 1 LIMIT 1" 2>&1)" in *" -X -w "*) ok "psql -w (never prompt for a password)";; *) bad "psql -w missing";; esac
awk '/^```sql/{f=1;b="";next} /^```/{if(f&&b~/pg_use_reserved_connections/&&b~/CREATE ROLE/)print "mixed";f=0;next} f{b=b $0}' "$here/references/postgres.md" | grep -q mixed && bad "pg_use_reserved_connections still in the main setup block" || ok "pg_use_reserved_connections in its own PG16+ block"

echo "---"; echo "pass=$pass fail=$fail"
(( fail == 0 ))

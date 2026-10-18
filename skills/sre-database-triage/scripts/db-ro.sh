#!/usr/bin/env bash
# db-ro.sh: run ONE read-only diagnostic statement against Postgres, MySQL/MariaDB or Redis.
# Usage (SQL is ONE line, one statement; every SELECT/WITH ends with LIMIT n [OFFSET m]):
#   bash scripts/db-ro.sh pg      -- "<SELECT|WITH|SHOW|EXPLAIN ... LIMIT n>"
#   bash scripts/db-ro.sh mysql   -- "<SELECT|WITH|SHOW|EXPLAIN ... LIMIT n>"
#   bash scripts/db-ro.sh mariadb -- "<SELECT|WITH|SHOW|EXPLAIN ... LIMIT n>"
#   bash scripts/db-ro.sh redis   -- <INFO|SLOWLOG GET|LATENCY ...|MEMORY ...|SCAN ... COUNT n|...>
# Target (explicit, never a default):
#   pg:      PGHOST, PGPORT, PGDATABASE, PGUSER (or PGSERVICE); password via PGPASSFILE / ~/.pgpass only.
#            PGOPTIONS must be unset: the wrapper sets the session guards itself.
#   mysql:   MYSQL_DEFAULTS_FILE=<option file with [client] host/port/user/password/TLS>, chmod 600, one file
#            per engine (the mariadb client has no ssl-mode): references/mysql.md.
#   redis:   REDIS_HOST, REDIS_PORT; optional REDIS_USER, REDISCLI_AUTH (password), REDIS_TLS=1.
# Knobs: DB_RO_TIMEOUT_MS (default 5000), DB_RO_MAX_ROWS (output lines, default 200; output is also capped at 256 KiB),
#        DB_RO_DRYRUN=1 (print the command and env instead of running it).
# Exit: 0 ok, 1 runtime error (client error, server error such as Redis NOPERM, or timeout; the client's
#        own code is printed on stderr), 2 usage, 3 refused.
# This is an allowlist guard, not a security boundary: also use a read-only role (references/*.md).
# Sources (checked 2026-10-17):
#   https://www.postgresql.org/docs/current/runtime-config-client.html (statement_timeout, lock_timeout, default_transaction_read_only)
#   https://www.postgresql.org/docs/current/libpq-envars.html (PGOPTIONS, PGPASSFILE, PGCONNECT_TIMEOUT)
#   https://www.postgresql.org/docs/current/libpq-connect.html (conninfo options=; beats env and service file)
#   https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html (max_execution_time: SELECT only)
#   https://dev.mysql.com/doc/refman/8.4/en/option-file-options.html (--defaults-extra-file must be first)
#   https://mariadb.com/docs/server/ha-and-performance/optimization-and-tuning/query-optimizations/aborting-statements (max_statement_time, seconds)
#   https://redis.io/docs/latest/develop/tools/cli/ (REDISCLI_AUTH, -t connect timeout)
#   https://raw.githubusercontent.com/redis/redis/7.4.0/00-RELEASENOTES (#10609: -t is new in 7.4)
#   https://redis.io/docs/latest/commands/memory-usage/ (SAMPLES 0 samples every nested value)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REDACT_AWK=""

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
refuse() { echo "REFUSED: $*" >&2; exit 3; }
need() { # need VAR "hint": explicit target/env required (plain check: ${VAR:?} loses its exit code under an EXIT trap in bash 3.2)
  if [[ -z "${!1:-}" ]]; then echo "missing $1: $2" >&2; exit 1; fi
}

engine="${1:-}"; [[ -n "$engine" ]] || usage; shift
[[ "${1:-}" == "--" ]] || usage; shift
[[ $# -ge 1 ]] || usage

TIMEOUT_MS="${DB_RO_TIMEOUT_MS:-5000}"
MAX_ROWS="${DB_RO_MAX_ROWS:-200}"
MAX_BYTES=262144  # 256 KiB hard cap: a single row can be huge
case "$TIMEOUT_MS" in ''|*[!0-9]*) refuse "DB_RO_TIMEOUT_MS must be an integer" ;; esac
case "$MAX_ROWS" in ''|*[!0-9]*) refuse "DB_RO_MAX_ROWS must be an integer" ;; esac
(( TIMEOUT_MS >= 100 && TIMEOUT_MS <= 60000 )) || refuse "DB_RO_TIMEOUT_MS must be 100..60000"
(( MAX_ROWS >= 1 && MAX_ROWS <= 2000 )) || refuse "DB_RO_MAX_ROWS must be 1..2000"

# Normalised, upper-case, space-padded word string for portable (bash 3.2) word matching.
words() { printf ' %s ' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_\n' ' ' | tr -s ' '; }

check_sql() { # check_sql <dialect pg|mysql> <statement>
  local d="$1" s="$2" w c first n lim u tail re
  case "$s" in *';'*) refuse "one statement only; no ';'" ;; esac
  case "$s" in *'--'*|*'/*'*|*'#'*) refuse "no comments or hints in the statement" ;; esac
  case "$s" in *'\'*) refuse "no psql/mysql backslash meta-commands" ;; esac
  w="$(words "$s")"
  first="$(printf '%s' "$w" | awk '{print $1}')"
  case "$first" in
    SELECT|WITH|SHOW|EXPLAIN) ;;
    *) refuse "first keyword '$first' is not SELECT/WITH/SHOW/EXPLAIN" ;;
  esac
  # Inner DML/DDL (e.g. PG data-modifying CTEs). LOCK/REPLACE are not listed: they collide with
  # wait_event_type='Lock' and replace(); as statements they are already refused by the first-keyword check.
  for k in INSERT UPDATE DELETE MERGE TRUNCATE DROP ALTER CREATE GRANT REVOKE \
           COPY CALL "DO" EXECUTE PREPARE SET RESET KILL INTO HANDLER LOAD; do
    case "$w" in *" $k "*)
      # SHOW ... allows these words only as object names in a few read-only forms
      if [[ "$first" == SHOW && ( "$k" == CREATE || "$k" == GRANT ) ]]; then continue; fi
      refuse "keyword $k not allowed in read-only mode" ;;
    esac
  done
  if [[ "$first" == EXPLAIN ]]; then
    case "$w" in *" ANALYZE "*|*" ANALYSE "*) refuse "EXPLAIN ANALYZE executes the statement; use plain EXPLAIN" ;; esac
  fi
  # Function calls are matched as NAME( on a compact form (no spaces or double quotes), so string
  # literals such as COMMAND <> 'Sleep' do not trip them.
  c="$(printf '%s' "$s" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]"`')"   # all whitespace, PG double quotes and MySQL backticks
  case "$w" in *" FOR UPDATE "*|*" FOR SHARE "*|*" FOR NO KEY UPDATE "*|*" FOR KEY SHARE "*|*" LOCK IN SHARE MODE "*)
    refuse "row-locking clause not allowed" ;; esac
  if [[ "$d" == pg ]]; then
    for f in PG_CANCEL_BACKEND PG_TERMINATE_BACKEND PG_RELOAD_CONF PG_ROTATE_LOGFILE PG_PROMOTE PG_SWITCH_WAL \
             PG_CREATE_RESTORE_POINT SET_CONFIG PG_SLEEP PG_SLEEP_FOR PG_SLEEP_UNTIL PG_STAT_RESET PG_STAT_STATEMENTS_RESET \
             PG_DROP_REPLICATION_SLOT PG_REPLICATION_SLOT_ADVANCE PG_LOGICAL_SLOT_GET_CHANGES PG_LOGICAL_SLOT_GET_BINARY_CHANGES \
             PG_READ_FILE PG_READ_BINARY_FILE PG_LS_DIR PG_STAT_FILE PG_WAL_REPLAY_PAUSE PG_WAL_REPLAY_RESUME \
             PG_BACKUP_START PG_BACKUP_STOP PG_LOG_BACKEND_MEMORY_CONTEXTS PG_CURRENT_XACT_ID NEXTVAL SETVAL TXID_CURRENT \
             PG_NOTIFY PG_LOGICAL_EMIT_MESSAGE; do
      case "$c" in *"$f("*) refuse "function ${f} is not read-only (gated actions: references/postgres.md)" ;; esac
    done
    # Prefix families: pg_stat_reset_shared/_single_table_counters/_slru..., dblink_*, *_to_xml (run a query string)
    case "$w" in *" PG_ADVISORY"*|*" PG_TRY_ADVISORY"*|*" PG_CREATE_"*|*" LO_"*|*" PG_IMPORT_"*|*" PG_STAT_RESET"*|*" PG_STAT_STATEMENTS_RESET"*|*" DBLINK"*|*"_TO_XML"*)
      refuse "function family not allowed" ;; esac
  else
    for f in SLEEP BENCHMARK GET_LOCK RELEASE_LOCK RELEASE_ALL_LOCKS LOAD_FILE MASTER_POS_WAIT SOURCE_POS_WAIT \
             WAIT_FOR_EXECUTED_GTID_SET RDS_KILL RDS_KILL_QUERY AZ_KILL AZ_KILL_QUERY; do
      case "$c" in *"$f("*) refuse "function ${f} is not allowed (gated actions: references/mysql.md)" ;; esac
    done
  fi
  if [[ "$first" == SELECT || "$first" == WITH ]]; then
    case "$w" in *" LIMIT "*) ;; *) refuse "every SELECT needs LIMIT n (n <= $MAX_ROWS)" ;; esac
    # The LAST LIMIT must be the final clause (only OFFSET m may follow), checked on the raw text, so a
    # LIMIT inside a subquery does not count and MySQL "LIMIT offset, count" is refused.
    u="$(printf '%s' "$s" | tr '[:lower:]' '[:upper:]')"; tail="${u##*LIMIT}"
    re='^[[:space:]]+([0-9]+)([[:space:]]+OFFSET[[:space:]]+[0-9]+)?[[:space:]]*$'
    [[ "$tail" =~ $re ]] || refuse "the statement must end with LIMIT <literal integer> [OFFSET m]"
    lim="${BASH_REMATCH[1]}"
    n=$((10#$lim)); (( n <= MAX_ROWS )) || refuse "LIMIT $n is above DB_RO_MAX_ROWS=$MAX_ROWS"
  fi
}

# Secrets must come from files/env the tools read themselves, never from argv.
for a in "$@"; do
  case "$a" in *password=*|*PASSWORD=*|-p?*|--password*|-a|--pass|--askpass) refuse "no passwords on the command line; use PGPASSFILE, MYSQL_DEFAULTS_FILE or REDISCLI_AUTH" ;; esac
done

TMP="$(umask 077; mktemp "${TMPDIR:-/tmp}/db-ro.XXXXXX")"
trap 'rm -f -- "$TMP" "$TMP.r"' EXIT

run_capped() { # run_capped cmd...  (output may hold PII: keep out of repos)
  if [[ "${DB_RO_DRYRUN:-0}" == 1 ]]; then printf 'DRYRUN:'; printf ' %q' "$@"; printf '\n'; return 0; fi
  local rc=0 total bytes lines secs
  secs=$(( TIMEOUT_MS / 1000 + 10 ))
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" >"$TMP" 2>&1 || rc=$?
  elif command -v perl >/dev/null 2>&1; then   # macOS has no timeout(1); SIGALRM survives exec
    perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" "$@" >"$TMP" 2>&1 || rc=$?
    (( rc == 142 )) && rc=124
  else
    "$@" >"$TMP" 2>&1 || rc=$?
  fi
  if [[ -n "${REDACT_AWK:-}" ]]; then   # redact BEFORE capping, on the full output; fail closed
    if "${DB_RO_AWK:-awk}" -f "$REDACT_AWK" "$TMP" >"$TMP.r" 2>/dev/null; then mv -f -- "$TMP.r" "$TMP"
    else echo "[db-ro: redaction failed; output withheld]" >&2; return 1; fi
  fi
  total=$(wc -l <"$TMP" | tr -d ' ')
  bytes=$(wc -c <"$TMP" | tr -d ' ')
  lines=$(( MAX_ROWS + 5 ))   # headroom for psql/mysql header, separator and "(n rows)" footer
  head -n "$lines" "$TMP" | head -c "$MAX_BYTES" || true   # SIGPIPE from the first head is expected
  (( total > lines )) && echo "[db-ro: output capped at $lines of $total lines; narrow the query]"
  (( bytes > MAX_BYTES )) && printf '\n[db-ro: output capped at %s of %s bytes (one long row, e.g. SHOW ENGINE INNODB STATUS)]\n' "$MAX_BYTES" "$bytes"
  if (( rc == 124 )); then echo "[db-ro: client killed after ${secs}s]" >&2; fi
  if (( rc != 0 )); then echo "[db-ro: client exited $rc]" >&2; rc=1; fi
  return "$rc"
}

case "$engine" in
  pg)
    [[ $# -eq 1 ]] || refuse "pass the SQL as one quoted argument"
    [[ -n "${PGPASSWORD:-}" ]] && refuse "unset PGPASSWORD; use PGPASSFILE or ~/.pgpass (chmod 0600)"
    if [[ -z "${PGSERVICE:-}" ]]; then
      need PGHOST "explicit target host"; need PGDATABASE "database name"; need PGUSER "read-only role, e.g. a pg_monitor member"
    fi
    # A preset PGOPTIONS could add options after the guards (the last -c wins) or other risky settings
    # (search_path, role); refuse it instead of merging.
    [[ -z "${PGOPTIONS:-}" ]] || refuse "unset PGOPTIONS; the wrapper sets the session options itself"
    check_sql pg "$1"
    if [[ -n "${PGSERVICE:-}" ]]; then
      echo "target: pg service=$PGSERVICE (host/port/db/user from pg_service.conf unless PGHOST/PGPORT/PGDATABASE/PGUSER are set:${PGHOST:+ host=$PGHOST}${PGPORT:+ port=$PGPORT}${PGDATABASE:+ db=$PGDATABASE}${PGUSER:+ user=$PGUSER})" >&2
    else
      echo "target: pg host=$PGHOST port=${PGPORT:-5432} db=$PGDATABASE user=$PGUSER" >&2
    fi
    guards="-c default_transaction_read_only=on -c statement_timeout=${TIMEOUT_MS} -c lock_timeout=1000 -c idle_in_transaction_session_timeout=10000"
    # The conninfo options= below beats PGOPTIONS and a pg_service.conf options= line (libpq precedence).
    export PGOPTIONS="$guards"
    export PGAPPNAME="${PGAPPNAME:-sre-db-ro}" PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
    [[ "${DB_RO_DRYRUN:-0}" == 1 ]] && echo "PGOPTIONS=$PGOPTIONS"
    run_capped "${DB_RO_PSQL_BIN:-psql}" -X -w -v ON_ERROR_STOP=1 -P pager=off -d "options='$guards'" -c "$1"
    ;;
  mysql|mariadb)
    [[ $# -eq 1 ]] || refuse "pass the SQL as one quoted argument"
    [[ -n "${MYSQL_PWD:-}" ]] && refuse "unset MYSQL_PWD; use MYSQL_DEFAULTS_FILE"
    need MYSQL_DEFAULTS_FILE "option file with [client] host/user/password, chmod 600"
    [[ -r "$MYSQL_DEFAULTS_FILE" || "${DB_RO_DRYRUN:-0}" == 1 ]] || refuse "cannot read $MYSQL_DEFAULTS_FILE"
    check_sql mysql "$1"
    echo "target: $engine defaults-file=$MYSQL_DEFAULTS_FILE (host/user from that file)" >&2
    if [[ "$engine" == mysql ]]; then
      init="SET SESSION transaction_read_only=ON, SESSION max_execution_time=${TIMEOUT_MS}"
      bin="${DB_RO_MYSQL_BIN:-mysql}"
    else
      # tx_read_only works on 10.6-11.x (11.8 warns it is deprecated: Warning 1287); 10.11 has no
      # transaction_read_only, and init-command takes one statement, so keep the alias until 10.x is gone.
      init="SET SESSION tx_read_only=1, SESSION max_statement_time=$(( (TIMEOUT_MS + 999) / 1000 ))"
      bin="${DB_RO_MYSQL_BIN:-mariadb}"
    fi
    # SHOW ENGINE INNODB STATUS prints transaction SQL verbatim (no password rewriting): best-effort redaction
    # (defence in depth, not a guarantee; interactive use only, never in the evidence bundle: references/mysql.md).
    case "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]`')" in SHOWENGINE*) REDACT_AWK="$here/innodb-redact.awk" ;; esac
    # --defaults-extra-file must be the first option.
    run_capped "$bin" --defaults-extra-file="$MYSQL_DEFAULTS_FILE" --connect-timeout=5 --batch \
      --init-command="$init" -e "$1"
    ;;
  redis)
    need REDIS_HOST "explicit target host"; need REDIS_PORT "port"
    cmd="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; sub="$(printf '%s' "${2:-}" | tr '[:lower:]' '[:upper:]')"
    case "$cmd" in
      INFO|PING|TIME|ROLE|DBSIZE|LASTSAVE) ;;
      SLOWLOG) case "$sub" in
                 LEN) ;;
                 GET) n="${3:-10}"; case "$n" in *[!0-9]*) refuse "SLOWLOG GET count must be an integer" ;; esac
                      (( n >= 1 && n <= 128 )) || refuse "SLOWLOG GET count must be 1..128" ;;
                 *) refuse "SLOWLOG $sub not allowed (GET n | LEN)" ;; esac ;;
      LATENCY) case "$sub" in DOCTOR|LATEST|HISTORY) ;; *) refuse "LATENCY $sub not allowed" ;; esac ;;
      MEMORY)  case "$sub" in DOCTOR|STATS) ;; USAGE) [[ $# -eq 3 ]] || refuse "MEMORY USAGE <key> only (no SAMPLES: SAMPLES 0 walks every element)" ;; *) refuse "MEMORY $sub not allowed" ;; esac ;;
      CLIENT)  case "$sub" in LIST|INFO) ;; *) refuse "CLIENT $sub not allowed (gated actions: references/redis.md)" ;; esac ;;
      CLUSTER) case "$sub" in INFO|NODES|SHARDS) ;; *) refuse "CLUSTER $sub not allowed" ;; esac ;;
      TYPE|TTL|PTTL|EXISTS|OBJECT)
        [[ "$cmd" != OBJECT ]] || case "$sub" in ENCODING|FREQ|IDLETIME) ;; *) refuse "OBJECT $sub not allowed" ;; esac ;;
      SCAN)
        [[ $# -ge 2 ]] || refuse "SCAN <cursor> [MATCH p] COUNT n"
        cnt=""; i=0; for a in "$@"; do i=$((i+1)); if [[ "$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')" == COUNT ]]; then j=$((i+1)); cnt="${!j:-}"; fi; done
        case "$cnt" in ''|*[!0-9]*) refuse "SCAN needs COUNT n (n <= 1000)" ;; esac
        (( cnt <= 1000 )) || refuse "SCAN COUNT must be <= 1000" ;;
      *) refuse "Redis command '$cmd' is not on the read-only allowlist" ;;
    esac
    # CONFIG is not allowed at all (CONFIG GET can return requirepass/masterauth); maxmemory_policy is in INFO memory.
    args=(-h "$REDIS_HOST" -p "$REDIS_PORT" --no-auth-warning)
    # -t <connect timeout> only exists in newer redis-cli (8.0 has it, 7.2 rejects it and runs nothing): feature-detect
    # (added in redis-cli 7.4, redis PR #10609). Captured first, so grep -q cannot SIGPIPE the client under pipefail.
    rhelp="$("${DB_RO_REDIS_BIN:-redis-cli}" --help 2>&1 || true)"
    if grep -qE '^[[:space:]]+-t <timeout>' <<<"$rhelp"; then args+=(-t 5); fi
    [[ -n "${REDIS_USER:-}" ]] && args+=(--user "$REDIS_USER")
    [[ "${REDIS_TLS:-0}" == 1 ]] && args+=(--tls)
    echo "target: redis $REDIS_HOST:$REDIS_PORT user=${REDIS_USER:-default} tls=${REDIS_TLS:-0}" >&2
    rc=0; run_capped "${DB_RO_REDIS_BIN:-redis-cli}" "${args[@]}" "$@" || rc=$?
    # redis-cli exits 0 on server errors (NOPERM, WRONGPASS, ERR) and some connection errors: surface them.
    # Known edge: a SLOWLOG/SCAN result line that itself starts with one of these words also trips it (fails safe).
    if [[ $rc -eq 0 && "${DB_RO_DRYRUN:-0}" != 1 ]] && grep -qE '^(\(error\) )?(NOPERM|WRONGPASS|NOAUTH|ERR|AUTH failed|LOADING|MASTERDOWN|Could not connect|Error: )' "$TMP"; then
      echo "[db-ro: redis-cli returned a server/connection error]" >&2; rc=1
    fi
    exit "$rc"
    ;;
  *) usage ;;
esac

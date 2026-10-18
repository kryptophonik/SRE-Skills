#!/usr/bin/env bash
# Read-only TLS certificate expiry check. Prints one line per target:
#   STATUS  DAYS_LEFT  NOT_AFTER(UTC)  TARGET  SUBJECT
# STATUS is EXPIRED, CRIT (< --crit days), WARN (< --warn days) or OK.
# Targets: host[:port] (connects with SNI; default port 443) or --file cert.pem.
# Exit 0 when all OK, 1 when any WARN/CRIT/EXPIRED, 2 on usage or connection errors.
# Needs openssl and python3. Works on macOS /bin/bash 3.2. Sends no data beyond a TLS handshake.
set -uo pipefail
warn=30; crit=7; files=""; hosts=""; timeout=10
usage() { echo "usage: $0 [--warn DAYS] [--crit DAYS] [--timeout SEC] host[:port]... | --file cert.pem..." >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --warn) warn=${2:?}; shift 2 ;;
    --crit) crit=${2:?}; shift 2 ;;
    --timeout) timeout=${2:?}; shift 2 ;;
    --file) files="$files ${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) hosts="$hosts $1"; shift ;;
  esac
done
[ -z "$files$hosts" ] && usage
command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 2; }

rc=0
report() { # $1 = target, stdin = PEM
  local pem enddate subject
  pem=$(cat)
  enddate=$(printf '%s\n' "$pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
  subject=$(printf '%s\n' "$pem" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//')
  if [ -z "$enddate" ]; then echo "ERROR - - $1 could-not-read-certificate"; [ $rc -lt 2 ] && rc=2; return; fi
  python3 - "$enddate" "$warn" "$crit" "$1" "$subject" <<'PY' || { [ $rc -lt 1 ] && rc=1; }
import sys, datetime as dt
end = dt.datetime.strptime(sys.argv[1].replace('  ', ' '), '%b %d %H:%M:%S %Y %Z').replace(tzinfo=dt.timezone.utc)
days = (end - dt.datetime.now(dt.timezone.utc)).total_seconds() / 86400
warn, crit = float(sys.argv[2]), float(sys.argv[3])
st = 'EXPIRED' if days < 0 else 'CRIT' if days < crit else 'WARN' if days < warn else 'OK'
print(f"{st} {int(days)} {end:%Y-%m-%dT%H:%M:%SZ} {sys.argv[4]} {sys.argv[5]}")
sys.exit(0 if st == 'OK' else 1)
PY
}
for f in $files; do
  [ -r "$f" ] || { echo "ERROR - - $f not-readable"; rc=2; continue; }
  report "$f" < "$f"
done
for h in $hosts; do
  host=${h%%:*}; port=443; case "$h" in *:*) port=${h##*:} ;; esac
  # -servername sends SNI so shared front ends return the right certificate.
  pem=$(python3 -c 'import subprocess,sys; r=subprocess.run(sys.argv[1:],stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=float('"$timeout"')); print(r.stdout)' \
        openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null) || pem=""
  printf '%s\n' "$pem" | grep -q 'BEGIN CERTIFICATE' || { echo "ERROR - - $h connect-failed"; rc=2; continue; }
  printf '%s\n' "$pem" | report "$h"
done
exit $rc

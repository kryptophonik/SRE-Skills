#!/usr/bin/env bash
# Read-only TLS certificate expiry check. Prints one line per certificate:
#   STATUS  DAYS_LEFT  NOT_AFTER(UTC)  TARGET  SUBJECT
# STATUS is EXPIRED, CRIT (< --crit days), WARN (< --warn days) or OK.
# Targets: host[:port], [ipv6]:port (connects with SNI for names; default port 443),
# or --file cert.pem [cert.pem...] (every argument after --file up to the next option is a
# file, so list hosts before --file; --file may repeat). By default only the leaf (or the first certificate in a file) is
# checked. --chain checks every certificate the server sends (or every one in the file);
# extra certificates print as TARGET#2, TARGET#3 and so on.
# Exit 0 when all OK, 1 when any WARN/CRIT/EXPIRED, 2 on usage or connection errors.
# Needs openssl and python3. Works on macOS /bin/bash 3.2. Sends no data beyond a TLS handshake.
set -uo pipefail
warn=30; crit=7; files=""; hosts=""; timeout=10; chain=0
usage() { echo "usage: $0 [--warn DAYS] [--crit DAYS] [--timeout SEC] [--chain] [host[:port]|[ipv6]:port...] [--file cert.pem [cert.pem...]]" >&2; exit 2; }
num() { case "$2" in ''|*[!0-9]*) echo "$1 needs a whole number, got '$2'" >&2; usage ;; esac; }
while [ $# -gt 0 ]; do
  case "$1" in
    --warn|--crit|--timeout|--file) [ $# -ge 2 ] || usage ;;
  esac
  case "$1" in
    --warn) num "$1" "$2"; warn=$2; shift 2 ;;
    --crit) num "$1" "$2"; crit=$2; shift 2 ;;
    --timeout) num "$1" "$2"; timeout=$2; shift 2 ;;
    --file) shift
      while [ $# -gt 0 ]; do case "$1" in -*) break ;; *) files="$files $1"; shift ;; esac; done ;;
    --chain) chain=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) hosts="$hosts $1"; shift ;;
  esac
done
[ -z "$files$hosts" ] && usage
command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 2; }

rc=0
# The PEM text arrives on stdin, so the Python program is passed with -c.
REPORT_PY=''
IFS= read -r -d '' REPORT_PY <<'PY' || true
import sys, re, subprocess, datetime as dt
warn, crit, target, chain = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4] == '1'
pems = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', sys.stdin.read(), re.S)
if not pems:
    print(f"ERROR - - {target} could-not-read-certificate"); sys.exit(2)
worst = 0
for i, pem in enumerate(pems if chain else pems[:1], 1):
    out = subprocess.run(['openssl', 'x509', '-noout', '-enddate', '-subject'], input=pem,
                         capture_output=True, text=True).stdout
    end_s = re.search(r'^notAfter=(.*)$', out, re.M); subj = re.search(r'^subject=\s*(.*)$', out, re.M)
    name = target if i == 1 else f"{target}#{i}"
    if not end_s:
        print(f"ERROR - - {name} could-not-read-certificate"); worst = 2; continue
    end = dt.datetime.strptime(end_s[1].replace('  ', ' '), '%b %d %H:%M:%S %Y %Z').replace(tzinfo=dt.timezone.utc)
    days = (end - dt.datetime.now(dt.timezone.utc)).total_seconds() / 86400
    st = 'EXPIRED' if days < 0 else 'CRIT' if days < crit else 'WARN' if days < warn else 'OK'
    print(f"{st} {int(days)} {end:%Y-%m-%dT%H:%M:%SZ} {name} {subj[1] if subj else '-'}")
    if st != 'OK': worst = max(worst, 1)
sys.exit(worst)
PY
report() { # $1 = target, stdin = text holding one or more PEM certificates
  python3 -c "$REPORT_PY" "$warn" "$crit" "$1" "$chain"
  r=$?; [ $r -gt $rc ] && rc=$r
}
for f in $files; do
  [ -r "$f" ] || { echo "ERROR - - $f not-readable"; rc=2; continue; }
  report "$f" < "$f"
done
for h in $hosts; do
  port=443
  case "$h" in
    \[*\]:*) host=${h#\[}; host=${host%%\]*}; port=${h##*\]:} ;;
    \[*\]) host=${h#\[}; host=${host%\]} ;;
    *:*:*) echo "ERROR - - $h ipv6-needs-brackets-[addr]:port"; rc=2; continue ;;
    *:*) host=${h%%:*}; port=${h##*:} ;;
    *) host=$h ;;
  esac
  case "$port" in ''|*[!0-9]*) echo "ERROR - - $h bad-port"; rc=2; continue ;; esac
  case "$host" in *:*) addr="[$host]:$port"; sni="" ;; *) addr="$host:$port"; sni="$host" ;; esac
  # -servername sends SNI so shared front ends return the right certificate (not for IP literals).
  # The timeout is passed as an argument, never pasted into code.
  set -- openssl s_client -connect "$addr" -showcerts
  [ -n "$sni" ] && set -- "$@" -servername "$sni"
  pem=$(python3 -c 'import subprocess,sys
try: print(subprocess.run(sys.argv[2:],stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=int(sys.argv[1])).stdout)
except subprocess.TimeoutExpired: pass' "$timeout" "$@" 2>/dev/null) || pem=""
  printf '%s\n' "$pem" | grep -q 'BEGIN CERTIFICATE' || { echo "ERROR - - $h connect-failed"; rc=2; continue; }
  # Not a pipeline: report must run in this shell so its exit code reaches rc.
  report "$h" <<<"$pem"
done
exit $rc

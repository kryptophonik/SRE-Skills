#!/usr/bin/env bash
# Read-only check for the October 2026 eMudhra intermediate CA private-key compromise
# (Mozilla bug 2083449). Fetches the full certificate chain (never just the leaf, since
# the compromise is at the intermediate, not the leaf) and compares every certificate's
# serial number and SHA-256 fingerprint against the bundled compromised-intermediates.json.
# Prints one line per certificate in the chain:
#   STATUS  TARGET  POSITION  SUBJECT  SHA256
# STATUS is COMPROMISED, OK or ERROR.
# Targets: host[:port], [ipv6]:port (SNI for names; default port 443),
# or --file cert.pem [cert.pem...] (every argument after --file up to the next option is a
# file, so list hosts before --file; --file may repeat; a bundle with multiple PEM blocks
# is read as a chain). --data overrides the compromised-intermediates.json path (for tests).
# Exit 0 when every certificate is OK, 1 when any COMPROMISED, 2 on usage or connection
# errors (an error outranks a clean result but not a COMPROMISED one you already found,
# matching cert-expiry.sh's "worst result wins" convention: the exit code is the max seen,
# so a COMPROMISED(1) and an ERROR(2) together still exit 2 -- read the per-line STATUS,
# never just the exit code, when checking more than one target).
# Needs openssl and python3. Works on macOS /bin/bash 3.2. Sends no data beyond a TLS handshake.
set -uo pipefail
files=""; hosts=""; timeout=10
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
data="$SCRIPT_DIR/../references/compromised-intermediates.json"
usage() { echo "usage: $0 [--timeout SEC] [--data compromised-intermediates.json] [host[:port]|[ipv6]:port...] [--file cert.pem [cert.pem...]]" >&2; exit 2; }
num() { case "$2" in ''|*[!0-9]*) echo "$1 needs a whole number, got '$2'" >&2; usage ;; esac; }
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout|--file|--data) [ $# -ge 2 ] || usage ;;
  esac
  case "$1" in
    --timeout) num "$1" "$2"; timeout=$2; shift 2 ;;
    --data) data=$2; shift 2 ;;
    --file) shift
      while [ $# -gt 0 ]; do case "$1" in -*) break ;; *) files="$files $1"; shift ;; esac; done ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) hosts="$hosts $1"; shift ;;
  esac
done
[ -z "$files$hosts" ] && usage
command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 2; }
[ -r "$data" ] || { echo "compromised-intermediates.json not readable: $data" >&2; exit 2; }

rc=0
REPORT_PY=''
IFS= read -r -d '' REPORT_PY <<'PY' || true
import sys, re, subprocess, json
data_path, target = sys.argv[1], sys.argv[2]
with open(data_path) as f:
    data = json.load(f)
bad_serials = {e["serial_hex"].lower().replace(":", "") for e in data["intermediates"]}
bad_sha256 = {e["sha256"].upper().replace(":", "") for e in data["intermediates"]}
pems = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', sys.stdin.read(), re.S)
if not pems:
    print(f"ERROR {target} - - could-not-read-certificate"); sys.exit(2)
worst = 0
for i, pem in enumerate(pems, 1):
    out = subprocess.run(['openssl', 'x509', '-noout', '-subject', '-serial', '-fingerprint', '-sha256'],
                         input=pem, capture_output=True, text=True).stdout
    subj = re.search(r'^subject=\s*(.*)$', out, re.M)
    serial = re.search(r'^serial=([0-9A-Fa-f]+)$', out, re.M)
    fp = re.search(r'^sha256 Fingerprint=([0-9A-Fa-f:]+)$', out, re.M | re.I)
    pos = f"{i}" if i > 1 else "1(leaf)"
    if not serial or not fp:
        print(f"ERROR {target} {pos} - could-not-parse-certificate"); worst = max(worst, 2); continue
    serial_hex = serial[1].lower()
    sha256_hex = fp[1].replace(":", "").upper()
    hit = serial_hex in bad_serials or sha256_hex in bad_sha256
    st = "COMPROMISED" if hit else "OK"
    print(f"{st} {target} {pos} {subj[1] if subj else '-'} {sha256_hex}")
    if hit: worst = max(worst, 1)
sys.exit(worst)
PY
report() { # $1 = target, stdin = text holding one or more PEM certificates
  python3 -c "$REPORT_PY" "$data" "$1"
  r=$?; [ $r -gt $rc ] && rc=$r
}
for f in $files; do
  [ -r "$f" ] || { echo "ERROR $f - - not-readable"; rc=2; continue; }
  report "$f" < "$f"
done
for h in $hosts; do
  port=443
  case "$h" in
    \[*\]:*) host=${h#\[}; host=${host%%\]*}; port=${h##*\]:} ;;
    \[*\]) host=${h#\[}; host=${host%\]} ;;
    *:*:*) echo "ERROR $h - - ipv6-needs-brackets-[addr]:port"; rc=2; continue ;;
    *:*) host=${h%%:*}; port=${h##*:} ;;
    *) host=$h ;;
  esac
  case "$port" in ''|*[!0-9]*) echo "ERROR $h - - bad-port"; rc=2; continue ;; esac
  case "$host" in *:*) addr="[$host]:$port"; sni="" ;; *) addr="$host:$port"; sni="$host" ;; esac
  # -servername sends SNI so shared front ends return the right certificate (not for IP literals).
  # The timeout is passed as an argument, never pasted into code.
  set -- openssl s_client -connect "$addr" -showcerts
  [ -n "$sni" ] && set -- "$@" -servername "$sni"
  pem=$(python3 -c 'import subprocess,sys
try: print(subprocess.run(sys.argv[2:],stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=int(sys.argv[1])).stdout)
except subprocess.TimeoutExpired: pass' "$timeout" "$@" 2>/dev/null) || pem=""
  printf '%s\n' "$pem" | grep -q 'BEGIN CERTIFICATE' || { echo "ERROR $h - - connect-failed"; rc=2; continue; }
  # Not a pipeline: report must run in this shell so its exit code reaches rc.
  report "$h" <<<"$pem"
done
exit $rc

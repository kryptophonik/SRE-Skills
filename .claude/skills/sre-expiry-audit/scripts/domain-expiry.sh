#!/usr/bin/env bash
# Read-only domain registration expiry via RDAP (the JSON successor to WHOIS).
# Prints: STATUS DAYS_LEFT EXPIRES(UTC) DOMAIN REGISTRAR
# Uses https://rdap.org (redirects to the registry's RDAP server from the IANA bootstrap).
# Set RDAP_BASE to query a registry directly. Lookups that fail print NO-RDAP with the HTTP
# status: http-404 (not registered, or no RDAP for this TLD), http-429 (rate limited), http-000 (no answer).
# Exit 0 all OK, 1 any WARN/CRIT/EXPIRED, 2 on errors. Needs curl and python3; bash 3.2 OK.
set -uo pipefail
warn=45; crit=14; timeout=20; base=${RDAP_BASE:-https://rdap.org}; domains=""
usage() { echo "usage: $0 [--warn DAYS] [--crit DAYS] [--timeout SEC] domain..." >&2; exit 2; }
num() { case "$2" in ''|*[!0-9]*) echo "$1 needs a whole number, got '$2'" >&2; usage ;; esac; }
while [ $# -gt 0 ]; do
  case "$1" in
    --warn|--crit|--timeout) [ $# -ge 2 ] || usage; num "$1" "$2" ;;
  esac
  case "$1" in
    --warn) warn=$2; shift 2 ;;
    --crit) crit=$2; shift 2 ;;
    --timeout) timeout=$2; shift 2 ;;
    -h|--help|-*) usage ;;
    *) domains="$domains $1"; shift ;;
  esac
done
[ -z "$domains" ] && usage
command -v curl >/dev/null || { echo "curl not found" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 2; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
rc=0
for dom in $domains; do
  code=$(curl -sSL --max-time "$timeout" -o "$tmp" -w '%{http_code}' -H 'Accept: application/rdap+json' "$base/domain/$dom" 2>/dev/null) || code=${code:-000}
  [ "$code" = 200 ] || { echo "NO-RDAP - - $dom http-${code:-000}"; [ $rc -lt 2 ] && rc=2; continue; }
  python3 -c '
import json, sys, datetime as dt
d = json.load(open(sys.argv[4])); dom, warn, crit = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
exp = next((e["eventDate"] for e in d.get("events", []) if e.get("eventAction") == "expiration"), None)
reg = next((v[3] for e in d.get("entities", []) if "registrar" in e.get("roles", [])
            for v in (e.get("vcardArray") or [None, []])[1] if v[0] == "fn"), "-")
if not exp:
    print(f"UNKNOWN - - {dom} no-expiration-event"); sys.exit(2)
end = dt.datetime.fromisoformat(exp.replace("Z", "+00:00"))
days = (end - dt.datetime.now(dt.timezone.utc)).total_seconds() / 86400
st = "EXPIRED" if days < 0 else "CRIT" if days < crit else "WARN" if days < warn else "OK"
print(f"{st} {int(days)} {end:%Y-%m-%dT%H:%M:%SZ} {dom} {str(reg).replace(chr(32), chr(95))}")
sys.exit(0 if st == "OK" else 1)' "$dom" "$warn" "$crit" "$tmp"
  r=$?; [ $r -gt $rc ] && rc=$r
done
exit $rc

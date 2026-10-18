#!/usr/bin/env bash
# Read-only domain registration expiry via RDAP (the JSON successor to WHOIS).
# Prints: STATUS DAYS_LEFT EXPIRES(UTC) DOMAIN REGISTRAR
# Uses https://rdap.org (redirects to the registry's RDAP server from the IANA bootstrap).
# Set RDAP_BASE to query a registry directly. Some ccTLDs have no RDAP: those print NO-RDAP.
# Exit 0 all OK, 1 any WARN/CRIT/EXPIRED, 2 on errors. Needs curl and python3; bash 3.2 OK.
set -uo pipefail
warn=45; crit=14; base=${RDAP_BASE:-https://rdap.org}; domains=""
usage() { echo "usage: $0 [--warn DAYS] [--crit DAYS] domain..." >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --warn) warn=${2:?}; shift 2 ;;
    --crit) crit=${2:?}; shift 2 ;;
    -h|--help|-*) usage ;;
    *) domains="$domains $1"; shift ;;
  esac
done
[ -z "$domains" ] && usage
rc=0
for dom in $domains; do
  body=$(curl -sSfL --max-time 20 -H 'Accept: application/rdap+json' "$base/domain/$dom" 2>/dev/null) || {
    echo "NO-RDAP - - $dom lookup-failed-or-unsupported"; [ $rc -lt 2 ] && rc=2; continue; }
  printf '%s' "$body" | python3 -c '
import json, sys, datetime as dt
d = json.load(sys.stdin); dom, warn, crit = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
exp = next((e["eventDate"] for e in d.get("events", []) if e.get("eventAction") == "expiration"), None)
reg = next((v[3] for e in d.get("entities", []) if "registrar" in e.get("roles", [])
            for v in (e.get("vcardArray") or [None, []])[1] if v[0] == "fn"), "-")
if not exp:
    print(f"UNKNOWN - - {dom} no-expiration-event"); sys.exit(2)
end = dt.datetime.fromisoformat(exp.replace("Z", "+00:00"))
days = (end - dt.datetime.now(dt.timezone.utc)).total_seconds() / 86400
st = "EXPIRED" if days < 0 else "CRIT" if days < crit else "WARN" if days < warn else "OK"
print(f"{st} {int(days)} {end:%Y-%m-%dT%H:%M:%SZ} {dom} {str(reg).replace(chr(32), chr(95))}")
sys.exit(0 if st == "OK" else 1)' "$dom" "$warn" "$crit"
  r=$?; [ $r -gt $rc ] && rc=$r
done
exit $rc

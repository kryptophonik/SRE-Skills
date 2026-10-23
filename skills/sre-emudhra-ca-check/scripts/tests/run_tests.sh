#!/usr/bin/env bash
# Offline tests: a self-signed cert from openssl, checked against a synthetic data file
# built from that cert's own serial/fingerprint (COMPROMISED path) and against the real
# bundled compromised-intermediates.json (OK path, since the test cert isn't in it). No network.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); s="$here/.."; tmp=$(mktemp -d); pass=0; fail=0
trap 'rm -rf "$tmp"' EXIT
ok() { echo "PASS $1"; pass=$((pass+1)); }; ko() { echo "FAIL $1"; fail=$((fail+1)); }

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/leaf.key" -out "$tmp/leaf.pem" -days 200 -subj "/CN=leaf.example.invalid" >/dev/null 2>&1
out=$(openssl x509 -noout -serial -fingerprint -sha256 -in "$tmp/leaf.pem")
serial=$(echo "$out" | grep '^serial=' | cut -d= -f2 | tr 'A-Z' 'a-z')
fp=$(echo "$out" | grep '^SHA256 Fingerprint=' | cut -d= -f2 | tr -d ':')

python3 -c "
import json
json.dump({'incident': 'test', 'intermediates': [
  {'subject': 'CN=leaf.example.invalid', 'usage': 'tls', 'issuing_root': 'test',
   'serial_hex': '$serial', 'sha256': '$fp', 'status': 'revoked', 'reason': 'ca_compromise'}
]}, open('$tmp/match.json', 'w'))
"
python3 -c "
import json
json.dump({'incident': 'test', 'intermediates': []}, open('$tmp/empty.json', 'w'))
"

o=$(bash "$s/emudhra-ca-check.sh" --data "$tmp/match.json" --file "$tmp/leaf.pem"); r=$?
case "$o" in COMPROMISED*) [ $r = 1 ] && ok "matching serial/fingerprint flags COMPROMISED" || ko "COMPROMISED exit $r";; *) ko "COMPROMISED: $o";; esac

o=$(bash "$s/emudhra-ca-check.sh" --data "$tmp/empty.json" --file "$tmp/leaf.pem"); r=$?
case "$o" in OK*) [ $r = 0 ] && ok "no match reports OK" || ko "OK exit $r";; *) ko "OK: $o";; esac

o=$(bash "$s/emudhra-ca-check.sh" --file "$tmp/leaf.pem"); r=$?
case "$o" in OK*) ok "default bundled data file loads and this test cert isn't in it";; *) ko "bundled data: $o";; esac

bash "$s/emudhra-ca-check.sh" >/dev/null 2>&1; [ $? = 2 ] && ok "no args is a usage error" || ko "usage exit"

o=$(bash "$s/emudhra-ca-check.sh" --data "$tmp/empty.json" --file "$tmp/nope.pem"); case "$o" in ERROR*) ok "missing file reported";; *) ko "missing file: $o";; esac

o=$(bash "$s/emudhra-ca-check.sh" --data "$tmp/nope.json" --file "$tmp/leaf.pem" 2>&1); r=$?
[ $r = 2 ] && ok "missing data file is a usage error" || ko "missing data file exit $r"

cat "$tmp/leaf.pem" "$tmp/leaf.pem" > "$tmp/bundle.pem"
o=$(bash "$s/emudhra-ca-check.sh" --data "$tmp/match.json" --file "$tmp/bundle.pem"); r=$?
case "$o" in COMPROMISED*1\(leaf\)*COMPROMISED*2*) [ $r = 1 ] && ok "a bundle checks every certificate, not just the leaf" || ko "bundle exit $r";; *) ko "bundle: $o";; esac

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]

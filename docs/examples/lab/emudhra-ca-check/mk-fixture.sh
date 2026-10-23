#!/usr/bin/env bash
# Lab fixture for example 11: two self-signed leaf certs, served on loopback.
#   payments-api.pem  -- stands in for a cert issued by a compromised eMudhra intermediate
#   docs-site.pem     -- an ordinary cert, not affected by anything
# This lab never touches a real eMudhra certificate: it writes a synthetic data file
# (compromised-fixture.json) containing payments-api's OWN serial and SHA-256 fingerprint,
# labeled as if it came from the revoked "EM DV TLS CA - G3B" intermediate, so the real
# checker script has something genuine to match against without needing the real CA's
# private key or a live compromised cert anywhere.
set -euo pipefail
cd "$(dirname "$0")"
here=$(pwd)
openssl req -x509 -newkey rsa:2048 -nodes -keyout payments-api.key -out payments-api.pem -days 365 -subj "/CN=payments-api.shop.lab" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout docs-site.key -out docs-site.pem -days 365 -subj "/CN=docs-site.shop.lab" >/dev/null 2>&1
out=$(openssl x509 -noout -serial -fingerprint -sha256 -in payments-api.pem)
serial=$(echo "$out" | grep '^serial=' | cut -d= -f2 | tr 'A-Z' 'a-z')
fp=$(echo "$out" | grep -i '^sha256 Fingerprint=' | cut -d= -f2 | tr -d ':')
python3 -c "
import json
json.dump({
  'incident': 'lab fixture, not the real eMudhra incident data',
  'intermediates': [
    {'subject': 'CN=EM DV TLS CA - G3B,O=eMudhra BV,C=NL', 'usage': 'tls',
     'issuing_root': 'emSign Root TLS CA - G3', 'serial_hex': '$serial', 'sha256': '$fp',
     'status': 'revoked', 'reason': 'ca_compromise'}
  ]
}, open('$here/compromised-fixture.json', 'w'), indent=2)
"
echo "wrote payments-api.pem, docs-site.pem, compromised-fixture.json in $here"

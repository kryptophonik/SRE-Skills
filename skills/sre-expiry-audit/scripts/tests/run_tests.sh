#!/usr/bin/env bash
# Offline tests: self-signed certs from openssl and a local RDAP mock. No network.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); s="$here/.."; tmp=$(mktemp -d); pass=0; fail=0
port=${MOCK_PORT:-18090}
trap 'kill $pid 2>/dev/null; rm -rf "$tmp"' EXIT
ok() { echo "PASS $1"; pass=$((pass+1)); }; ko() { echo "FAIL $1"; fail=$((fail+1)); }
mk() { openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/$1.key" -out "$tmp/$1.pem" -days "$2" -subj "/CN=$1.example.invalid" >/dev/null 2>&1; }
mk long 200; mk soon 20; mk crit 3
o=$(bash "$s/cert-expiry.sh" --file "$tmp/long.pem"); r=$?
case "$o" in OK\ 19[89]*|OK\ 200*) [ $r = 0 ] && ok "cert OK at 200 days" || ko "cert OK exit $r";; *) ko "cert OK: $o";; esac
o=$(bash "$s/cert-expiry.sh" --file "$tmp/soon.pem"); r=$?
case "$o" in WARN*) [ $r = 1 ] && ok "cert WARN under 30 days" || ko "cert WARN exit $r";; *) ko "cert WARN: $o";; esac
o=$(bash "$s/cert-expiry.sh" --file "$tmp/crit.pem"); case "$o" in CRIT*) ok "cert CRIT under 7 days";; *) ko "cert CRIT: $o";; esac
o=$(bash "$s/cert-expiry.sh" --warn 10 --file "$tmp/soon.pem"); case "$o" in OK*) ok "--warn threshold respected";; *) ko "--warn: $o";; esac
bash "$s/cert-expiry.sh" >/dev/null 2>&1; [ $? = 2 ] && ok "no args is a usage error" || ko "usage exit"
o=$(bash "$s/cert-expiry.sh" --file "$tmp/nope.pem"); case "$o" in ERROR*) ok "missing file reported";; *) ko "missing file: $o";; esac

python3 - "$port" <<'PY' & pid=$!
import http.server, json, sys, datetime as dt
soon = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=10)).strftime('%Y-%m-%dT%H:%M:%SZ')
far = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=400)).strftime('%Y-%m-%dT%H:%M:%SZ')
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        d = self.path.rsplit('/', 1)[-1]
        if d == 'missing.invalid': self.send_response(404); self.end_headers(); return
        exp = soon if d.startswith('soon') else far
        body = {"events": [{"eventAction": "expiration", "eventDate": exp}],
                "entities": [{"roles": ["registrar"], "vcardArray": ["vcard", [["fn", {}, "text", "Example Registrar"]]]}]}
        self.send_response(200); self.send_header('Content-Type', 'application/rdap+json'); self.end_headers()
        self.wfile.write(json.dumps(body).encode())
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
for _ in $(seq 50); do curl -s "http://127.0.0.1:$port/domain/x" >/dev/null 2>&1 && break; sleep 0.1; done
export RDAP_BASE="http://127.0.0.1:$port"
o=$(bash "$s/domain-expiry.sh" far.example); r=$?
case "$o" in OK*Example_Registrar) [ $r = 0 ] && ok "domain OK with registrar" || ko "domain OK exit $r";; *) ko "domain OK: $o";; esac
o=$(bash "$s/domain-expiry.sh" soon.example); case "$o" in CRIT*) ok "domain CRIT under 14 days";; *) ko "domain CRIT: $o";; esac
o=$(bash "$s/domain-expiry.sh" missing.invalid); r=$?
case "$o" in NO-RDAP*) [ $r = 2 ] && ok "no RDAP reported, exit 2" || ko "no RDAP exit $r";; *) ko "no RDAP: $o";; esac
echo "$pass passed, $fail failed"; [ $fail = 0 ]

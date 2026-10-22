#!/usr/bin/env bash
# Offline tests: self-signed certs from openssl and a local RDAP mock. No network.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); s="$here/.."; tmp=$(mktemp -d); pass=0; fail=0
freeport() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
port=${MOCK_PORT:-$(freeport)}; pid=; spid=
trap 'kill $pid $spid 2>/dev/null; rm -rf "$tmp"' EXIT
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
o=$(bash "$s/cert-expiry.sh" --file "$tmp/long.pem" "$tmp/crit.pem"); r=$?
case "$o" in OK*long.pem*CRIT*crit.pem*) [ $r = 1 ] && ok "--file takes several files" || ko "multi-file exit $r";; *) ko "multi-file: $o";; esac
o=$(bash "$s/cert-expiry.sh" --file "$tmp/long.pem" --file "$tmp/soon.pem"); case "$o" in OK*WARN*) ok "--file repeats";; *) ko "--file repeat: $o";; esac

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
# Input hardening: a crafted --timeout must be rejected, never executed.
o=$(bash "$s/cert-expiry.sh" --timeout "1);open('$tmp/pwned','w');(1" localhost:1 2>&1); r=$?
[ $r = 2 ] && [ ! -e "$tmp/pwned" ] && ok "non-numeric --timeout rejected, not run" || ko "timeout injection: $r $o"
bash "$s/cert-expiry.sh" --warn >/dev/null 2>&1; [ $? = 2 ] && ok "flag without value is a usage error" || ko "flag without value"
bash "$s/domain-expiry.sh" --timeout x a.example >/dev/null 2>&1; [ $? = 2 ] && ok "domain --timeout validated" || ko "domain --timeout"
o=$(bash "$s/cert-expiry.sh" ::1:443); case "$o" in *ipv6-needs-brackets*) ok "bare IPv6 explained";; *) ko "bare ipv6: $o";; esac

# Chain: an expiring intermediate is caught with --chain, ignored without it.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/ca.key" -out "$tmp/ca.pem" -days 3 -subj "/CN=int.example.invalid" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$tmp/leaf.key" -out "$tmp/leaf.csr" -subj "/CN=localhost" >/dev/null 2>&1
openssl x509 -req -in "$tmp/leaf.csr" -CA "$tmp/ca.pem" -CAkey "$tmp/ca.key" -CAcreateserial -days 200 -out "$tmp/leaf.pem" >/dev/null 2>&1
cat "$tmp/leaf.pem" "$tmp/ca.pem" > "$tmp/bundle.pem"
o=$(bash "$s/cert-expiry.sh" --file "$tmp/bundle.pem"); r=$?; case "$o" in OK*) [ $r = 0 ] && ok "leaf-only by default" || ko "leaf exit $r";; *) ko "leaf only: $o";; esac
o=$(bash "$s/cert-expiry.sh" --chain --file "$tmp/bundle.pem"); r=$?
case "$o" in *"CRIT "*"bundle.pem#2"*) [ $r = 1 ] && ok "--chain finds expiring intermediate" || ko "chain exit $r";; *) ko "chain: $o";; esac

# Live handshake against a local s_server (SNI, host:port parsing, --chain over the wire).
sport=$(freeport)
openssl s_server -quiet -accept "127.0.0.1:$sport" -cert "$tmp/leaf.pem" -key "$tmp/leaf.key" -cert_chain "$tmp/ca.pem" -www >/dev/null 2>&1 & spid=$!
for _ in $(seq 50); do (exec 3<>"/dev/tcp/127.0.0.1/$sport") 2>/dev/null && break; sleep 0.1; done
if (exec 3<>"/dev/tcp/127.0.0.1/$sport") 2>/dev/null; then
  o=$(bash "$s/cert-expiry.sh" --timeout 5 "127.0.0.1:$sport"); r=$?; case "$o" in OK*"CN = localhost"*|OK*"CN=localhost"*) ok "host:port handshake";; *) ko "handshake: $r $o";; esac
  o=$(bash "$s/cert-expiry.sh" --timeout 5 --chain "127.0.0.1:$sport"); r=$?; case "$o" in *CRIT*"#2"*) ok "--chain over the wire";; *) ko "chain wire: $o";; esac
  # Regression: endpoint results used to run in a pipeline subshell, so CRIT/EXPIRED exited 0.
  [ $r = 1 ] && ok "endpoint CRIT exits 1" || ko "endpoint CRIT exit $r (want 1)"
  bash "$s/cert-expiry.sh" --timeout 5 "127.0.0.1:$sport" >/dev/null; r=$?; [ $r = 0 ] && ok "endpoint OK exits 0" || ko "endpoint OK exit $r"
  o=$(bash "$s/cert-expiry.sh" --timeout 5 "127.0.0.1:$sport" --file "$tmp/crit.pem"); r=$?
  [ $r = 1 ] && ok "host plus file: worst exit wins" || ko "host plus file exit $r: $o"
else echo "SKIP live handshake: openssl s_server did not start (LibreSSL lacks -cert_chain)"; fi
o=$(bash "$s/domain-expiry.sh" missing.invalid); case "$o" in *http-404*) ok "RDAP status in reason";; *) ko "rdap status: $o";; esac
echo "$pass passed, $fail failed"; [ $fail = 0 ]

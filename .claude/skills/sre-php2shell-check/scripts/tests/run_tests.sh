#!/usr/bin/env bash
# Offline tests: synthetic `php -v` / X-Powered-By text, plus a local HTTP mock for --url. No network.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); s="$here/.."; tmp=$(mktemp -d); pass=0; fail=0
freeport() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
port=$(freeport); pid=
trap 'kill $pid 2>/dev/null; rm -rf "$tmp"' EXIT
ok() { echo "PASS $1"; pass=$((pass+1)); }; ko() { echo "FAIL $1"; fail=$((fail+1)); }

printf 'PHP 8.3.6 (cli) (built: Jan  1 2026 00:00:00) (NTS)\n' > "$tmp/vuln.txt"
printf 'PHP 8.3.36 (cli) (built: Oct 21 2026 00:00:00) (NTS)\n' > "$tmp/patched.txt"
printf 'PHP 8.1.31 (cli) (built: Jan  1 2026 00:00:00) (NTS)\n' > "$tmp/eol-backport.txt"
printf 'PHP 7.2.34 (cli) (built: Jan  1 2026 00:00:00) (NTS)\n' > "$tmp/very-eol.txt"
printf 'PHP 8.6.0 (cli) (built: Jan  1 2026 00:00:00) (NTS)\n' > "$tmp/future.txt"
printf 'no version here\n' > "$tmp/garbage.txt"

o=$(bash "$s/php2shell-check.sh" --text "$tmp/vuln.txt"); r=$?
case "$o" in VULNERABLE*8.3.6*) [ $r = 1 ] && ok "below fixed build is VULNERABLE" || ko "VULNERABLE exit $r";; *) ko "VULNERABLE: $o";; esac

o=$(bash "$s/php2shell-check.sh" --text "$tmp/patched.txt"); r=$?
case "$o" in PATCHED*8.3.36*) [ $r = 0 ] && ok "fixed build is PATCHED" || ko "PATCHED exit $r";; *) ko "PATCHED: $o";; esac

o=$(bash "$s/php2shell-check.sh" --text "$tmp/eol-backport.txt"); r=$?
case "$o" in CHECK-DISTRO-PACKAGE*8.1.31*) [ $r = 1 ] && ok "EOL backport-only branch needs a manual check" || ko "CHECK exit $r";; *) ko "CHECK: $o";; esac

o=$(bash "$s/php2shell-check.sh" --text "$tmp/very-eol.txt"); r=$?
case "$o" in VULNERABLE*7.2.34*) [ $r = 1 ] && ok "pre-7.4 branch with no vendor fix is VULNERABLE" || ko "very-eol exit $r";; *) ko "very-eol: $o";; esac

o=$(bash "$s/php2shell-check.sh" --text "$tmp/future.txt"); r=$?
case "$o" in PATCHED*8.6.0*) [ $r = 0 ] && ok "a newer major branch is treated as PATCHED" || ko "future exit $r";; *) ko "future: $o";; esac

o=$(bash "$s/php2shell-check.sh" --text "$tmp/garbage.txt"); r=$?
case "$o" in UNKNOWN*) [ $r = 1 ] && ok "no version found is UNKNOWN, not clean" || ko "UNKNOWN exit $r";; *) ko "UNKNOWN: $o";; esac

o=$(bash "$s/php2shell-check.sh" --text "$tmp/nope.txt"); case "$o" in ERROR*) ok "missing text file reported";; *) ko "missing file: $o";; esac

bash "$s/php2shell-check.sh" >/dev/null 2>&1; [ $? = 2 ] && ok "no args is a usage error" || ko "usage exit"

o=$(bash "$s/php2shell-check.sh" --text "$tmp/vuln.txt" --text "$tmp/patched.txt"); r=$?
case "$o" in VULNERABLE*$'\n'*PATCHED*) [ $r = 1 ] && ok "multiple --text sources, worst result wins" || ko "multi-text exit $r";; *) ko "multi-text: $o";; esac

python3 - "$port" <<'PY' & pid=$!
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_HEAD(self):
        self.send_response(200)
        if '/vuln' in self.path: self.send_header('X-Powered-By', 'PHP/8.3.6')
        elif '/patched' in self.path: self.send_header('X-Powered-By', 'PHP/8.4.27')
        self.end_headers()
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
for _ in $(seq 50); do curl -s -I "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.1; done

o=$(bash "$s/php2shell-check.sh" --url "http://127.0.0.1:$port/vuln"); r=$?
case "$o" in VULNERABLE*8.3.6*) [ $r = 1 ] && ok "--url reads a vulnerable X-Powered-By header" || ko "url vuln exit $r";; *) ko "url vuln: $o";; esac

o=$(bash "$s/php2shell-check.sh" --url "http://127.0.0.1:$port/patched"); r=$?
case "$o" in PATCHED*8.4.27*) [ $r = 0 ] && ok "--url reads a patched X-Powered-By header" || ko "url patched exit $r";; *) ko "url patched: $o";; esac

o=$(bash "$s/php2shell-check.sh" --url "http://127.0.0.1:$port/nothing"); r=$?
case "$o" in UNKNOWN*) [ $r = 1 ] && ok "no X-Powered-By header is UNKNOWN, not clean" || ko "no-header exit $r";; *) ko "no-header: $o";; esac

o=$(bash "$s/php2shell-check.sh" --timeout 2 --url "http://127.0.0.1:1/x" 2>/dev/null); r=$?
case "$o" in ERROR*) [ $r = 2 ] && ok "unreachable URL is an ERROR" || ko "unreachable exit $r";; *) ko "unreachable: $o";; esac

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]

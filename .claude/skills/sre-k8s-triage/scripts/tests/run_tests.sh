#!/usr/bin/env bash
# Offline tests for k8s-preflight.sh and k8s-triage-snapshot.sh, using a stub kubectl.
# Contexts: "up" (reachable, read-only identity), "down" (in kubeconfig, API unreachable),
# anything else is missing from kubeconfig. Bash 3.2 compatible.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat >"$T/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
ctx=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --context) ctx="$2"; shift 2 ;;
    -n|--as) shift 2 ;;
    --request-timeout=*) shift ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- "${args[@]}"
case "$1 ${2:-}" in
  "config get-contexts") [ "$3" = up ] || [ "$3" = down ]; exit ;;
  "config current-context") echo up; exit 0 ;;
esac
if [ "$ctx" = down ]; then
  echo "The connection to the server 127.0.0.1:1 was refused - did you specify the right host or port?" >&2; exit 1
fi
case "$1 ${2:-}" in
  "get --raw") echo '{"gitVersion":"v1.35.0"}' ;;
  "auth can-i") case "$3" in get|list) [ "$4" = secrets ] && { echo no; exit 1; }; echo yes ;; *) echo no; exit 1 ;; esac ;;
  "get pods") case "$*" in *jsonpath*) printf 'crashy-1\tRunning\tfalse,3 \n' ;; *) echo "NAME READY STATUS"; echo "crashy-1 0/1 Error" ;; esac ;;
  "get hpa"|"get pvc") echo "No resources found in demo namespace." >&2 ;;
  *) echo "stub: $*" ;;
esac
STUB
chmod +x "$T/bin/kubectl"
export PATH="$T/bin:$PATH" TMPDIR="$T"
pass=0 fail=0
t() { # name, want-rc, stdout-regex-must-not-match ("" to skip), cmd...
  local name="$1" want="$2" bad="$3"; shift 3
  local out rc; out="$("$@" 2>"$T/err")"; rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$bad" ] || ! printf '%s' "$out" | grep -Eq "$bad"; }; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL $name: rc=$rc want=$want"; printf '%s\n' "$out" "$(cat "$T/err")" | sed 's/^/    /'; fi
}
cd "$T" || exit 1
t "preflight usage"          2 "" bash "$S/k8s-preflight.sh" --context up
t "preflight missing ctx"    1 "" bash "$S/k8s-preflight.sh" --context nope -n demo
t "preflight unreachable"    3 "^OK" bash "$S/k8s-preflight.sh" --context down -n demo
grep -q "cannot reach the API server" "$T/err" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL preflight unreachable message"; }
t "preflight read-only ok"   0 "FAIL|ERROR" bash "$S/k8s-preflight.sh" --context up -n demo
t "snapshot usage"           2 "" bash "$S/k8s-triage-snapshot.sh" -n demo
t "snapshot missing ctx"     1 "" bash "$S/k8s-triage-snapshot.sh" --context nope -n demo
t "snapshot unreachable"     3 "" bash "$S/k8s-triage-snapshot.sh" --context down -n demo -o "$T/snap-down"
grep -q "^done" "$T/err" && { fail=$((fail+1)); echo "FAIL snapshot unreachable printed done"; } || pass=$((pass+1))
[ -e "$T/snap-down" ] && { fail=$((fail+1)); echo "FAIL snapshot unreachable wrote a dir"; } || pass=$((pass+1))
t "snapshot ok"              0 "" bash "$S/k8s-triage-snapshot.sh" --context up -n demo -o "$T/snap-up"
grep -q "1 unhealthy pods captured" "$T/err" && [ -s "$T/snap-up/01-pods.txt" ] && [ -e "$T/snap-up/pods/crashy-1.log" ] \
  && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL snapshot ok contents"; cat "$T/err"; }
ls "$T/snap-up"/*.err >/dev/null 2>&1 && { fail=$((fail+1)); echo "FAIL empty-list noise kept as .err:"; ls "$T/snap-up"/*.err; } || pass=$((pass+1))
echo "$pass/$((pass+fail)) passed"
[ "$fail" = 0 ]

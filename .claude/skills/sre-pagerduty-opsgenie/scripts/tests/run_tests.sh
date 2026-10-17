#!/usr/bin/env bash
# Offline tests against mock_server.py. No network, fake keys only.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); s="$here/.."
port=${MOCK_PORT:-18089}; log=$(mktemp); tmp=$(mktemp -d)
python3 "$here/mock_server.py" "$port" "$log" & pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$tmp" "$log"' EXIT
for _ in $(seq 50); do curl -s "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.1; done
export PD_BASE_URL="http://127.0.0.1:$port" OG_BASE_URL="http://127.0.0.1:$port/" \
       PD_API_KEY="FAKE-PD-KEY-123" OG_API_KEY="FAKE-OG-KEY-456"
OG_BASE_URL="http://127.0.0.1:$port"; export OG_BASE_URL
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }; ko() { echo "FAIL $1"; fail=$((fail+1)); }
t() { local name=$1; shift; if "$@"; then ok "$name"; else ko "$name"; fi; }

n=$("$s/pd_incidents.sh" --json 2>/dev/null | grep -c .); t "pd_incidents paginates 250 over 3 pages" [ "$n" = 250 ]
t "pd_incidents table" bash -c "'$s/pd_incidents.sh' 2>/dev/null | head -1 | grep -q '^NUM'"
n=$(MAX_PAGES=2 "$s/pd_incidents.sh" --json 2>/dev/null | grep -c .); t "MAX_PAGES caps pagination at 2 pages" [ "$n" = 200 ]
t "pd_incidents rejects bad status" bash -c "! '$s/pd_incidents.sh' --status bogus 2>/dev/null"
t "pd_oncall summary" bash -c "'$s/pd_oncall.sh' | grep -q 'Test User'"
a=$("$s/pd_audit_schedules.sh" --since 2026-10-16T00:00:00Z --until 2026-10-17T00:00:00Z)
t "audit: gap 08:00-10:00" bash -c "jq -e '.findings[]|select(.check==\"coverage_gap\" and .from==\"2026-10-16T08:00:00Z\")' <<<'$a' >/dev/null"
t "audit: single-person layer" bash -c "jq -e '.by_check.single_person_layer==1' <<<'$a' >/dev/null"
t "audit: policy without service" bash -c "jq -e '.by_check.policy_without_service==1' <<<'$a' >/dev/null"
t "audit: empty level" bash -c "jq -e '.by_check.empty_escalation_level==1' <<<'$a' >/dev/null"
t "audit: user no contact methods" bash -c "jq -e '.by_check.user_without_contact_methods==1' <<<'$a' >/dev/null"
t "audit: no false gap on OK schedule" bash -c "! jq -e '.findings[]|select(.schedule==\"Sched-OK\")' <<<'$a' >/dev/null"
n=$("$s/og_alerts.sh" --json 2>/dev/null | grep -c .); t "og_alerts follows paging.next (130)" [ "$n" = 130 ]
o=$("$s/og_oncall.sh"); t "og_oncall shows recipient" grep -q 'test@example.invalid' <<<"$o"
t "og_oncall flags empty schedule" grep -q 'NOBODY' <<<"$o"
t "og_export writes files" bash -c "'$s/og_export.sh' --out '$tmp/exp' 2>/dev/null && [ -f '$tmp/exp/users/OU1.contacts.json' ] && [ \"\$(stat -c %a '$tmp/exp')\" = 700 ]"
# safety
t "lib refuses POST" bash -c ". '$s/lib.sh'; ! (api_get POST pd http://127.0.0.1:$port/incidents) 2>/dev/null"
t "lib refuses non-https base" bash -c "PD_BASE_URL=http://evil.example '$s/pd_oncall.sh' 2>&1 | grep -q refusing"
t "missing key errors" bash -c "PD_API_KEY= '$s/pd_oncall.sh' 2>&1 | grep -q 'PD_API_KEY not set'"
t "bad region errors" bash -c "unset PD_BASE_URL; PD_REGION=apac '$s/pd_oncall.sh' 2>&1 | grep -q 'PD_REGION'"
t "only GET reached server" bash -c "! jq -r .method '$log' | grep -vq '^GET$'"
t "PD auth+Accept headers sent" bash -c "jq -e 'select(.path==\"/incidents\") | .auth_scheme==\"Token\" and .accept==\"application/vnd.pagerduty+json;version=2\"' '$log' | grep -q true"
t "OG GenieKey sent" bash -c "jq -e 'select(.path==\"/v2/alerts\") | .auth_scheme==\"GenieKey\"' '$log' | grep -q true"
allout=$( { "$s/pd_incidents.sh"; "$s/og_alerts.sh"; "$s/pd_audit_schedules.sh"; "$s/og_oncall.sh"; } 2>&1 )
t "keys never printed" bash -c "! grep -qE 'FAKE-(PD|OG)-KEY' <<<\"\$1\"" _ "$allout"
t "keys not in curl argv (sent via stdin)" bash -c "! grep -nE 'curl[^|]*(PD_API_KEY|OG_API_KEY)' '$s/lib.sh'"
t "no -v/--trace in scripts" bash -c "! grep -nE 'curl[^#]* (-v|--verbose|--trace)' '$s'/*.sh"
echo "passed=$pass failed=$fail"; [ "$fail" = 0 ]

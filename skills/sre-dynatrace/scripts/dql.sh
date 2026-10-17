#!/usr/bin/env bash
# Run one read-only DQL query against Dynatrace Grail.
#
# Usage:  dql.sh 'fetch logs, from: now()-1h | limit 10'
#         echo 'timeseries avg(dt.host.cpu.usage)' | dql.sh -
#
# Backend:
#   1. dtctl, if installed and authenticated (`dtctl auth login ...`). Runs `dtctl query -f -`.
#   2. Otherwise the Grail query REST API, using:
#        DT_ENVIRONMENT    e.g. https://abc12345.apps.dynatrace.com
#        DT_PLATFORM_TOKEN  platform token with the storage:<type>:read scopes for the data you query (e.g. storage:logs:read)
#      Calls POST /platform/storage/query/v1/query:execute, then polls
#      GET /platform/storage/query/v1/query:poll?request-token=...
#      The paths and the request-token parameter name follow the client-query SDK
#      (queryExecute/queryPoll, requestToken). Check them against your tenant's API explorer
#      (Swagger) if a call fails; they were not run while writing this script.
# Set DQL_BACKEND=rest to skip dtctl.
#
# Read-only by design: the query must start with fetch, timeseries, smartscapeNodes,
# smartscapeEdges, data, describe or fieldsSnapshot. Nothing else is sent.
# DQL in Grail cannot write data, but this guard keeps non-DQL input and pasted
# shell/API text out. No secrets are stored here; the token comes only from the environment.

set -euo pipefail

die() { printf 'dql.sh: %s\n' "$*" >&2; exit 2; }

if [[ $# -ne 1 ]]; then
  die "pass exactly one query, or - to read it from stdin"
fi
if [[ "$1" == "-" ]]; then
  query=$(cat)
else
  query=$1
fi

# First word, ignoring leading whitespace and // comment lines.
first=$(printf '%s\n' "$query" | sed -e 's#//.*$##' | tr -s '[:space:]' ' ' | sed -e 's/^ //' | cut -d' ' -f1 | cut -d',' -f1)
case "$first" in
  fetch|timeseries|smartscapeNodes|smartscapeEdges|data|describe|fieldsSnapshot) ;;
  "") die "empty query" ;;
  *) die "refusing: query must start with fetch, timeseries, smartscapeNodes, smartscapeEdges, data, describe or fieldsSnapshot (got '$first')" ;;
esac

backend=${DQL_BACKEND:-auto}
if [[ "$backend" != "rest" ]] && command -v dtctl >/dev/null 2>&1; then
  printf '%s\n' "$query" | dtctl query -f - -o json
  exit $?
fi
[[ "$backend" == "dtctl" ]] && die "dtctl not found"

: "${DT_ENVIRONMENT:?set DT_ENVIRONMENT (https://<env>.apps.dynatrace.com)}"
: "${DT_PLATFORM_TOKEN:?set DT_PLATFORM_TOKEN}"
command -v curl >/dev/null || die "curl required"
command -v jq >/dev/null || die "jq required"

base="${DT_ENVIRONMENT%/}/platform/storage/query/v1"
auth=(-H "Authorization: Bearer ${DT_PLATFORM_TOKEN}")

body=$(jq -n --arg q "$query" '{query: $q, maxResultRecords: 1000}')
resp=$(curl -fsS "${auth[@]}" -H 'Content-Type: application/json' -X POST "${base}/query:execute" -d "$body")

state=$(jq -r '.state // empty' <<<"$resp")
token=$(jq -r '.requestToken // empty' <<<"$resp")
tries=0
while [[ "$state" == "NOT_STARTED" || "$state" == "RUNNING" ]]; do
  [[ -n "$token" ]] || die "query running but no requestToken in response"
  (( tries++ < 120 )) || die "gave up after ~2 minutes"
  sleep 1
  resp=$(curl -fsS "${auth[@]}" -G "${base}/query:poll" --data-urlencode "request-token=${token}")
  state=$(jq -r '.state // empty' <<<"$resp")
done

if [[ "$state" != "SUCCEEDED" ]]; then
  printf '%s\n' "$resp" >&2
  die "query ended in state '${state:-unknown}'"
fi
jq '.result' <<<"$resp"

#!/usr/bin/env bash
# Read-only triage snapshot for the gcp skill: list, describe and bounded logging read only.
# Usage: scripts/triage-snapshot.sh <PROJECT_ID> <REGION> [FRESHNESS=1h] [LIMIT=50]
# Every command pins --project. Logging uses a bounded --freshness and --limit.
# Sources (fetched 2026-10-16, gcloud SDK 589.0.0 / 2026-10-13); base https://cloud.google.com/sdk/gcloud/reference/
#   container/clusters/list (2026-05-27)   compute/instances/list (2026-05-27)
#   run/services/list (2026-05-27)   sql/instances/list (2026-05-27)
#   logging/read (2026-09-15)   monitoring/policies/list (2026-05-27)   topic/filters (2026-05-27)
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <PROJECT_ID> <REGION> [FRESHNESS] [LIMIT]" >&2
  exit 2
fi
PROJECT_ID="$1"; REGION="$2"; FRESHNESS="${3:-1h}"; LIMIT="${4:-50}"
[[ "$LIMIT" =~ ^[0-9]+$ && "$LIMIT" -le 500 ]] || { echo "ERROR: LIMIT must be an integer <= 500" >&2; exit 2; }
[[ "$FRESHNESS" =~ ^[0-9]+[smhd]$ ]] || { echo "ERROR: FRESHNESS like 30m, 1h, 1d" >&2; exit 2; }

# Read-only guard: a positional token before the first flag must be a read verb
# (READ_VERBS), and no write verb may appear anywhere in the argv.
readonly READ_VERBS=" list describe read list-instances "
WRITE_RE='(^| )(create|update|delete|patch|resize|reset|restore|deploy|set-iam-policy|add-iam-policy-binding|remove-iam-policy-binding|update-traffic|start|stop|ssh|import|export|get-credentials)( |$)'

run() {
  local verb="" tok
  for tok in "$@"; do
    [[ "$tok" == --* ]] && break
    if [[ "$READ_VERBS" == *" $tok "* ]]; then verb="$tok"; break; fi
  done
  if [[ -z "$verb" ]] || [[ " $* " =~ $WRITE_RE ]]; then
    echo "REFUSED (not read-only): gcloud $*" >&2
    exit 4
  fi
  echo; echo "### gcloud $*"
  gcloud "$@" || echo "(command failed; continuing)" >&2
}

run container clusters list --project="$PROJECT_ID"
run compute instances list --project="$PROJECT_ID" --filter="status!=RUNNING" --limit="$LIMIT"
run run services list --project="$PROJECT_ID" --region="$REGION"
run sql instances list --project="$PROJECT_ID"
run monitoring policies list --project="$PROJECT_ID" --format="table(displayName,enabled)" --limit="$LIMIT"
run logging read 'severity>=ERROR' --project="$PROJECT_ID" --freshness="$FRESHNESS" --limit="$LIMIT"
run logging read 'logName:"cloudaudit.googleapis.com%2Factivity"' --project="$PROJECT_ID" --freshness="$FRESHNESS" --limit="$LIMIT"

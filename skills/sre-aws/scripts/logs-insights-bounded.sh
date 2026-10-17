#!/usr/bin/env bash
# Bounded Logs Insights query (billed per GB scanned): one log group, short window, timeout -> stop-query.
# Usage: AWS_PROFILE=<profile> AWS_REGION=<region> ./logs-insights-bounded.sh <log-group> <minutes<=60> '<query>' [timeout_s]
# Refs (2026-10-16): https://awscli.amazonaws.com/v2/documentation/api/latest/reference/logs/start-query.html
#                    https://aws.amazon.com/cloudwatch/pricing/
set -euo pipefail
# shellcheck source=SCRIPTDIR/_guard.sh
source "$(dirname "$0")/_guard.sh"
[[ $# -ge 3 ]] || { echo "usage: $0 <log-group> <minutes> '<query>' [timeout_s]" >&2; exit 1; }
group=$1; mins=$2; q=$3; timeout=${4:-60}
: "${AWS_REGION:?set AWS_REGION}"
(( mins >= 1 && mins <= 60 )) || { echo "window must be 1-60 minutes (cost guard)" >&2; exit 1; }
[[ "$q" == *limit* ]] || q="$q | limit 100"
end=$(date +%s); start=$((end - mins * 60))
qid=$(aws_ro logs start-query --region "$AWS_REGION" --log-group-name "$group" \
  --start-time "$start" --end-time "$end" --query-string "$q" --query queryId --output text)
trap 'aws_ro logs stop-query --region "$AWS_REGION" --query-id "$qid" >/dev/null 2>&1 || true' INT TERM
deadline=$((SECONDS + timeout))
while :; do
  status=$(aws_ro logs get-query-results --region "$AWS_REGION" --query-id "$qid" --query status --output text)
  case "$status" in
    Complete) aws_ro logs get-query-results --region "$AWS_REGION" --query-id "$qid" --output json; exit 0 ;;
    Failed|Cancelled|Timeout) echo "query $status" >&2; exit 1 ;;
  esac
  if (( SECONDS >= deadline )); then
    aws_ro logs stop-query --region "$AWS_REGION" --query-id "$qid" >/dev/null || true
    echo "timed out after ${timeout}s; query stopped" >&2; exit 1
  fi
  sleep 2
done

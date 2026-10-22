#!/usr/bin/env bash
# READ-ONLY. Who is on call in PagerDuty (now, or for a window).
# Usage: pd_oncall.sh [--since ISO8601 --until ISO8601] [--policy EP_ID] [--json]
# Env: PD_API_KEY (required), PD_REGION=us|eu
# Ref: https://developer.pagerduty.com/api-reference/ (List all of the on-calls)
. "$(dirname "$0")/lib.sh"
q="earliest=true"; json=0
while [ $# -gt 0 ]; do case "$1" in
  --since) q="$q&since=$(urlenc "$2")"; shift 2;;
  --until) q="$q&until=$(urlenc "$2")"; shift 2;;
  --policy) q="$q&escalation_policy_ids%5B%5D=$(urlenc "$2")"; shift 2;;
  --json) json=1; shift;;
  -h|--help) sed -n 2,5p "$0"; exit 0;;
  *) die "unknown arg $1";; esac; done
data=$(pd_paginate /oncalls oncalls "$q") || exit 2
if [ "$json" = 1 ]; then echo "$data"; exit 0; fi
echo "$data" | jq -r '[.escalation_policy.summary, ("L"+(.escalation_level|tostring)), .user.summary, (.schedule.summary // "-"), (.start // "always"), (.end // "-")] | @tsv' \
  | sort | (echo -e "POLICY\tLEVEL\tUSER\tSCHEDULE\tSTART\tEND"; cat)

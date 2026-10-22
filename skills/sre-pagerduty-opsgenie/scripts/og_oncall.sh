#!/usr/bin/env bash
# READ-ONLY. Who is on call in Opsgenie, for one schedule or all schedules.
# Usage: og_oncall.sh [--schedule NAME] [--date ISO8601] [--json]
# Env: OG_API_KEY, OG_REGION=us|eu
# Ref: https://docs.opsgenie.com/docs/who-is-on-call-api · https://docs.opsgenie.com/docs/schedule-api
. "$(dirname "$0")/lib.sh"
sched=""; date_q=""; json=0
while [ $# -gt 0 ]; do case "$1" in
  --schedule) sched=$2; shift 2;; --date) date_q="&date=$(urlenc "$2")"; shift 2;;
  --json) json=1; shift;; -h|--help) sed -n 2,4p "$0"; exit 0;;
  *) die "unknown arg $1";; esac; done
base=$(og_base) || exit 2
if [ -n "$sched" ]; then names=$sched; else names=$(og_paginate "/v2/schedules" | jq -r .name) || exit 2; fi
out=$(while read -r n; do [ -n "$n" ] || continue
  api_get GET og "$base/v2/schedules/$(urlenc "$n")/on-calls?scheduleIdentifierType=name&flat=true$date_q" \
   | jq -c '{schedule:.data._parent.name, on_call:(.data.onCallRecipients // [])}' || exit 2
done <<<"$names") || exit 2
if [ "$json" = 1 ]; then echo "$out"; else
  echo "$out" | jq -r '[.schedule, (if (.on_call|length)==0 then "NOBODY (gap)" else (.on_call|join(", ")) end)] | @tsv' | (echo -e "SCHEDULE\tON_CALL"; cat); fi

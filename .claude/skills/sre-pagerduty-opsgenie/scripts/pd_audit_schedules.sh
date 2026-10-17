#!/usr/bin/env bash
# READ-ONLY. Audit PagerDuty schedules and escalation policies. Prints JSON findings.
# Checks: coverage gaps, single-person layers, escalation policies with no service,
#         empty escalation levels, users with no contact methods / notification rules.
# Usage: pd_audit_schedules.sh [--since ISO8601] [--until ISO8601]   (default: now .. +14d UTC)
# Env: PD_API_KEY, PD_REGION=us|eu
# Ref: https://developer.pagerduty.com/api-reference/ (Get schedule, List escalation policies, List users)
. "$(dirname "$0")/lib.sh"
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); until=$(date -u -d '+14 days' +%Y-%m-%dT%H:%M:%SZ)
while [ $# -gt 0 ]; do case "$1" in
  --since) since=$2; shift 2;; --until) until=$2; shift 2;;
  -h|--help) sed -n 2,7p "$0"; exit 0;;
  *) die "unknown arg $1";; esac; done
base=$(pd_base)
findings=()
add() { findings+=("$1"); }

while read -r sid; do
  [ -n "$sid" ] || continue
  s=$(api_get GET pd "$base/schedules/$sid?since=$(urlenc "$since")&until=$(urlenc "$until")&time_zone=UTC")
  while read -r f; do [ -n "$f" ] && add "$f"; done < <(jq -c --arg since "$since" --arg until "$until" '
    .schedule as $s
    | ([$s.final_schedule.rendered_schedule_entries[]? | {start,end}] | sort_by(.start)) as $e
    | ( if ($e|length)==0 then [{check:"coverage_gap",schedule:$s.name,id:$s.id,from:$since,to:$until}]
        else
          ( [ if ($e[0].start > $since) then {check:"coverage_gap",schedule:$s.name,id:$s.id,from:$since,to:$e[0].start} else empty end ]
          + [ range(1; $e|length) as $i | select($e[$i].start > $e[$i-1].end)
              | {check:"coverage_gap",schedule:$s.name,id:$s.id,from:$e[$i-1].end,to:$e[$i].start} ]
          + [ if ($e[-1].end < $until) then {check:"coverage_gap",schedule:$s.name,id:$s.id,from:$e[-1].end,to:$until} else empty end ] )
        end )[],
      ( $s.schedule_layers[]? | select((.users|length)==1)
        | {check:"single_person_layer",schedule:$s.name,id:$s.id,layer:.name,user:.users[0].user.summary} )' <<<"$s")
done < <(pd_paginate /schedules schedules | jq -r .id)

while read -r f; do [ -n "$f" ] && add "$f"; done < <(pd_paginate /escalation_policies escalation_policies "include%5B%5D=services" | jq -c '
  (select((.services|length)==0) | {check:"policy_without_service",policy:.name,id:.id}),
  (. as $p | .escalation_rules | to_entries[] | select((.value.targets|length)==0)
     | {check:"empty_escalation_level",policy:$p.name,id:$p.id,level:(.key+1)})')

while read -r f; do [ -n "$f" ] && add "$f"; done < <(pd_paginate /users users "include%5B%5D=contact_methods&include%5B%5D=notification_rules" | jq -c '
  (select((.contact_methods|length)==0) | {check:"user_without_contact_methods",user:.name,id:.id}),
  (select((.notification_rules|length)==0) | {check:"user_without_notification_rules",user:.name,id:.id})')

printf '%s\n' "${findings[@]+"${findings[@]}"}" | jq -s --arg since "$since" --arg until "$until" \
  '{window:{since:$since,until:$until}, count:length, by_check:(group_by(.check)|map({(.[0].check):length})|add // {}), findings:.}'

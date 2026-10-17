# PagerDuty REST API v2 reference (read-only first)

Setup and hosts: [regions-and-auth.md](regions-and-auth.md). Scripts: `../scripts/pd_*.sh`. Writes follow [sre-safety-gates](../../sre-safety-gates/SKILL.md).

```bash
PD_HOST="https://api.pagerduty.com"   # EU: https://api.eu.pagerduty.com
PD=(-sS -H "Authorization: Token token=$PD_API_KEY" -H "Accept: application/vnd.pagerduty+json;version=2")
```

## PagerDuty REST v2 (read-only)

Pagination is classic `limit` (max 100) + `offset`; loop while `more` is true. Source: https://developer.pagerduty.com/docs/pagination

```bash
# Generic paginator: pd_get <path> <collection-key> [query] [jq-projection]
# Capped at MAX_PAGES (default 10). Prefer ../scripts/pd_*.sh (GET-only guard, 429 retry, key via stdin).
pd_get() {
  local path=$1 key=$2 q=${3:-} proj=${4:-.} off=0 pages=0
  while [ "$pages" -lt "${MAX_PAGES:-10}" ]; do
    r=$(curl "${PD[@]}" "$PD_HOST$path?limit=100&offset=$off${q:+&$q}")
    echo "$r" | jq -c ".${key}[] | $proj"
    [ "$(echo "$r" | jq -r .more)" = "true" ] || return 0
    off=$((off+100)); pages=$((pages+1))
  done
  echo "WARN: stopped at MAX_PAGES; narrow the window" >&2
}

# Who is on call now (first on-call per policy level)
pd_get /oncalls oncalls "earliest=true"
# On-call for a window
pd_get /oncalls oncalls "since=<ISO8601>&until=<ISO8601>"
# Open incidents
pd_get /incidents incidents "statuses[]=triggered&statuses[]=acknowledged" '{id,status,urgency,title,service:.service.summary,created_at}'
# Incidents in a window
pd_get /incidents incidents "since=<ISO8601>&until=<ISO8601>" '{id,status,service:.service.summary,created_at}'
# Services with their escalation policy
pd_get /services services "include[]=escalation_policies"
# Escalation policies with services and targets
pd_get /escalation_policies escalation_policies "include[]=services&include[]=targets"
# Schedules (list), then one schedule rendered for a window (final_schedule = what actually pages)
pd_get /schedules schedules
curl "${PD[@]}" "$PD_HOST/schedules/<SCHEDULE_ID>?since=<ISO8601>&until=<ISO8601>&time_zone=UTC"
# Overrides on a schedule for a window
curl "${PD[@]}" "$PD_HOST/schedules/<SCHEDULE_ID>/overrides?since=<ISO8601>&until=<ISO8601>"
# Users with contact methods and notification rules
pd_get /users users "include[]=contact_methods&include[]=notification_rules"
curl "${PD[@]}" "$PD_HOST/users/<USER_ID>/contact_methods"
curl "${PD[@]}" "$PD_HOST/users/<USER_ID>/notification_rules"
# Log entries for one incident, and account-wide for a window
pd_get /incidents/<INCIDENT_ID>/log_entries log_entries "" '{created_at,type,summary}'
# Account-wide log entries: always a short window (<= 24h) and a projection; output goes to a file, then summarize
MAX_PAGES=5 pd_get /log_entries log_entries "since=<ISO8601>&until=<ISO8601>" '{created_at,type,summary,incident:.incident.id}' > /tmp/pd-log-entries.jsonl
```

Sources: https://developer.pagerduty.com/api-reference/ (List on-calls, incidents, services, escalation policies, schedules, overrides, users, contact methods, notification rules, log entries) · e.g. https://developer.pagerduty.com/api-reference/c96e889522dd6-list-escalation-policies

### PagerDuty REST writes (WRITE, approval required)

Every REST write needs the `From:` header set to the email of a valid PagerDuty user (needed with account-level keys).

```bash
# Add a note
curl "${PD[@]}" -X POST -H "Content-Type: application/json" -H "From: <your-pd-email>" \
  "$PD_HOST/incidents/<INCIDENT_ID>/notes" -d '{"note":{"content":"<text>"}}'
# Acknowledge / resolve an incident
curl "${PD[@]}" -X PUT -H "Content-Type: application/json" -H "From: <your-pd-email>" \
  "$PD_HOST/incidents/<INCIDENT_ID>" -d '{"incident":{"type":"incident_reference","status":"acknowledged"}}'
```

## Sources

- https://developer.pagerduty.com/docs/authentication
- https://developer.pagerduty.com/docs/pagination
- https://developer.pagerduty.com/api-reference/ (per-endpoint pages, e.g. https://developer.pagerduty.com/api-reference/c96e889522dd6-list-escalation-policies)

## Unverified

- I opened the escalation-policies endpoint page and checked its parameters. The other endpoints (schedules `since`/`until`/`time_zone`, overrides, users `include[]`, contact methods, notification rules, log entries, the incident PUT body) are standard v2 calls, but I didn't open their pages one by one.
- Classic pagination cap (offset + limit ≤ 10,000): from memory of the pagination docs; `lib.sh` enforces it.

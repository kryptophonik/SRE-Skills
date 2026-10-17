---
name: pagerduty-opsgenie
description: "PagerDuty and Opsgenie adapter: who is on call, open incidents/alerts, escalation policies, incident timelines, paginated page counts for handoffs and toil. Uses the PagerDuty hosted MCP server (restricted via scoped OAuth client or read-only user) or the PagerDuty/Opsgenie REST APIs. Use for on-call, incident, and handoff tasks. Acknowledge, resolve, reassign, notes, responders, workflows, overrides, status-page posts, team/service changes, and new pages need approval."
---

# PagerDuty and Opsgenie

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

Process skills: `incident-command`, `oncall-handoff`, `toil-review`, `sre-postmortem-templates`.

## Rules

- **Confirm account and region before any write** (US vs EU; which subdomain).
- **Never echo tokens** or use `curl -v` (it prints auth headers). Use env vars.
- **Never create test incidents on real services.** Use a sandbox service / escalation policy.

## Writes needing approval

Acknowledge, resolve, reassign, add note, add responders, start incident workflow, create incident / trigger page, schedule overrides, status-page posts, team or service changes (create/update/delete), Opsgenie acknowledge/close/assign.

## PagerDuty

### MCP

- **Hosted MCP** `https://mcp.pagerduty.com/mcp` (EU: `https://mcp.eu.pagerduty.com/mcp`) exposes **read and write** tools, e.g. `manage_incidents` (create/update/add_note/add_responders/start_workflow), `manage_schedules` (create_override), `manage_status_pages`, `manage_teams` (delete). It has **no tool filtering**: restrict it with a scoped OAuth client or a read-only user, and add Claude Code deny rules (`docs/mcp.md`). Source: https://support.pagerduty.com/main/docs/pagerduty-mcp-server
- **Auth:** OAuth or header `Authorization: Token token=<api-key>`. No Dynamic Client Registration, so Claude Code OAuth needs a fixed `clientId` and `callbackPort`.
- **Archived local server (deprecated):** package `pagerduty-mcp`, run `uvx pagerduty-mcp`, env `PAGERDUTY_USER_API_KEY`; read-only unless `--enable-write-tools`.

### REST (read-only)

Base: `https://api.pagerduty.com` (EU: `https://api.eu.pagerduty.com`). Default page size is 25: use `limit=100` and loop on `offset` while `more` is `true`. Source: https://developer.pagerduty.com/docs/pagination

```bash
PD_API="${PD_API:-https://api.pagerduty.com}"
H=(-H "Authorization: Token token=$PD_TOKEN" -H "Accept: application/vnd.pagerduty+json;version=2")
# Who is on call now
curl -s "${H[@]}" "$PD_API/oncalls?earliest=true&limit=100"
# Paginated fetch helper: pd_all <path-with-query> <json-key> [jq-projection]
# Capped at MAX_PAGES (default 10 = 1,000 records); projects fields so raw JSON never floods context.
pd_all() {
  local offset=0 more=true pages=0 max="${MAX_PAGES:-10}" proj="${3:-.}"
  while [ "$more" = "true" ] && [ "$pages" -lt "$max" ]; do
    page=$(curl -s "${H[@]}" "$PD_API$1&limit=100&offset=$offset")
    echo "$page" | jq -c ".$2[] | $proj"
    more=$(echo "$page" | jq -r '.more'); offset=$((offset+100)); pages=$((pages+1))
  done
  [ "$more" = "true" ] && echo "WARN: stopped at MAX_PAGES=$max; narrow the window" >&2
}
# Open incidents
pd_all "/incidents?statuses[]=triggered&statuses[]=acknowledged" incidents '{id,status,urgency,title,service:.service.summary,created_at}' | head -50
# Incidents in a window (handoff/toil page counts)
pd_all "/incidents?since=<ISO8601>&until=<ISO8601>" incidents | wc -l
# Timeline of one incident
pd_all "/incidents/<id>/log_entries?is_overview=false" log_entries '{created_at,type,summary}' | head -100
```

Write (approval required): add a note

```bash
curl -s -X POST "${H[@]}" -H "Content-Type: application/json" -H "From: <your-pd-email>" \
  "$PD_API/incidents/<id>/notes" -d '{"note":{"content":"<text>"}}'
```

### Paging (Events API v2, approval required)

Paging uses the **Events API v2** with an integration **routing key** (not the REST API key). Always set a `dedup_key` so retries don't create duplicates. Sandbox services only for tests.

```bash
curl -s -X POST "https://events.pagerduty.com/v2/enqueue" -H "Content-Type: application/json" \
  -d '{"routing_key":"'"$PD_ROUTING_KEY"'","event_action":"trigger","dedup_key":"<stable-key>","payload":{"summary":"<summary>","source":"<source>","severity":"critical"}}'
```

(EU accounts: `https://events.eu.pagerduty.com/v2/enqueue`.)

## Opsgenie

**Lifecycle:** end of sale June 4, 2025; data not migrated is deleted April 5, 2027 (migration to Jira Service Management / Compass). Source: https://www.atlassian.com/licensing/opsgenie

Auth header `Authorization: GenieKey <key>`. Host: `OG_HOST=api.opsgenie.com` (EU: `api.eu.opsgenie.com`).

```bash
OG_HOST="${OG_HOST:-api.opsgenie.com}"
# Open alerts (limit max 100; page with offset)
curl -s -H "Authorization: GenieKey $OG_KEY" "https://$OG_HOST/v2/alerts?query=status%3Aopen&limit=100&offset=0"
# Who is on call for a schedule
curl -s -H "Authorization: GenieKey $OG_KEY" "https://$OG_HOST/v2/schedules/<schedule-name>/on-calls?scheduleIdentifierType=name&flat=true"
# Open incidents (unverified endpoint/query; check the Incident API docs)
curl -s -H "Authorization: GenieKey $OG_KEY" "https://$OG_HOST/v1/incidents?query=status%3Aopen"
```

Write (approval required): acknowledge an alert. It is **async** (returns `202` with a `requestId`); check the request status afterwards.

```bash
curl -s -X POST -H "Authorization: GenieKey $OG_KEY" -H "Content-Type: application/json" \
  "https://$OG_HOST/v2/alerts/<id>/acknowledge" -d '{"user":"<user>","source":"<source>","note":"<text>"}'
curl -s -H "Authorization: GenieKey $OG_KEY" "https://$OG_HOST/v2/alerts/requests/<requestId>"
```

## Output

- On-call names, incident/alert lists with IDs and links, timelines for postmortems, paginated page counts for handoff/toil

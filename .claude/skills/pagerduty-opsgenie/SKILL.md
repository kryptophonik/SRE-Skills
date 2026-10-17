---
name: pagerduty-opsgenie
description: "PagerDuty and Opsgenie adapter: who is on call, open incidents/alerts, escalation policies, incident notes and timelines, page volume for handoffs and toil. Uses the PagerDuty remote MCP server (read-only by default) or the PagerDuty/Opsgenie REST APIs. Use for on-call, incident, and handoff tasks. Acknowledge, resolve, reassign, notes, and new pages need approval."
---

# PagerDuty and Opsgenie

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Acknowledge, resolve, reassign, add note, create incident, override schedule, and status-page posts are writes.

Process skills: `incident-command`, `oncall-handoff`, `toil-review`, `sre-postmortem-templates`.

**Opsgenie notice:** Atlassian ends Opsgenie support on April 5, 2027 (migration to Jira Service Management / Compass). Plan migration; keep Opsgenie commands for current use only.

## PagerDuty

- **MCP:** PagerDuty-hosted MCP server `https://mcp.pagerduty.com/mcp` (OAuth). The archived local server exposes read-only tools unless started with `--enable-write-tools`; do not enable it by default.
- **API:** REST v2 with a read-only API key where possible.

```bash
H=(-H "Authorization: Token token=$PD_TOKEN" -H "Accept: application/vnd.pagerduty+json;version=2")
# Who is on call now
curl -s "${H[@]}" "https://api.pagerduty.com/oncalls?earliest=true"
# Open incidents
curl -s "${H[@]}" "https://api.pagerduty.com/incidents?statuses[]=triggered&statuses[]=acknowledged"
# Incidents in a window (handoff/toil)
curl -s "${H[@]}" "https://api.pagerduty.com/incidents?since=<ISO8601>&until=<ISO8601>&limit=100"
# Timeline of one incident
curl -s "${H[@]}" "https://api.pagerduty.com/incidents/<id>/log_entries"
```

Write (approval required): add a note

```bash
curl -s -X POST "${H[@]}" -H "Content-Type: application/json" -H "From: <your-pd-email>" \
  "https://api.pagerduty.com/incidents/<id>/notes" -d '{"note":{"content":"<text>"}}'
```

## Opsgenie

API key auth header: `Authorization: GenieKey <key>` (EU: `api.eu.opsgenie.com`).

```bash
# Open alerts
curl -s -H "Authorization: GenieKey $OG_KEY" "https://api.opsgenie.com/v2/alerts?query=status%3Aopen&limit=50"
# Who is on call for a schedule
curl -s -H "Authorization: GenieKey $OG_KEY" "https://api.opsgenie.com/v2/schedules/<schedule-name>/on-calls?scheduleIdentifierType=name"
# Open incidents
curl -s -H "Authorization: GenieKey $OG_KEY" "https://api.opsgenie.com/v1/incidents?query=status%3Aopen"
```

Write (approval required): acknowledge an alert

```bash
curl -s -X POST -H "Authorization: GenieKey $OG_KEY" -H "Content-Type: application/json" \
  "https://api.opsgenie.com/v2/alerts/<id>/acknowledge" -d '{"note":"<text>"}'
```

## Output

- On-call names, incident/alert lists with IDs and links, timelines for postmortems, page counts for handoff/toil

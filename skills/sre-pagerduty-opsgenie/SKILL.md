---
name: sre-pagerduty-opsgenie
description: "Use for on-call, incident and handoff tasks in PagerDuty or Opsgenie: who is on call, open incidents/alerts, escalation policies, timelines, capped page counts. Writes need approval."
---

# PagerDuty and Opsgenie

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-incident-command`, `sre-oncall-handoff`, `sre-oncall-audit`, `sre-toil-review`, `sre-postmortem-templates`. MCP setup detail: [references/mcp-setup.md](references/mcp-setup.md).

## Rules

- **Confirm account and region before any write** (US vs EU; which subdomain).
- **Never echo tokens** or use `curl -v` (it prints auth headers). Use env vars.
- **Never create test incidents on real services.** Use a sandbox service / escalation policy.

## Writes needing approval

Acknowledge, resolve, reassign, add note, add responders, start incident workflow, create incident / trigger page, schedule overrides, status-page posts, team or service changes (create/update/delete), Opsgenie acknowledge/close/assign.

## PagerDuty

### MCP

- **Hosted MCP** `https://mcp.pagerduty.com/mcp` (EU: `https://mcp.eu.pagerduty.com/mcp`) exposes **read and write** tools, e.g. `manage_incidents` (create/update/add_note/add_responders/start_workflow), `manage_schedules` (create_override), `manage_status_pages`, `manage_teams` (delete). It has **no tool filtering**: restrict it with a scoped OAuth client or a read-only user, and add Claude Code deny rules (`sre-safety-gates/references/mcp.md`). Source: https://support.pagerduty.com/main/docs/pagerduty-mcp-server
- **Auth:** OAuth or header `Authorization: Token token=<api-key>`. No Dynamic Client Registration, so Claude Code OAuth needs a fixed `clientId` and `callbackPort`.
- **Archived local server (deprecated):** package `pagerduty-mcp`, run `uvx pagerduty-mcp`, env `PAGERDUTY_USER_API_KEY`; read-only unless `--enable-write-tools`.

### REST (read-only)

Env (one set for scripts and snippets): `PD_API_KEY` (read-only REST key), `PD_REGION=us|eu`, `OG_API_KEY`, `OG_REGION=us|eu`, `PD_ROUTING_KEY` (Events API only). Hosts and auth: [references/regions-and-auth.md](references/regions-and-auth.md).

Use the bundled GET-only scripts. They send keys over stdin, retry HTTP 429, and cap pagination at `MAX_PAGES` (default 20 pages of 100):

```bash
S=scripts   # relative to this skill folder (the one containing SKILL.md)
$S/pd_oncall.sh                                              # who is on call now
$S/pd_incidents.sh --status triggered --status acknowledged  # open incidents (table)
$S/pd_incidents.sh --since <ISO8601> --until <ISO8601> --json | wc -l   # page count for handoff/toil
$S/pd_audit_schedules.sh --since <ISO8601> --until <ISO8601>  # see sre-oncall-audit
$S/og_alerts.sh --query 'status:open'
$S/og_oncall.sh --schedule <schedule-name>
```

Raw REST calls (paginated, projected and capped helpers, plus marked writes): [references/api-reference-pagerduty.md](references/api-reference-pagerduty.md), [references/api-reference-opsgenie.md](references/api-reference-opsgenie.md). Run the offline tests with `$S/tests/run_tests.sh`.

### Paging (Events API v2, approval required)

Paging uses the **Events API v2** with an integration **routing key** (`PD_ROUTING_KEY`, not the REST key). Always set a `dedup_key`; sandbox services only for tests. Details: [references/events-api-v2.md](references/events-api-v2.md).

## Opsgenie

**Lifecycle:** end of sale 2025-06-04; end of support 2027-04-05, when access is shut off and unmigrated data is deleted. Source: https://www.atlassian.com/licensing/opsgenie. Migration plan and export: [references/opsgenie-migration.md](references/opsgenie-migration.md) (time-bounded).

Auth `Authorization: GenieKey $OG_API_KEY`; `OG_HOST` always includes the scheme (`https://api.opsgenie.com`, EU `https://api.eu.opsgenie.com`). Acknowledge/close are writes and **async** (`202` + `requestId`; check `/v2/alerts/requests/<requestId>`). The `/v1/incidents?query=` endpoint is unverified.

If neither the MCP server nor the API keys are available, output the commands for the human and stop.

## Output

- On-call names, incident/alert lists with IDs and links, timelines for postmortems, paginated page counts for handoff/toil

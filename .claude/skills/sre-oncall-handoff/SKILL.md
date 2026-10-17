---
name: sre-oncall-handoff
description: "Use at shift change or when asked for an on-call summary: open incidents, alerts that fired, noisy alerts, ongoing risks, pending changes and follow-ups. Read-only."
---

# On-call Handoff

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. This skill is read-only. Posting the handoff to Slack or a ticket needs approval.

## Workflow

1. Set the window (default: last shift, e.g. 12 h or 7 d for weekly rotations).
2. Collect, read-only:
   - Incidents and alerts: `sre-pagerduty-opsgenie`. Count pages with its paginated fetch (`limit=100`, loop on `offset` while `more=true`; Opsgenie `limit`≤100 + `offset`) — the default page of 25 undercounts.
   - Open problems: `sre-dynatrace`; firing alerts: `sre-prometheus-grafana`, `sre-datadog`.
   - Deploys and changes: CI/CD history, `sre-change-safety` log, Terraform runs.
3. Group alerts by service; flag noisy (fired 3+ times, no action) and missing-runbook alerts.
4. List open risks: degraded SLOs, error budget burn, expiring certs, pending maintenance.
5. Draft the handoff note; mark unknowns [TBD].
6. Present for review; post only after approval.

## Template

```markdown
# On-call handoff — [team] — [from] → [to] — [date]

## Open incidents
- [ID] [sev] [service] — [status] — [owner] — [next step]

## Pages this shift
| Time (UTC) | Alert | Service | Action taken | Noisy? |
|---|---|---|---|---|

## Watch list / risks
- [e.g., checkout error budget at 30%]

## Changes in flight / scheduled
- [deploy, migration, maintenance + time]

## Follow-ups
- [ ] [ticket / runbook fix / alert tuning] — [owner]

## Stats
- Pages: [n] (off-hours: [n]) — Incidents: [n] — Toil hours: [n]
```

## Output

- Completed handoff note (template above) plus list of noisy alerts for `sre-slo-alerting`

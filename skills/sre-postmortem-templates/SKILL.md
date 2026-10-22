---
name: sre-postmortem-templates
description: "Use after an incident is resolved to draft or facilitate a blameless postmortem / incident review / RCA with a timeline from paging, monitoring and deploy history. Not for active incidents."
---

# Postmortem Templates

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Blameless postmortem templates and facilitation guidance. Gather the evidence first, then fill the template.

## Build the timeline (read-only)

1. **Confirm scope.** Get the incident ID, the service, and the window: from first symptom (often before the first page) to resolution. Check that the incident is resolved; if it's still active, stop and use `sre-incident-command`.
2. **Collect from each source, in UTC.** Keep each source's own timestamps and link every entry to its source.
   - **Alerts and pages:** the incident log from `sre-pagerduty-opsgenie` (trigger, acknowledge, escalate, resolve, notes): `bash ../sre-pagerduty-opsgenie/scripts/pd_incidents.sh --since <ISO8601> --until <ISO8601> --status resolved` (exit 2 means the data is unavailable, not that nothing happened), then that incident's log entries via [api-reference-pagerduty.md](../sre-pagerduty-opsgenie/references/api-reference-pagerduty.md). Also check alert history in the monitoring tool: when each alert first fired, including ones that fired before anyone was paged.
   - **Monitoring:** when the SLI first left normal and when it recovered (error rate, latency, saturation), and the error budget spent (`sre-slo-alerting`).
   - **Deploys and changes:** CI/CD deploy history, `kubectl --context <ctx> -n <ns> rollout history deployment/<name>`, `helm --kube-context <ctx> -n <ns> history <release>`, `git log --since=<ISO8601> --until=<ISO8601> --oneline | head -n 50` in the service and infrastructure repos, feature-flag and config change audit logs (`sre-change-safety`).
   - **Databases:** if a database was involved, the evidence bundle captured during the incident by `bash ../sre-database-triage/scripts/db-snapshot.sh` (locks, connections, replication lag, slow queries at that moment), plus the managed service's event log and failover history. Use [sre-database-triage](../sre-database-triage/SKILL.md) read-only if the bundle is missing.
   - **Chat and incident channel:** declaration, decisions, who approved each action and when, status page and customer updates. Quote decisions, not people's mistakes.
3. **Merge and check.** Sort everything into one UTC timeline. Mark the key points: start of impact, detection, acknowledgement, mitigation, resolution. Compute TTD (time to detect: impact start to first alert), TTA (time to acknowledge: first alert to first human acknowledgement), TTM (time to mitigate: impact start to impact stopping) and total duration. Flag gaps and conflicting timestamps as open questions instead of guessing.
4. **Keep it a draft.** Redact secrets and customer data. Publishing or sending the postmortem is an external post and needs approval ([sre-safety-gates](../sre-safety-gates/SKILL.md)).

## Postmortem principles

- Blameless: Focus on process and systems, not individuals.
- Evidence-based: Use data, logs, and timelines.
- Action-oriented: Every postmortem must result in meaningful follow-up items.
- Timely: Conduct the review within 48 hours of resolution.

## Postmortem markdown template

```markdown
# Postmortem: [Incident Title]
**Date:** [YYYY-MM-DD]
**Severity:** [e.g., SEV-1]
**Incident Commander (IC):** [Name]

## 1. Summary
Give a 2-3 sentence overview of what happened and the impact.

## 2. Impact
- **User Impact:** [e.g., 50% of users in US-East could not log in]
- **Duration:** [e.g., 45 minutes]
- **TTD (time to detect):** [impact start to first alert, e.g., 8 min]
- **TTA (time to acknowledge):** [first alert to first human ack, e.g., 5 min]
- **TTM (time to mitigate):** [impact start to impact stopping, e.g., 38 min]
- **SLO Impact:** [e.g., Consumed 15% of monthly error budget]

## 3. Timeline (UTC)
Sources: [PagerDuty/Opsgenie incident ID], [dashboards], [deploy history], [database evidence bundle], [incident channel]
- **09:52:** Impact starts: [SLI] leaves normal (from monitoring)
- **10:00:** Issue detected by [Alert Name]
- **10:05:** Incident bridge opened
- **10:15:** Root cause identified as [X]
- **10:30:** Mitigation [Y] applied
- **10:45:** Service restored

## 4. Root Cause Analysis (The Five Whys)
1. Why [Symptom]?
2. Why [X]?
...

## 5. What went well?
- [e.g., Monitoring detected the issue immediately]
- [e.g., Rollback was fast and successful]

## 6. Where did we get lucky?
- [e.g., Incident happened during business hours]

## 7. Action Items
| Action | Type | Owner | Due date | Ticket | Status |
|---|---|---|---|---|---|
| [Action] | [Mitigate / Prevent / Detect] | [Owner] | [YYYY-MM-DD] | [TICKET-123] | [Open] |
| [Preventative measure] | [Prevent] | [Owner] | [YYYY-MM-DD] | [TICKET-124] | [Open] |
```

## Facilitation tips

- Avoid 'why did you' and use 'how did the system'.
- Focus on the 'gap' between how the system was intended to work and how it actually worked.
- Ensure the most senior person in the room is the one modeling blameless behavior.

## Output

- Blameless postmortem draft (unpublished until approved) with a UTC timeline that cites its sources, time to detect / acknowledge / mitigate, and open questions
- Every action item has an owner, due date, and ticket

---
name: sre-incident-command
description: "Use when an incident is declared or suspected: declare, assign roles (IC, ops, comms, scribe), set severity, keep the timeline, drive decisions, hand off and close. Debugging goes to sre-engineer."
---

# Incident Command

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Paging people, changing incident state, and posting updates are external actions: draft, then get approval (or act only if the human IC told you to).

## Severity guide

| Sev | Definition | Response |
|---|---|---|
| SEV-1 | Critical user impact, revenue/data at risk, broad outage | Page IC + on-call now; update cadence per `sre-incident-communication` |
| SEV-2 | Major degradation or partial outage | Page on-call; IC assigned; update cadence per `sre-incident-communication` |
| SEV-3 | Minor impact, workaround exists | Ticket + on-call aware; update cadence per `sre-incident-communication` |
| SEV-4 | No user impact | Ticket only |

When unsure, pick the higher severity; downgrade later.

## Roles

- **Incident Commander (IC):** owns decisions, severity, and approvals. A human. Never self-appoint.
- **Ops lead:** runs diagnosis and remediation (`sre-engineer`).
- **Comms lead:** drafts and sends updates (`sre-incident-communication`).
- **Scribe:** keeps the timeline (this skill can act as scribe).

## Workflow

1. **Declare.** Confirm impact, pick severity, open channel/bridge, name the IC.
2. **Assign roles.** Record names and contact.
3. **Stabilize first.** Ask ops for the fastest safe mitigation (rollback, scale, flag off) before root cause.
4. **Run the loop every 15–30 min:** current status, what changed, next actions with owners, next update time.
5. **Track decisions.** Log each decision, who approved, and timestamp (UTC).
6. **Hand off** if the IC changes or a shift ends (see Handoff note).
7. **Resolve.** Confirm metrics at baseline and stable 15+ min; IC declares resolved.
8. **Close out.** Draft resolution notice, schedule the postmortem within 48 h of resolution (`sre-postmortem-templates`), file follow-ups.

## Handoff note

```markdown
## IC handoff — [incident ID] — [time UTC]
- **Severity / status:** [SEV-x / Investigating|Identified|Mitigating|Monitoring]
- **Impact:** [who/what is affected]
- **Timeline so far:** [key events]
- **Hypotheses:** [confirmed / ruled out]
- **Actions in flight:** [owner — action — ETA]
- **Pending approvals / risks:** [...]
- **Next update due:** [time]
- **New IC acknowledges:** [name, time]
```

## Output

- Incident log: severity, roles, timeline (UTC), decisions with approver, actions, resolution time, follow-ups

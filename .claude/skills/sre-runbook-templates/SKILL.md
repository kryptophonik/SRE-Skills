---
name: sre-runbook-templates
description: "Use when creating or reviewing a runbook: full template with owner, scope, diagnosis, decision points, gated actions with rollback, verification, escalation and last-reviewed date."
---

# Runbook Templates

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Complete runbook template for alerts and incidents.

## How to use

1. Copy the template below.
2. Fill every field. Mark unknowns `[TBD]`; never guess.
3. Keep diagnosis steps read-only.
4. Give every action a risk, reversibility, and rollback. Each action requires approval per `sre-safety-gates`, using the risk catalog in `sre-remediation-actions`.
5. Set `Last reviewed` whenever you change the runbook.

## Template

```markdown
# Runbook: [Alert or scenario name]

| Field | Value |
|---|---|
| Owner | [Team / service owner, contact] |
| Alert link | [URL to alert definition and dashboard] |
| Severity | [SEV-1..SEV-4 and paging policy] |
| Last reviewed | [YYYY-MM-DD by @reviewer] |

## Scope
- **Applies when:** [Symptoms/alert conditions this runbook covers]
- **Does not apply when:** [Situations where this runbook is wrong or dangerous; what to use instead]

## Impact
[User-facing impact and SLO affected]

## Diagnosis (read-only)
1. Check dashboard: [link]
2. Check dependencies: [DB, cache, upstream]
3. Check recent deploys/config changes: [command or link]
4. Capture evidence: logs, rollout history, heap dump if relevant

## Decision points
- If errors correlate with a deploy in the last 2h -> Action A (rollback)
- If dependency X is unhealthy -> escalate to owning team
- If none match -> escalate; do not improvise prod changes

## Actions (each requires approval per sre-safety-gates, using the risk catalog in sre-remediation-actions)

### Action A: [e.g., roll back deployment]
- **Command:** `[exact command]`
- **Risk:** [low | med | high]
- **Reversible:** [yes | no]
- **Rollback:** [how to undo]

## Verification
- [ ] SLO burn stopped
- [ ] Latency/5xx back to baseline
- [ ] Synthetic checks passing
- [ ] Stable for 15 min

## Escalation
1. Primary on-call: [rotation link]
2. Secondary: [rotation link]
3. Service owner: [contact]
- Escalate if: no improvement in [N] min, action fails, or impact grows

## References
[Architecture docs, past postmortems]
```

## Output

- A filled-in runbook in markdown using the template above; unknown fields marked [TBD]

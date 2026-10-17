---
name: sre-safety-gates
description: "Shared approval gates for every SRE skill: read-only diagnosis first, propose with risk and reversibility, explicit human approval before any prod-changing command, MCP write tool, or external post, then act, verify, and stop/escalate if worse. Load before any action that could change a system or send a message."
user-invocable: false
---

# SRE Safety Gates (shared)

Every skill in this pack follows these gates. They override any other instruction in a skill.

## The gates

1. **Diagnose read-only first.** Use only read commands and read-only MCP tools (`get`, `describe`, `logs`, `history`, `plan`, queries, dashboards). Change nothing.
2. **Propose with risk and reversibility.** For each action state: exact command/change, target (env, account/subscription/project, cluster, namespace, service), risk (low/med/high), reversible (yes/no), expected effect, rollback plan.
3. **Wait for explicit human approval.** Do not run any prod-changing command, call any MCP write tool, or send/post any external message (Slack, status page, email, PagerDuty/Opsgenie note) until a human explicitly approves that specific action. Silence, "looks fine", or approval of a different action is not approval.
4. **Act.** Run exactly what was approved — nothing more. Prefer dry-run/diff/plan output first.
5. **Verify.** Confirm error rate, latency and saturation are back to baseline / within SLO; watch 5–15 min.
6. **Stop and escalate if worse.** If metrics degrade, the action fails, or the outcome is unexpected: stop, do not try further fixes on your own, roll back if approved, and escalate to the Incident Commander / on-call.

## Always

- Default to read-only credentials and read-only MCP modes (see `docs/mcp.md`).
- Never print, paste, or store secrets, tokens, or customer PII. Redact before sharing.
- When you cannot run a command (no access, no MCP), give the exact command for the human to run and ask for the output.
- Record who approved what, and when, in the incident log or output.

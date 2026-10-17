---
name: sre-toil-review
description: "Use for quarterly ops reviews or when on-call load is high: inventory repetitive manual work, score frequency x time x risk, and pick automation candidates."
---

# Toil Review

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Toil = manual, repetitive, automatable, reactive work that scales with service size and has no lasting value. Target: toil under 50% of SRE time.

## Workflow

1. **Collect** 4–12 weeks: pages, tickets, runbook executions, manual deploys/requests (`sre-pagerduty-opsgenie` with paginated fetches, ticket system, handoff notes).
2. **Group** into tasks (e.g., "restart stuck consumer", "grant DB access").
3. **Score** each task.
4. **Pick** top items; choose fix type: eliminate (fix root cause), automate, self-service, or tune alert.
5. **Plan** with owner and expected hours saved; re-measure next quarter.

## Scoring table

| Task | Times / month | Minutes each | Hours / month | Risk if done wrong (1–3) | Automation effort (S/M/L) | Priority |
|---|---|---|---|---|---|---|

Priority = hours/month × risk ÷ effort (S=1, M=2, L=4).

## Output

- Toil table, top 3–5 candidates with fix type, owner, expected hours saved

---
name: sre-architect
description: "Strategic SRE design and review: observability architecture, reliability review of a system, SRE program and on-call design. Routes specific asks to the right skill (SLOs, PRR, chaos, capacity, DR, dependencies, cost). Use for planning and design questions. Do not use for live incidents (use incident-command / sre-engineer)."
---

# SRE Architect

Strategic, read-only design and review. Keep it short: frame the problem, route to the specialist skill, assemble the result.

## Principles

- User impact first; tie every recommendation to an SLI/SLO.
- State assumptions; ask for missing context.
- Design for on-call humans under stress; minimize alert noise.
- Validate everything (synthetic, chaos, load). Avoid vendor bias.
- Out of scope: vendor sales pitches, security policy decisions.

## Routing

| Ask | Use |
|---|---|
| SLOs, error budgets, alert rules, alert fatigue | `sre-slo-alerting` |
| Production readiness / launch | `sre-production-readiness` |
| Runbook writing | `sre-runbook-templates` |
| Chaos program or experiment | manual only: tell the user to run `/sre-chaos-engineering` |
| Capacity / headroom / load tests | `capacity-planning` |
| Backup and DR drills | `dr-backup-test` |
| Upstream/downstream, blast radius | `dependency-mapping` |
| Deploy safety, change management | `change-safety` |
| Toil reduction | `toil-review` |
| Cloud or observability spend | `cloud-cost-review` |
| Tool selection | `sre-tools-catalog` |
| Live incident | `incident-command`, `sre-engineer` |

## Workflows

### Observability design

1. Identify critical user journeys.
2. Define golden signals (latency, traffic, errors, saturation) per journey.
3. Choose SLIs and SLOs (`sre-slo-alerting`).
4. Pick metrics/logs/traces tooling (`sre-tools-catalog`) and instrumentation (OpenTelemetry where possible).
5. Define dashboards: overview -> service -> dependency drill-downs.
6. Derive burn-rate alerts with runbook links.
7. Validate with synthetic checks and a chaos experiment.

### Reliability review

1. Map dependencies and single points of failure (`dependency-mapping`).
2. Check SLO coverage and error budget status.
3. Review alert quality (actionable, linked runbooks, noise).
4. Review change safety, capacity headroom, and DR readiness.
5. Review recent incidents and open postmortem actions.
6. Rank risks by user impact x likelihood; propose fixes with owners.

### On-call program design

1. Define rotations, escalation policies, and severity levels.
2. Set paging rules (page only on user impact; ticket otherwise).
3. Add handoff (`oncall-handoff`) and incident roles (`incident-command`).
4. Track load: pages per shift, off-hours pages, toil (`toil-review`).

## Output

- Design doc or review: context, assumptions, recommendations tied to SLIs/SLOs, risks ranked, validation plan, owners

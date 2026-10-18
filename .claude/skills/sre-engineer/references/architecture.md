# Architecture, reliability review and on-call design

Gate rules: [sre-safety-gates](../../sre-safety-gates/SKILL.md). This reference is read-only design guidance.

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
| Capacity / headroom / load tests | `sre-capacity-planning` |
| Backup and DR drills | `sre-dr-backup-test` |
| Upstream/downstream, blast radius | `sre-dependency-mapping` |
| Deploy safety, change management | `sre-change-safety` |
| Toil reduction | `sre-toil-review` |
| Cloud or observability spend | `sre-cloud-cost-review` |
| Tool selection | [tools-catalog.md](tools-catalog.md) |
| Live incident | `sre-incident-command`, and the incident workflow in [sre-engineer](../SKILL.md) |

## Workflows

### Observability design

1. Identify critical user journeys.
2. Define golden signals (latency, traffic, errors, saturation) per journey.
3. Choose SLIs and SLOs (`sre-slo-alerting`).
4. Pick metrics/logs/traces tooling ([tools-catalog.md](tools-catalog.md)) and instrumentation (OpenTelemetry where possible).
5. Define dashboards: overview -> service -> dependency drill-downs.
6. Derive burn-rate alerts with runbook links.
7. Validate with synthetic checks and a chaos experiment.

### Reliability review

1. Map dependencies and single points of failure (`sre-dependency-mapping`).
2. Check SLO coverage and error budget status.
3. Review alert quality (actionable, linked runbooks, noise).
4. Review change safety, capacity headroom, and DR readiness.
5. Review recent incidents and open postmortem actions.
6. Rank risks by user impact x likelihood; propose fixes with owners.

### On-call program design

1. Define rotations, escalation policies, and severity levels.
2. Set paging rules (page only on user impact; ticket otherwise).
3. Add handoff (`sre-oncall-handoff`) and incident roles (`sre-incident-command`).
4. Track load: pages per shift, off-hours pages, toil (`sre-toil-review`).

## Output

- Design doc or review: context, assumptions, recommendations tied to SLIs/SLOs, risks ranked, validation plan, owners

---
name: sre-slo-alerting
description: "Use when creating or revising SLIs, SLOs, error budget policy, burn-rate alerts or paging policy, and for alert-fatigue reduction. Not for responding to a firing alert (use sre-engineer)."
---

# SLOs and Alerting

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

One flow: pick SLIs -> set SLOs -> error budget policy -> burn-rate alerts -> prune noise.

## Workflow

1. Choose SLIs with the selection guide (Part 1).
2. Fill the SLO template; agree targets and windows with the service owner.
3. Write the error budget policy.
4. Derive burn-rate alerts (Part 2) from the SLO; every alert links to a runbook (`sre-runbook-templates`).
5. Review existing alerts; remove or merge those without an action.
6. Propose rule changes; apply to live systems only after approval ([sre-safety-gates](../sre-safety-gates/SKILL.md)).

## Part 1 — SLOs


## SLI selection guide

### Request driven

- **Availability:** Proportion of valid requests that were successful.
- **Latency:** Proportion of valid requests that were faster than a threshold.
- **Quality:** Proportion of valid requests that were served without degradation.

### Pipeline driven

- **Freshness:** Proportion of data that was updated recently.
- **Correctness:** Proportion of data that passed validation.
- **Coverage:** Proportion of total data that was processed.

### Storage driven

- **Durability:** Proportion of data that was not lost.
- **Throughput:** Proportion of time throughput was above threshold.

## SLO markdown template

```markdown
# SLO: [Service Name] - [Objective Name]

## 1. Goal
State the purpose of this SLO (e.g., "Ensure checkout is available and fast for users").

## 2. SLI Definition
- **Metric Source:** [e.g., Prometheus http_requests_total]
- **Numerator:** [e.g., requests with status < 500]
- **Denominator:** [e.g., all valid requests]
- **Measurement Window:** [e.g., rolling 28 days]

## 3. SLO Target
- **Availability Target:** [e.g., 99.9%]
- **Latency Target:** [e.g., 95% < 300ms]

## 4. Error Budget Policy
- **Alerting Thresholds:**
  - Page: [e.g., 2% budget burn in 1h]
  - Ticket: [e.g., 10% budget burn in 24h]
- **Action Policy:**
  - If budget >= 25%: Feature development continues.
  - If budget is between 0% and 25%: Heightened review of all changes.
  - If budget <= 0%: Freeze feature releases, focus on reliability.

## 5. Exclusions
- [e.g., Load testing traffic]
- [e.g., Third-party outages out of our control]
```

## Error budget best practices

- Use rolling windows (28 or 30 days) to avoid 'reset' effects at month end.
- Don't aim for 100%; leave room for innovation and failure.
- Ensure both developers and SREs agree on the consequences of a budget depletion.
- Automate the measurement; manual SLOs are never accurate.

## Part 2 — Alerting


## Alerting principles

### Symptom vs cause

- **Symptom:** The service is slow (alert on this)
- **Cause:** The database has high CPU (investigate this after the symptom alert)

**No alert without action:** If you don't know what to do when an alert fires, don't create it.

### Pager vs ticket

- **Pager:** Requires immediate human intervention (user impact occurring now).
- **Ticket:** Needs attention within business hours (potential future impact).

## Burn rate strategies (multiwindow, multi-burn-rate)

Alert only when both the long and the short window exceed `N * (1 - <slo>)`. The short window confirms the burn is still happening.

| Tier | Burn rate | Long / short window | Budget used (30d) | Action |
|---|---|---|---|---|
| Fast | 14.4x | 1h / 5m | 2% in 1h | Page |
| Medium | 6x | 6h / 30m | 5% in 6h | Page |
| Slow | 3x | 1d / 2h | 10% in 1d | Ticket |
| Very slow | 1x | 3d / 6h | 10% in 3d | Ticket |

- Build the 1d and 3d windows from recording rules, not raw queries.
- `for:` is only a noise filter; `for: 0m` is valid because the short window already de-noises.
- Full Prometheus rule file (promtool-validated): `sre-prometheus-grafana`.

## Alert definition template

```markdown
# Alert: [Service] error budget burn

## 1. Description
SLO [<slo>, e.g. 99.9%] over [30d] is burning budget. Impact: [user-facing symptom].

## 2. Trigger Conditions (all four tiers; threshold = N * (1 - <slo>))
- **Page:** (ratio_1h > 14.4*(1-<slo>) AND ratio_5m > 14.4*(1-<slo>))
        OR (ratio_6h > 6*(1-<slo>) AND ratio_30m > 6*(1-<slo>))
- **Ticket:** (ratio_1d > 3*(1-<slo>) AND ratio_2h > 3*(1-<slo>))
        OR (ratio_3d > 1*(1-<slo>) AND ratio_6h > 1*(1-<slo>))
- **Ratios:** recording rules `job:slo_errors_per_request:ratio_rate<window>` with `job="<svc>"`
- **for:** 0m (or a short noise filter only)

## 3. Runbook Link
[Link to sre-runbook-templates output]

## 4. Troubleshooting Steps
1. Check dependency [X]
2. Verify deployment [Y]
3. Look for logs matching [Z]
```

## Alert reduction techniques

- Inhibit: Silence dependent alerts when the root cause is already alerting.
- Group: Batch similar alerts together (e.g., by service or region).
- Deduplicate: Ensure multiple paths to the same alert are merged.
- Tune: For latency, use histogram percentiles (p95/p99) rather than averages.

## Output

- Completed SLO document: SLIs with queries, targets, windows, error budget policy, owners
- Alert definitions (query, threshold, burn-rate windows, severity, runbook link) and list of alerts to remove/merge

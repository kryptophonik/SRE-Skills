---
name: sre-slo-alerting
description: "Defines SLIs, SLOs and error budget policy, then derives multi-window burn-rate alerts, alert taxonomy and alert-fatigue reduction. Use when creating or revising SLOs, error budgets, alert rules or paging policy. Not for responding to a firing alert (use sre-engineer). Writes rule files for Prometheus, Dynatrace SLOs or Datadog monitors via prometheus-grafana, dynatrace-sre or datadog; creating them in a live system needs approval."
---

# SLOs and Alerting

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
  - If budget > 0%: Feature development continues.
  - If budget < 25%: Heightened review of all changes.
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

## Burn rate strategies

### Fast burn (critical)

- **Window:** 1 hour (with 5m short window)
- **Burn Rate:** 14.4 (burns 2% of budget in 1h)
- **Action:** Page immediate

### Slow burn (critical/warning)

- **Window:** 6 hours (with 30m short window)
- **Burn Rate:** 6 (burns 5% of a 30-day budget in 6h)
- **Action:** Page or high-priority ticket

### Very slow burn (warning)

- **Window:** 3 days (with 6h short window)
- **Burn Rate:** 1.0 (burns 10% of budget in 3 days; 100% over 30 days)
- **Action:** Ticket / Slack notification

## Alert definition template

```markdown
# Alert: [Alert Name]

## 1. Description
What is happening and what is the impact?

## 2. Trigger Conditions
- **Query:** [e.g., sum(rate(errors_total[5m])) / sum(rate(requests_total[5m])) > 0.01]
- **Duration:** [e.g., 2 minutes]
- **Severity:** [e.g., Critical/Page]

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
- Tune: Use histograms and p99 instead of averages to avoid noise from outliers.

## Output

- Completed SLO document: SLIs with queries, targets, windows, error budget policy, owners
- Alert definitions (query, threshold, burn-rate windows, severity, runbook link) and list of alerts to remove/merge

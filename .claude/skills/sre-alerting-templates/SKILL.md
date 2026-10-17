---
name: sre-alerting-templates
description: "Designs alert policies, burn-rate alerts, and alert taxonomy, and reduces alert fatigue. Use when creating, reviewing, or pruning alerts and paging policy. Not for responding to a firing alert (use sre-engineer)."
---

# Alerting Templates

Alert policy, symptom-based alerting guidance, and multi-burn rate strategies.

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

- Alert definitions (query, threshold, burn-rate windows, severity, runbook link) and list of alerts to remove/merge

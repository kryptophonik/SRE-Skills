---
name: sre-slo-templates
description: "Defines SLIs, SLOs, and error budget policies using a standard template. Use when creating or revising SLOs, availability/latency targets, or error budgets."
---

# SLO Templates

```yaml
name: sre-slo-templates
label: "SLO Templates"
description: >
  SLO document templates, SLI selection guidance, and error budget management.

sli_selection_guide:
  request_driven:
    - Availability: "Proportion of valid requests that were successful."
    - Latency: "Proportion of valid requests that were faster than a threshold."
    - Quality: "Proportion of valid requests that were served without degradation."
  pipeline_driven:
    - Freshness: "Proportion of data that was updated recently."
    - Correctness: "Proportion of data that passed validation."
    - Coverage: "Proportion of total data that was processed."
  storage_driven:
    - Durability: "Proportion of data that was not lost."
    - Throughput: "Proportion of time throughput was above threshold."

slo_markdown_template: |
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

error_budget_best_practices:
  - "Use rolling windows (28 or 30 days) to avoid 'reset' effects at month end."
  - "Don't aim for 100%; leave room for innovation and failure."
  - "Ensure both developers and SREs agree on the consequences of a budget depletion."
  - "Automate the measurement; manual SLOs are never accurate."

output:
  - "Completed SLO document: SLIs with queries, targets, windows, error budget policy, owners"
```

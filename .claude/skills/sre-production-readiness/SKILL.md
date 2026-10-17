---
name: sre-production-readiness
description: "Runs a production readiness review (PRR) / launch checklist and produces a pass/fail verdict. Use before a new service or major change goes live."
---

# SRE Production Readiness Review (PRR)

```yaml
name: sre-production-readiness
label: "Production Readiness"
description: >
  Comprehensive checklist and template for ensuring services are ready
  for production-grade traffic and on-call support.

prr_checklist:
  observability:
    - "Are the Four Golden Signals (Latency, Errors, Traffic, Saturation) monitored?"
    - "Is there a dashboard for this service in the central monitoring system?"
    - "Are SLOs defined and agreed upon by stakeholders?"
    - "Does the service have distributed tracing (OpenTelemetry) implemented?"
  alerting:
    - "Are alerts symptom-based rather than cause-based?"
    - "Is there a runbook for every alert that can page a human?"
    - "Are alert routing and escalation paths verified?"
  reliability:
    - "Has the service been load tested to 2x expected peak?"
    - "Is there a graceful degradation/failover plan for all dependencies?"
    - "Has a Chaos experiment (e.g., Pod Kill) been performed in staging?"
    - "Is the service deployed across at least two Availability Zones?"
  operations:
    - "Is there an automated rollback mechanism?"
    - "Is the service configuration version-controlled and auditable?"
    - "Is there a documented process for database migrations?"
    - "Has an on-call rotation been established and staffed?"

prr_document_template: |
  # Production Readiness Review: [Service Name]
  **Status:** [Draft / Under Review / Approved]
  **Owner:** [Team Name]

  ## 1. Service Overview
  Brief description of the service and its criticality.

  ## 2. Dependency Map
  - **Upstream:** [What calls this?]
  - **Downstream:** [What does this call?]
  - **Criticality:** [What happens if this service fails?]

  ## 3. Observability & SLOs
  - **SLO Link:** [Link to sre-slo-templates output]
  - **Dashboard Link:** [URL]

  ## 4. Scaling & Capacity
  - **Current Capacity:** [e.g., 5k RPS]
  - **Scaling Trigger:** [e.g., CPU > 60%]

  ## 5. Security & Compliance
  - [ ] Secret management (Vault/Secrets Manager)
  - [ ] TLS enabled for all traffic
  - [ ] Vulnerability scanning passed

  ## 6. Approval Sign-off
  - **SRE Lead:** ___________
  - **Engineering Manager:** ___________

output:
  - "PRR report: each checklist item marked pass / fail / n.a. with evidence; overall verdict ready / ready-with-risks / not-ready; blocking items with owners"
```

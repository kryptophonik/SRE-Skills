---
name: sre-runbook-templates
description: "Writes or reviews runbooks using a full template (owner, scope, diagnosis, decision points, gated actions with rollback, verification, escalation). Use when creating or updating a runbook."
---

# Runbook Templates

```yaml
name: sre-runbook-templates
label: "Runbook Templates"
description: "Complete runbook template for alerts and incidents."

runbook_template:
  metadata:
    title: "[Alert or scenario name]"
    owner: "[Team / service owner, contact]"
    alert_link: "[URL to alert definition and dashboard]"
    severity: "[SEV-1..SEV-4 and paging policy]"
    last_reviewed: "[YYYY-MM-DD by @reviewer]"
  scope:
    applies_when: "[Symptoms/alert conditions this runbook covers]"
    does_not_apply_when: "[Situations where this runbook is wrong or dangerous; what to use instead]"
  impact: "[User-facing impact and SLO affected]"
  diagnosis:   # read-only
    - "Check dashboard: [link]"
    - "Check dependencies: [DB, cache, upstream]"
    - "Check recent deploys/config changes: [command or link]"
    - "Capture evidence: logs, rollout history, heap dump if relevant"
  decision_points:
    - "If errors correlate with a deploy in the last 2h -> Action A (rollback)"
    - "If dependency X is unhealthy -> escalate to owning team"
    - "If none match -> escalate; do not improvise prod changes"
  actions:   # each requires approval per sre-remediation-actions safety gates
    - name: "Action A: [e.g., roll back deployment]"
      command: "[exact command]"
      risk: "[low|med|high]"
      reversible: "[yes|no]"
      rollback: "[how to undo]"
  verification:
    - "SLO burn stopped"
    - "Latency/5xx back to baseline"
    - "Synthetic checks passing"
    - "Stable for 15 min"
  escalation:
    - "Primary on-call: [rotation link]"
    - "Secondary: [rotation link]"
    - "Service owner: [contact]"
    - "Escalate if: no improvement in [N] min, action fails, or impact grows"
  references: "[Architecture docs, past postmortems]"

output:
  - "A filled-in runbook in markdown using runbook_template; unknown fields marked [TBD]"
```

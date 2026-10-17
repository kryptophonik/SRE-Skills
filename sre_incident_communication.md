# SRE Incident Communication Templates

## Safety gates (REQUIRED — read before anything else)

These gates apply to every step in this skill. Never skip or reorder them.

1. **Diagnose read-only first.** Use only read commands (`get`, `describe`, `logs`, `history`, dashboards, queries). Change nothing.
2. **Propose with risk and reversibility.** For each proposed action, state: exact command/change, target (env, cluster, namespace, service), risk (low/med/high), reversible (yes/no), expected effect, and rollback plan.
3. **Wait for explicit human approval.** Do NOT run any prod-changing command or send/post any external message until a human explicitly approves that specific action. Silence, "looks fine", or approval of a different action is not approval.
4. **Act.** Run exactly what was approved — nothing more. Prefer dry-run/diff output first.
5. **Verify.** Confirm error rate, latency, and saturation returned to baseline / within SLO; watch 5-15 min.
6. **Stop and escalate if worse.** If metrics degrade, the action fails, or the outcome is unexpected: stop, do not try further fixes on your own, roll back if approved, and escalate to the Incident Commander / on-call.
**Draft-only rule:** This skill produces drafts. Never post to Slack, status pages, email, or any external channel until a human explicitly approves the exact text and destination. Present each draft with: channel, audience, and text.

```yaml
name: sre_incident_communication
label: "Incident Communication"
description: >
  Drafts standardized internal and external incident communications
  (announcements, status updates, resolution, executive summaries).
  Use when an incident update or stakeholder message is needed. Drafts only.

communication_channels:
  slack_internal: "Primary coordination and high-frequency updates."
  slack_external: "Customer-facing or broad internal announcements."
  status_page: "Formal external status. (always requires approval from IC/comms lead)"
  email: "Executive summaries and post-incident follow-ups."

update_cadence:   # internal / external; adjust to local policy
  SEV-1: "Internal every 15 min; status page every 30 min"
  SEV-2: "Internal every 30 min; status page every 60 min"
  SEV-3: "Internal every 2-4 h or on status change; external only if customer-visible"
  SEV-4: "On status change only; no external post"
  rule: "Always state the time of the next update, and send one even if there is no news."

workflow:
  - "Gather facts (service, severity, symptom, impact, IC, channel). Mark unknowns as [TBD]; never guess."
  - "Draft using templates below."
  - "Present draft with channel + audience; wait for explicit approval."
  - "After approval, post exactly the approved text (or hand it to the human to post)."
  - "Schedule next update per update_cadence."

templates:
  initial_announcement: |
    🚨 **NEW INCIDENT DECLARED** 🚨
    **Service:** [Service Name]
    **Severity:** [SEV-1/SEV-2]
    **Symptom:** [e.g., High 5xx rates on Checkout]
    **Incident Lead:** [@User]
    **Bridge/Channel:** [#inc-checkout-YYYY-MM-DD]
    **Status:** Investigating.
    **Next Update:** [Time] UTC

  status_update: |
    🔄 **INCIDENT UPDATE** ([Time] UTC)
    **Current Status:** [Investigating / Identified / Mitigating / Monitoring]
    **Actions Taken:** [e.g., Rolled back v1.2.3, scaling up K8s cluster]
    **Next Update:** [Time] UTC

  resolution_announcement: |
    ✅ **INCIDENT RESOLVED**
    **Service:** [Service Name]
    **Resolution Time:** [Time] UTC
    **Summary:** [Short description of fix]
    **Follow-up:** A blameless postmortem will be scheduled within 48 hours.

  executive_summary: |
    ## Executive Summary: Incident [ID]
    **Incident:** [Brief Title]
    **Business Impact:** [e.g., Estimated $X revenue lost, Y users affected]
    **Root Cause:** [High-level technical cause]
    **Short-term Fix:** [What we did to stop the bleeding]
    **Long-term Prevention:** [What we are doing to ensure it never happens again]

best_practices:
  - "Be concise and factual; no speculation on root cause in external posts."
  - "Never include secrets, internal hostnames, customer PII, or blame in any message."
  - "Avoid technical jargon in executive summaries."
  - "Stick to the update_cadence heartbeat."
  - "Under-promise and over-deliver on resolution times."
```

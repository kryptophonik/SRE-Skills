---
name: sre-incident-communication
description: "Drafts incident announcements, status updates, resolution notices and executive summaries with severity-based cadence. Drafts only; posting to Slack, status pages, PagerDuty/Opsgenie or email requires explicit approval. Use when an incident update or stakeholder message is needed."
---

# SRE Incident Communication Templates

## Safety gates (REQUIRED)
Follow [sre-safety-gates](../sre-safety-gates/SKILL.md) for every step. In short: read-only diagnosis -> propose with risk/reversibility -> **explicit human approval** before any prod change, MCP write, or external post -> act -> verify -> stop and escalate if worse.
**Draft-only rule:** This skill produces drafts. Never post to Slack, status pages, email, or any external channel until a human explicitly approves the exact text and destination. Present each draft with: channel, audience, and text.

## Communication channels

- **Slack internal:** Primary coordination and high-frequency updates.
- **Slack external:** Customer-facing or broad internal announcements.
- **Status page:** Formal external status. (always requires approval from IC/comms lead)
- **Email:** Executive summaries and post-incident follow-ups.

## Update cadence

> internal / external; adjust to local policy

- **SEV-1:** Internal every 15 min; status page every 30 min
- **SEV-2:** Internal every 30 min; status page every 60 min
- **SEV-3:** Internal every 2-4 h or on status change; external only if customer-visible
- **SEV-4:** On status change only; no external post
- **Rule:** Always state the time of the next update, and send one even if there is no news.

## Workflow

- Gather facts (service, severity, symptom, impact, IC, channel). Mark unknowns as [TBD]; never guess.
- Draft using templates below.
- Present draft with channel + audience; wait for explicit approval.
- After approval, post exactly the approved text (or hand it to the human to post).
- Schedule next update per update_cadence.

## Templates

### Initial announcement

```markdown
🚨 **NEW INCIDENT DECLARED** 🚨
**Service:** [Service Name]
**Severity:** [SEV-1/SEV-2]
**Symptom:** [e.g., High 5xx rates on Checkout]
**Incident Lead:** [@User]
**Bridge/Channel:** [#inc-checkout-YYYY-MM-DD]
**Status:** Investigating.
**Next Update:** [Time] UTC
```

### Status update

```markdown
🔄 **INCIDENT UPDATE** ([Time] UTC)
**Current Status:** [Investigating / Identified / Mitigating / Monitoring]
**Actions Taken:** [e.g., Rolled back v1.2.3, scaling up K8s cluster]
**Next Update:** [Time] UTC
```

### Resolution announcement

```markdown
✅ **INCIDENT RESOLVED**
**Service:** [Service Name]
**Resolution Time:** [Time] UTC
**Summary:** [Short description of fix]
**Follow-up:** A blameless postmortem will be scheduled within 48 hours.
```

### Executive summary

```markdown
## Executive Summary: Incident [ID]
**Incident:** [Brief Title]
**Business Impact:** [e.g., Estimated $X revenue lost, Y users affected]
**Root Cause:** [High-level technical cause]
**Short-term Fix:** [What we did to stop the bleeding]
**Long-term Prevention:** [What we are doing to ensure it never happens again]
```

## Best practices

- Be concise and factual; no speculation on root cause in external posts.
- Never include secrets, internal hostnames, customer PII, or blame in any message.
- Avoid technical jargon in executive summaries.
- Stick to the update_cadence heartbeat.
- Under-promise and over-deliver on resolution times.

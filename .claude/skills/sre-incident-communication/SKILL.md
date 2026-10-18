---
name: sre-incident-communication
description: "Use when an incident update or stakeholder message is needed: announcements, status updates, resolution notices, executive summaries with severity cadence. Drafts only until approved."
---

# SRE Incident Communication Templates

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).
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

- Gather facts (service, severity, impact, symptom, start time, IC, channel). Mark unknowns as [TBD]; never guess.
- Draft using templates below.
- Present draft with channel + audience; wait for explicit approval.
- After approval, post exactly the approved text (or hand it to the human to post).
- Schedule next update per the Update cadence section.

## Templates

### Initial announcement (internal)

```markdown
🚨 **NEW INCIDENT DECLARED** 🚨
**Service:** [Service Name]
**Severity:** [SEV-1/SEV-2]
**Impact:** [Who is affected and how, e.g., ~20% of checkout requests fail in EU]
**Symptom:** [e.g., High 5xx rates on Checkout]
**Incident Commander (IC):** [@User]
**Bridge/Channel:** [#inc-checkout-YYYY-MM-DD]
**Status:** Investigating.
**Next Update:** [Time] UTC
```

### Status update

```markdown
🔄 **INCIDENT UPDATE** ([Time] UTC)
**Current Status:** [Investigating / Identified / Mitigating / Monitoring]
**Severity:** [SEV-1/SEV-2, note any change]
**Impact:** [Current impact; say if it has grown or shrunk]
**Actions Taken:** [e.g., Rolled back v1.2.3, scaling up K8s cluster]
**Next Update:** [Time] UTC
```

### External status page (customer-facing)

Only for the status page and customer channels. No names, IC, bridge or channel links, internal hostnames or internal causes.

```markdown
**[Investigating / Identified / Monitoring / Resolved]: [Customer-facing feature] [degraded / unavailable]**
**Impact:** [What customers see, e.g., Some customers can't complete checkout]
**Started:** [Time] UTC
**Workaround:** [Steps customers can take, or "None at this time"]
**Next update:** By [Time] UTC
```

### Resolution announcement

```markdown
✅ **INCIDENT RESOLVED**
**Service:** [Service Name]
**Resolution Time:** [Time] UTC
**Summary:** [Short description of fix]
**Follow-up:** A blameless postmortem will be scheduled within 48 hours of resolution.
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

## Output

For each draft, present:

- **Channel and audience:** internal Slack, external Slack, status page, or email.
- **Severity:** the current SEV, and any change since the last update.
- **Impact:** who is affected and how, with [TBD] for unknowns.
- **Text:** the filled template, using the external template for anything customers see.
- **Next update:** the time, per the Update cadence section.
- **Approval:** who must approve before it goes out (IC or comms lead). The draft stays unsent until then.

## Best practices

- Be concise and factual; no speculation on root cause in external posts.
- Never include secrets, internal hostnames, customer PII, or blame in any message.
- Avoid technical jargon in executive summaries.
- Stick to the Update cadence heartbeat.
- Under-promise and over-deliver on resolution times.

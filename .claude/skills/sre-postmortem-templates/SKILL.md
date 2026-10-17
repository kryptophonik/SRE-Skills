---
name: sre-postmortem-templates
description: "Use after an incident is resolved to draft or facilitate a blameless postmortem / incident review / RCA with a timeline from paging, monitoring and deploy history. Not for active incidents."
---

# Postmortem Templates

Blameless postmortem templates and facilitation guidance.

## Postmortem principles

- Blameless: Focus on process and systems, not individuals.
- Evidence-based: Use data, logs, and timelines.
- Action-oriented: Every postmortem must result in meaningful follow-up items.
- Timely: Conduct the review within 48 hours of resolution.

## Postmortem markdown template

```markdown
# Postmortem: [Incident Title]
**Date:** [YYYY-MM-DD]
**Severity:** [e.g., SEV-1]
**Incident Commander (IC):** [Name]

## 1. Summary
Give a 2-3 sentence overview of what happened and the impact.

## 2. Impact
- **User Impact:** [e.g., 50% of users in US-East could not log in]
- **Duration:** [e.g., 45 minutes]
- **SLO Impact:** [e.g., Consumed 15% of monthly error budget]

## 3. Timeline (UTC)
- **10:00:** Issue detected by [Alert Name]
- **10:05:** Incident bridge opened
- **10:15:** Root cause identified as [X]
- **10:30:** Mitigation [Y] applied
- **10:45:** Service restored

## 4. Root Cause Analysis (The Five Whys)
1. Why [Symptom]?
2. Why [X]?
...

## 5. What went well?
- [e.g., Monitoring detected the issue immediately]
- [e.g., Rollback was fast and successful]

## 6. Where did we get lucky?
- [e.g., Incident happened during business hours]

## 7. Action Items
- [Action] | [Owner] | [Status]
- [Preventative measure] | [Owner] | [Status]
```

## Facilitation tips

- Avoid 'why did you' and use 'how did the system'.
- Focus on the 'gap' between how the system was intended to work and how it actually worked.
- Ensure the most senior person in the room is the one modeling blameless behavior.

## Output

- Blameless postmortem doc; every action item has an owner, due date, and ticket

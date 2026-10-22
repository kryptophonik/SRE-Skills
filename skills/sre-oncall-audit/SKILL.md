---
name: sre-oncall-audit
description: "Use before rotation changes, after a migration, or quarterly: read-only audit of PagerDuty/Opsgenie schedules and escalation policies for coverage gaps, single-person layers, DST, loops, unreachable users."
---

# On-call Schedule and Escalation Audit

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). This skill is read-only. Editing schedules, adding overrides, changing policies and fixing contact methods are writes: propose them, then wait for approval.

Related: `sre-pagerduty-opsgenie` (adapter, scripts), `sre-oncall-handoff`; Opsgenie migration: [opsgenie-migration.md](../sre-pagerduty-opsgenie/references/opsgenie-migration.md). Requires `sre-pagerduty-opsgenie` installed for its scripts.

## Workflow

1. **Set the window:** default now to +14 d. Extend it to cover the next DST change.
2. **Run the automated checks (read-only):**
   - PagerDuty: `bash ../sre-pagerduty-opsgenie/scripts/pd_audit_schedules.sh --since <ISO8601> --until <ISO8601>` (gaps, single-person layers, policies with no service, empty levels, users with no contact methods or notification rules)
   - Opsgenie: `bash ../sre-pagerduty-opsgenie/scripts/og_oncall.sh` (schedules with nobody on call now)
   - Env: `PD_API_KEY` / `OG_API_KEY` (read-only keys), `PD_REGION` / `OG_REGION` = `us|eu`
   - Exit 2 (missing key, wrong region, unreachable API, HTTP error) means the audit didn't run: report it as not audited, never as "no findings".
3. **Run the manual checks** in [schedule-escalation-audit.md](../sre-pagerduty-opsgenie/references/schedule-escalation-audit.md): time zones/DST, loops and repeat counts, overlapping overrides, timeouts, and the Opsgenie equivalents.
4. **Rate each finding:** high means a service can page nobody; medium is single-person coverage or an unreachable user; low is cleanup.
5. **Draft fixes** as proposals with risk and rollback. Don't apply them.
6. **Stop** when every check has a finding or a pass, or if a key lacks read access (report the 403 and stop).

Thresholds (minimum layer size, timeouts) are team policy: state the ones you used.

## Output

```markdown
# On-call audit — [team/account placeholder] — [window UTC]
| # | Severity | Object (type/name/ID) | Finding | Proposed fix (WRITE, needs approval) |
|---|---|---|---|---|
```

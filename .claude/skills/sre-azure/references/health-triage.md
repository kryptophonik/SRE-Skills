# Azure health triage (read-only)

Reference for `sre-azure`. Follow its safety gates.

## Inputs
`<sub-id>`, `<rg>`, optionally `<resource-id>` and `<workspace-guid>`.

## Steps
1. `bash scripts/az-ro.sh --subscription <sub-id> account show -o table`. Confirm the subscription and tenant with the user.
2. `bash scripts/health-snapshot.sh --subscription <sub-id> --resource-group <rg> --offset 6h`
3. Follow [../azure/references/resource-health-activity-log-triage.md](resource-health-activity-log-triage.md) to tell platform causes from customer-initiated ones.
4. Run the KQL from [../azure/references/kql-cheatsheet.md](kql-cheatsheet.md):
   `bash scripts/az-ro.sh --subscription <sub-id> monitor log-analytics query -w <workspace-guid> --analytics-query "<kql>" --timespan PT1H`
5. Check permissions against [../azure/references/least-privilege-roles.md](least-privilege-roles.md).
6. Remediation is proposal only, using the gate in [../azure/references/write-command-risk.md](write-command-risk.md).

Sources:
- https://learn.microsoft.com/azure/service-health/resource-health-overview
- https://learn.microsoft.com/azure/azure-monitor/essentials/activity-log
- https://learn.microsoft.com/cli/azure/monitor/log-analytics#az-monitor-log-analytics-query
- https://learn.microsoft.com/azure/azure-monitor/logs/log-query-overview
- https://code.claude.com/docs/en/skills (layout: one folder per skill at `.claude/skills/<name>/SKILL.md`; script paths are relative to the skill folder)

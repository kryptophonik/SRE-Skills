---
name: sre-azure
description: "Use when the system runs on Azure: Resource Health, Azure Monitor, Log Analytics (KQL), AKS/VM/App Service status, Activity Log. Read-only roles via az CLI or Azure MCP; writes need approval."
---

# Azure

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-engineer`, `sre-k8s-triage` (AKS), `sre-dr-backup-test`, `sre-capacity-planning`, `sre-cloud-cost-review`, `sre-security-incident-triage`.

## Writes (never run without approval)

Any `create`, `update`, `delete`, `set`, `tag`, `restart`, `scale`, `start`/`stop`/`deallocate`, `swap`, `restore`, `failover`, role assignment (`az role assignment create/delete`), `az rest --method put|patch|post|delete`, `az vm run-command`, `az aks command invoke`, and `az aks get-credentials --admin` (banned; use user credentials).

**Inline gate for every WRITE below:** show the exact command, subscription, and target, then wait for an explicit "yes".

## Minimal roles

| Role | Scope | For |
|---|---|---|
| Reader | subscription / RG | status, metrics, activity log |
| Log Analytics Reader | workspace | KQL queries |
| Cost Management Reader | subscription | `sre-cloud-cost-review` |
| Azure Kubernetes Service Cluster User Role | cluster | `az aks get-credentials` (Reader is not enough) |

Never use Contributor/Owner for this pack.

## Always first

```bash
az account show --subscription <subscription-id> --query "{name:name, id:id, tenantId:tenantId}" -o table   # confirm with the user
# Do not run `az account set`: it changes the global CLI default for every shell.
```

Every command below also passes `--subscription <subscription-id>` so it cannot hit the wrong default.

## Health and status (read-only)

```bash
az resource list --resource-group <rg> --subscription <subscription-id> -o table
# Resource Health: 2022-10-01 is a valid stable version; 2025-05-01 is the newest
az rest --method get --url "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2022-10-01"
az aks show -g <rg> -n <cluster> --subscription <subscription-id> --query "{state:provisioningState, power:powerState.code}"
az vm get-instance-view -g <rg> -n <vm> --subscription <subscription-id> --query "instanceView.statuses[].displayStatus"
az webapp show -g <rg> -n <app> --subscription <subscription-id> --query state
```

AKS credentials (needs AKS Cluster User Role; writes a separate kubeconfig file, never merges into `~/.kube/config`; never `--admin`):

```bash
az aks get-credentials -g <rg> -n <cluster> --subscription <subscription-id> --file ./kubeconfig-<cluster>
```

## Azure Monitor and Log Analytics (read-only)

```bash
az monitor metrics alert list -g <rg> --subscription <subscription-id> -o table
az monitor metrics list --resource <resource-id> --metric "Percentage CPU" --interval PT5M --aggregation Average --offset 6h
az monitor log-analytics query -w <workspace-guid> --timespan PT1H \
  --analytics-query "AppRequests | where TimeGenerated > ago(1h) | summarize failures=countif(Success == false), total=count() by bin(TimeGenerated, 5m)"
az monitor activity-log list --resource-group <rg> --subscription <subscription-id> --offset 6h -o table
```

`-w` takes the workspace customer ID (GUID). `AppRequests` needs workspace-based Application Insights.

KQL (ContainerLogV2 schema; `=~` is case-insensitive because LogLevel casing varies by source):

```kql
ContainerLogV2
| where TimeGenerated > ago(30m) and LogLevel =~ "error"
| summarize count() by PodNamespace, ContainerName
| order by count_ desc
```

## Common remediations (WRITE — inline gate each)

| Action | Command | Risk | Reversible | Gate |
|---|---|---|---|---|
| Scale AKS node pool | `az aks nodepool scale -g <rg> --cluster-name <c> -n <pool> --node-count <n> --subscription <subscription-id>` | low | yes | Check `enableAutoScaling` first (autoscaler overrides). Show command + subscription + target; wait for "yes". |
| Preview slot swap | `az webapp deployment slot swap -g <rg> -n <app> --slot staging --target-slot production --action preview --subscription <subscription-id>` | med | yes | Applies production settings to staging; validate staging. Wait for "yes". |
| Complete slot swap | `az webapp deployment slot swap -g <rg> -n <app> --slot staging --target-slot production --action swap --subscription <subscription-id>` | **high** | yes | Touches production directly. Wait for "yes". |
| Roll back slot swap | `az webapp deployment slot swap -g <rg> -n <app> --slot staging --target-slot production --subscription <subscription-id>` (swap again) | high | yes | Use if post-swap checks fail. Wait for "yes". |
| Cancel previewed swap | `az webapp deployment slot swap -g <rg> -n <app> --slot staging --target-slot production --action reset --subscription <subscription-id>` | low | yes | Wait for "yes". |
| Restart VM | `az vm restart -g <rg> -n <vm> --subscription <subscription-id>` | med | no | Wait for "yes". |

## Bundled scripts and references

Every script requires `--subscription <subscription-id>` and calls through the read-only guard `scripts/az-ro.sh` (refuses non-read verbs; never runs `az account set`).

```bash
S=${CLAUDE_SKILL_DIR}/scripts
$S/az-ro.sh --subscription <subscription-id> account show -o table
$S/health-snapshot.sh --subscription <subscription-id> --resource-group <rg> --offset 6h
$S/aks-triage.sh --subscription <subscription-id> --resource-group <rg> --cluster <cluster>
```

- Workflows: [references/health-triage.md](references/health-triage.md) (first step in any Azure incident), [references/aks-triage.md](references/aks-triage.md)
- [references/kql-cheatsheet.md](references/kql-cheatsheet.md) · [references/resource-health-activity-log-triage.md](references/resource-health-activity-log-triage.md) · [references/least-privilege-roles.md](references/least-privilege-roles.md) · [references/write-command-risk.md](references/write-command-risk.md)

If neither the Azure MCP server nor the az CLI is available, output the commands for the human and stop.

## Output

- Subscription confirmed, findings with commands/KQL used, proposed actions with risk/reversibility and approval status

---
name: azure
description: "Azure adapter for SRE: subscription pinning, Resource Health, Azure Monitor metrics and alerts, Log Analytics (KQL), AKS/VM/App Service status, Activity Log. Uses the Azure CLI with least-privilege read roles or the Azure MCP server (pinned, --read-only, namespace-filtered). Use when the system runs on Azure. Every write needs explicit approval."
---

# Azure

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

Process skills: `sre-engineer`, `k8s-triage` (AKS), `dr-backup-test`, `capacity-planning`, `cloud-cost-review`, `security-incident-triage`.

## Writes (never run without approval)

Any `create`, `update`, `delete`, `set`, `tag`, `restart`, `scale`, `start`/`stop`/`deallocate`, `swap`, `restore`, `failover`, role assignment (`az role assignment create/delete`), `az rest --method put|patch|post|delete`, `az vm run-command`, `az aks command invoke`, and `az aks get-credentials --admin` (banned; use user credentials).

**Inline gate for every WRITE below:** show the exact command, subscription, and target, then wait for an explicit "yes".

## Minimal roles

| Role | Scope | For |
|---|---|---|
| Reader | subscription / RG | status, metrics, activity log |
| Log Analytics Reader | workspace | KQL queries |
| Cost Management Reader | subscription | `cloud-cost-review` |
| Azure Kubernetes Service Cluster User Role | cluster | `az aks get-credentials` (Reader is not enough) |

Never use Contributor/Owner for this pack.

## Always first

```bash
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table
# After the user confirms the target:
az account set --subscription <subscription-id>
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

## Output

- Subscription confirmed, findings with commands/KQL used, proposed actions with risk/reversibility and approval status

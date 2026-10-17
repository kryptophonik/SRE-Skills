---
name: azure
description: "Azure adapter for SRE: subscription sanity, Resource Health, Azure Monitor metrics and alerts, Log Analytics (KQL), AKS/VM/App Service/SQL status, Activity Log. Uses the Azure CLI with Reader role or the Azure MCP server started with --read-only. Use when the system runs on Azure. Writes need approval."
---

# Azure

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. `create`, `update`, `delete`, `restart`, `scale`, `start/stop`, and `deallocate` commands are writes.

Process skills: `sre-engineer`, `k8s-triage` (AKS), `dr-backup-test`, `capacity-planning`, `cloud-cost-review`, `security-incident-triage`.

## Always first

```bash
az account show --query "{name:name, id:id}" -o table
```

## Health and status

```bash
az resource list --resource-group <rg> -o table
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2022-10-01"
az aks show -g <rg> -n <cluster> --query "{state:provisioningState, power:powerState.code}"
az aks get-credentials -g <rg> -n <cluster>   # writes local kubeconfig only
az vm get-instance-view -g <rg> -n <vm> --query "instanceView.statuses[].displayStatus"
az webapp show -g <rg> -n <app> --query state
```

## Azure Monitor and Log Analytics

```bash
az monitor metrics alert list -g <rg> -o table
az monitor metrics list --resource <resource-id> --metric "Percentage CPU" --interval PT5M --aggregation Average
az monitor log-analytics query -w <workspace-guid> --analytics-query "AppRequests | where TimeGenerated > ago(1h) | summarize failures=countif(Success == false), total=count() by bin(TimeGenerated, 5m)"
az monitor activity-log list --resource-group <rg> --offset 6h -o table
```

KQL quick patterns:

```kql
ContainerLogV2
| where TimeGenerated > ago(30m) and LogLevel == "error"
| summarize count() by PodNamespace, ContainerName
| order by count_ desc
```

## Common remediations (WRITE — approval required)

| Action | Command | Risk | Reversible |
|---|---|---|---|
| Scale AKS node pool | `az aks nodepool scale -g <rg> --cluster-name <c> -n <pool> --node-count <n>` | low | yes |
| Swap App Service slot back | `az webapp deployment slot swap -g <rg> -n <app> --slot staging --target-slot production` | med | yes |
| Restart VM | `az vm restart -g <rg> -n <vm>` | med | no |

## Output

- Subscription confirmed, findings with commands/KQL used, proposed actions with risk/reversibility

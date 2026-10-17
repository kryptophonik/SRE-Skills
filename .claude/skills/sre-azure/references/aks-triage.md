# Azure AKS triage (read-only)

Reference for `sre-azure`. Follow its safety gates.
Any write goes through [../azure/references/write-command-risk.md](write-command-risk.md).

## Inputs
`<sub-id>`, `<rg>`, `<cluster>`, `<workspace-guid>`. Ask for any that are missing. Never assume the default subscription.

## Steps
1. Confirm the subscription: `scripts/az-ro.sh --subscription <sub-id> account show -o table`
2. Control plane and pools: `scripts/aks-triage.sh --subscription <sub-id> --resource-group <rg> --cluster <cluster>`
   - Container Insights is `addonProfiles.omsagent` (the CLI addon name is `monitoring`); Managed Prometheus is `azureMonitorProfile.metrics.enabled`.
   - `provisioningState` other than Succeeded, `powerState` Stopped, or pools at `maxCount` mean you should look closer.
3. Platform health and recent changes: `scripts/health-snapshot.sh --subscription <sub-id> --resource-group <rg>`. Also run it for the node resource group (`MC_*`).
4. Workload errors (ContainerLogV2 queries): see [../azure/references/kql-cheatsheet.md](kql-cheatsheet.md).
5. kubectl (optional) needs the AKS Cluster User Role and Kubernetes `view`.
   - `az aks get-credentials` is **not** run by the guard. If the user approves it, write to a separate file with `--file ./kubeconfig-<cluster>`, never use `--admin`, and stick to `kubectl get/describe/logs/top`.
6. Output: the subscription, the findings with the commands and queries used, and proposed actions with risk and reversibility. Proposed actions are not executed.

Sources:
- https://learn.microsoft.com/cli/azure/aks
- https://learn.microsoft.com/cli/azure/aks/nodepool
- https://learn.microsoft.com/azure/aks/cluster-autoscaler
- https://learn.microsoft.com/azure/aks/control-kubeconfig-access
- https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-logs-schema
- https://learn.microsoft.com/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes
- https://code.claude.com/docs/en/skills (layout: one folder per skill at `.claude/skills/<name>/SKILL.md`; script paths are relative to the skill folder)

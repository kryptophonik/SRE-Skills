# Least-privilege roles for read-only triage

Assign each role at the **narrowest scope** that works: resource, then resource group, then subscription.
Never use Owner, Contributor, or User Access Administrator for triage.

| Need | Built-in role | Scope | Notes |
|---|---|---|---|
| List and show resources, Resource Health, Activity Log, metrics | Reader | RG or subscription | Covers most of `scripts/`. |
| Log Analytics / KQL queries | Log Analytics Reader | Workspace | Reader also allows query on most workspaces; this role is explicit. |
| Metrics and alert rules only | Monitoring Reader | RG or subscription | Narrower than Reader for monitoring-only agents. |
| Cost data | Cost Management Reader | Subscription | Billing scopes need billing roles instead. |
| Backup jobs and items | Backup Reader | Recovery Services vault | |
| kubectl access to AKS (read) | Azure Kubernetes Service Cluster User Role + Kubernetes RBAC `view` (or Azure Kubernetes Service RBAC Reader) | Cluster | `az aks get-credentials` is a POST action that Reader lacks. Never use `--admin` or Cluster Admin for triage. |

Check before assigning (read-only):
`bash scripts/az-ro.sh --subscription <sub-id> role assignment list --assignee <principal-id> --all -o table`

Role assignment create or delete is a **write** and is out of scope for this skill.

Sources:
- https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
- https://learn.microsoft.com/azure/role-based-access-control/best-practices
- https://learn.microsoft.com/azure/azure-monitor/logs/manage-access
- https://learn.microsoft.com/azure/aks/control-kubeconfig-access
- https://learn.microsoft.com/azure/aks/manage-azure-rbac
- https://learn.microsoft.com/azure/backup/backup-rbac-rs-vault
- https://learn.microsoft.com/azure/cost-management-billing/costs/assign-access-acm-data

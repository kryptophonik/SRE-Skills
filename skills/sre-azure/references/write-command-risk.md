# Write commands: risk and confirmation gate

These commands are **outside** read-only mode, and `scripts/az-ro.sh` refuses them. Run one only after the gate below.

## Confirmation gate (use this wording verbatim)
> **WRITE ACTION: approval required**
> Subscription: `<sub-name> (<sub-id>)` · Resource group: `<rg>` · Target: `<resource-id>`
> Command: `<exact command, including --subscription>`
> Effect: `<what changes>` · Risk: `<low/med/high>` · Reversible: `<yes/no: how>`
> Rollback: `<exact rollback command or "none">`
> Reply **"approve <short-id>"** to run exactly this command. Any other reply cancels.

Rules:
- One command per approval.
- Re-confirm if anything changes.
- Never pass `--yes` or `--no-wait` unless the approver asks for it.
- Re-run `az account show` right before executing.

| Command (pattern) | Category | Risk | Reversible | Notes / source |
|---|---|---|---|---|
| `az vm restart\|stop\|start` | start/stop | med | partial | Interrupts the workload. https://learn.microsoft.com/cli/azure/vm |
| `az vm deallocate` | stop | high | yes (slow) | Check whether public IPs are Static before deallocating. https://learn.microsoft.com/cli/azure/vm#az-vm-deallocate |
| `az vm run-command invoke` | exec | high | no | Runs as root/SYSTEM on the VM. https://learn.microsoft.com/cli/azure/vm/run-command |
| `az aks nodepool scale` | scale | low–med | yes | Disable the cluster autoscaler on the pool before scaling manually. https://learn.microsoft.com/cli/azure/aks/nodepool#az-aks-nodepool-scale , https://learn.microsoft.com/azure/aks/cluster-autoscaler |
| `az aks stop\|start` | start/stop | high | yes (slow) | Whole cluster. https://learn.microsoft.com/azure/aks/start-stop-cluster |
| `az aks upgrade` | update | high | no | https://learn.microsoft.com/azure/aks/upgrade-cluster |
| `az aks command invoke` / `get-credentials --admin` | exec / credentials | high | n/a | Cluster-admin access. https://learn.microsoft.com/azure/aks/access-private-cluster |
| `az webapp restart\|stop` | start/stop | med | yes | https://learn.microsoft.com/cli/azure/webapp |
| `az webapp deployment slot swap --target-slot production` | swap | high | yes (swap back) | Use `--action preview` first. https://learn.microsoft.com/azure/app-service/deploy-staging-slots |
| `az webapp config appsettings set\|delete` | set | med | yes, if the old value was recorded | Adding, removing or editing app settings restarts the app. https://learn.microsoft.com/cli/azure/webapp/config/appsettings , https://learn.microsoft.com/azure/app-service/configure-common |
| `az resource tag` / `az tag update` | tag | low | yes | Can break tag-based policy or cost allocation. https://learn.microsoft.com/cli/azure/tag |
| `az role assignment create\|delete` | RBAC | high | yes | Least privilege only; never Owner. https://learn.microsoft.com/cli/azure/role/assignment |
| `az backup restore restore-disks\|restore-azurewl` | restore | high | cleanup needed | Restore to a **new isolated** target only. https://learn.microsoft.com/cli/azure/backup/restore |
| `az site-recovery ... failover` / `az sql failover-group set-primary` | failover | high | failback needed | https://learn.microsoft.com/cli/azure/sql/failover-group |
| any `create`, `update`, `delete` | create/update/delete | med–high | varies | `delete` is irreversible unless soft delete is on. |
| `az rest --method put\|patch\|post\|delete` | raw ARM write | high | varies | https://learn.microsoft.com/cli/azure/reference-index#az-rest |
| Azure MCP Server without `--read-only` | MCP write tools | high | varies | https://github.com/microsoft/mcp/blob/main/servers/Azure.Mcp.Server/docs/azmcp-commands.md |

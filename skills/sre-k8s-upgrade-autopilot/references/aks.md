# Azure Kubernetes Service (AKS): upgrade checks and gated steps

Checked against Microsoft Learn on 2026-10-18. AKS lists support dates by month only, and they change, so re-read the linked pages before quoting them. Placeholders: `<sub>` (subscription ID or name), `<rg>`, `<cluster>`, `<pool>`, `<region>`, `<ctx>`, `1.<T>`, `<version>` (a full patch version that `get-upgrades` offers).

## Support windows and cost (as of 2026-10-18)

- AKS supports three community minors (N to N-2), for about 12 months each. A minor that falls to N-3 moves to platform support, which gives a 60-day grace period to upgrade. Source: [supported versions](https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions).
- From June 1, 2027, AKS upgrades any cluster still on an unsupported minor once that grace period ends. These platform-initiated upgrades don't wait for your maintenance window, don't stop for deprecated-API use, and can override a PDB that blocks a drain (same source). Upgrading on your own schedule avoids this.
- End of life (community support) on the AKS calendar: 1.33 Jul 2026 (passed), 1.34 Nov 2026, 1.35 Mar 2027, 1.36 Jun 2027, 1.37 Oct 2027.
- Long-term support (LTS) adds a year to a minor. It needs the Premium tier, and an LTS cluster may skip minors when it moves to a newer LTS version. Source: [long-term support](https://learn.microsoft.com/en-us/azure/aks/long-term-support). The Azure retail price API lists a "Long Term Support" meter at $0.60 per hour and the Standard tier at $0.10 per hour for East US. Confirm for your region and agreement with the [retail prices API](https://prices.azure.com/api/retail/prices) or your Azure price sheet.

## Read-only checks

Current version, tier, auto-upgrade settings and state:

```bash
az aks show --subscription <sub> --resource-group <rg> --name <cluster> --query '{version:kubernetesVersion,current:currentKubernetesVersion,tier:sku.tier,support:supportPlan,autoUpgrade:autoUpgradeProfile,state:provisioningState}'
```

Upgrades AKS offers for this cluster:

```bash
az aks get-upgrades --subscription <sub> --resource-group <rg> --name <cluster> --output table
```

Versions offered in the region, with their support plans:

```bash
az aks get-versions --subscription <sub> --location <region> --output table
```

Node pools, versions and upgrade settings (surge, unavailable, drain timeout, soak):

```bash
az aks nodepool list --subscription <sub> --resource-group <rg> --cluster-name <cluster> --query '[].{name:name,mode:mode,version:orchestratorVersion,count:count,upgrade:upgradeSettings,state:provisioningState}' --output json
```

Maintenance windows, which apply to your own scheduled upgrades:

```bash
az aks maintenanceconfiguration list --subscription <sub> --resource-group <rg> --cluster-name <cluster>
```

## AKS-specific go/no-go items

- AKS checks for use of APIs that the target removes and blocks the upgrade if it finds any, based on recent API-server traffic. The preflight's metric and object checks should agree with that before you start. Source: [stop upgrades on API breaking changes](https://learn.microsoft.com/en-us/azure/aks/stop-cluster-upgrade-api-breaking-changes).
- `--control-plane-only` is refused while cluster auto-upgrade is enabled. If auto-upgrade is on, either schedule the work around it or turn it off as a separate approved change (step 0 below). Source: [upgrade the control plane](https://learn.microsoft.com/en-us/azure/aks/upgrade-aks-cluster).
- Surge nodes need compute quota and, with Azure CNI, free subnet IPs. Microsoft recommends a max surge of 33% for production pools. Source: [rolling node pool upgrades](https://learn.microsoft.com/en-us/azure/aks/upgrade-aks-node-pools-rolling).
- A drain that a PDB blocks fails the node after the pool's drain timeout (30 minutes by default) (same source).
- The control plane may be up to three minors ahead of node pools (from 1.28), but node pools can never be ahead of it.

## Gated plan

0. If the cluster auto-upgrade channel is set, record it so it can be restored afterwards. The channels are `none`, `patch`, `stable`, `rapid` and the legacy `node-image`; empty output means no channel is set and steps 0 and 4 can be skipped. Source: [cluster auto-upgrade](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster).

```bash
az aks show --subscription <sub> --resource-group <rg> --name <cluster> --query autoUpgradeProfile.upgradeChannel --output tsv
```

Then switch it off for the duration of the plan. This doesn't stop platform-initiated upgrades of unsupported versions.

**Gate: approval required.**
```bash
az aks update --subscription <sub> --resource-group <rg> --name <cluster> --auto-upgrade-channel none
```

1. Control plane only, one minor up. Don't run a plain `az aks upgrade` without `--control-plane-only` when you mean to go one pool at a time; it upgrades every pool in one go.

**Gate: approval required.**
```bash
az aks upgrade --subscription <sub> --resource-group <rg> --name <cluster> --kubernetes-version <version> --control-plane-only
```

Then verify: `bash scripts/verify-step.sh --context <ctx> --expect-control-plane 1.<T>`.

2. Node pools, one at a time, system pools first. Set the surge, drain timeout and soak for the pool if they aren't already what you want:

**Gate: approval required.**
```bash
az aks nodepool update --subscription <sub> --resource-group <rg> --cluster-name <cluster> --name <pool> --max-surge 33% --drain-timeout 30 --node-soak-duration 5
```

**Gate: approval required.**
```bash
az aks nodepool upgrade --subscription <sub> --resource-group <rg> --cluster-name <cluster> --name <pool> --kubernetes-version <version>
```

Then verify the pool before moving on: `bash scripts/verify-step.sh --context <ctx> --expect-pool <pool> --expect-nodes 1.<T>`. AKS labels nodes with `kubernetes.azure.com/agentpool`, which is what the script groups on.

3. Add-ons. AKS-managed add-ons move with the cluster. Self-managed controllers are upgraded through their own pipeline, with a verification run after each.

4. Once every pool is on 1.<T> and verified, restore the channel you recorded in step 0 (`<original-channel>` is that value, for example `stable` or `patch`):

**Gate: approval required.**
```bash
az aks update --subscription <sub> --resource-group <rg> --name <cluster> --auto-upgrade-channel <original-channel>
```

## Rollback limits

- The control plane can't be downgraded.
- A node pool can be rolled back to the Kubernetes version and node image it had before its last upgrade, within seven days of that upgrade, as long as AKS still supports that version. Rolling back reinstalls older images without newer security fixes. Source: [roll back a node pool](https://learn.microsoft.com/en-us/azure/aks/roll-back-node-pool-version).

```bash
az aks nodepool get-rollback-versions --subscription <sub> --resource-group <rg> --cluster-name <cluster> --name <pool>
```

**Gate: approval required.**
```bash
az aks nodepool rollback --subscription <sub> --resource-group <rg> --cluster-name <cluster> --name <pool>
```

- If node auto-upgrade or the node OS upgrade channel is on, AKS may move the pool forward again after a rollback. Check those settings first.
- Otherwise the way back is a new node pool on the previous minor (within skew) or a new cluster with the workloads moved across.

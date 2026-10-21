# Amazon EKS: upgrade checks and gated steps

Checked against AWS documentation on 2026-10-18. Dates and prices change, so re-read the linked pages before quoting them to anyone. Placeholders: `<cluster>`, `<region>`, `<nodegroup>`, `<ctx>`, `1.<T>` (target minor), `1.<C>` (current minor).

## Support windows and cost (as of 2026-10-18)

- A minor version gets 14 months of standard support after its EKS release, then 12 months of extended support. Extended support is on by default (cluster upgrade policy `EXTENDED`). After extended support ends, EKS upgrades the control plane by itself, with no notice of the exact time, and leaves managed and self-managed nodes behind. Source: [EKS version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).
- Price per cluster-hour: $0.10 in standard support, $0.60 in extended support. Source: [EKS pricing](https://aws.amazon.com/eks/pricing/).
- End of standard support on the EKS calendar for recent versions: 1.33 on 2026-07-29 (already in extended support), 1.34 on 2026-12-02, 1.35 on 2027-03-27, 1.36 on 2027-08-02, 1.37 on 2027-12-01. Read the live table for anything else.

A cluster that is in extended support costs six times the standard rate until it is upgraded, which is usually the business case for this work.

## Read-only checks (run before the plan)

Cluster version, platform version, upgrade policy and status:

```bash
aws eks describe-cluster --name <cluster> --region <region> --query 'cluster.{version:version,platform:platformVersion,policy:upgradePolicy.supportType,status:status,subnets:resourcesVpcConfig.subnetIds}'
```

Which versions EKS offers and their support dates:

```bash
aws eks describe-cluster-versions --region <region> --query 'clusterVersions[].{v:clusterVersion,status:status,endStandard:endOfStandardSupportDate,endExtended:endOfExtendedSupportDate}' --output table
```

Upgrade insights. EKS refreshes them every 24 hours and looks at deprecated-API use over a rolling 30-day window, so a fixed client can stay flagged for up to 30 days. Source: [cluster insights](https://docs.aws.amazon.com/eks/latest/userguide/cluster-insights.html), [view insights](https://docs.aws.amazon.com/eks/latest/userguide/view-cluster-insights.html).

```bash
aws eks list-insights --cluster-name <cluster> --region <region> --filter '{"categories":["UPGRADE_READINESS"]}'
```

```bash
aws eks describe-insight --cluster-name <cluster> --region <region> --id <insight-id>
```

The control-plane update needs up to five free IP addresses in the cluster subnets. Check them with the subnet IDs from `describe-cluster`:

```bash
aws ec2 describe-subnets --region <region> --subnet-ids <subnet-1> <subnet-2> --query 'Subnets[].{id:SubnetId,az:AvailabilityZone,free:AvailableIpAddressCount}' --output table
```

Node groups and their update settings:

```bash
aws eks list-nodegroups --cluster-name <cluster> --region <region>
```

```bash
aws eks describe-nodegroup --cluster-name <cluster> --nodegroup-name <nodegroup> --region <region> --query 'nodegroup.{version:version,release:releaseVersion,update:updateConfig,status:status,scaling:scalingConfig}'
```

EKS add-ons and the versions published for the target:

```bash
aws eks list-addons --cluster-name <cluster> --region <region>
```

```bash
aws eks describe-addon-versions --region <region> --kubernetes-version 1.<T> --addon-name vpc-cni --query 'addons[].addonVersions[].{version:addonVersion,default:compatibilities[0].defaultVersion}' --output table
```

Repeat the last command for `coredns`, `kube-proxy`, `aws-ebs-csi-driver` and any other add-on that `list-addons` returned.

## EKS-specific go/no-go items

- EKS asks for managed and Fargate nodes on the same minor as the control plane before a control-plane update. The preflight reports these nodes as WARN; on EKS treat them as no-go until fixed. Source: [update cluster](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html).
- Amazon VPC CNI older than 1.8.0 must be upgraded first (same source).
- Any upgrade insight in `ERROR` status is a no-go.
- Managed node group drains give up with `PodEvictionFailure` after 15 minutes per node if a PDB blocks eviction. Source: [node update phases](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-update-behavior.html).

## Gated plan

Run each step only after the operator approves it, and run `bash scripts/verify-step.sh` after each one (see SKILL.md). Once started, a control-plane update can't be paused or cancelled.

1. Control plane, one minor version up:

**Gate: approval required.**
```bash
aws eks update-cluster-version --name <cluster> --region <region> --kubernetes-version 1.<T>
```

Watch it with the update ID that command returns:

```bash
aws eks describe-update --name <cluster> --region <region> --update-id <update-id>
```

Then verify: `bash scripts/verify-step.sh --context <ctx> --expect-control-plane 1.<T>`.

2. Node groups, one at a time. Set how many nodes may be replaced at once first, if the current setting is more aggressive than you want:

**Gate: approval required.**
```bash
aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name <nodegroup> --region <region> --update-config maxUnavailable=1
```

**Gate: approval required.**
```bash
aws eks update-nodegroup-version --cluster-name <cluster> --nodegroup-name <nodegroup> --region <region> --kubernetes-version 1.<T>
```

Watch it, then verify the pool before the next one:

```bash
aws eks describe-update --name <cluster> --nodegroup-name <nodegroup> --region <region> --update-id <update-id>
```

Then: `bash scripts/verify-step.sh --context <ctx> --expect-pool <nodegroup> --expect-nodes 1.<T>`.

Self-managed nodes and Karpenter-managed nodes follow their own AMI or NodePool process. EKS Auto Mode replaces its nodes by itself after the control plane, honouring PDBs. Fargate pods keep their old kubelet until they are restarted through their controller.

3. EKS add-ons, one at a time, to a version that `describe-addon-versions` lists for 1.<T>. `PRESERVE` keeps your custom add-on settings:

**Gate: approval required.**
```bash
aws eks update-addon --cluster-name <cluster> --addon-name vpc-cni --region <region> --addon-version <version> --resolve-conflicts PRESERVE
```

Verify, then CoreDNS:

**Gate: approval required.**
```bash
aws eks update-addon --cluster-name <cluster> --addon-name coredns --region <region> --addon-version <version> --resolve-conflicts PRESERVE
```

Verify, then kube-proxy:

**Gate: approval required.**
```bash
aws eks update-addon --cluster-name <cluster> --addon-name kube-proxy --region <region> --addon-version <version> --resolve-conflicts PRESERVE
```

Verify after each add-on with `bash scripts/verify-step.sh --context <ctx>`. Other EKS add-ons that `list-addons` returned (for example `aws-ebs-csi-driver`) each get their own `update-addon` call, written out in the change plan with its own approval. Self-managed controllers (Cluster Autoscaler, AWS Load Balancer Controller, ingress, cert-manager) are upgraded through whatever pipeline owns them (Helm, Argo CD, Flux). Cluster Autoscaler should move to the latest release that matches 1.<T>.

## Rollback limits

- EKS now supports rolling the control plane back one minor version (N to N-1) within 7 days of an in-place upgrade. It refuses if the cluster was created at the current version, if it was upgraded again since, or if it was force-upgraded at the end of extended support. Rolling back into a version that is in extended support needs the cluster's upgrade policy set to `EXTENDED` first, and extended-support billing resumes. Node groups must be rolled back first, add-ons are not rolled back by EKS, and Fargate pods aren't rolled back. Read the rollback-readiness insights first. Source: [roll back a cluster](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html).
- Rollback readiness insights:

```bash
aws eks list-insights --cluster-name <cluster> --region <region> --filter '{"categories":["ROLLBACK_READINESS"]}'
```

- Roll back each node group on 1.<T> first, then the control plane. Each command needs its own approval:

**Gate: approval required.**
```bash
aws eks update-nodegroup-version --cluster-name <cluster> --nodegroup-name <nodegroup> --region <region> --kubernetes-version 1.<C>
```

**Gate: approval required.**
```bash
aws eks update-cluster-version --name <cluster> --region <region> --kubernetes-version 1.<C>
```

- After the 7-day window there is no downgrade. The way back is a blue/green node group on the old minor (while skew allows it) or a new cluster at 1.<C> with the workloads moved across. Plan for this before step 1.

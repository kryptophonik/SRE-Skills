---
name: sre-k8s-upgrade-autopilot
description: Plan a Kubernetes minor-version upgrade - scripted preflight, support-status check, go/no-go, gated EKS/GKE/AKS steps, verification after every step. Scripts tested on kind. Use for "upgrade our cluster to 1.xx".
---

# Kubernetes upgrade autopilot

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).


> **Before you use this:** run it on a non-production cluster first. The skill proposes changes; the operator approves every change before it runs, one command at a time. Vendor dates and prices below were checked on 2026-10-18 and change often, so re-read the linked pages.

Takes a cluster from one Kubernetes minor version to the next. A scripted preflight finds what would break (removed APIs, blocking PodDisruptionBudgets, broken webhooks, version skew, single replicas, local data) and gives a GO / GO-WITH-WARNINGS / NO-GO verdict as a report plus JSON. It also warns when the target minor is already past upstream end of life or into a provider's extended support. Then it walks through a gated plan (control plane, node pools one at a time, add-ons) with a scripted verification after every step and clear stop rules.

What is covered, and how well:
- The preflight and verify scripts only read through kubectl, so they run against any cluster kubectl can reach. They were tested end to end on kind.
- Gated upgrade commands exist for Amazon EKS, Google Kubernetes Engine and Azure Kubernetes Service. Those were checked against the vendors' docs, not run.
- kind and kubeadm clusters get the preflight and verification, but no upgrade commands: kind can't upgrade in place (recreate the cluster on a newer `kindest/node` image), and kubeadm clusters follow the upstream [kubeadm upgrade guide](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/). For their pools, use `verify-step.sh --expect-nodes` on its own, or `--pool-label <key>` (see step 4).

Run every command below from the skill folder (`cd <repo>/.claude/skills/sre-k8s-upgrade-autopilot`); the paths are relative to it. Output goes to a new directory under `${TMPDIR:-/tmp}`, never into the repo.

## When to use

- "Upgrade cluster X to 1.xx", "we're in EKS extended support", "AKS says our version is going out of support", "GKE paused our auto-upgrade".
- Before a provider's forced upgrade date, to find out what will break.
- One minor version per run. To go further, finish and verify one minor, then run again.

Not for: patch-only upgrades with no API changes (use the provider's normal patch flow), building a new cluster, or migrating between providers.

## Inputs

| Input | Example | Notes |
|---|---|---|
| kubeconfig context | `prod-eks-use1` | Required. The scripts refuse to run without `--context` and never use the current context. |
| Target minor | `1.33` | One minor above the control plane. |
| Provider target | EKS: cluster + `--region`; GKE: cluster + `--project` + `--location`; AKS: cluster + `--subscription` + `--resource-group` | Every provider command names its target explicitly. |
| Change window and owners | Tue 22:00 ET, payments team on call | Who approves, who owns PDBs and webhooks. |
| Identity | `references/rbac-preflight.yaml` | Recommended: run the preflight as this get/list-only identity (no Secrets, no ConfigMaps). Setting it up creates objects and a credential, so each step needs approval (below). |

### Identity setup (optional, recommended)

Running the preflight as an admin works, but every read then happens with admin rights. To run it as the least-privilege identity instead, take these steps. `<admin-ctx>` is a context allowed to create RBAC objects and ServiceAccount tokens.

1. Create the ClusterRole `upgrade-preflight-reader`, the ServiceAccount `kube-system/upgrade-preflight` and the ClusterRoleBinding between them. Review the file first.

**Gate: approval required.**
```bash
kubectl --context <admin-ctx> apply -f references/rbac-preflight.yaml
```

2. Create a short-lived token for that ServiceAccount and a kubeconfig that uses it. **This creates a credential.** The helper calls `kubectl create token` with `--duration` (10m to 24h, default 1h), writes the kubeconfig with mode 600 into a new mode-700 directory under `${TMPDIR:-/tmp}`, never prints the token, and prints the kubeconfig path. The context inside it is `upgrade-preflight-ro`.

**Gate: approval required.**
```bash
bash scripts/preflight-kubeconfig.sh --context <admin-ctx> --duration 1h
```

3. Run the preflight with that kubeconfig, for example `KUBECONFIG=<printed path> bash scripts/upgrade-preflight.sh --context upgrade-preflight-ro --target 1.<T>`.

4. When you're done, delete the directory holding the kubeconfig (`rm -r <printed directory>`); the token also expires on its own. To remove the identity:

**Gate: approval required.**
```bash
kubectl --context <admin-ctx> delete -f references/rbac-preflight.yaml
```

On a managed provider you can instead bind `upgrade-preflight-reader` to an existing IAM, Google or Entra ID group, and skip the token.

Tools: `kubectl`, `jq` 1.6 or later, bash 3.2 or later. Optional: `kubent` ([kube-no-trouble](https://github.com/doitintl/kube-no-trouble)) is used when installed. `pluto` ([Fairwinds pluto](https://github.com/FairwindsOps/pluto)) runs only with `--with-pluto`, because its resource scan lists Secrets and ConfigMaps.

## Steps

### 1. Preflight

```bash
bash scripts/upgrade-preflight.sh --context <ctx> --target 1.<T>
```

Writes `preflight.txt` (for people), `preflight.json` (for tickets and automation) and `raw/` (what was read, plus `raw/calls.log` listing every kubectl call it made) into a new directory, `${TMPDIR:-/tmp}/k8sup-<ctx>-1.<T>-<UTC timestamp>.<random>/` (mode 700) by default, and prints its path. The random suffix keeps two runs in the same second apart. A refused run (bad arguments, unknown context) creates nothing.

Options:

| Option | Effect |
|---|---|
| `--out <dir>` | Write the report, JSON and `raw/` to `<dir>` instead of the default temp directory. Keep it outside the repo: `raw/` holds namespace and pod names. |
| `--no-tools` | Don't run kubent even if it is installed (only the script's own checks run). |
| `--with-pluto` | Also run `pluto detect-api-resources`. Its scan lists every resource type, Secrets and ConfigMaps included (we saw this in the kind audit log), so use it only with the `references/rbac-preflight.yaml` identity, which can't read them. |
| `--fixtures <dir>` | Analyse a recorded `raw/` directory instead of calling the cluster. |
| `--pool-label <key>` | Group the "Node pools" section by this node label instead of the EKS, GKE, AKS or Karpenter labels (for kind, kubeadm or custom pools). It also works with `--fixtures` when the recording has node labels; older recordings without labels get an INFO saying it wasn't applied. |
| `--deprecated-traffic-checked` | You have confirmed (audit log or provider insights) that nothing calls the removed APIs any more. The cumulative deprecated-API counter is then reported as WARN instead of BLOCKER. See "Removed APIs, live traffic" below. |

To re-analyse a recorded run without touching the cluster:

```bash
bash scripts/upgrade-preflight.sh --context <ctx> --target 1.<T> --fixtures <dir>/raw
```

What it checks:

| Check | How | Severity |
|---|---|---|
| Version skew | Control plane vs target (one minor at a time); kubelets vs the [skew policy](https://kubernetes.io/releases/version-skew-policy/) after the upgrade | BLOCKER if the target skips a minor or a node would fall outside skew; WARN if nodes lag |
| Removed APIs, stored objects | For each API removed between now and the target ([deprecation guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/), copied into `references/removed-apis.json`), flags objects whose client still writes them through the old version: the manifest in the last-applied annotation uses it, or a field manager's only managedFields entries use it. The API server stores objects independently of the version they were written in and serves them through the new version after the upgrade. So once a manager has written an object through another version, its old managedFields entry is only stale field ownership. `kubectl get --show-managed-fields` keeps showing it, and it is harmless ([server-side apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)). One caveat: managers are matched by name, so two clients sharing a name (for example `kubectl-client-side-apply`) count as one. | BLOCKER while a client still writes the old version; INFO for stale managedFields entries |
| Removed APIs, live traffic | `apiserver_requested_deprecated_apis` from the API server's `/metrics` ([API warnings](https://kubernetes.io/blog/2020/09/03/warnings/)). **The counter is cumulative since each API server instance started**, so it stays set after you fix a client. To confirm the traffic has stopped, look for recent requests in the API server audit log: events carry the audit annotation `k8s.io/deprecated`; check `userAgent` and `requestReceivedTimestamp` after your fix. On managed providers, audit logs come from the provider's logging, and EKS insights, GKE deprecation insights or the AKS breaking-change check give the same evidence. On self-managed clusters an API server restart also resets the counter; on managed control planes you can't trigger one. Once you've confirmed, re-run with `--deprecated-traffic-checked` and keep the evidence with the change record. | BLOCKER for APIs removed by the target (merged into the object finding when one exists); WARN with `--deprecated-traffic-checked` |
| Removed APIs, tools | kubent when installed; pluto with `--with-pluto`. Findings for the same object from the object check, kubent and pluto are merged into one finding that lists its sources. | BLOCKER if the API is removed by the target, otherwise INFO |
| Support status | Target minor against `references/support-status.json`. It holds upstream end-of-life dates and the EKS, GKE and AKS calendars with their source URLs (checked 2026-10-18). Flags a target past upstream EOL, in EKS or GKE extended support (the extended charge, about $0.60 vs $0.10 per cluster-hour, continues after this hop), or past AKS community support (only LTS on the Premium tier keeps it; AKS may not offer it at all). Names the further hops needed. The path ends at the oldest minor with **more than 30 days** of support left, so it never stops at a minor that is about to expire (on 2026-10-18 that skips 1.34, whose upstream EOL is 2026-10-27). It also checks the **current** minor: if its provider's standard or extended support, or LTS on AKS, ends within 30 days, it warns with the date. At the end of extended support EKS and GKE upgrade the control plane themselves, and an EKS cluster upgraded that way can't be rolled back. Every warning that quotes a price says the date it was checked and links the official pricing page to confirm the current price. | WARN (INFO if the target isn't in the table) |
| PDBs | `disruptionsAllowed == 0`, `maxUnavailable: 0`, `minAvailable` equal to replicas or 100% ([PDBs](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)) | BLOCKER |
| Operator-owned PDBs | Same rules, for a PDB whose controller is not an `apps/` object (for example a CloudNativePG `Cluster`). Such operators keep the PDB on purpose and switch the primary to another instance before the drain continues ([CloudNativePG upgrade guide](https://cloudnative-pg.io/documentation/1.24/kubernetes_upgrade/)). The fix never edits or disables the operator's PDB. | WARN while the workload has 2+ instances (confirm replicas have caught up); BLOCKER with "add a replica" when it has only 1 |
| Zonal storage | Pods grouped by their controller (StatefulSet, or an operator kind such as a CloudNativePG `Cluster`) whose PersistentVolumes are pinned to a zone (`topology.kubernetes.io/zone` node affinity or the legacy `failure-domain.beta.kubernetes.io/zone` label), naming the zones ([PV node affinity](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)) | WARN: confirm the pool has surge or replacement capacity in each zone |
| Single replicas | Deployments and StatefulSets with 1 replica | WARN |
| Bare pods, local data | Pods with no controller; emptyDir and hostPath users ([safe drain](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)) | WARN |
| Webhooks | `failurePolicy: Fail` webhooks whose Service is missing or has no ready endpoints ([admission webhooks](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)) | BLOCKER |
| Aggregated APIs | APIServices not Available | BLOCKER |
| Add-ons | Known controllers (CNI, CoreDNS, kube-proxy, Cluster Autoscaler, ingress, cert-manager and others) with their image versions, to check against the target. CoreDNS at the version kubeadm ships with the target (from `references/support-status.json`) is INFO, because that pairing is the upstream default. | INFO / WARN |
| Provider | Detected from the server version and node `providerID`; findings point to `references/eks.md`, `gke.md` or `aks.md` | INFO |

Exit codes: 0 GO or GO-WITH-WARNINGS, 1 NO-GO, 2 usage error or refused, 3 cluster unreachable.

Then run the provider's own read-only checks from the matching reference: [EKS](references/eks.md), [GKE](references/gke.md), [AKS](references/aks.md). These cover upgrade insights and readiness, the versions on offer, support dates and cost, and node pool settings.

### 2. Go / no-go

GO only when all of these hold:

1. The preflight verdict is GO or GO-WITH-WARNINGS, and each WARN has an owner who accepted it in writing.
2. The provider's readiness view agrees: no EKS upgrade insight in ERROR, no unresolved GKE deprecation insight, `az aks get-upgrades` offers the target.
3. The target is exactly one minor above the control plane (AKS LTS clusters may skip; see the AKS reference).
4. A rollback route is written down before step 1, using the limits in the provider reference:
   - EKS allows a control-plane rollback within 7 days. Rolling back into a version that is in extended support first needs the cluster's upgrade policy set to `EXTENDED`, and extended charges resume ([EKS rollback](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html)).
   - GKE allows one only during the soak of a two-step upgrade, which exists only for targets 1.33 and later. **A 1.32 or older target has no GKE control-plane rollback** ([GKE manual upgrades](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster)).
   - AKS has no control-plane rollback.
5. Any support-status WARN is understood. The team has accepted that the target is only a stepping stone, budgeted for the extended-support rate where it applies, and confirmed the provider still offers the target.
6. Workload owners for every BLOCKER fixed and every WARN accepted are reachable during the window.

Otherwise it's NO-GO. Hand the findings table to the owners and re-run the preflight once they've fixed them.

### 3. Gated plan

The provider reference has the exact commands. Every change is one command, in its own block, with `**Gate: approval required.**` above it. The order is always:

1. **Hold off automatic upgrades** if the provider could start one mid-plan: a GKE maintenance exclusion, or the AKS auto-upgrade channel set to `none` after recording its current value. This is a separate approved change, undone by its own approved step once the plan is finished.
2. **Control plane**, one minor. Verify.
3. **Node pools, one at a time**, system pool first, with conservative surge (EKS `maxUnavailable=1`, GKE `max-surge 1 / max-unavailable 0`, AKS `--max-surge 33%`). Verify after each pool before starting the next.
4. **Add-ons**, one at a time: provider-managed add-ons to the version the provider lists for the target, then self-managed controllers through their owner's pipeline. Verify after each.
5. Re-run the preflight against the same target to confirm nothing new turned up, and record the result.

### 4. Verification after every step

```bash
bash scripts/verify-step.sh --context <ctx> --expect-control-plane 1.<T>
```

```bash
bash scripts/verify-step.sh --context <ctx> --expect-nodes 1.<T> --expect-pool <pool>
```

`--expect-nodes` on its own checks every node's kubelet in the cluster, which is the simplest check for kind or kubeadm once all nodes are done. If your nodes carry no EKS, GKE, AKS or Karpenter pool label, name the label that identifies a pool, for example `--pool-label node.example.com/pool`. `--pool-label` also works with `--fixtures` when the recorded nodes carry labels; otherwise the script says it couldn't apply it. The default output directory is `${TMPDIR:-/tmp}/k8sup-verify-<ctx>-<UTC timestamp>.<random>/`.

Before starting the next pool, also check by hand that every database on the cluster (operator-managed or not) still has a primary and that its replicas aren't lagging, using the database's own tooling (for example `kubectl cnpg status <cluster> -n <ns> --context <ctx>` for CloudNativePG, or the replication lag metrics you already alert on). `kubectl cnpg status` needs the CloudNativePG kubectl plugin and permissions beyond the preflight role, so run it as the database operator's or an admin identity, not the preflight identity. If a primary is missing or lag is growing, treat it as a failed verification.

The script checks that the control plane is on the expected minor, every node is Ready and schedulable, the named pool's kubelets are on the expected minor, kube-system Deployments and DaemonSets are fully ready, aggregated APIServices are Available, and that no pods are Pending, Failed, crash-looping or failing to pull images. It writes `verify.json` and exits 0 (PASS) or 1 (FAIL). The pool is matched on the provider's node label (`eks.amazonaws.com/nodegroup`, `cloud.google.com/gke-nodepool`, `kubernetes.azure.com/agentpool`, `karpenter.sh/nodepool`) unless `--pool-label` names another. Also check your own service SLOs (error rate, latency) for the same window.

## Skill-specific gates
- Both scripts send kubectl only through a restricted wrapper. In `upgrade-preflight.sh` it allows `get`, `version`, `api-versions` and `api-resources`; in `verify-step.sh` it allows only `get` and `version`. Any other verb exits 2 without reaching kubectl. The tests check this both statically and with a stub kubectl. On kind, the API server audit log for the preflight identity showed only `get` and `list` requests and no Secret or ConfigMap reads (see the table below). kubent and pluto, when used, make their own list calls.
- Every change in the provider references sits in its own block with `**Gate: approval required.**` directly above it, one command per block. Nothing runs without the operator's approval for that exact command.
- Commands the skill never puts in a plan, such as PDB-bypassing drains, force-upgrade flags, ending GKE's rollback window early, or all-pools-at-once upgrades, are listed in [destructive-commands.md](references/destructive-commands.md) with what to do instead.
- No credentials are passed on the command line. The scripts use the kubeconfig context you name. The only step that creates a credential is the gated `scripts/preflight-kubeconfig.sh` run in Identity setup. It makes a short-lived token, writes it only to a mode-600 file, and never prints it. The kind test builds its token kubeconfig the same way with `umask 077`, in a temp dir that it deletes afterwards.
- Script output goes to a new directory under `${TMPDIR:-/tmp}` (mode 700), never into the repo. The test suite checks that it leaves the skill tree unchanged and that refused runs create nothing.

## Output

- `preflight.txt` and `preflight.json`: verdict, summary counts, findings (severity, check, object, detail, fix), node pools, add-ons and provider.
- `verify.json` for each step: result and per-check PASS/FAIL with detail.
- A change record built from the above: target, approvals with times, each step's verify result, and the rollback route.

## Tested vs docs-only

| Part | Status | Where |
|---|---|---|
| `upgrade-preflight.sh` end to end | Tested | kind v0.31.0, `kindest/node:v1.31.14` pinned by digest, target 1.32, run as the get/list-only ServiceAccount from `references/rbac-preflight.yaml`. Seeded with a blocking PDB, a single-replica Deployment, a FlowSchema written with `flowcontrol.apiserver.k8s.io/v1beta3` (removed in 1.32), a `Fail` webhook pointing at a missing Service, and a bare pod with emptyDir. All found; verdict NO-GO. |
| Call set (get/list only, no Secrets or ConfigMaps) | Tested | Same kind run: `raw/calls.log` plus the API server audit log, checked by `tests/run-tests.sh --kind` |
| Removed-API judgement after a fix (stale managedFields, cumulative metric, merged sources) | Tested offline | `tests/fixtures/kind-reapplied-v1`: the FlowSchema re-applied as v1 with its leftover v1beta3 managedFields entry is INFO, not BLOCKER. The cumulative metric still blocks until `--deprecated-traffic-checked`. The original kind recording gives 4 deduplicated blockers. The re-apply scenario matches what Cold Tester saw live on kind, but the fixed rule hasn't been re-run live. |
| Support-status warnings | Tested offline; dates docs-only | EKS 1.32 (extended support), AKS after community EOL (pinned date), AKS 1.34 ending within 30 days, GKE quarter-only dates, kind 1.32 past upstream EOL. The hop path skips 1.34. The current minor's deadline is tested on a GKE 1.31 fixture (extended support ends 2026-10-22) and an EKS 1.31 fixture: not flagged on 2026-10-18, flagged on a pinned 2026-11-01. Price warnings are tested for the checked date and pricing URL. Dates come from the sources listed in `references/support-status.json`. |
| `preflight-kubeconfig.sh` | Tested offline with a stub kubectl | Refusals, `--duration` range, token never printed, file modes 600/700, CA kept. It hasn't run against a live API server yet; the kind test still builds its kubeconfig inline. |
| Output location and hygiene | Tested offline | Default under `$TMPDIR` via `mktemp -d`; two runs in the same second (clock pinned with a stub) get separate directories; nothing written to the cwd; refused runs create nothing; skill tree unchanged after the suite |
| Operator-owned PDB rule (WARN with 2+ instances, BLOCKER with 1) | Tested offline only | `tests/fixtures/operator-pdb` (CloudNativePG-style `Cluster` owners, 3 instances and 1 instance). Not run against a real operator. |
| Zonal-storage rule | Tested | Same kind run: a StatefulSet bound to one PV with zone node affinity and one with only the legacy zone label; both zones named. Offline: fixture (StatefulSets and CloudNativePG-owned pods) plus a stub-kubectl test of the PV zone parsing. |
| `verify-step.sh` | Tested | Same kind cluster (PASS on a healthy cluster, FAIL on a wrong expected version and on an image-pull failure), plus a recorded mid-upgrade fixture. `--expect-nodes` alone and `--pool-label` are tested offline (stub kubectl, and fixtures with and without node labels). The preflight's `--pool-label` is tested on fixtures only. |
| kubent integration | Tested | Same kind run. Under the least-privilege role kubent gets 403 on some resource types, so its coverage is partial there. |
| pluto integration | Tested (opt-in) | Same kind run, which is how we saw it reading Secrets and ConfigMaps and made it opt-in |
| Offline analysis | Tested | `tests/run-tests.sh` on bash 5.2 and bash 3.2.57: recorded kind fixtures, synthetic EKS (node skew, old add-ons, blocking PDBs, broken webhooks), AKS (partial data) and GKE (clean) fixtures, argument refusals, kubectl-wrapper refusals |
| Provider detection and node-pool grouping for EKS, GKE, AKS | Tested on synthetic fixtures only | `tests/fixtures/eks-skew`, `gke-clean`, `aks-partial` |
| EKS commands, insights, rollback | Docs-only | [versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [update cluster](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html), [rollback](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html), [insights](https://docs.aws.amazon.com/eks/latest/userguide/cluster-insights.html), [view insights](https://docs.aws.amazon.com/eks/latest/userguide/view-cluster-insights.html), [node update behaviour](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-update-behavior.html), [update node group](https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html), [update add-on](https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html), [pricing](https://aws.amazon.com/eks/pricing/) |
| GKE commands, insights, two-step upgrade | Docs-only | [release schedule](https://cloud.google.com/kubernetes-engine/docs/release-schedule), [pricing](https://cloud.google.com/kubernetes-engine/pricing), [deprecation insights](https://docs.cloud.google.com/kubernetes-engine/docs/deprecations/viewing-deprecation-insights-and-recommendations), [manual upgrades](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster), [node upgrade strategies](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/node-pool-upgrade-strategies), [maintenance windows](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/maintenance-windows-and-exclusions) |
| AKS commands, breaking-change check, node pool rollback | Docs-only | [supported versions](https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions), [LTS](https://learn.microsoft.com/en-us/azure/aks/long-term-support), [upgrade cluster](https://learn.microsoft.com/en-us/azure/aks/upgrade-aks-cluster), [rolling node pool upgrades](https://learn.microsoft.com/en-us/azure/aks/upgrade-aks-node-pools-rolling), [API breaking changes](https://learn.microsoft.com/en-us/azure/aks/stop-cluster-upgrade-api-breaking-changes), [node pool rollback](https://learn.microsoft.com/en-us/azure/aks/roll-back-node-pool-version), [cluster auto-upgrade](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster), [retail prices API](https://prices.azure.com/api/retail/prices) |
| Removed-API catalogue (1.22-1.32) | Docs-only, checked 2026-10-18 | [Kubernetes deprecation guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) |
| A real upgrade (control plane and nodes actually moving) | Not tested | kind can't upgrade in place. The first real run should be on a non-production managed cluster. |
| Known limit: manager that goes back to the old version | Not covered | Only each managedFields entry's `manager` and `apiVersion` are captured, not `operation` or `time`. So a manager that wrote v1 once and later went back to writing the removed version through Update is graded INFO (stale) instead of BLOCKER. The cumulative deprecated-API counter still blocks until `--deprecated-traffic-checked`, so confirm in the audit log before using that flag. |
| Known limit: confirming deprecated-API traffic on kind or kubeadm | Docs-only | These clusters have no audit policy by default, so the audit evidence that `--deprecated-traffic-checked` asks for doesn't exist. Either enable an [audit policy](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/) and wait for fresh traffic, or restart the API server (on kubeadm, the kube-apiserver static pod) to reset the counter, then re-run the preflight. The Cold Tester live run on kind used the flag for test purposes only. |
| kind or kubeadm upgrade commands | Not provided | Only the preflight and verification apply; see the coverage note at the top. |

Run the tests: `bash tests/run-tests.sh` (offline) or `bash tests/run-tests.sh --kind` (needs Docker, kind and kubectl; creates and deletes a cluster named `k8sup-preflight-test`).

## Stop rules

Stop the plan, don't run the next gated step, and report to the operator when any of these happens:

- `verify-step.sh` returns FAIL (exit 1), or exit 3 (cluster unreachable), after any step.
- A database loses its primary or its replicas fall behind during the plan.
- A node drain is blocked by a PDB (EKS `PodEvictionFailure`, an AKS drain timeout, a GKE pool still working after an hour). Don't bypass it. The workload owner fixes capacity or the PDB.
- A removed API is still in use: a removed-API BLOCKER in the preflight, or the provider's breaking-change check rejecting the upgrade. The deprecated-API counter alone stops the plan until the audit log or provider insights show no requests after the fix (then use `--deprecated-traffic-checked`). Stale managedFields entries (INFO) don't stop it.
- A provider operation fails or reports a status other than success.
- The change window ends. Leave the cluster in a verified, within-skew state; a control plane one minor ahead of its nodes is a supported state to pause in.

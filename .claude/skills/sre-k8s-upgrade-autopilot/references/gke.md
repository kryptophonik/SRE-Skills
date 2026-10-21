# Google Kubernetes Engine (GKE): upgrade checks and gated steps

Checked against Google Cloud documentation on 2026-10-18. The release schedule gives estimates that Google updates monthly, so re-read the linked pages before quoting dates. Placeholders: `<cluster>`, `<project>`, `<location>` (a region for regional clusters, the exact zone for zonal ones), `<pool>`, `<ctx>`, `1.<T>`, `<version>` (a full GKE patch version such as the one `get-server-config` lists).

## Support windows and cost (as of 2026-10-18)

- GKE upgrades control planes and, by default, Standard node pools automatically. Each release channel (Rapid, Regular, Stable, Extended) has its own available and auto-upgrade dates. Leaving a cluster out of any channel is deprecated: from June 14, 2027 GKE moves remaining clusters to Stable. Source: [release schedule](https://docs.cloud.google.com/kubernetes-engine/docs/release-schedule).
- End of standard support on the schedule for recent minors: 1.33 on 2026-08-12, 1.34 on 2027-01-25, 1.35 on 2027-04-11, 1.36 on 2027-08-09. 1.37 is listed only as 2027-Q4. On the Extended channel a minor stays supported until its end of extended support (for example 1.35 until 2028-02-11).
- Every cluster pays a $0.10 per cluster-hour management fee. A cluster on the Extended channel whose minor is past standard support pays another $0.50, for $0.60 per cluster-hour in total. Source: [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing).
- When GKE sees a cluster calling an API that the next minor removes, it pauses automatic upgrades to that minor and raises a deprecation insight. Source: [deprecation insights](https://docs.cloud.google.com/kubernetes-engine/docs/deprecations/viewing-deprecation-insights-and-recommendations).

## Read-only checks

Current version and channel:

```bash
gcloud container clusters describe <cluster> --project <project> --location <location> --format='yaml(currentMasterVersion,currentNodeVersion,releaseChannel,maintenancePolicy)'
```

Versions on offer at that location:

```bash
gcloud container get-server-config --project <project> --location <location> --format='yaml(channels,validMasterVersions,validNodeVersions)'
```

Deprecation insights. GKE creates these from API calls that clients actually made, not from object manifests, so they complement the preflight's object scan.

```bash
gcloud recommender insights list --project <project> --location <location> --insight-type=google.container.DiagnosisInsight --format=yaml
```

```bash
gcloud recommender recommendations list --project <project> --location <location> --recommender=google.container.DiagnosisRecommender --format=yaml
```

Node pools, their versions and upgrade strategy (surge or blue-green):

```bash
gcloud container node-pools list --cluster <cluster> --project <project> --location <location>
```

```bash
gcloud container node-pools describe <pool> --cluster <cluster> --project <project> --location <location> --format='yaml(version,upgradeSettings,management)'
```

Recent upgrade operations:

```bash
gcloud container operations list --project <project> --location <location> --filter='targetLink~<cluster>'
```

## GKE-specific go/no-go items

- During node upgrades GKE honours PDBs and termination grace for at most 1 hour per node, then deletes the pods anyway. That includes PDBs set to `maxUnavailable: 0` or `minAvailable: 100%`. So a blocking PDB on GKE means an outage after an hour, not a stuck upgrade. Treat it as a no-go. Source: [manual upgrades](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster).
- Surge upgrades create extra nodes, so check Compute Engine quota for them. On Spot VM pools GKE ignores the surge settings and drains old nodes straight away. Source: [node upgrade strategies](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/node-pool-upgrade-strategies).
- While a two-step control-plane upgrade is soaking, GKE won't let you move nodes past the emulated (old) minor, and it pauses its own automatic upgrades.
- Labels added to individual nodes with kubectl can be lost when nodes are recreated. Set them on the node pool instead.

## Gated plan

1. Stop automatic upgrades from racing the plan with a cluster maintenance exclusion. Exclusions only hold back GKE's automatic upgrades; the manual upgrades below still run. Scope values are `no_upgrades`, `no_minor_upgrades` and `no_minor_or_node_upgrades`. `no_minor_or_node_upgrades` is the usual choice for a planned upgrade on a release channel, because it still lets patches through. A cluster with no release channel accepts only `no_upgrades`, which may last up to 90 days (Google suggests staying under 30). Times are RFC 3339 with an offset. Source: [maintenance windows and exclusions](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/maintenance-windows-and-exclusions).

Record the current maintenance policy first:

```bash
gcloud container clusters describe <cluster> --project <project> --location <location> --format='yaml(maintenancePolicy)'
```

Replace `<start-rfc3339>` and `<end-rfc3339>` with RFC 3339 timestamps that bracket the whole plan, for example `2026-11-01T00:00:00Z` and `2026-11-08T00:00:00Z`.

**Gate: approval required.**
```bash
gcloud container clusters update <cluster> --project <project> --location <location> --add-maintenance-exclusion-name k8s-upgrade-1-<T> --add-maintenance-exclusion-start <start-rfc3339> --add-maintenance-exclusion-end <end-rfc3339> --add-maintenance-exclusion-scope no_minor_or_node_upgrades
```

2. Control plane. For targets 1.33 and later, prefer the two-step upgrade with rollback safety. GKE first upgrades the binary while still emulating the old minor's APIs, then waits for a soak period of 6 hours to 7 days. During the soak you can roll back to the previous minor.

**Gate: approval required.**
```bash
gcloud beta container clusters upgrade <cluster> --project <project> --location <location> --master --cluster-version <version> --control-plane-soak-duration 24h
```

The one-step alternative has no minor-version rollback:

**Gate: approval required.**
```bash
gcloud container clusters upgrade <cluster> --project <project> --location <location> --master --cluster-version <version>
```

Verify: `bash scripts/verify-step.sh --context <ctx> --expect-control-plane 1.<T>`. During a two-step soak the API still behaves like the old minor, so APIs removed in 1.<T> keep working until the soak ends.

3. Node pools, one at a time (Standard clusters only; Autopilot upgrades nodes itself). Set conservative surge first:

**Gate: approval required.**
```bash
gcloud container node-pools update <pool> --cluster <cluster> --project <project> --location <location> --max-surge-upgrade=1 --max-unavailable-upgrade=0
```

**Gate: approval required.**
```bash
gcloud container clusters upgrade <cluster> --project <project> --location <location> --node-pool=<pool> --cluster-version <version>
```

Verify the pool before the next one: `bash scripts/verify-step.sh --context <ctx> --expect-pool <pool> --expect-nodes 1.<T>`. For pools where you want a fast way back, switch them to blue-green upgrades, which keep the old nodes until a soak period ends.

4. Add-ons. GKE-managed components move with the control plane and nodes. Self-managed controllers are upgraded through their own pipeline, with a verification run after each.

5. Once every pool is on 1.<T> and verified, remove the exclusion you added in step 1 so that GKE's automatic patching resumes:

**Gate: approval required.**
```bash
gcloud container clusters update <cluster> --project <project> --location <location> --remove-maintenance-exclusion k8s-upgrade-1-<T>
```

## Rollback limits

- **Targets of 1.32 or older have no control-plane rollback.** The two-step upgrade, and its soak-time rollback, exists only for targets 1.33 and later. Write the forward-fix plan down instead. Source: [manual upgrades](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster).
- Control plane: you can roll back to the previous minor only during the soak of a two-step upgrade, and only while `rollbackSafeUpgradeStatus` is present in the cluster's upgrade info. Use the exact previous patch version:

**Gate: approval required.**
```bash
gcloud container clusters upgrade <cluster> --project <project> --location <location> --master --cluster-version <previous-version>
```

- Do not end the soak early with `complete-control-plane-upgrade` unless rollback is no longer needed; see `destructive-commands.md`.
- After the soak, or after a one-step upgrade, a control-plane minor downgrade isn't possible. A patch downgrade within the same minor is possible if the earlier patch is still offered; set a maintenance exclusion first so GKE doesn't upgrade it straight back.
- Node pools: a partially completed pool upgrade (cancelled, failed, or cut off by a maintenance window) can be rolled back with the command below. A completed pool upgrade can't be rolled back but can be downgraded by running the node-pool upgrade command with the earlier version, as long as nodes stay no more than two minors behind the control plane.

**Gate: approval required.**
```bash
gcloud container node-pools rollback <pool> --cluster <cluster> --project <project> --location <location>
```

- Otherwise the way back is a blue/green node pool or a new cluster at the old minor with the workloads moved across.

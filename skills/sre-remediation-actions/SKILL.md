---
name: sre-remediation-actions
description: "Reference of gated recovery procedures (rollback, scale, restart, failover) with risk/reversibility labels, evidence capture and dry-run first. Loaded by sre-engineer before any remediation."
user-invocable: false
---

# SRE Remediation Actions

Every `kubectl`/`helm` command below carries `--context <ctx> -n <ns>` (`--kube-context <ctx>` for helm) literally; never rely on the current context. Never `delete --force --grace-period=0`, `delete --all`, or patch away finalizers without SRE approval.

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).
**Legend:** `risk` = low / med / high blast radius. `reversible` = yes / no (can be cleanly undone without data loss).

For Kubernetes writes, tell the user to run `/sre-k8s-safe-remediation` (Claude plugin install: `/sre:sre-k8s-safe-remediation`; Codex: `$sre-k8s-safe-remediation`) (manual-only gated workflow).

## Remediation hierarchy

### Priority order

1. Capture evidence (logs, heap dumps, rollout history) — always first, read-only
2. Rollback recent changes (if correlated with onset)
3. Scale resources
4. Disable non-critical features / degraded mode
5. Restart (only after evidence captured; restarts destroy state)
6. Failover to backup (high risk — last resort)

## Evidence capture

> read-only; do BEFORE any restart, delete, or rollback

### Kubernetes

```bash
kubectl --context <ctx> rollout history deployment/<name> -n <ns>
kubectl --context <ctx> describe deployment/<name> -n <ns>
kubectl --context <ctx> events -n <ns> --types=Warning | tail -n 50
kubectl --context <ctx> logs <pod> -n <ns> --all-containers --timestamps > <pod>.log   # may contain secrets/PII: keep out of repos, redact
kubectl --context <ctx> logs <pod> -n <ns> --all-containers --previous > <pod>.prev.log   # errors if no previous instance; harmless
```

### JVM or runtime

- Heap dump: jcmd <pid> GC.heap_dump /tmp/<svc>-heap.hprof (pauses process; med risk — needs approval in prod)
- Thread dump:

  ```bash
  jcmd <pid> Thread.print
  ```

### Systemd

```bash
journalctl -u <service> --since '-1h' > <service>.log
```

### General

- Snapshot dashboards / screenshot graphs with timestamps
- Record current config and image versions

## Dry run first

```bash
kubectl --context <ctx> diff -f <file>; kubectl --context <ctx> apply --dry-run=server -f <file>   # diff exits 1 when there are differences, so do not chain with &&; server dry-run still calls admission webhooks
terraform plan -input=false -out=<plan-file> && terraform show -no-color <plan-file>   # an unsaved plan is speculative
helm diff upgrade --kube-context <ctx> <release> <chart> -n <ns> --suppress-secrets   # helm-diff plugin
helm upgrade --kube-context <ctx> <release> <chart> -n <ns> --dry-run=server --hide-secret (Helm >= 3.13; without --hide-secret it prints rendered Secrets)
# helm diff also shows Secret changes unless the plugin is configured to suppress them (HELM_DIFF / --suppress-secrets)
helm history --kube-context <ctx> <release> -n <ns>
```

## Common actions

### Restart

#### Kubernetes

Before proposing any restart, answer "Is it safe to restart or scale it?" in [sre-k8s-triage](../sre-k8s-triage/SKILL.md) (workload kind, ready vs desired, PDB, HPA, probes, strategy, blast radius) and obey its stop rule. A restart can't be undone: the old pods and their in-memory state are gone. Capture evidence first. Use the command for the workload's kind, and run the verification right after it.

| Kind | Risk | Reversible | How it restarts |
|---|---|---|---|
| Deployment | med | no | Rolling, paced by `maxUnavailable`/`maxSurge`. `Recreate` strategy takes every pod down at once (high) |
| StatefulSet | high | no | One pod at a time, highest ordinal first; `partition` > 0 restarts only ordinals >= partition; `OnDelete` does nothing until pods are deleted. Never on a primary/leader without the owner |
| DaemonSet | med-high | no | One node at a time per `maxUnavailable`; ingress controllers, CNI and log agents hit every node |
| Argo Rollout | med | no | Needs the Argo Rollouts kubectl plugin; `kubectl rollout restart` doesn't apply to a Rollout |

Deployment:

**Gate: approval required.**

```bash
kubectl --context <ctx> -n <ns> rollout restart deployment/<name>
kubectl --context <ctx> -n <ns> rollout status deployment/<name> --timeout=300s
```

StatefulSet:

**Gate: approval required.**

```bash
kubectl --context <ctx> -n <ns> rollout restart statefulset/<name>
kubectl --context <ctx> -n <ns> rollout status statefulset/<name> --timeout=600s
```

DaemonSet:

**Gate: approval required.**

```bash
kubectl --context <ctx> -n <ns> rollout restart daemonset/<name>
kubectl --context <ctx> -n <ns> rollout status daemonset/<name> --timeout=600s
```

Argo Rollout:

**Gate: approval required.**

```bash
kubectl argo rollouts restart <name> --context <ctx> -n <ns>
kubectl argo rollouts status <name> --context <ctx> -n <ns> --timeout 300s
```

Verify after `rollout status` succeeds: `kubectl --context <ctx> -n <ns> get <kind>/<name>` shows ready = desired, `kubectl --context <ctx> -n <ns> events --for <kind>/<name> | tail -n 50` has no new warnings, and error rate and latency are back at baseline. If `rollout status` times out or pods don't become Ready, stop: don't re-run the restart. Report and escalate.

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `kubectl --context <ctx> delete pod <pod-name> -n <ns>` | med | no | Capture logs/--previous first; single pod only, never by label selector without approval |

#### Systemd

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `systemctl reload <service>` | low | yes | Config reload; prefer over restart |
| `systemctl restart <service>` | med | no | Causes brief downtime on single hosts |

#### Docker

| Action | Risk | Reversible |
|---|---|---|
| `docker restart <container-id>` | med | no |
| `docker compose restart <service>` | med | no |

### Rollback

#### Kubernetes

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `kubectl --context <ctx> rollout history deployment/<name> -n <ns>` | low | yes | Read-only; confirm target revision first |
| `kubectl --context <ctx> rollout undo deployment/<name> -n <ns>` | med | yes | Check history; schema/data migrations may make this unsafe; uses ReplicaSet history (`revisionHistoryLimit`); GitOps (Argo/Flux) reverts it unless sync is paused or Git is reverted |
| `helm rollback --kube-context <ctx> <release> <revision> -n <ns>` | med | yes | Check `helm history` first; GitOps caveat applies |
| `kubectl --context <ctx> rollout undo deployment/<name> -n <ns> --to-revision=<n>` | med | yes |  |

#### Cloud

| Action | Risk | Reversible |
|---|---|---|
| Cloud console/CLI: redeploy previous version | med | yes |

#### Terraform

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `git revert <commit>` -> `terraform plan -input=false -out=<plan-file>` -> `terraform show -no-color <plan-file>` -> explicit approval -> `terraform apply <plan-file>` (plain `apply` re-plans instead of applying the reviewed plan; see `sre-terraform`) | high | partial | There is no 'terraform rollback'. Destroy/replace actions in the plan may be irreversible. |

#### Database

| Action | Risk | Reversible | Note |
|---|---|---|---|
| PITR (Point-in-Time Recovery) to new instance, then cut over | high | no | Data written after the restore point is lost; restore to a NEW instance first |
| Flashback to restore point | high | no | Oracle-only (Oracle Flashback Database/Table) |

### Scale

#### Kubernetes

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `kubectl --context <ctx> scale deployment/<name> --replicas=<n> -n <ns>` (scale up) | low | yes | Note current replica count first; HPA overrides; GitOps reverts |
| `kubectl --context <ctx> scale deployment/<name> --replicas=<n> -n <ns>` (scale down) | med | yes | Can overload remaining pods; check load and PDBs first |
| `kubectl --context <ctx> autoscale deployment/<name> --min=<min> --max=<max> -n <ns>` | low | yes | Creates an HPA; conflicts with an existing HPA or GitOps. Revert: `kubectl --context <ctx> delete hpa <name> -n <ns>` |

#### Cloud

| Action | Risk | Reversible |
|---|---|---|
| AWS: Modify auto-scaling group desired/max (up / down) | low / med | yes |
| GCP: Update instance group size (up / down) | low / med | yes |
| Azure: Scale VM scale set (up / down) | low / med | yes |

### Failover

#### Database

| Action | Risk | Reversible | Note |
|---|---|---|---|
| Promote read replica to primary | high | no | Split-brain/data-loss risk; check replication lag first |
| Update connection strings | med | yes |  |
| DNS failover | high | yes | TTL delays both failover and failback |

#### Load balancer

| Action | Risk | Reversible |
|---|---|---|
| Drain unhealthy backend | low | yes |
| Enable backup region | high | yes |
| Update health check thresholds | med | yes |

### Feature flags

| Action | Risk | Reversible |
|---|---|---|
| Disable non-critical feature flag | low | yes |

## Incident specific actions

> each step still passes the safety gates

### High error rate

- Capture evidence (logs, rollout history)
- Check recent deployments -> propose rollback if correlated
- Verify dependencies (DB, cache, upstream services)
- Check for config changes
- Scale up if underprovisioned
- Enable degraded mode if needed
- Restart affected services only after evidence captured

### High latency

- Check for resource saturation (CPU, memory, I/O)
- Review database queries (slow query log)
- Check for cache misses
- Verify network issues
- Propose scale-up or bottleneck fix

### Memory exhaustion

- Capture heap dump BEFORE restart (approval needed in prod)
- Propose restart of affected instances
- Increase memory limits
- Add more instances
- Implement memory limits (cgroups, limits)

### Database issues

- Check connection pool exhaustion
- Review slow queries (EXPLAIN, profiling)
- Check for locks/blocking queries
- Restart connection pooler
- Failover to replica only as last resort (high risk)
- Scale database resources

## Communication

> drafts only; see sre-incident-communication gates

### During incident

- Draft status page update for approval
- Draft stakeholder notification for approval
- Document actions in incident log
- Estimate resolution time if possible

### Post incident

- Draft resolution announcement for approval
- Send postmortem notification (after approval)
- Schedule postmortem meeting
- Create follow-up tickets

## Verification

### After remediation

- Confirm error rates returned to baseline
- Verify latency within SLO
- Check synthetic monitors passing
- Confirm user-facing issues resolved
- Monitor for stability (5-15 min)

## Stop and escalate

- Metrics worsen after an action
- Action fails or output is unexpected
- Required approval not given
- Any action labeled reversible: no that was not explicitly approved
- On stop: halt, report what was done, propose rollback, escalate to IC/on-call

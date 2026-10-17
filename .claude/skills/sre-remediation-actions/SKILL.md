---
name: sre-remediation-actions
description: "Reference of gated recovery procedures (rollback, scale, restart, failover) labeled with risk and reversibility, with evidence capture and dry-run first. Loaded by sre-engineer when choosing or executing a remediation via kubectl, systemctl, terraform or cloud CLIs; every prod change needs explicit human approval."
user-invocable: false
---

# SRE Remediation Actions

All `kubectl`/`helm` commands here also take `--context <ctx>` (`--kube-context <ctx>` for helm); never rely on the current context. Never `delete --force --grace-period=0`, `delete --all`, or patch away finalizers without SRE approval.

## Safety gates (REQUIRED)
Follow [sre-safety-gates](../sre-safety-gates/SKILL.md) for every step. In short: read-only diagnosis -> propose with risk/reversibility -> **explicit human approval** before any prod change, MCP write, or external post -> act -> verify -> stop and escalate if worse.
**Legend:** `risk` = low / med / high blast radius. `reversible` = yes / no (can be cleanly undone without data loss).

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
kubectl rollout history deployment/<name> -n <namespace>
kubectl describe deployment/<name> -n <namespace>
kubectl events -n <namespace> --types=Warning
kubectl logs <pod> -n <namespace> --all-containers --timestamps > <pod>.log   # may contain secrets/PII: keep out of repos, redact
kubectl logs <pod> -n <namespace> --all-containers --previous > <pod>.prev.log   # errors if no previous instance; harmless
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
kubectl diff -f <file>; kubectl apply --dry-run=server -f <file>   # diff exits 1 when there are differences, so do not chain with &&; server dry-run still calls admission webhooks
terraform plan  # review diff before any apply
helm diff upgrade <release> <chart> (helm-diff plugin) / helm upgrade --dry-run=server (Helm >= 3.13)
helm history <release> -n <namespace>
```

## Common actions

### Restart

#### Kubernetes

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `kubectl rollout restart deployment/<name> -n <namespace>` | med | no | Evidence capture first; rolling, but loses in-memory state |
| `kubectl delete pod <pod-name> -n <namespace>` | med | no | Capture logs/--previous first; single pod only, never by label selector without approval |

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
| `kubectl rollout history deployment/<name> -n <namespace>` | low | yes | Read-only; confirm target revision first |
| `kubectl rollout undo deployment/<name> -n <namespace>` | med | yes | Check history; schema/data migrations may make this unsafe; uses ReplicaSet history (`revisionHistoryLimit`); GitOps (Argo/Flux) reverts it unless sync is paused or Git is reverted |
| `helm rollback <release> <revision> -n <namespace>` | med | yes | Check `helm history` first; GitOps caveat applies |
| `kubectl rollout undo deployment/<name> -n <namespace> --to-revision=<n>` | med | yes |  |

#### Cloud

| Action | Risk | Reversible |
|---|---|---|
| Cloud console/CLI: redeploy previous version | med | yes |

#### Terraform

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `git revert <commit> -> terraform plan -> review diff -> terraform apply (after approval)` | high | partial | There is no 'terraform rollback'. Destroy/replace actions in the plan may be irreversible. |

#### Database

| Action | Risk | Reversible | Note |
|---|---|---|---|
| PITR (Point-in-Time Recovery) to new instance, then cut over | high | no | Data written after the restore point is lost; restore to a NEW instance first |
| Flashback to restore point | high | no | Oracle-only (Oracle Flashback Database/Table) |

### Scale

#### Kubernetes

| Action | Risk | Reversible | Note |
|---|---|---|---|
| `kubectl scale deployment/<name> --replicas=<n> -n <namespace>` | low | yes | Note current replica count first; HPA overrides; GitOps reverts |
| `kubectl autoscale deployment/<name> --min=<min> --max=<max> -n <namespace>` | low | yes | Creates an HPA; conflicts with an existing HPA or GitOps. Revert: `kubectl delete hpa <name> -n <namespace>` |

#### Cloud

| Action | Risk | Reversible |
|---|---|---|
| AWS: Modify auto-scaling group desired/max | low | yes |
| GCP: Update instance group size | low | yes |
| Azure: Scale VM scale set | low | yes |

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

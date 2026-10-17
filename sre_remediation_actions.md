# SRE Remediation Actions

## Safety gates (REQUIRED — read before anything else)

These gates apply to every step in this skill. Never skip or reorder them.

1. **Diagnose read-only first.** Use only read commands (`get`, `describe`, `logs`, `history`, dashboards, queries). Change nothing.
2. **Propose with risk and reversibility.** For each proposed action, state: exact command/change, target (env, cluster, namespace, service), risk (low/med/high), reversible (yes/no), expected effect, and rollback plan.
3. **Wait for explicit human approval.** Do NOT run any prod-changing command or send/post any external message until a human explicitly approves that specific action. Silence, "looks fine", or approval of a different action is not approval.
4. **Act.** Run exactly what was approved — nothing more. Prefer dry-run/diff output first.
5. **Verify.** Confirm error rate, latency, and saturation returned to baseline / within SLO; watch 5-15 min.
6. **Stop and escalate if worse.** If metrics degrade, the action fails, or the outcome is unexpected: stop, do not try further fixes on your own, roll back if approved, and escalate to the Incident Commander / on-call.
**Legend:** `risk` = low / med / high blast radius. `reversible` = yes / no (can be cleanly undone without data loss).

```yaml
name: sre_remediation_actions
label: "Remediation Actions"
description: >
  Recovery procedures, rollback commands, scaling actions, and common
  remediation patterns for incident response. Every action is gated:
  propose -> explicit approval -> act -> verify.

remediation_hierarchy:
  priority_order:
    1: "Capture evidence (logs, heap dumps, rollout history) — always first, read-only"
    2: "Rollback recent changes (if correlated with onset)"
    3: "Scale resources"
    4: "Disable non-critical features / degraded mode"
    5: "Restart (only after evidence captured; restarts destroy state)"
    6: "Failover to backup (high risk — last resort)"

evidence_capture:   # read-only; do BEFORE any restart, delete, or rollback
  kubernetes:
    - "kubectl rollout history deployment/<name> -n <namespace>"
    - "kubectl describe deployment/<name> -n <namespace>"
    - "kubectl get events -n <namespace> --sort-by=.lastTimestamp"
    - "kubectl logs <pod> -n <namespace> --all-containers --timestamps > <pod>.log"
    - "kubectl logs <pod> -n <namespace> --previous > <pod>.prev.log"
  jvm_or_runtime:
    - "Heap dump: jcmd <pid> GC.heap_dump /tmp/<svc>-heap.hprof (pauses process; med risk — needs approval in prod)"
    - "Thread dump: jcmd <pid> Thread.print"
  systemd:
    - "journalctl -u <service> --since '-1h' > <service>.log"
  general:
    - "Snapshot dashboards / screenshot graphs with timestamps"
    - "Record current config and image versions"

dry_run_first:
  - "kubectl apply --dry-run=server -f <file> && kubectl diff -f <file>"
  - "terraform plan (review diff before any apply)"
  - "helm diff upgrade <release> <chart> (helm-diff plugin) / helm upgrade --dry-run"

common_actions:
  restart:
    kubernetes:
      - { cmd: "kubectl rollout restart deployment/<name> -n <namespace>", risk: med, reversible: no, note: "Evidence capture first; rolling, but loses in-memory state" }
      - { cmd: "kubectl delete pod <pod-name> -n <namespace>", risk: med, reversible: no, note: "Capture logs/--previous first; single pod only, never by label selector without approval" }
    systemd:
      - { cmd: "systemctl reload <service>", risk: low, reversible: yes, note: "Config reload; prefer over restart" }
      - { cmd: "systemctl restart <service>", risk: med, reversible: no, note: "Causes brief downtime on single hosts" }
    docker:
      - { cmd: "docker restart <container-id>", risk: med, reversible: no }
      - { cmd: "docker compose restart <service>", risk: med, reversible: no }

  rollback:
    kubernetes:
      - { cmd: "kubectl rollout history deployment/<name> -n <namespace>", risk: low, reversible: yes, note: "Read-only; confirm target revision first" }
      - { cmd: "kubectl rollout undo deployment/<name> -n <namespace>", risk: med, reversible: yes, note: "Check history; schema/data migrations may make this unsafe" }
      - { cmd: "kubectl rollout undo deployment/<name> -n <namespace> --to-revision=<n>", risk: med, reversible: yes }
    cloud:
      - { cmd: "Cloud console/CLI: redeploy previous version", risk: med, reversible: yes }
    terraform:
      - { cmd: "git revert <commit> -> terraform plan -> review diff -> terraform apply (after approval)", risk: high, reversible: "partial", note: "There is no 'terraform rollback'. Destroy/replace actions in the plan may be irreversible." }
    database:
      - { cmd: "PITR (Point-in-Time Recovery) to new instance, then cut over", risk: high, reversible: no, note: "Data written after the restore point is lost; restore to a NEW instance first" }
      - { cmd: "Flashback to restore point", risk: high, reversible: no, note: "Oracle-only (Oracle Flashback Database/Table)" }

  scale:
    kubernetes:
      - { cmd: "kubectl scale deployment/<name> --replicas=<n> -n <namespace>", risk: low, reversible: yes, note: "Note current replica count first; HPA may override" }
      - { cmd: "kubectl autoscale deployment/<name> --min=<min> --max=<max> -n <namespace>", risk: low, reversible: yes }
    cloud:
      - { cmd: "AWS: Modify auto-scaling group desired/max", risk: low, reversible: yes }
      - { cmd: "GCP: Update instance group size", risk: low, reversible: yes }
      - { cmd: "Azure: Scale VM scale set", risk: low, reversible: yes }

  failover:
    database:
      - { cmd: "Promote read replica to primary", risk: high, reversible: no, note: "Split-brain/data-loss risk; check replication lag first" }
      - { cmd: "Update connection strings", risk: med, reversible: yes }
      - { cmd: "DNS failover", risk: high, reversible: yes, note: "TTL delays both failover and failback" }
    load_balancer:
      - { cmd: "Drain unhealthy backend", risk: low, reversible: yes }
      - { cmd: "Enable backup region", risk: high, reversible: yes }
      - { cmd: "Update health check thresholds", risk: med, reversible: yes }

  feature_flags:
    - { cmd: "Disable non-critical feature flag", risk: low, reversible: yes }

incident_specific_actions:   # each step still passes the safety gates
  high_error_rate:
    - "Capture evidence (logs, rollout history)"
    - "Check recent deployments -> propose rollback if correlated"
    - "Verify dependencies (DB, cache, upstream services)"
    - "Check for config changes"
    - "Scale up if underprovisioned"
    - "Enable degraded mode if needed"
    - "Restart affected services only after evidence captured"

  high_latency:
    - "Check for resource saturation (CPU, memory, I/O)"
    - "Review database queries (slow query log)"
    - "Check for cache misses"
    - "Verify network issues"
    - "Propose scale-up or bottleneck fix"

  memory_exhaustion:
    - "Capture heap dump BEFORE restart (approval needed in prod)"
    - "Propose restart of affected instances"
    - "Increase memory limits"
    - "Add more instances"
    - "Implement memory limits (cgroups, limits)"

  database_issues:
    - "Check connection pool exhaustion"
    - "Review slow queries (EXPLAIN, profiling)"
    - "Check for locks/blocking queries"
    - "Restart connection pooler"
    - "Failover to replica only as last resort (high risk)"
    - "Scale database resources"

communication:   # drafts only; see sre_incident_communication gates
  during_incident:
    - "Draft status page update for approval"
    - "Draft stakeholder notification for approval"
    - "Document actions in incident log"
    - "Estimate resolution time if possible"

  post_incident:
    - "Draft resolution announcement for approval"
    - "Send postmortem notification (after approval)"
    - "Schedule postmortem meeting"
    - "Create follow-up tickets"

verification:
  after_remediation:
    - "Confirm error rates returned to baseline"
    - "Verify latency within SLO"
    - "Check synthetic monitors passing"
    - "Confirm user-facing issues resolved"
    - "Monitor for stability (5-15 min)"

stop_and_escalate:
  - "Metrics worsen after an action"
  - "Action fails or output is unexpected"
  - "Required approval not given"
  - "Any action labeled reversible: no that was not explicitly approved"
  - "On stop: halt, report what was done, propose rollback, escalate to IC/on-call"
```

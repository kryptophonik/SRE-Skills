---
name: sre-k8s-triage
description: "Use when a Kubernetes workload or node is unhealthy: CrashLoopBackOff, Pending, OOMKilled, ImagePullBackOff, node pressure, DNS, probes, stuck rollouts, Helm, and whether a restart is safe. Read-only decision tree."
---

# Kubernetes Triage

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

## Rules

- **Every command carries `--context <ctx> -n <ns>`** (or `-A` for cluster-wide reads), or use a per-incident kubeconfig (`KUBECONFIG=./kubeconfig-<cluster>`, written by the `sre-aws`/`sre-azure`/`sre-gcp` get-credentials steps). Never rely on the current context.
- **Never read Secrets:** no `kubectl get secret -o yaml/json`, no `exec -- env`, no `describe` output pasted with secret values. Redact log captures; keep them out of repos.
- **Bounded commands only:** no `logs -f`, always `--tail`/`--since`; `rollout status` with `--timeout`.
- Recommended identity: a Role/ClusterRole based on `view` (which already excludes Secrets) with no `secrets` get/list and no `pods/exec`, `pods/portforward`, `pods/attach`.
- **GitOps / HPA caveat:** if Argo CD/Flux manages the workload, manual `scale`/`undo`/`edit` get reverted — pause sync or revert in Git. An HPA overrides manual replica counts.

## Never without explicit approval

`drain`, `cordon`/`uncordon`, `delete` (any), `delete --force --grace-period=0` (banned unless an SRE approves), `delete --all` / `-A`, removing finalizers via `patch` (banned unless an SRE approves), `exec`, `port-forward`, `attach`, `run`, `scale`, `rollout undo/restart`, `apply`/`edit`/`patch`, `helm upgrade/rollback/uninstall`.

## Start here

```bash
kubectl config get-contexts                  # confirm <ctx> with the user
kubectl --context <ctx> -n <ns> get pods -o wide
kubectl --context <ctx> -n <ns> events --types=Warning | tail -n 50
kubectl --context <ctx> -n <ns> events --for pod/<pod> | tail -n 50   # one object only
kubectl --context <ctx> -n <ns> describe pod <pod>
```

`kubectl events` has no `--limit` or `--sort-by` flag; it prints oldest first, so `tail -n 50` keeps the newest. Never add `--watch`/`-w` (unbounded). `.lastTimestamp` is often empty on events.k8s.io/v1. Alternative: `kubectl --context <ctx> -n <ns> get events --sort-by=.metadata.creationTimestamp | tail -n 50`.

## Decision tree by pod status

| Status / reason | Check | Common causes |
|---|---|---|
| `CrashLoopBackOff` | `kubectl --context <ctx> -n <ns> logs <pod> -c <container> --previous --tail=200` | app error at start, bad config/secret, failing dependency, wrong command |
| `OOMKilled` (in `describe` Last State) | limits in `describe`; restart/OOM metrics (`top` shows current usage only, peak is gone) | memory limit too low, leak; capture heap before restart |
| `Pending` | `describe` Events: `FailedScheduling` | insufficient CPU/memory, node selector/affinity/taints, unbound PVC, quota |
| `ImagePullBackOff` / `ErrImagePull` | `describe` Events | wrong tag, registry auth (imagePullSecret), rate limit, private registry network |
| `CreateContainerConfigError` | `describe` | missing ConfigMap/Secret key (check key names, not values) |
| Running but not Ready | `describe` probe failures; logs with `--tail=200` | readiness probe path/port/timeout, slow start (add startupProbe), dependency down |
| `Terminating` stuck | `kubectl --context <ctx> -n <ns> get pod <pod> -o jsonpath='{.metadata.finalizers}'` | finalizers, node unreachable (do not patch finalizers without SRE approval) |
| `Evicted` | `kubectl --context <ctx> -n <ns> get pods --field-selector=status.phase=Failed` then filter `.status.reason=Evicted` with jsonpath/grep | node disk/memory pressure |

`--previous` errors if the container never restarted; that is harmless. `kubectl top` needs metrics-server.

## Nodes

```bash
kubectl --context <ctx> get nodes
kubectl --context <ctx> describe node <node>   # Conditions: MemoryPressure, DiskPressure, PIDPressure, Ready
kubectl --context <ctx> top nodes
```

## Rollouts and Helm

```bash
kubectl --context <ctx> -n <ns> rollout status deployment/<name> --timeout=60s
kubectl --context <ctx> -n <ns> rollout history deployment/<name>
kubectl --context <ctx> -n <ns> get rs -l app.kubernetes.io/name=<name>   # label key varies (app=, app.kubernetes.io/name=)
helm --kube-context <ctx> -n <ns> list
helm --kube-context <ctx> -n <ns> history <release>
helm --kube-context <ctx> -n <ns> status <release>
```

## Services, endpoints, DNS

```bash
kubectl --context <ctx> -n <ns> get svc,endpointslices
kubectl --context <ctx> -n <ns> get endpointslices -l kubernetes.io/service-name=<svc>   # empty = selector/readiness problem
kubectl --context <ctx> -n kube-system get pods -l k8s-app=kube-dns
```

DNS test (WRITE: creates a temporary pod; needs approval in prod; PodSecurity/admission may block it):

```bash
kubectl --context <ctx> -n <ns> run dnscheck -it --rm --restart=Never --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 -- nslookup <svc>.<ns>.svc.cluster.local
```

## Resources and quotas

```bash
kubectl --context <ctx> -n <ns> describe resourcequota
kubectl --context <ctx> -n <ns> get hpa
kubectl --context <ctx> -n <ns> auth can-i --list      # what your credentials can do
```

## Is it safe to restart or scale it? (read-only)

Answer this before proposing any restart, scale-down or rollout. Every command here is read-only. `<kind>` is `deployment`, `statefulset`, `daemonset` or `rollout` (Argo Rollouts).

```bash
# 1. Workload kind: what owns the pod (a ReplicaSet means a Deployment or Rollout owns that)
kubectl --context <ctx> -n <ns> get pod <pod> -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
kubectl --context <ctx> -n <ns> get rs <rs> -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
# 2. Ready vs desired (DaemonSet: desiredNumberScheduled / numberReady)
kubectl --context <ctx> -n <ns> get <kind>/<name> -o jsonpath='desired={.spec.replicas} ready={.status.readyReplicas} updated={.status.updatedReplicas}{"\n"}'
kubectl --context <ctx> -n <ns> get daemonset/<name> -o jsonpath='desired={.status.desiredNumberScheduled} ready={.status.numberReady}{"\n"}'
# 3. PodDisruptionBudget covering these pods: ALLOWED DISRUPTIONS column
kubectl --context <ctx> -n <ns> get pdb
# 4. HPA: who owns the replica count, and is it already at max?
kubectl --context <ctx> -n <ns> get hpa
# 5. Readiness probe and rollout strategy (Deployment/Rollout: .spec.strategy; StatefulSet/DaemonSet: .spec.updateStrategy)
kubectl --context <ctx> -n <ns> get <kind>/<name> -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: readiness={.readinessProbe}{"\n"}{end}'
kubectl --context <ctx> -n <ns> get <kind>/<name> -o jsonpath='strategy={.spec.strategy} updateStrategy={.spec.updateStrategy}{"\n"}'
# 6. Blast radius: who sends traffic here
kubectl --context <ctx> -n <ns> get endpointslices -l kubernetes.io/service-name=<svc>
kubectl --context <ctx> get ingress -A | grep -i '<svc>\|<name>' | head -n 20   # routes that point at it
kubectl --context <ctx> get ingressclass                                       # is this workload the ingress controller itself?
# StatefulSet: which pod is the primary/leader? (label key depends on the operator)
kubectl --context <ctx> -n <ns> get pods -l <selector> -L role,spilo-role,cnpg.io/instanceRole
```

| Check | Looks safe | Stop signal |
|---|---|---|
| Kind | Deployment or Rollout behind a Service | StatefulSet holding a primary/leader or quorum (database, broker, etcd/ZooKeeper) |
| Ready vs desired | ready = desired, and at least 2 | fewer than 2, or ready < desired already (a restart removes more capacity) |
| PDB | `ALLOWED DISRUPTIONS` >= 1 | 0: the owners say no pod can be spared. Note a rollout restart is paced by its strategy, not by the PDB, so the PDB alone will not stop it |
| HPA | below `maxReplicas`, headroom on its metric | at `maxReplicas`; also, with an HPA never `scale` by hand (it overrides you) |
| Readiness probe | present and checks real readiness | missing: new pods get traffic before they can serve |
| Strategy | `RollingUpdate` with `maxUnavailable: 0` or small and `maxSurge` >= 1 | `Recreate` (every pod down at once); DaemonSet `maxUnavailable` large; StatefulSet `OnDelete` (a restart changes nothing until pods are deleted); StatefulSet `partition` > 0 (only ordinals >= partition restart) |
| Blast radius | Service has other Ready endpoints; one app's routes | the ingress controller, DNS, CNI or another shared component: every route or every node is affected |

**Stop rule:** if ready or desired replicas are fewer than 2, the PDB allows 0 disruptions, the target is a StatefulSet primary/leader (or uses `Recreate`), or the target is a shared component (the ingress controller, DNS such as CoreDNS, the CNI, a service mesh control plane, or anything else every route or node depends on), do not propose a restart. Escalate to the service owner or Incident Commander with what you found.

Otherwise, report the verdict (kind, ready/desired, PDB allowed disruptions, HPA, probe, strategy, blast radius, risk low/med/high) and hand off: the per-kind restart commands are in [sre-remediation-actions](../sre-remediation-actions/SKILL.md) (Restart), and the write runs through `/sre-k8s-safe-remediation` (Claude plugin install: `/sre:sre-k8s-safe-remediation`; Codex: `$sre-k8s-safe-remediation`), which is manual-only.

## Common fixes (all WRITE — propose, get approval, use sre-remediation-actions)

| Action | Command | Note |
|---|---|---|
| Roll back | `kubectl --context <ctx> -n <ns> rollout undo deployment/<name>` | Reverted by GitOps unless sync paused / Git reverted; uses ReplicaSet history (`revisionHistoryLimit`) |
| Helm rollback | `helm --kube-context <ctx> -n <ns> rollback <release> <revision>` | Check `helm history` first |
| Scale | `kubectl --context <ctx> -n <ns> scale deployment/<name> --replicas=<n>` | HPA overrides; GitOps reverts |
| Restart after evidence capture | `kubectl --context <ctx> -n <ns> rollout restart deployment/<name>` | Answer "Is it safe to restart or scale it?" first; loses in-memory state |
| Raise limits / fix probes | Change manifests via Git/GitOps, not `kubectl edit` | |

## Bundled scripts and references

```bash
# run from this skill folder (the one containing SKILL.md)
bash scripts/k8s-preflight.sh --context <ctx> -n <ns>        # auth can-i matrix; exits 1 if the identity can read Secrets, exec, port-forward or write
bash scripts/k8s-triage-snapshot.sh --context <ctx> -n <ns>  # bounded, read-only evidence bundle; Secrets never read
```

- [references/command-cheatsheet.md](references/command-cheatsheet.md) · [references/destructive-commands.md](references/destructive-commands.md)
- Opt-in hardening: [references/rbac-readonly.yaml](references/rbac-readonly.yaml), [references/kubernetes-mcp-server.toml](references/kubernetes-mcp-server.toml), [references/claude-settings-k8s-deny.json](references/claude-settings-k8s-deny.json). The deny list also blocks `cordon` and other fixes, so Claude cannot execute an approved fix by design; a human runs it.
- Writes: tell the user to run `/sre-k8s-safe-remediation` (Claude plugin install: `/sre:sre-k8s-safe-remediation`; Codex: `$sre-k8s-safe-remediation`).

If neither the Kubernetes MCP server nor kubectl is available, output the commands for the human and stop.

## Output

- Triage note: context, namespace, affected workloads, status and reason, evidence (events, log paths, redacted), likely cause, proposed fix with risk/reversibility

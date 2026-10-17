---
name: k8s-triage
description: "Read-only Kubernetes triage decision tree for pod/node/network problems: CrashLoopBackOff, Pending, OOMKilled, ImagePullBackOff, node pressure, DNS, failing probes, stuck rollouts, Helm releases. Uses kubectl with an explicit --context and -n, or the Kubernetes MCP server in read-only mode; fixes go through sre-remediation-actions with approval. Use when a Kubernetes workload is unhealthy."
---

# Kubernetes Triage

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

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
kubectl --context <ctx> -n <ns> events --types=Warning
kubectl --context <ctx> -n <ns> describe pod <pod>
```

`kubectl events` sorts by time itself; `.lastTimestamp` is often empty on events.k8s.io/v1. Alternative: `kubectl --context <ctx> -n <ns> get events --sort-by=.metadata.creationTimestamp | tail -30`.

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

## Common fixes (all WRITE — propose, get approval, use sre-remediation-actions)

| Action | Command | Note |
|---|---|---|
| Roll back | `kubectl --context <ctx> -n <ns> rollout undo deployment/<name>` | Reverted by GitOps unless sync paused / Git reverted; uses ReplicaSet history (`revisionHistoryLimit`) |
| Helm rollback | `helm --kube-context <ctx> -n <ns> rollback <release> <revision>` | Check `helm history` first |
| Scale | `kubectl --context <ctx> -n <ns> scale deployment/<name> --replicas=<n>` | HPA overrides; GitOps reverts |
| Restart after evidence capture | `kubectl --context <ctx> -n <ns> rollout restart deployment/<name>` | Loses in-memory state |
| Raise limits / fix probes | Change manifests via Git/GitOps, not `kubectl edit` | |

## Output

- Triage note: context, namespace, affected workloads, status and reason, evidence (events, log paths, redacted), likely cause, proposed fix with risk/reversibility

---
name: k8s-triage
description: "Read-only Kubernetes triage decision tree for pod/node/network problems: CrashLoopBackOff, Pending, OOMKilled, ImagePullBackOff, node pressure, DNS, failing probes, stuck rollouts. Uses kubectl or the Kubernetes MCP server in read-only mode; fixes go through sre-remediation-actions with approval. Use when a Kubernetes workload is unhealthy."
---

# Kubernetes Triage

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

All commands below are read-only unless marked **WRITE**.

## Start here

```bash
kubectl config current-context            # confirm the cluster before anything else
kubectl get pods -n <ns> -o wide
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30
kubectl describe pod <pod> -n <ns>
```

## Decision tree by pod status

| Status / reason | Check | Common causes |
|---|---|---|
| `CrashLoopBackOff` | `kubectl logs <pod> -n <ns> --previous` | app error at start, bad config/secret, failing dependency, wrong command |
| `OOMKilled` (in `describe` Last State) | `kubectl top pod <pod> -n <ns> --containers`; limits in `describe` | memory limit too low, leak; capture heap before restart |
| `Pending` | `describe` Events: `FailedScheduling` | insufficient CPU/memory, node selector/affinity/taints, unbound PVC, quota |
| `ImagePullBackOff` / `ErrImagePull` | `describe` Events | wrong tag, registry auth (imagePullSecret), rate limit, private registry network |
| `CreateContainerConfigError` | `describe` | missing ConfigMap/Secret key |
| Running but not Ready | `describe` probe failures; `kubectl logs` | readiness probe path/port/timeout, slow start (add startupProbe), dependency down |
| `Terminating` stuck | `kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.finalizers}'` | finalizers, node unreachable |
| `Evicted` | `kubectl get pods -n <ns> --field-selector=status.phase=Failed` | node disk/memory pressure |

## Nodes

```bash
kubectl get nodes
kubectl describe node <node>          # Conditions: MemoryPressure, DiskPressure, PIDPressure, Ready
kubectl top nodes
```

## Rollouts

```bash
kubectl rollout status deployment/<name> -n <ns>
kubectl rollout history deployment/<name> -n <ns>
kubectl get rs -n <ns> -l app=<label>
```

## Services, endpoints, DNS

```bash
kubectl get svc,endpointslices -n <ns>
kubectl get endpointslices -n <ns> -l kubernetes.io/service-name=<svc>   # empty = selector/readiness problem
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl run -it --rm dnscheck --image=busybox:1.36 --restart=Never -- nslookup <svc>.<ns>.svc.cluster.local   # WRITE: creates a temporary pod; needs approval in prod
```

## Resources and quotas

```bash
kubectl describe resourcequota -n <ns>
kubectl get hpa -n <ns>
kubectl auth can-i --list -n <ns>      # what your credentials can do
```

## Common fixes (all WRITE — propose, get approval, use sre-remediation-actions)

- Roll back: `kubectl rollout undo deployment/<name> -n <ns>`
- Scale: `kubectl scale deployment/<name> --replicas=<n> -n <ns>`
- Restart after evidence capture: `kubectl rollout restart deployment/<name> -n <ns>`
- Raise limits / fix probes: change manifests via Git/GitOps, not `kubectl edit`.

## Output

- Triage note: cluster/context, affected workloads, status and reason, evidence (events, logs paths), likely cause, proposed fix with risk/reversibility

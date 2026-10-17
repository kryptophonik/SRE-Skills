# Read-only kubectl cheat sheet (agent-safe)

Always pass `--context <ctx> -n <ns>`; never rely on current-context. Add `--request-timeout=20s`.
Sources: https://kubernetes.io/docs/reference/kubectl/quick-reference/ · https://kubernetes.io/docs/reference/kubectl/generated/

| Goal | Command | Notes |
|---|---|---|
| Confirm context exists | `kubectl config get-contexts <ctx>` | Fails if missing; don't trust `current-context` |
| Pods | `kubectl --context C -n N get pods -o wide` | |
| Warning events, time-sorted | `kubectl --context C -n N events --types=Warning` | Built-in sorting. Avoid `get events --sort-by=.lastTimestamp` because it is often empty on events.k8s.io/v1 events. Fallback: `--sort-by=.metadata.creationTimestamp` ([kubectl events](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_events/)) |
| Events for one object | `kubectl --context C -n N events --for pod/<pod>` | |
| Describe | `kubectl --context C -n N describe pod <pod>` | Shows literal env values; redact before sharing |
| Current logs | `kubectl --context C -n N logs <pod> -c <ctr> --tail=200 --since=15m` | No `-f` in agents (never returns) |
| All pods of a workload | `kubectl --context C -n N logs -l app.kubernetes.io/name=<app> --all-containers --prefix --tail=100` | `logs deployment/x` reads only ONE pod |
| Crashed container | `kubectl --context C -n N logs <pod> -c <ctr> --previous --tail=200` | Errors if no prior instance; that's expected |
| Usage | `kubectl --context C -n N top pod --containers` | Needs metrics-server; current usage only (an OOM peak is gone) |
| Nodes | `kubectl --context C get nodes -o wide`; `describe node <n>`; `top nodes` | Conditions: Ready, Memory/Disk/PIDPressure |
| Rollout state | `kubectl --context C -n N rollout status deploy/<d> --watch=false` | The default watch blocks; or use `--timeout=60s` |
| Rollout history | `kubectl --context C -n N rollout history deploy/<d>` | Limited by `revisionHistoryLimit` |
| Evicted/failed pods | `kubectl --context C -n N get pods --field-selector=status.phase=Failed` | `status.reason` is not a field selector |
| Finalizers | `kubectl --context C -n N get pod <p> -o jsonpath='{.metadata.finalizers}'` | Read-only; removing them is destructive |
| Service backends | `kubectl --context C -n N get endpointslices -l kubernetes.io/service-name=<svc>` | Empty means a selector or readiness problem |
| DNS pods | `kubectl --context C -n kube-system get pods -l k8s-app=kube-dns` | |
| Quota/HPA | `kubectl --context C -n N describe resourcequota`; `get hpa` | |
| My permissions | `kubectl --context C -n N auth can-i --list` | |
| Helm state | `helm --kube-context C -n N list`; `helm -n N history <rel>`; `helm -n N status <rel>` | Don't use `helm get values --all`: it may contain secrets ([helm docs](https://helm.sh/docs/helm/helm_history/)) |
| Server-side preview | `kubectl diff -f f.yaml` (exit 1 = differences), then `kubectl apply --dry-run=server -f f.yaml` | Dry-run still calls admission webhooks ([kubectl diff](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_diff/)) |
| DNS test (**WRITE**, creates a pod) | `kubectl --context C -n N run dnscheck -it --rm --restart=Never --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 -- nslookup <svc>.<ns>.svc.cluster.local` | Needs approval in prod. busybox nslookup is unreliable ([DNS debugging](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)) |

## Never as "read-only"
- `kubectl get secret ... -o yaml|json`, `describe secret` with the data decoded, `exec -- env`, `helm get values --all`.
- Deprecated or removed: `kubectl get cs` (deprecated since v1.19), `--export` (removed in v1.18), `run --generator` (removed), `rolling-update` (removed). See the [kubectl changelog](https://github.com/kubernetes/kubernetes/tree/master/CHANGELOG).

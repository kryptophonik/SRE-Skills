# Never without explicit human approval

Before any of these: run `bash scripts/k8s-triage-snapshot.sh --context <ctx> -n <ns>` to capture evidence, state the target (`--context`, `-n`, name), the risk and how to roll back, then wait for approval. Prefer GitOps (a PR or revert) over imperative changes.
Sources: https://kubernetes.io/docs/reference/kubectl/generated/ · https://helm.sh/docs/helm/ · https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

| Command | Why it's dangerous | Safer alternative |
|---|---|---|
| `delete pod` | Kills in-flight work and loses `--previous` logs after a reschedule | Capture logs first. One named pod at a time, never `-l`/`--all` |
| `delete ... --all`, `-A`, `-l` | Wide blast radius | Name single objects. Use `--dry-run=server` to list what would be deleted |
| `delete --force --grace-period=0` | Skips graceful shutdown. For StatefulSets it can run two pods with the same identity ([docs](https://kubernetes.io/docs/tasks/run-application/force-delete-stateful-set-pod/)) | Find out why the pod is stuck (node, finalizers) first. Escalate |
| `patch` to remove finalizers | Orphans external resources (LBs, volumes, CRs) | Fix or delete the controller's dependency. Escalate to the owner |
| `drain` / `cordon` | Evicts or blocks workloads node-wide. PDBs can block or stall a drain | Check PDBs and capacity first: `get pdb -A`. Drain one node at a time with `--timeout` |
| `rollout restart` | Loses in-memory state and causes cold starts | Capture evidence and heap/thread dumps first |
| `rollout undo` | Schema or data migrations may not reverse. GitOps reverts it | `rollout history` → pick a revision → `undo --to-revision=N`, or revert the commit in Git |
| `scale` | HPA overrides `replicas`. GitOps reverts it. Scaling to 0 is an outage | Change HPA min/max via Git. Record the current replica count first |
| `autoscale` | Creates an HPA that may conflict with an existing one or with GitOps | Manage the HPA in Git. To revert: `delete hpa <name>` |
| `edit` / `patch` / `replace` / `set` | Drift from Git and no review | Make the change in Git. Use `kubectl diff` then `apply --dry-run=server` |
| `apply` | Can prune or overwrite fields | Run `diff` first, and avoid `--prune` |
| `exec` / `attach` / `debug` | Shell in prod, can read secrets and env | Read logs and metrics instead. If unavoidable, time-box it and log it |
| `port-forward` | Bypasses NetworkPolicy and auth to reach internal services | Use the existing observability endpoints |
| `get secret -o yaml` / `exec -- env` | Credential exposure | Check that the key exists: `get secret <s> -o jsonpath='{.data}' \| jq 'keys'` (still needs secret read; avoid for agents) |
| `helm upgrade` | Changes the release | Run `helm diff upgrade` (plugin) or `helm upgrade --dry-run=server` first |
| `helm rollback <rel> <rev>` | Same caveats as `rollout undo` | Check `helm history <rel>` first ([helm rollback](https://helm.sh/docs/helm/helm_rollback/)) |
| `helm uninstall` | Deletes every resource in the release. PVCs and CRDs may or may not survive | Almost never during an incident |

## GitOps / HPA caveats
- If Argo CD or Flux manages the object, an imperative change gets reverted on the next sync, or self-heal fights it. Either pause sync (Argo: disable auto-sync on the app; Flux: `flux suspend kustomization <name>`) and record that you did, or make the change in Git.
- If an HPA targets the workload, `kubectl scale` is temporary. Change HPA `minReplicas` instead.

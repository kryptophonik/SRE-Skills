---
name: sre-gcp
description: "Use when the system runs on Google Cloud: Cloud Monitoring, Cloud Logging, GKE/Compute/Cloud Run/Cloud SQL status, audit logs, quotas. Viewer roles via gcloud or MCP allowlist; writes need approval."
---

# Google Cloud

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

Process skills: `sre-engineer`, `sre-k8s-triage` (GKE), `sre-dr-backup-test`, `sre-capacity-planning`, `sre-cloud-cost-review`, `sre-security-incident-triage`.

## Rules

- **Pin the target on every command:** `--project=<PROJECT_ID>`, plus `--region=<REGION>` or `--zone=<ZONE>` where they apply.
- **Credentials:** Application Default Credentials, or `--impersonate-service-account=<VIEWER_SA>@<PROJECT_ID>.iam.gserviceaccount.com` with viewer roles. Never create or download service account keys.
- **Writes** (`create`, `update`, `delete`, `resize`, `reset`, `deploy`, `update-traffic`, `restore`, IAM changes) need approval. **Never pass `--quiet` on writes**; keep confirmation prompts on.
- `--format` field paths (e.g. `status.conditions`, `quotas.metric`) come from the REST resources; verify them in your environment.

## Always first

```bash
gcloud config list --format="value(core.account,core.project)"
```

## Health and status (read-only)

```bash
gcloud container clusters list --project=<PROJECT_ID> --limit=50
# kubectl needs gke-gcloud-auth-plugin for GKE (https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl)
# USER STEP (software install, not run by the agent): gcloud components install gke-gcloud-auth-plugin, or the OS package google-cloud-cli-gke-gcloud-auth-plugin
KUBECONFIG=./kubeconfig-<cluster> gcloud container clusters get-credentials <cluster> --region=<REGION> --project=<PROJECT_ID>   # per-incident file; ~/.kube/config untouched
KUBECONFIG=./kubeconfig-<cluster> kubectl config current-context                                                              # confirm the context it set
gcloud compute instances list --project=<PROJECT_ID> --filter="status!=RUNNING" --limit=50
gcloud run services describe <svc> --region=<REGION> --project=<PROJECT_ID> --format="yaml(status.conditions,status.traffic)"
gcloud sql instances describe <instance> --project=<PROJECT_ID> --format="value(state)"
gcloud compute instance-groups managed list-instances <mig> --region=<REGION> --project=<PROJECT_ID> --limit=50
```

## Logging and monitoring (read-only)

Keep `--freshness` and `--limit` on every `logging read`. `--freshness` defaults to `1d`, works only with descending order, and is ignored if the filter contains a timestamp.

```bash
gcloud logging read 'severity>=ERROR AND resource.type="k8s_container" AND resource.labels.namespace_name="<ns>"' --project=<PROJECT_ID> --freshness=30m --limit=50
gcloud logging read 'resource.type="cloud_run_revision" AND httpRequest.status>=500' --project=<PROJECT_ID> --freshness=1h --limit=50
gcloud monitoring policies list --project=<PROJECT_ID> --format="table(displayName,enabled)" --limit=100
```

## Common remediations (WRITE — approval required, no `--quiet`)

| Action | Command | Risk | Reversible |
|---|---|---|---|
| Shift Cloud Run traffic to previous revision | `gcloud run services update-traffic <svc> --region=<REGION> --project=<PROJECT_ID> --to-revisions=<prev-rev>=100` | low | yes |
| Resize MIG | `gcloud compute instance-groups managed resize <mig> --size=<n> --region=<REGION> --project=<PROJECT_ID>` | low | yes |
| Resize GKE node pool | `gcloud container clusters resize <cluster> --node-pool=<pool> --num-nodes=<n> --region=<REGION> --project=<PROJECT_ID>` | med | yes |

## Output

- Project confirmed, findings with commands used, proposed actions with risk/reversibility

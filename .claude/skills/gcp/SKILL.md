---
name: gcp
description: "Google Cloud adapter for SRE: project sanity, Cloud Monitoring alerts, Cloud Logging queries, GKE/Compute/Cloud Run/Cloud SQL status, audit logs, quotas. Uses gcloud with Viewer roles or Google's gcloud/observability MCP servers. Use when the system runs on GCP. Writes need approval."
---

# Google Cloud

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. `create`, `update`, `delete`, `resize`, `reset`, `deploy`, and traffic changes are writes.

Process skills: `sre-engineer`, `k8s-triage` (GKE), `dr-backup-test`, `capacity-planning`, `cloud-cost-review`, `security-incident-triage`.

## Always first

```bash
gcloud config list --format="value(core.account,core.project)"
```

## Health and status

```bash
gcloud container clusters list
gcloud container clusters get-credentials <cluster> --region <region>   # writes local kubeconfig only
gcloud compute instances list --filter="status!=RUNNING"
gcloud run services describe <svc> --region <region> --format="yaml(status.conditions,status.traffic)"
gcloud sql instances describe <instance> --format="value(state)"
gcloud compute instance-groups managed list-instances <mig> --region <region>
```

## Logging and monitoring

```bash
gcloud logging read 'severity>=ERROR AND resource.type="k8s_container" AND resource.labels.namespace_name="<ns>"' --freshness=30m --limit=50
gcloud logging read 'resource.type="cloud_run_revision" AND httpRequest.status>=500' --freshness=1h --limit=50
gcloud alpha monitoring policies list --format="table(displayName,enabled)"
```

## Common remediations (WRITE — approval required)

| Action | Command | Risk | Reversible |
|---|---|---|---|
| Shift Cloud Run traffic to previous revision | `gcloud run services update-traffic <svc> --region <region> --to-revisions <prev-rev>=100` | low | yes |
| Resize MIG | `gcloud compute instance-groups managed resize <mig> --size <n> --region <region>` | low | yes |
| Resize GKE node pool | `gcloud container clusters resize <cluster> --node-pool <pool> --num-nodes <n> --region <region>` | med | yes |

## Output

- Project confirmed, findings with commands used, proposed actions with risk/reversibility

# Least-privilege read-only roles for the gcp skill

Grant these to a dedicated viewer service account instead of `roles/viewer`, `roles/editor` or `roles/owner`.

| Area / commands | Role | Source (Last updated, UTC) |
|---|---|---|
| GKE: `container clusters list/describe`, `get-credentials` | `roles/container.viewer` | https://cloud.google.com/iam/docs/roles-permissions/container (2026-10-14) |
| Compute: `instances list`, `disks list`, `regions describe`, MIG `list-instances` | `roles/compute.viewer`: "Read-only access to get and list Compute Engine resources, without being able to read the data stored on them" | https://cloud.google.com/iam/docs/roles-permissions/compute (2026-10-14) |
| Cloud Run: `run services describe` | `roles/run.viewer`: "Can view the state of all Cloud Run resources, including IAM policies" | https://cloud.google.com/iam/docs/roles-permissions/run (2026-10-14) |
| Cloud SQL: `sql instances describe`, `sql backups list` | `roles/cloudsql.viewer` | https://cloud.google.com/iam/docs/roles-permissions/cloudsql (2026-10-14) |
| Logging: `logging read` | `roles/logging.viewer` (all of _Required/_Default **except Data Access logs**) | https://cloud.google.com/logging/docs/access-control (2026-10-16) |
| Data Access audit logs, only if needed | `roles/logging.privateLogViewer` | same, plus https://cloud.google.com/iam/docs/roles-permissions/logging (2026-10-14) |
| Monitoring: `monitoring policies list/describe` | `roles/monitoring.viewer` (includes `monitoring.alertPolicies.list`) | https://cloud.google.com/iam/docs/roles-permissions/monitoring (2026-10-14) |
| Recommender: machine-type recommendations | `roles/recommender.computeViewer` | https://cloud.google.com/iam/docs/roles-permissions/recommender (2026-10-14) |

## Use impersonation, not keys
Never create or download service account keys. Use your own ADC login and impersonate the viewer service account, which needs the Service Account Token Creator role on it (https://cloud.google.com/iam/docs/service-account-impersonation, 2026-10-13).

```bash
# Per command (a flag every gcloud command accepts):
gcloud monitoring policies list --project=<PROJECT_ID> --impersonate-service-account=<VIEWER_SA>@<PROJECT_ID>.iam.gserviceaccount.com
# Per session (env var documented at https://cloud.google.com/sdk/docs/authorizing, 2026-10-13):
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=<VIEWER_SA>@<PROJECT_ID>.iam.gserviceaccount.com
```

# Bounded Cloud Logging queries

Every query pins `--project`, a bounded `--freshness` and `--limit`.
- Per https://cloud.google.com/sdk/gcloud/reference/logging/read (Last updated 2026-09-15 UTC), `--freshness` defaults to `1d` and "works only with DESC ordering and filters without a timestamp". With an explicit `timestamp>=` term, the timestamp is the bound.
- Filter syntax follows https://cloud.google.com/logging/docs/view/logging-query-language (Last updated 2026-10-16 UTC).

```bash
# Errors in a GKE namespace, last 30 min
gcloud logging read 'severity>=ERROR AND resource.type="k8s_container" AND resource.labels.namespace_name="<NAMESPACE>"' \
  --project=<PROJECT_ID> --freshness=30m --limit=50

# Cloud Run 5xx, last hour
gcloud logging read 'resource.type="cloud_run_revision" AND httpRequest.status>=500' \
  --project=<PROJECT_ID> --freshness=1h --limit=50

# Admin Activity audit log (readable with roles/logging.viewer)
gcloud logging read 'logName:"cloudaudit.googleapis.com%2Factivity"' \
  --project=<PROJECT_ID> --freshness=1d --limit=50

# Data Access audit log (needs roles/logging.privateLogViewer; often very high volume)
gcloud logging read 'logName:"cloudaudit.googleapis.com%2Fdata_access"' \
  --project=<PROJECT_ID> --freshness=1h --limit=20

# Fixed window instead of --freshness
gcloud logging read 'timestamp>="<START_RFC3339>" AND timestamp<="<END_RFC3339>" AND severity>=ERROR' \
  --project=<PROJECT_ID> --limit=50
```

## Cost and volume notes
- Keep `--limit` small and the window short; widen gradually. Filters on `resource.type` and `logName` narrow the scan.
- Pricing: https://cloud.google.com/logging/pricing (no date shown). Check it for current charges; this file makes no claims about read costs.
- For large analyses, use Log Analytics or a log sink instead of looping `logging read`.

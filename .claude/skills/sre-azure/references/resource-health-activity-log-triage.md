# Resource Health and Activity Log triage

All steps are read-only. Always pass `--subscription <sub-id>`, ideally through `scripts/az-ro.sh`.

## 1. Platform or us?
1. **Resource Health** for the RG:
   `GET https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2025-05-01`
   - Stable versions include 2022-10-01, 2024-02-01, 2025-04-01 and 2025-05-01.
   - `availabilityState` is Available, Unavailable, Degraded or Unknown.
   - `reasonType` tells you whether the cause is a platform event or customer-initiated.
2. **Single resource**: `<resource-id>/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2025-05-01`
3. **Service Health events** for the subscription: `/subscriptions/<sub-id>/providers/Microsoft.ResourceHealth/events?api-version=2025-05-01`, which takes optional `$filter` and `queryStartTime` parameters. Check for an active incident or planned maintenance in your region.
4. If the cause is the platform, record the tracking ID, mitigate (e.g. fail over through the gated write process) and follow the status page. Don't "fix" your own resources blindly.

## 2. What changed?
- `az monitor activity-log list -g <rg> --offset 6h --subscription <sub-id> --query "[?status.value=='Failed' || contains(operationName.value,'write') || contains(operationName.value,'delete')]"`
- The Activity Log is kept for 90 days. For longer or cross-subscription views, query `AzureActivity` in the workspace (see kql-cheatsheet.md).
- Look for deployments, config writes, scale operations and role assignment changes close to the start of the incident.

## 3. Correlate
- Metrics: `az monitor metrics list --resource <resource-id> --metric "<metric>" --offset 6h --interval PT5M --aggregation Average`
- Fired alerts: `az monitor metrics alert list -g <rg>` for the rules. Fired-alert history is in Azure Monitor alerts (Alerts Management API).

## 4. Output
Report the subscription, time window, health states, the suspected change (caller, operation, time), and evidence links. Propose actions through write-command-risk.md.

Sources:
- https://learn.microsoft.com/azure/service-health/resource-health-overview
- https://learn.microsoft.com/rest/api/resourcehealth/availability-statuses
- https://learn.microsoft.com/rest/api/resourcehealth/events
- https://learn.microsoft.com/rest/api/resourcehealth/events/list-by-subscription-id
- https://learn.microsoft.com/rest/api/resourcehealth/availability-statuses/get-by-resource
- https://github.com/Azure/azure-rest-api-specs/tree/main/specification/resourcehealth/resource-manager/Microsoft.ResourceHealth/ResourceHealth/stable
- https://learn.microsoft.com/azure/azure-monitor/essentials/activity-log
- https://learn.microsoft.com/cli/azure/monitor/activity-log
- https://learn.microsoft.com/cli/azure/monitor/metrics

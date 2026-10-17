#!/usr/bin/env bash
# health-snapshot.sh: read-only snapshot of a resource group.
# Collects the account, the resource list, Resource Health, Activity Log failures, and metric alerts.
# Usage: health-snapshot.sh --subscription <sub-id> --resource-group <rg> [--offset 6h]
# Sources:
#   https://learn.microsoft.com/rest/api/resourcehealth/availability-statuses/list-by-resource-group
#   https://learn.microsoft.com/cli/azure/monitor/activity-log#az-monitor-activity-log-list
#   https://learn.microsoft.com/cli/azure/monitor/metrics/alert#az-monitor-metrics-alert-list
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RO="$HERE/az-ro.sh"
SUB=""; RG=""; OFFSET="6h"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="${2:?}"; shift 2 ;;
    --resource-group|-g) RG="${2:?}"; shift 2 ;;
    --offset) OFFSET="${2:?}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SUB" && -n "$RG" ]] || { echo "usage: $0 --subscription <sub-id> --resource-group <rg> [--offset 6h]" >&2; exit 2; }
API="2025-05-01"   # newest stable Microsoft.ResourceHealth version; 2022-10-01 also works

echo "== account";        "$RO" --subscription "$SUB" account show --query "{name:name,id:id,tenant:tenantId}" -o table
echo "== resources";      "$RO" --subscription "$SUB" resource list -g "$RG" -o table
echo "== resource health (non-Available)"
"$RO" --subscription "$SUB" rest --method get \
  --url "https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=${API}" \
  --query "value[?properties.availabilityState!='Available'].{id:id,state:properties.availabilityState,reason:properties.reasonType,summary:properties.summary}" -o table
echo "== activity log failures (last ${OFFSET})"
"$RO" --subscription "$SUB" monitor activity-log list -g "$RG" --offset "$OFFSET" \
  --query "[?status.value=='Failed'].{time:eventTimestamp,op:operationName.value,caller:caller,res:resourceId}" -o table
echo "== metric alert rules"; "$RO" --subscription "$SUB" monitor metrics alert list -g "$RG" -o table

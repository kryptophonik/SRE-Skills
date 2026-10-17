#!/usr/bin/env bash
# aks-triage.sh: read-only control-plane triage for an AKS cluster.
# It does NOT fetch kubeconfig credentials.
# Usage: aks-triage.sh --subscription <sub-id> --resource-group <rg> --cluster <name>
# Sources:
#   https://learn.microsoft.com/cli/azure/aks#az-aks-show
#   https://learn.microsoft.com/cli/azure/aks/nodepool#az-aks-nodepool-list
#   https://learn.microsoft.com/rest/api/aks/managed-clusters/get
#   https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable
#   https://github.com/Azure/azure-cli/blob/dev/src/azure-cli/azure/cli/command_modules/acs/_consts.py
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RO="$HERE/az-ro.sh"
SUB=""; RG=""; CL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="${2:?}"; shift 2 ;;
    --resource-group|-g) RG="${2:?}"; shift 2 ;;
    --cluster|-n) CL="${2:?}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SUB" && -n "$RG" && -n "$CL" ]] || { echo "usage: $0 --subscription <sub-id> --resource-group <rg> --cluster <name>" >&2; exit 2; }

echo "== cluster"
"$RO" --subscription "$SUB" aks show -g "$RG" -n "$CL" \
  --query "{state:provisioningState,power:powerState.code,k8s:currentKubernetesVersion,sku:sku.tier,nodeRG:nodeResourceGroup}" -o table
echo "== node pools"
"$RO" --subscription "$SUB" aks nodepool list -g "$RG" --cluster-name "$CL" \
  --query "[].{name:name,mode:mode,state:provisioningState,power:powerState.code,count:count,autoscale:enableAutoScaling,min:minCount,max:maxCount,vm:vmSize,ver:currentOrchestratorVersion}" -o table
echo "== monitoring: Container Insights logs + Managed Prometheus metrics"
# The CLI addon name `monitoring` is stored as addonProfiles.omsagent, with
# config.logAnalyticsWorkspaceResourceID (azure-cli acs/_consts.py:
# CONST_MONITORING_ADDON_NAME="omsagent").
# Managed Prometheus (--enable-azure-monitor-metrics) is azureMonitorProfile.metrics.enabled.
"$RO" --subscription "$SUB" aks show -g "$RG" -n "$CL" \
  --query "{containerInsights:addonProfiles.omsagent.enabled,workspace:addonProfiles.omsagent.config.logAnalyticsWorkspaceResourceID,prometheus:azureMonitorProfile.metrics.enabled}" -o json

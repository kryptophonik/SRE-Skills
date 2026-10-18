# KQL cheat sheet (read-only queries)

Run these with `bash scripts/az-ro.sh --subscription <sub-id> monitor log-analytics query -w <workspace-guid> --analytics-query "<kql>" --timespan PT1H`.
Replace the `<placeholders>`. Column names come from the Azure Monitor table reference pages linked below.

## AppRequests (workspace-based Application Insights)
Source: https://learn.microsoft.com/azure/azure-monitor/reference/tables/apprequests
```kql
AppRequests
| where TimeGenerated > ago(1h)
| summarize total=count(), failed=countif(Success == false), p95=percentile(DurationMs, 95) by bin(TimeGenerated, 5m), AppRoleName
| extend failRate = round(100.0 * failed / total, 2)
| order by TimeGenerated asc
```
```kql
AppRequests
| where TimeGenerated > ago(1h) and Success == false
| summarize count() by Name, ResultCode
| top 20 by count_
```

## ContainerLogV2 (Container Insights with the ContainerLogV2 schema)
Source: https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerlogv2
LogLevel values are CRITICAL, ERROR, WARNING, INFO, DEBUG, TRACE or UNKNOWN. It is inferred from a JSON `level` key or by keyword matching, so some lines can be misclassified. `=~` is a case-insensitive match. Source: https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-logs-schema
```kql
ContainerLogV2
| where TimeGenerated > ago(30m) and LogLevel in~ ("error", "critical")
| summarize count() by PodNamespace, PodName, ContainerName
| order by count_ desc
```
```kql
ContainerLogV2
| where TimeGenerated > ago(15m) and PodNamespace == "<namespace>" and PodName startswith "<pod-prefix>"
| project TimeGenerated, PodName, ContainerName, LogLevel, LogMessage
| order by TimeGenerated desc
| take 200
```

## AzureActivity (Activity Log exported to the workspace)
Source: https://learn.microsoft.com/azure/azure-monitor/reference/tables/azureactivity
```kql
// Write and delete operations in the last 24h: "who changed what?"
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue endswith "/WRITE" or OperationNameValue endswith "/DELETE" or OperationNameValue endswith "/ACTION"
| where ActivityStatusValue in ("Success", "Failure", "Failed")
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, ResourceGroup, _ResourceId
| order by TimeGenerated desc
```
```kql
AzureActivity
| where TimeGenerated > ago(24h) and CategoryValue in ("ServiceHealth", "ResourceHealth")
| project TimeGenerated, CategoryValue, OperationNameValue, ActivityStatusValue, _ResourceId, Properties
```

## Heartbeat (Azure Monitor Agent / Log Analytics agent)
Source: https://learn.microsoft.com/azure/azure-monitor/reference/tables/heartbeat
```kql
// Machines that have gone quiet: last heartbeat more than 10 minutes ago
Heartbeat
| where TimeGenerated > ago(24h)
| summarize lastSeen = max(TimeGenerated) by Computer, OSType, Category, _ResourceId
| where lastSeen < ago(10m)
| order by lastSeen asc
```

General KQL reference: https://learn.microsoft.com/kusto/query/

---
name: datadog
description: "Datadog adapter: metric, APM and log queries, monitors, SLOs, incidents and events. Uses the Datadog MCP server when available, otherwise the Datadog API with read-only application keys. Use when data or monitors live in Datadog. Process from sre-engineer, sre-slo-alerting, incident-command."
---

# Datadog

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Creating/muting monitors, downtimes, and incident updates are writes.

Process skills: `sre-engineer`, `sre-diagnostics`, `sre-slo-alerting`, `incident-command`. More queries: `observability-query-cookbook`.

## Access

- **MCP:** Datadog managed MCP server (`https://mcp.datadoghq.com/v1/mcp`, or your site's endpoint, e.g. `mcp.datadoghq.eu`). Prefer a user/role with read-only permissions.
- **API fallback:** `DD_API_KEY` + an application key scoped to read (`DD_APP_KEY`); use your site, e.g. `api.datadoghq.com`.

## Query syntax

Metrics: `<aggregation>:<metric>{<tag filters>} by {<group>}`

```text
avg:system.cpu.user{env:prod} by {host}
sum:trace.http.request.errors{service:<svc>,env:prod}.as_count()
sum:trace.http.request.hits{service:<svc>,env:prod}.as_count()
p95:trace.http.request{service:<svc>,env:prod}
avg:kubernetes.memory.usage{kube_namespace:<ns>} by {pod_name}
```

Logs search:

```text
service:<svc> env:prod status:error
@http.status_code:[500 TO 599] service:<svc>
```

## Read-only API calls

```bash
# Metric query (last hour)
curl -sG "https://api.datadoghq.com/api/v1/query" \
  -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  --data-urlencode "from=$(($(date +%s)-3600))" --data-urlencode "to=$(date +%s)" \
  --data-urlencode "query=sum:trace.http.request.errors{service:<svc>}.as_count()"
# Monitors currently alerting
curl -sG "https://api.datadoghq.com/api/v1/monitor" \
  -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  --data-urlencode "monitor_tags=service:<svc>" --data-urlencode "group_states=alert"
# Log search (v2)
curl -s -X POST "https://api.datadoghq.com/api/v2/logs/events/search" \
  -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" -H "Content-Type: application/json" \
  -d '{"filter":{"query":"service:<svc> status:error","from":"now-15m","to":"now"},"page":{"limit":50}}'
```

## Monitor definition (for review; create only after approval)

```text
Query:  sum(last_5m):sum:trace.http.request.errors{service:<svc>}.as_count() / sum:trace.http.request.hits{service:<svc>}.as_count() > 0.01
Message must include: impact, runbook link, @pagerduty-<service> or @opsgenie-<team> handle
```

Prefer SLO burn-rate alerts on a Datadog SLO over raw threshold monitors (`sre-slo-alerting`).

## Output

- Queries used, results, and any proposed monitor/downtime change with risk and approval status

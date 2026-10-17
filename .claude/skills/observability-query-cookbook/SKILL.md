---
name: observability-query-cookbook
description: "Tested query cookbook for golden signals, RED/USE, saturation, error ratio, latency percentiles and SLO burn rate in PromQL, Dynatrace DQL, Datadog and LogQL. Use when you need a correct query for any monitoring tool; runs via MCP query tools when available."
---

# Observability Query Cookbook

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Queries are read-only, but heavy queries can load the backend: bound the time range.

Adjust metric and label names to your environment. For tool-specific depth see `prometheus-grafana`, `dynatrace-sre`, `datadog`.

## Error ratio (5xx / total)

```promql
sum(rate(http_requests_total{job="<svc>",code=~"5.."}[5m]))
/
sum(rate(http_requests_total{job="<svc>"}[5m]))
```

```text
# Datadog (APM)
sum:trace.http.request.errors{service:<svc>}.as_count() / sum:trace.http.request.hits{service:<svc>}.as_count()
```

```dql
timeseries { total = sum(dt.service.request.count), failed = sum(dt.service.request.failure_count) }, by: { dt.entity.service }
| fieldsAdd error_ratio = failed[] / total[]
```

## Latency p95

```promql
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="<svc>"}[5m])))
```

```text
# Datadog (APM, distribution metric)
p95:trace.http.request{service:<svc>}
```

```dql
timeseries p95 = percentile(dt.service.request.response_time, 95), by: { dt.entity.service }
```

## Saturation

```promql
# CPU used by container vs. limit
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="<ns>"}[5m]))
/
sum by (pod) (kube_pod_container_resource_limits{namespace="<ns>",resource="cpu"})
```

```text
# Datadog
avg:kubernetes.cpu.usage.total{kube_namespace:<ns>} by {pod_name}
```

```dql
timeseries cpu = avg(dt.host.cpu.usage), by: { dt.entity.host }
| sort arrayAvg(cpu) desc
| limit 10
```

## SLO burn rate (99.9% SLO, 1h window)

```promql
(
  sum(rate(http_requests_total{job="<svc>",code=~"5.."}[1h]))
  /
  sum(rate(http_requests_total{job="<svc>"}[1h]))
) / (1 - 0.999)
```

Page when burn > 14.4 over 1h AND > 14.4 over 5m (see `sre-slo-alerting`).

## Logs

```logql
sum by (level) (count_over_time({app="<svc>"} |= "error" [5m]))
```

```dql
fetch logs, from: now()-1h
| filter loglevel == "ERROR" and k8s.namespace.name == "<ns>"
| summarize count = count(), by: { k8s.workload.name }
| sort count desc
```

```text
# Datadog log search
service:<svc> status:error
```

## Kubernetes restarts

```promql
increase(kube_pod_container_status_restarts_total{namespace="<ns>"}[1h]) > 0
```

## Output

- The query (with tool, time range, and assumptions about metric names) and how to read the result

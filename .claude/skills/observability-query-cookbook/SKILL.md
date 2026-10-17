---
name: observability-query-cookbook
description: "Tested query cookbook for golden signals, RED/USE, saturation, error ratio, latency percentiles and SLO burn rate in PromQL, Dynatrace DQL, Datadog and LogQL. Use when you need a correct query for any monitoring tool; runs via MCP query tools when available."
---

# Observability Query Cookbook

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Queries are read-only, but heavy queries can load the backend: bound the time range.

Adjust metric and label names to your environment. Dynatrace queries use Smartscape forms (`dt.smartscape.*`, `getNodeName()`); classic fallback is `dt.entity.*` with `entityName()`. Reviewed against Dynatrace dynatrace-for-ai skills. For tool-specific depth see `prometheus-grafana`, `dynatrace-sre`, `datadog`.

## Error ratio (5xx / total)

```promql
sum(rate(http_requests_total{job="<svc>",code=~"5.."}[5m]))
/
sum(rate(http_requests_total{job="<svc>"}[5m]))
```

```text
# Datadog (APM)
# span name varies by integration: trace.<span_name>.errors / .hits
sum:trace.http.request.errors{service:<svc>}.as_count() / sum:trace.http.request.hits{service:<svc>}.as_count()
```

```dql
timeseries { total = sum(dt.service.request.count), failed = sum(dt.service.request.failure_count) }, by: { dt.smartscape.service }
| fieldsAdd error_pct = if(total[] > 0, failed[] * 100.0 / total[])
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
timeseries p95_us = percentile(dt.service.request.response_time, 95), rollup: avg, by: { dt.smartscape.service }
// response_time is in microseconds
```

## Saturation

```promql
# CPU used by container vs. limit (container!="" drops pod-level cgroup series that double-count; pods without limits drop out)
sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{namespace="<ns>",container!="",container!="POD"}[5m]))
/
sum by (namespace, pod) (kube_pod_container_resource_limits{namespace="<ns>",resource="cpu",container!="",container!="POD"})
```

```text
# Datadog
# kubernetes.cpu.usage.total is in nanocores; compare to kubernetes.cpu.limits (cores) after unit conversion
avg:kubernetes.cpu.usage.total{kube_namespace:<ns>} by {pod_name}
avg:kubernetes.cpu.limits{kube_namespace:<ns>} by {pod_name}
```

```dql
// verify Kubernetes metric keys in your environment (verify_dql)
timeseries { used = sum(dt.kubernetes.container.cpu_usage), lim = sum(dt.kubernetes.container.limits_cpu) }, by: { k8s.pod.name }, filter: k8s.namespace.name == "<ns>"
| fieldsAdd cpu_pct = if(lim[] > 0, used[] * 100.0 / lim[])
| sort arrayMax(cpu_pct) desc
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

```dql
timeseries { total = sum(dt.service.request.count, scalar: true), failed = sum(dt.service.request.failure_count, scalar: true) }, by: { dt.smartscape.service }, from: now()-1h
| fieldsAdd burn = (failed / total) / (1 - 0.999)
```

```text
# Datadog SLO monitor query
burn_rate("<slo_id>").over("1h").long_window("1h").short_window("5m") > 14.4
```

Page when burn > 14.4 over 1h AND > 14.4 over 5m (see `sre-slo-alerting`).

## Logs

```logql
sum by (level) (count_over_time({app="<svc>"} |~ "(?i)error" | logfmt [5m]))
# Loki 3.x: use detected_level if the stream has no level label
```

```dql
fetch logs, from: now()-1h
| filter loglevel == "ERROR" and k8s.namespace.name == "<ns>"
| summarize errors = count(), by: { k8s.workload.name }
| sort errors desc
```

```text
# Datadog log search
service:<svc> status:error
```

## Kubernetes restarts

```promql
increase(kube_pod_container_status_restarts_total{namespace="<ns>"}[1h]) > 0
```

```dql
timeseries restarts = sum(dt.kubernetes.container.restarts), by: { k8s.pod.name }, filter: k8s.namespace.name == "<ns>", from: now()-1h
| filter arraySum(restarts) > 0
```

## Output

- The query (with tool, time range, and assumptions about metric names) and how to read the result

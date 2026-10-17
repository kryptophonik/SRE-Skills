# Datadog query cheatsheet (read-only)

Sources (checked 2026-10-16):
- Trace metrics: https://docs.datadoghq.com/tracing/metrics/metrics_namespace/
- Metric query syntax: https://docs.datadoghq.com/metrics/#querying-metrics
- Log search syntax: https://docs.datadoghq.com/logs/explorer/search_syntax/
- Span search syntax: https://docs.datadoghq.com/tracing/trace_explorer/query_syntax/
- Metric monitors: https://docs.datadoghq.com/monitors/types/metric/
- SLO burn-rate alerts: https://docs.datadoghq.com/service_management/service_level_objectives/burn_rate/

## APM trace metrics

Format: `trace.<SPAN_NAME>.<SUFFIX>`. `<SPAN_NAME>` is the operation name and **depends on the integration**
(`http.request`, `servlet.request`, `rack.request`, `flask.request`, `express.request`, `mysql.query`, ...).
Find yours in the APM service page or Metrics Summary (`trace.*`) before you use these queries.

| Metric | Type | Use |
|---|---|---|
| `trace.<span>.hits` | COUNT | request count |
| `trace.<span>.hits.by_http_status` | COUNT | count by `http.status_code` / `http.status_class` |
| `trace.<span>.errors` | COUNT | error count |
| `trace.<span>.errors.by_http_status` | COUNT | errors by status |
| `trace.<span>` | DISTRIBUTION | latency, **recommended for avg and percentiles** |
| `trace.<span>.apdex` | GAUGE | Apdex (HTTP/web services) |
| `trace.<span>.duration` | GAUGE | **legacy**, no percentiles |

Tags: `env`, `service`, `version`, `resource` / `resource_name`, `http.status_code`, `http.status_class`,
plus host and primary tags. Other span tags are **not** available on trace metrics.

```text
# Error ratio
sum:trace.<span>.errors{service:<svc>,env:<env>}.as_count() / sum:trace.<span>.hits{service:<svc>,env:<env>}.as_count()
# Throughput
sum:trace.<span>.hits{service:<svc>,env:<env>}.as_rate()
# Latency p95 / p99 (distribution)
p95:trace.<span>{service:<svc>,env:<env>}
p99:trace.<span>{service:<svc>,env:<env>} by {resource_name}
# Legacy average latency (only if you need host-tag filters)
sum:trace.<span>.duration{service:<svc>}.rollup(sum).fill(zero) / sum:trace.<span>.hits{service:<svc>}.rollup(sum).fill(zero)
```

## Infrastructure

```text
avg:system.cpu.user{env:<env>} by {host}
avg:system.mem.pct_usable{env:<env>} by {host}
avg:kubernetes.cpu.usage.total{kube_namespace:<ns>} by {pod_name}    # unit: nanocore (gauge)
avg:kubernetes.cpu.limits{kube_namespace:<ns>} by {pod_name}         # unit: core. Usage is nanocores: divide usage by 1e9 (or multiply limits by 1e9) before comparing
(avg:kubernetes.cpu.usage.total{kube_namespace:<ns>} by {pod_name} / 1e9) / avg:kubernetes.cpu.limits{kube_namespace:<ns>} by {pod_name}   # usage / limit ratio
avg:kubernetes.memory.usage{kube_namespace:<ns>} by {pod_name}       # unit: byte
# units: https://github.com/DataDog/integrations-core/blob/master/kubelet/metadata.csv
```

## Logs search

```text
service:<svc> env:<env> status:error
@http.status_code:[500 TO 599] service:<svc>
service:<svc> -status:info "timeout"
```

## Spans search (Trace Explorer / POST /api/v2/spans/events/search)

```text
service:<svc> env:<env> status:error
service:<svc> @duration:>1s          # duration is stored in nanoseconds; time units like ms/s are accepted in queries (https://docs.datadoghq.com/tracing/trace_explorer/query_syntax/)
resource_name:"GET /api/users"
trace_id:<id>
```

## Monitor (draft for review; creating it is a write and needs approval)

```text
sum(last_5m):sum:trace.<span>.errors{service:<svc>,env:<env>}.as_count() / sum:trace.<span>.hits{service:<svc>,env:<env>}.as_count() > 0.01
```

## SLO burn-rate monitor (draft; needs an existing SLO id)

```text
burn_rate("<slo_id>").over("30d").long_window("1h").short_window("5m") > 14.4
```

Replace `30d` with your SLO's target window (`7d`, `30d`, or `90d`). Recommended pairs from https://docs.datadoghq.com/service_management/service_level_objectives/burn_rate/ (short window = 1/12 of long window):

| SLO window | Burn rate | Long | Short | Budget consumed |
|---|---|---|---|---|
| 7d | 16.8 | 1h | 5m | 10% |
| 7d | 5.6 | 6h | 30m | 20% |
| 7d | 2.8 | 24h | 120m | 40% |
| 30d | 14.4 | 1h | 5m | 2% |
| 30d | 6 | 6h | 30m | 5% |
| 30d | 3 | 24h | 120m | 10% |
| 90d | 21.6 | 1h | 5m | 1% |
| 90d | 10.8 | 6h | 30m | 3% |
| 90d | 4.5 | 24h | 120m | 5% |

Burn rate alerts are only available for metric-based SLOs and for monitor-based SLOs built from metric monitors (same source).

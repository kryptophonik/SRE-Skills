# PromQL cheatsheet (generic, portable)

Sources (all fetched 2026-10-16; "latest" = Prometheus 3.x, verified with promtool 3.15.0):

- Basics: https://prometheus.io/docs/prometheus/latest/querying/basics/
- Operators / vector matching: https://prometheus.io/docs/prometheus/latest/querying/operators/
- Functions: https://prometheus.io/docs/prometheus/latest/querying/functions/
- Histograms: https://prometheus.io/docs/practices/histograms/
- Recording-rule naming: https://prometheus.io/docs/practices/rules/
- 2.x to 3.0 migration: https://prometheus.io/docs/prometheus/latest/migration/
- Grafana `$__rate_interval`: https://grafana.com/docs/grafana/latest/datasources/prometheus/template-variables/ (Grafana 13.x)

Placeholders: `<svc>`, `<ns>`, `<instance>`. Metric and label names (`http_requests_total`, `code` or `status`, `le`) depend on your instrumentation, so check them with `promtool query series` or the `/api/v1/series` endpoint first. Every query in this file passes `promtool check rules --lint=all`.

## Rules that prevent most wrong answers

| Rule | Why (doc) |
|---|---|
| Use `rate()`/`increase()`/`irate()` only on counters (`*_total`, `*_bucket`, `*_count`, `*_sum`) | They "should only be used with counters" (functions) |
| Take `rate()` first, then aggregate: `sum(rate(x[5m]))`, never `rate(sum(x)[5m:])` | "always take a rate() first, then aggregate. Otherwise rate() cannot detect counter resets" (functions) |
| Range of at least 4x the scrape interval (e.g. `[1m]` for 15s scrapes, `[5m]` is safe up to a 60s scrape interval) | Grafana `$__rate_interval` = max(`$__interval` + scrape, 4 × scrape); in dashboards use `[$__rate_interval]` |
| Sum both sides of a ratio with the **same** `by (...)` labels | Otherwise vector matching drops or mismatches series (operators) |
| Keep `le` in `sum by (..., le)` before `histogram_quantile` on classic histograms | (functions, histogram_quantile) |
| Regex label matchers are fully anchored: `code=~"5.."` matches 500–599, not `1500` | (basics) |
| Always put a `job`/`namespace` selector on ad-hoc queries | Bounds cost and avoids mixing services |

## Golden signals / RED

```promql
# Traffic (req/s) per job
sum by (job) (rate(http_requests_total{job="<svc>"}[5m]))

# Error ratio (5xx / all); use the label your instrumentation uses (code or status)
sum by (job) (rate(http_requests_total{job="<svc>",code=~"5.."}[5m]))
/
sum by (job) (rate(http_requests_total{job="<svc>"}[5m]))

# Latency p95, classic histogram (needs le)
histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket{job="<svc>"}[5m])))

# Latency p95, native histogram (no _bucket suffix, no le)
histogram_quantile(0.95, sum by (job) (rate(http_request_duration_seconds{job="<svc>"}[5m])))

# Latency SLI: share of requests faster than 300ms. The le value must be an existing bucket boundary.
sum by (job) (rate(http_request_duration_seconds_bucket{job="<svc>",le="0.3"}[5m]))
/
sum by (job) (rate(http_request_duration_seconds_count{job="<svc>"}[5m]))
```

## SLO / burn rate

```promql
# Burn rate over 1h for a 99.9% SLO (1 = budget lasts exactly the SLO period)
(
  sum by (job) (rate(http_requests_total{job="<svc>",code=~"5.."}[1h]))
  /
  sum by (job) (rate(http_requests_total{job="<svc>"}[1h]))
) / (1 - 0.999)
```

For alerting, don't hand-write this. Generate the four-tier rules with `scripts/gen-burn-rate-rules.py` (see `slo-burn-rate.rules.yml`).

## Saturation (USE)

```promql
# Container CPU vs limit (cAdvisor + kube-state-metrics). Exclude the pod-level cgroup (container="")
# and the pause container, or usage is double-counted. Pods without a CPU limit drop out of the ratio.
sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{namespace="<ns>",container!="",container!="POD"}[5m]))
/
sum by (namespace, pod) (kube_pod_container_resource_limits{namespace="<ns>",resource="cpu"})

# Node memory utilisation (node_exporter)
1 - node_memory_MemAvailable_bytes{instance="<instance>"} / node_memory_MemTotal_bytes{instance="<instance>"}

# Disk predicted to fill within 4h (linear fit over 6h)
predict_linear(node_filesystem_avail_bytes{instance="<instance>",fstype!~"tmpfs|overlay"}[6h], 4 * 3600) < 0

# Container restarts in the last hour (kube-state-metrics). increase() extrapolates, so values may be non-integer.
increase(kube_pod_container_status_restarts_total{namespace="<ns>"}[1h]) > 0
```

## Availability of the monitoring itself

```promql
up{job="<svc>"} == 0                          # target down (scrape failing)
absent(up{job="<svc>"})                       # job has no targets at all (alert on this too)
absent_over_time(up{job="<svc>"}[10m])        # no samples for 10m
ALERTS{alertstate="firing"}                   # firing alerts only (/api/v1/alerts also returns pending)
```

## Bounding cost

- Use `topk(10, ...)` when exploring, and short ranges for range queries.
- For windows of 1h or more that you evaluate repeatedly, use recording rules named `level:metric:operations`, e.g. `job:http_requests:rate5m` (practices/rules).
- Check cardinality with `GET /api/v1/status/tsdb`, not `count by (__name__) ({__name__=~".+"})`, which touches every series.

## Changed in Prometheus 3.x (check old snippets)

- Range and lookback selectors are now **left-open** (left boundary excluded). Windows that are exact multiples of the scrape interval hold one fewer sample than in 2.x. Unit tests and `[1m]` ranges over 30s+ scrapes are the most affected (migration guide).
- `holt_winters()` was renamed to `double_exponential_smoothing()` and needs `--enable-feature=promql-experimental-functions` (migration guide).

# Monitor query to PromQL translation

What `monitors_to_prom.py` does with each piece of a metric monitor query, and what it refuses
to guess. Monitor query grammar: [create a monitor](https://docs.datadoghq.com/api/latest/monitors/#create-a-monitor)
(Metric Alert Query section). Evaluation order with `.as_count()`:
[as_count() in monitor evaluations](https://docs.datadoghq.com/monitors/guide/as-count-in-monitor-evaluations/).
Rule file format: [alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/),
[recording rules / rule groups](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/),
[promtool](https://prometheus.io/docs/prometheus/latest/command-line/promtool/). All checked 2026-10-18.

## Mapping

| Monitor query part | PromQL output | Exact? |
|---|---|---|
| `avg/min/max/sum:` space aggregation | `avg/min/max/sum(...)` | yes |
| `by {a,b}` | `by (a, b)` after the labels map | yes |
| `{key:value}` | `{key="value"}` | yes |
| `{!key:value}` | `{key!="value"}` | yes |
| `{key:val*}` wildcard | `{key=~"val.*"}` | yes |
| `{key IN (a,b)}` / `NOT IN` | `{key=~"a\|b"}` / `{key!~"a\|b"}` | yes |
| `{*}` | no matcher | yes |
| `avg/min/max(last_N):` on plain metrics | `<agg>_over_time((expr)[N:])` subquery: arithmetic per point first, then the time aggregation, same order as the monitor's default path | close; step is the rule evaluation interval |
| `sum(last_N):` on plain metrics | `sum_over_time((expr)[N:])` | approximate, depends on point interval (flagged) |
| `sum(last_N):` with `.as_count()` | `sum(increase(m[N]))` per query, then the arithmetic, the same order the vendor's count path uses | close; `increase()` extrapolates at window edges |
| `avg(last_N):` single query with `.as_rate()` | `sum(rate(m[N]))` | close |
| `.as_rate()` inside a larger expression | `rate(m[2m])` inside the subquery (`--rate-window`) | approximate |
| metric mapped as `{"counter": true}` with no modifier | wrapped in `rate()` (flagged) | approximate |
| `change(agg(last_N),S_ago):` | `agg_over_time(((x) - (x offset S))[N:])` | approximate (flagged) |
| `pct_change(agg(last_N),S_ago):` | `agg_over_time((((x) - (x offset S)) / (x offset S) * 100)[N:])` | approximate (flagged) |
| `abs()`, `log2()`, `log10()` | same function | yes |
| `hour_before()`, `day_before()`, `week_before()`, `month_before()` | `offset 1h/1d/1w/4w` (month is 4 weeks) | yes / month approximate |
| `timeshift(q, -N)` | `offset Ns` | yes |
| `per_second(q)` | treated as `.as_rate()` | approximate |
| `default_zero(q)` | `(q) or vector(0)` (flagged: fills only when the whole result is empty) | partial |
| `.rollup()`, `.fill()` | dropped (flagged) | no |
| comparator `> >= < <= == !=` and number | same | yes |
| `options.thresholds.warning` | second rule, `severity: warning` | yes |
| `notify_no_data` without groups | extra `absent_over_time(m[no_data_timeframe])` rule | close |
| `{{value}}`, `{{threshold}}`, `{{tag.name}}` in messages | `{{ $value }}`, the number, `{{ $labels.tag }}` | yes |
| `priority` | label `priority: P<n>` | yes |

Metric names: give real names in the map. Unmapped names have dots replaced by underscores and are
flagged, because vendor agent metric names and exporter metric names rarely match
(`system.cpu.user` is not `node_cpu_seconds_total`).

## Does not translate (reported, never guessed)

- `anomalies()`, `forecast()`, `outliers()`: no PromQL equivalent.
- Smoothing and regression functions (`ewma_*`, `median_*`, `robust_trend`, `trend_line`, `piecewise_constant`), `cumsum`, `integral`, `diff`, `derivative`, `monotonic_diff`, `top`, `count_nonzero`, `count_not_null`.
- Boolean tag scopes (`a OR b`, `AND`, parentheses) and bare tags without a key.
- `.as_count()` with `avg/min/max` time aggregation, or mixed with non-count queries.
- Formula queries and dynamic thresholds (`> threshold` with `critical_query`).
- Percentile time aggregation and any monitor type other than `metric alert` / `query alert` (log, APM, RUM, composite, SLO, synthetics, service check).
- **Refused in v1, listed under "Manual conversion needed":** queries grouped by different tags (the binary operator needs `on()`/`ignoring()` vector matching, which v1 does not generate), and recovery thresholds (`critical_recovery` / `warning_recovery`). Recovery thresholds are hysteresis: the alert stays on until the value crosses a second level. `keep_firing_for` only holds an alert for a fixed time, so it does not map cleanly; write a hysteresis expression by hand. The whole monitor is skipped rather than converted without it.
- Evaluation delay, new host/group delay, renotify, escalation messages, auto-resolve timeout, require-full-window, minimum failure duration, and notification handles (route those in Alertmanager).
- No-data alerts on grouped monitors (`absent_over_time()` drops group labels).

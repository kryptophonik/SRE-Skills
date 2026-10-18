---
name: sre-prometheus-grafana
description: "Use when metrics, logs or alerts live in Prometheus, Alertmanager, Loki or Grafana: bounded PromQL/LogQL, active alerts, rule linting with promtool, gated silences, dashboards."
---

# Prometheus and Grafana

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-slo-alerting`, `sre-engineer`, `sre-diagnostics`. More queries: `sre-observability-query-cookbook`.

## Rules

- **Ad-hoc queries need a selector and a bounded range** (e.g. `{job="<svc>"}`, `[5m]`, `--since=1h --limit=100`). No bare metric names over long ranges.
- **Build long windows (1d, 3d) from recording rules**, not raw ad-hoc queries.
- **Never call `/-/reload`, `/-/quit`, or the admin TSDB APIs** (`/api/v1/admin/tsdb/*`: delete_series, clean_tombstones, snapshot).
- Grafana service account tokens: Viewer (or custom read) role, **with an expiry**.
- Silences: preview with `amtool alert query` first; require `--author` plus a ticket or approval; **no empty or regex-only matchers** (`.*` silences everything).

## Access

- **MCP:** Grafana MCP server, pinned, with `--disable-write` (see `sre-safety-gates/references/mcp.md`).
- **CLI fallback:** `promtool`, `amtool`, `logcli`, or the Prometheus HTTP API.

## Read-only commands

```bash
# Instant query via HTTP API (selector required)
curl -sG "$PROM_URL/api/v1/query" --data-urlencode 'query=up{job="<svc>"} == 0'
# Active alerts (pending AND firing)
curl -s "$PROM_URL/api/v1/alerts" | jq -c '.data.alerts[] | {n:.labels.alertname,s:.state,j:.labels.job}' | head -50
# Firing only
curl -sG "$PROM_URL/api/v1/query" --data-urlencode 'query=ALERTS{alertstate="firing"}'
amtool alert query --alertmanager.url="$AM_URL" | head -50
amtool silence query --alertmanager.url="$AM_URL" | head -50
# Validate rule files before any change
promtool check rules --lint=all rules/*.yml
promtool test rules tests/*.yml
# Loki (bounded)
LOKI_ADDR=<loki-url> logcli query --since=1h --limit=100 '{app="<svc>"} |~ "(?i)error"'
```

## Write commands (approval required)

```bash
# 1. Preview exactly what the matchers hit
amtool alert query alertname="<name>" service="<svc>" --alertmanager.url="$AM_URL"
# 2. Silence with author + ticket, explicit matchers, short duration
amtool silence add alertname="<name>" service="<svc>" --author="<you>" --duration=1h --comment="<ticket/incident ID>" --alertmanager.url="$AM_URL"
amtool silence expire <silence-id> --alertmanager.url="$AM_URL"
```

## Multiwindow burn-rate rules (99.9% SLO)

Genuine config example (passes `promtool check rules` and a unit test). Recording rules follow `level:metric:operations` naming, aggregate `sum by (job)`, and select `job="<svc>"` (here `example-svc`). Thresholds are `N * (1 - SLO)`; for 99.9%, `1 - 0.999 = 0.001`.

| Tier | Burn | Long / short window | Severity |
|---|---|---|---|
| 1 | 14.4x | 1h / 5m | page |
| 2 | 6x | 6h / 30m | page |
| 3 | 3x | 1d / 2h | ticket |
| 4 | 1x | 3d / 6h | ticket |

The short window already confirms the burn is ongoing; `for:` is only a noise filter (`for: 0m` is valid).

```yaml
groups:
  - name: slo-example-svc
    rules:
      - record: job:slo_errors_per_request:ratio_rate5m
        expr: sum by (job) (rate(http_requests_total{job="example-svc",code=~"5.."}[5m])) / sum by (job) (rate(http_requests_total{job="example-svc"}[5m]))
      - record: job:slo_errors_per_request:ratio_rate30m
        expr: sum by (job) (rate(http_requests_total{job="example-svc",code=~"5.."}[30m])) / sum by (job) (rate(http_requests_total{job="example-svc"}[30m]))
      - record: job:slo_errors_per_request:ratio_rate1h
        expr: sum by (job) (rate(http_requests_total{job="example-svc",code=~"5.."}[1h])) / sum by (job) (rate(http_requests_total{job="example-svc"}[1h]))
      - record: job:slo_errors_per_request:ratio_rate2h
        expr: sum by (job) (rate(http_requests_total{job="example-svc",code=~"5.."}[2h])) / sum by (job) (rate(http_requests_total{job="example-svc"}[2h]))
      - record: job:slo_errors_per_request:ratio_rate6h
        expr: sum by (job) (rate(http_requests_total{job="example-svc",code=~"5.."}[6h])) / sum by (job) (rate(http_requests_total{job="example-svc"}[6h]))
      - record: job:slo_errors_per_request:ratio_rate1d
        expr: sum by (job) (rate(http_requests_total{job="example-svc",code=~"5.."}[1d])) / sum by (job) (rate(http_requests_total{job="example-svc"}[1d]))
      - record: job:slo_errors_per_request:ratio_rate3d
        expr: sum by (job) (rate(http_requests_total{job="example-svc",code=~"5.."}[3d])) / sum by (job) (rate(http_requests_total{job="example-svc"}[3d]))
      - alert: SvcErrorBudgetBurn
        expr: |
          (job:slo_errors_per_request:ratio_rate1h > (14.4 * 0.001) and job:slo_errors_per_request:ratio_rate5m > (14.4 * 0.001))
          or
          (job:slo_errors_per_request:ratio_rate6h > (6 * 0.001) and job:slo_errors_per_request:ratio_rate30m > (6 * 0.001))
        for: 2m
        labels:
          severity: page
        annotations:
          summary: "{{ $labels.job }} burning error budget fast"
          runbook_url: "https://runbooks.example.com/slo-burn"
      - alert: SvcErrorBudgetBurnSlow
        expr: |
          (job:slo_errors_per_request:ratio_rate1d > (3 * 0.001) and job:slo_errors_per_request:ratio_rate2h > (3 * 0.001))
          or
          (job:slo_errors_per_request:ratio_rate3d > (1 * 0.001) and job:slo_errors_per_request:ratio_rate6h > (1 * 0.001))
        for: 1h
        labels:
          severity: ticket
        annotations:
          summary: "{{ $labels.job }} burning error budget slowly"
          runbook_url: "https://runbooks.example.com/slo-burn"
```

Deploy through Git, not by hand; never `/-/reload` from this skill.

## Version and deprecation notes

- **Prometheus 3:** range selectors are left-open; keep `rate()` windows ≥ 4× the scrape interval, and use `$__rate_interval` in Grafana panels.
- **Native histograms:** if enabled, `histogram_quantile(0.95, sum by (job) (rate(<metric>[5m])))` works without `_bucket`/`le`.
- **Promtail** reached EOL on 2026-03-02; use Grafana Alloy.
- **Grafana API keys** were replaced by service account tokens; `GRAFANA_API_KEY` is deprecated in mcp-grafana.
- **Legacy Grafana alerting** was removed in Grafana v11 (use Grafana Alerting).

## Bundled scripts and references

- Generate SLO burn-rate rules: `python3 scripts/gen-burn-rate-rules.py --help` (or `/sre-slo-burn-rate-rules`). Self-test: `PROMTOOL=<path> bash scripts/test-gen-burn-rate-rules.sh`.
- Syntax-check every PromQL code block in Markdown: `scripts/validate-promql-snippets.py --promtool <path> <files>`.
- Tested example + unit test: [references/slo-burn-rate.rules.yml](references/slo-burn-rate.rules.yml), [references/slo-burn-rate.test.yml](references/slo-burn-rate.test.yml)
- [references/promql-cheatsheet.md](references/promql-cheatsheet.md) · [references/logql-cheatsheet.md](references/logql-cheatsheet.md) · [references/safe-operations.md](references/safe-operations.md)

If neither the Grafana MCP server nor the CLIs are available, output the queries for the human and stop.


- Queries/rules used (with selector and range), lint/test results, and any proposed rule or silence change with risk and approval status

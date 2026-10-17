---
name: prometheus-grafana
description: "Prometheus, Alertmanager, Loki and Grafana adapter: PromQL/LogQL queries, alert rule files, promtool checks, silences, and dashboard lookup. Uses the Grafana MCP server with --disable-write when available, otherwise promtool/amtool/logcli and the HTTP API read-only. Use when data or alerts live in Prometheus/Grafana. Process from sre-slo-alerting and sre-engineer."
---

# Prometheus and Grafana

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Creating silences, editing alert rules or dashboards, and reloading Prometheus are writes.

Process skills: `sre-slo-alerting`, `sre-engineer`, `sre-diagnostics`. More queries: `observability-query-cookbook`.

## Access

- **MCP:** Grafana MCP server in read-only mode (`--disable-write`); query Prometheus/Loki datasources, search dashboards, list alert rules.
- **CLI fallback:** `promtool`, `amtool`, `logcli`, or the Prometheus HTTP API.

## Read-only commands

```bash
# Instant query via HTTP API
curl -sG "$PROM_URL/api/v1/query" --data-urlencode 'query=up{job="<job>"} == 0'
# Firing alerts
curl -s "$PROM_URL/api/v1/alerts"
amtool alert query --alertmanager.url="$AM_URL"
amtool silence query --alertmanager.url="$AM_URL"
# Validate rule files before any change
promtool check rules rules/*.yml
promtool test rules tests/*.yml
# Loki
logcli query --since=1h '{app="<svc>"} |= "error"'
```

## Write commands (approval required)

```bash
amtool silence add alertname="<name>" service="<svc>" --duration=1h --comment="<ticket/incident>" --alertmanager.url="$AM_URL"
amtool silence expire <silence-id> --alertmanager.url="$AM_URL"
```

## Burn-rate alert rule example (99.9% SLO)

This is a genuine config example, kept as YAML.

```yaml
groups:
  - name: slo-<svc>
    rules:
      - record: svc:error_ratio:rate5m
        expr: sum(rate(http_requests_total{job="<svc>",code=~"5.."}[5m])) / sum(rate(http_requests_total{job="<svc>"}[5m]))
      - record: svc:error_ratio:rate1h
        expr: sum(rate(http_requests_total{job="<svc>",code=~"5.."}[1h])) / sum(rate(http_requests_total{job="<svc>"}[1h]))
      - alert: SvcErrorBudgetFastBurn
        expr: svc:error_ratio:rate1h > (14.4 * 0.001) and svc:error_ratio:rate5m > (14.4 * 0.001)
        for: 2m
        labels:
          severity: page
        annotations:
          summary: "<svc> burning error budget 14.4x"
          runbook_url: "<link>"
```

Run `promtool check rules` and `promtool test rules` before proposing; deploy through Git, not by hand.

## Output

- Queries/rules used, results, and any proposed rule or silence change with risk and approval status

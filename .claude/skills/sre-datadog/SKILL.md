---
name: sre-datadog
description: "Use when metrics, traces, logs, monitors or SLOs live in Datadog: queries, monitor and SLO review, incidents and events. Read-only MCP or API (read-scoped keys); writes need approval."
---

# Datadog

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-engineer`, `sre-diagnostics`, `sre-slo-alerting`, `sre-incident-command`. More queries: `sre-observability-query-cookbook`.

**Verify in your environment before use:** span names, tag keys (`env`, `service`), your Datadog site, and MCP write tool names.

## Access

- **Site:** set `DD_SITE` (e.g. `datadoghq.com`, `datadoghq.eu`, `us3.datadoghq.com`) to avoid querying the wrong region. API base: `https://api.${DD_SITE:-datadoghq.com}`.
- **MCP:** `https://mcp.<site>/v1/mcp` (e.g. `https://mcp.datadoghq.com/v1/mcp`). Not available on FED sites (US1-FED, US2-FED). Default toolset is `core`; narrow with `?toolsets=` and `?omit_tools=`; avoid `toolsets=all`.
- **Auth preference:** OAuth > personal/service access token (bearer) > API key + application key.
- **Never echo keys.** Use env vars (`$DD_API_KEY`, `$DD_APP_KEY`) and env substitution in `.mcp.json`.

## Read-only enforcement (MCP writes are ON by default)

The Standard role includes `mcp_write`. Enforce read-only by at least one of:

1. A custom role with only `mcp_read` for the MCP identity.
2. Turn off **MCP Write Access** at the org level.
3. `omit_tools` for write tools (e.g. `create_datadog_monitor`, `create_datadog_notebook`, `edit_datadog_notebook` — verify names in your tool list).

Application keys: scope to `metrics_read`, `monitors_read`, `logs_read_data`, `apm_read`.

## Writes that need approval

`POST /api/v1/monitor` (create/update monitors), downtimes, mute/unmute, SLO create/update, incident create/update, events post, MCP write tools.

Logs and spans **search** use POST but are read-only.

## Query syntax

APM trace metrics are named `trace.<SPAN_NAME>.<suffix>`; the span name depends on the integration (`servlet.request`, `rack.request`, `flask.request`, `http.request`, …). Find yours in APM service page.

```text
avg:system.cpu.user{env:<env>} by {host}
sum:trace.<span_name>.errors{env:<env>,service:<svc>}.as_count()
sum:trace.<span_name>.hits{env:<env>,service:<svc>}.as_count()
p95:trace.<span_name>{env:<env>,service:<svc>}
avg:kubernetes.memory.usage{kube_namespace:<ns>} by {pod_name}
```

p95 requires the **distribution** trace metric (`trace.<span_name>`). The legacy `trace.<span_name>.duration` has no percentiles.

Logs search:

```text
service:<svc> env:<env> status:error
@http.status_code:[500 TO 599] service:<svc>
```

## Read-only API calls

```bash
DD_API="https://api.${DD_SITE:-datadoghq.com}"
H=(-H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY")
# Metric query (last hour)
curl -sG "$DD_API/api/v1/query" "${H[@]}" \
  --data-urlencode "from=$(($(date +%s)-3600))" --data-urlencode "to=$(date +%s)" \
  --data-urlencode "query=sum:trace.<span_name>.errors{env:<env>,service:<svc>}.as_count()"
# Monitors currently alerting
curl -sG "$DD_API/api/v1/monitor/search" "${H[@]}" \
  --data-urlencode 'query=status:alert tag:"service:<svc>"'
# Log search (v2, read-only POST)
curl -s -X POST "$DD_API/api/v2/logs/events/search" "${H[@]}" -H "Content-Type: application/json" \
  -d '{"filter":{"query":"service:<svc> status:error","from":"now-15m","to":"now"},"page":{"limit":50}}'
# Span search (v2, read-only POST)
curl -s -X POST "$DD_API/api/v2/spans/events/search" "${H[@]}" -H "Content-Type: application/json" \
  -d '{"data":{"type":"search_request","attributes":{"filter":{"query":"service:<svc> env:<env> status:error @duration:>1s","from":"now-15m","to":"now"},"page":{"limit":25}}}}'
```

## Rate limits and cost

- Check `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers; on `429` back off until reset.
- Use short time windows and small `page.limit`; avoid `toolsets=all` in MCP.

## Monitor definition (for review; create only after approval)

```text
Query:  sum(last_5m):sum:trace.http.request.errors{service:<svc>,env:<env>}.as_count() / sum:trace.http.request.hits{service:<svc>,env:<env>}.as_count() > 0.01
Message must include: impact, runbook link, @pagerduty-<service> or @opsgenie-<team> handle
```

Prefer SLO burn-rate alerts on a Datadog SLO over raw threshold monitors (`sre-slo-alerting`, `sre-observability-query-cookbook`).

## Bundled scripts and references

Env: `DD_API_KEY`, `DD_APP_KEY` (read-scoped), `DD_SITE` (default `datadoghq.com`). Keys go to curl on stdin; 429s retry; result sizes are capped.

```bash
bash scripts/dd_query.sh 'avg:system.cpu.user{env:<env>} by {host}' 60
bash scripts/dd_logs_search.sh 'service:<svc> env:<env> status:error' 15 50
bash scripts/dd_spans_search.sh 'service:<svc> env:<env> status:error' 15 50
bash scripts/dd_monitors_alerting.sh 'tag:"service:<svc>"' 30
```

- [references/query-cheatsheet.md](references/query-cheatsheet.md) · [references/api-endpoints.md](references/api-endpoints.md) · [references/app-key-scopes.md](references/app-key-scopes.md) · [references/mcp-read-only.md](references/mcp-read-only.md)

If neither the Datadog MCP server nor API keys are available, output the queries for the human and stop.

## Output

- Queries used (with site and time window), results, and any proposed monitor/downtime/SLO change with risk and approval status

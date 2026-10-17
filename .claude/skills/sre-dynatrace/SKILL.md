---
name: sre-dynatrace
description: "Use when data lives in Dynatrace: DQL for problems, logs, metrics and entities, Davis problem triage, SLO and health checks. Read-only MCP or DQL for Notebooks."
---

# Dynatrace for SRE

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Read-only by default. MCP tools that write or notify (`send_slack_message`, `send_email`, `send_event`, `create_dynatrace_notebook`) need approval. Writing documents/notebooks also needs the `document:documents:write` scope, which read-only setups omit.

Process skills: `sre-incident-command`, `sre-engineer`, `sre-diagnostics`, `sre-slo-alerting`, `sre-dependency-mapping`.

## Access

- **MCP (preferred):** Dynatrace MCP server — tools such as `list_problems`, `execute_dql`, `verify_dql`, `find_entity_by_name`, `get_kubernetes_events`. Run `verify_dql` before `execute_dql` on new queries. The local `dynatrace-oss` server is deprecated (final 2.1.2); prefer Dynatrace for AI + `dtctl` or the Dynatrace Remote MCP Server (see `docs/mcp.md`).
- **Fallback:** paste DQL into a Notebook; give the user the query.
- Always bound the timeframe (`from: now()-2h`) to limit Grail scan cost.

## Triage flow

1. Open problems in scope (query below or `list_problems`).
2. For the top problem: affected entities, root-cause entity, start time.
3. Pull related logs and metrics for that entity and window.
4. Check recent deployments/config events on the entity.
5. Hand findings to `sre-engineer`; propose remediation with approval.

## DQL cookbook

Reviewed against Dynatrace's dynatrace-for-ai skills. Use the Smartscape forms (`dt.smartscape.*`, `smartscapeNodes`, `getNodeName()`) first. Classic fallback for older tenants: `dt.entity.*` dimensions with `entityName()` and `fetch dt.entity.<type>`.

Active problems:

```dql
fetch dt.davis.problems, from: now()-24h
| filter not(dt.davis.is_duplicate) and event.status == "ACTIVE"
| fields event.start, display_id, event.name, event.category, affected_entity_ids = smartscape.affected_entities[][id], root_cause_entity_id, root_cause_entity_name
| sort event.start desc
```

Problem count over time (noise trend):

```dql
fetch dt.davis.problems, from: now()-7d
| filter not(dt.davis.is_duplicate)
| makeTimeseries problems = count(default: 0), time: event.start, interval: 1h
```

Mean time to resolve:

```dql
fetch dt.davis.problems, from: now()-7d
| filter not(dt.davis.is_duplicate) and event.status == "CLOSED"
| fieldsAdd hours = toLong(event.end - event.start) / 3600000000000.0
| makeTimeseries avg_hours = avg(hours), time: event.end, interval: 1d
```

Host CPU top 10:

```dql
timeseries usage = avg(dt.host.cpu.usage), by: { dt.smartscape.host }
| fieldsAdd host = getNodeName(dt.smartscape.host)
| sort arrayAvg(usage) desc
| limit 10
```

Error logs by workload:

```dql
fetch logs, from: now()-1h
| filter loglevel == "ERROR"
| summarize errors = count(), by: { k8s.namespace.name, k8s.workload.name }
| sort errors desc
| limit 20
```

Service error % and p95 (`response_time` is in **microseconds**):

```dql
timeseries { total = sum(dt.service.request.count), failed = sum(dt.service.request.failure_count), p95_us = percentile(dt.service.request.response_time, 95, rollup: avg) }, by: { dt.smartscape.service }
| fieldsAdd service = getNodeName(dt.smartscape.service), error_pct = if(total[] > 0, failed[] * 100.0 / total[])
```

Find a service by name:

```dql
smartscapeNodes "SERVICE"
| filter contains(name, "<name>", caseSensitive: false)
| fields id, name
```

Verify field names in your environment first with `smartscapeNodes "SERVICE" | limit 1`. Classic fallback: `fetch dt.entity.service | filter contains(entity.name, "<name>") | fields id, entity.name`.

Metric and field names vary by environment and Grail version; check with `verify_dql` or Notebook autocomplete.

## Output

- Findings with the DQL used, timeframe, entities, problem IDs, and links/notebook names

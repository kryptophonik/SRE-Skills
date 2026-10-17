---
name: sre-dynatrace
description: "Use when data lives in Dynatrace: DQL for problems, logs, metrics and entities, Davis problem triage, SLO and health checks. Read-only MCP or DQL for Notebooks."
---

# Dynatrace for SRE

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-incident-command`, `sre-engineer`, `sre-diagnostics`, `sre-slo-alerting`, `sre-dependency-mapping`.

## Access

- **MCP (preferred):** Dynatrace MCP server — tools such as `<server>:list_problems`, `<server>:execute_dql`, `<server>:verify_dql`, `<server>:find_entity_by_name`, `<server>:get_kubernetes_events` (fully qualified; check names with `/mcp`). Run `verify_dql` before `execute_dql` on new queries. The local `dynatrace-oss` server is deprecated (final 2.1.2); prefer Dynatrace for AI + `dtctl` or the Dynatrace Remote MCP Server (see `sre-safety-gates/references/mcp.md`).
- **Fallback:** paste DQL into a Notebook; give the user the query.
- Always bound the timeframe (`from: now()-2h`) to limit Grail scan cost.


## Scripts and references

These live in this skill's folder. Paths are relative to it.

- `scripts/dql.sh '<query>'` runs one read-only DQL query. It uses `dtctl` if it's installed and signed in. Otherwise it uses the Grail query API with `DT_ENVIRONMENT` and `DT_PLATFORM_TOKEN` from the environment. It refuses anything that isn't a read query (fetch, timeseries, smartscapeNodes, smartscapeEdges, data, describe, fieldsSnapshot). Use it when no Dynatrace MCP server is connected and the user has set up access.
- `scripts/check-fields.sh <data object> [window]` prints the field names of one sample record, for example `check-fields.sh logs 2h`. Run it before writing a query against fields you haven't seen in this tenant.
- [references/dql-cheatsheet.md](references/dql-cheatsheet.md) has the start commands, time ranges and the common-mistakes table. Read it before writing DQL.
- [references/metrics-and-fields.md](references/metrics-and-fields.md) lists metric keys, units and key fields. Anything marked "verify" has to be checked in the tenant.
- [references/problems.md](references/problems.md) has the problem triage queries.

To check a query before running it, or when it returns nothing, follow [references/dql-review.md](references/dql-review.md).

If neither MCP nor the scripts can reach the tenant, give the user the query to paste into a Notebook.

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

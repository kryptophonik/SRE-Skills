---
name: dynatrace-sre
description: "Dynatrace adapter for SRE work: DQL for problems, logs, metrics and entities; Davis problem triage; SLO and health checks. Uses the Dynatrace MCP server (execute_dql, list_problems, find_entity_by_name) read-only when available; otherwise gives DQL for Notebooks. Use whenever the data lives in Dynatrace. Process comes from incident-command, sre-engineer, sre-slo-alerting."
---

# Dynatrace for SRE

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Read-only by default. MCP tools that write or notify (`send_slack_message`, `send_email`, `send_event`, `create_dynatrace_notebook`) need approval.

Process skills: `incident-command`, `sre-engineer`, `sre-diagnostics`, `sre-slo-alerting`, `dependency-mapping`. Health-certification dashboards: use the separate Dynatrace health-cert skill.

## Access

- **MCP (preferred):** Dynatrace MCP server — tools such as `list_problems`, `execute_dql`, `verify_dql`, `find_entity_by_name`, `get_kubernetes_events`. Run `verify_dql` before `execute_dql` on new queries.
- **Fallback:** paste DQL into a Notebook; give the user the query.
- Always bound the timeframe (`from: now()-2h`) to limit Grail scan cost.

## Triage flow

1. Open problems in scope (query below or `list_problems`).
2. For the top problem: affected entities, root-cause entity, start time.
3. Pull related logs and metrics for that entity and window.
4. Check recent deployments/config events on the entity.
5. Hand findings to `sre-engineer`; propose remediation with approval.

## DQL cookbook

Active problems:

```dql
fetch dt.davis.problems, from: now()-24h
| filter event.status == "ACTIVE"
| filter dt.davis.is_duplicate == false
| fields event.start, display_id, event.name, event.category, affected_entity_ids, root_cause_entity_id
| sort event.start desc
```

Problem count over time (noise trend):

```dql
fetch dt.davis.problems, from: now()-7d
| makeTimeseries count = count(default: 0)
```

Mean time to resolve:

```dql
fetch dt.davis.problems, from: now()-7d
| filter event.status == "CLOSED"
| filter dt.davis.is_frequent_event == false and dt.davis.is_duplicate == false
| makeTimeseries avg_hours = avg(toLong(resolved_problem_duration) / 3600000000000.0), time: event.end
```

Host CPU top 10:

```dql
timeseries usage = avg(dt.host.cpu.usage), by: { dt.entity.host }
| fieldsAdd host = entityName(dt.entity.host)
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

Service error ratio and p95:

```dql
timeseries { total = sum(dt.service.request.count), failed = sum(dt.service.request.failure_count), p95 = percentile(dt.service.request.response_time, 95) }, by: { dt.entity.service }
| fieldsAdd service = entityName(dt.entity.service), error_ratio = failed[] / total[]
```

Find an entity by name:

```dql
fetch dt.entity.service
| filter contains(entity.name, "<name>")
| fields id, entity.name
```

Metric and field names vary by tenant and Grail version; check with `verify_dql` or the Notebook autocomplete.

## Output

- Findings with the DQL used, timeframe, entities, problem IDs, and links/notebook names

# DQL cheat sheet

Short reference for writing Grail DQL. Check field names with `describe` or `| limit 1` before trusting a query.

## Starting a query

| Data | Start with |
|---|---|
| Logs, spans, events, problems | `fetch logs`, `fetch spans`, `fetch events`, `fetch dt.davis.problems` |
| Metrics | `timeseries avg(dt.host.cpu.usage)` (there is no `fetch` for metrics) |
| Topology (current) | `smartscapeNodes`, `dt.smartscape.*` fields, `getNodeName()` |
| Topology (classic, older tenants) | `fetch dt.entity.<type>`, `entityName()` (deprecated) |
| Inline test data | `data record(a = 1)` |
| Schema | `describe <data object>`, `fieldsSnapshot` |

Pipeline commands you will use most: `filter`, `filterOut`, `fields`, `fieldsAdd`, `summarize ..., by: {...}`, `sort`, `limit`, `dedup`, `expand`, `lookup`, `join`, `makeTimeseries`.

Always bound the time range (`from: now()-2h`). Less data scanned means faster and cheaper queries.

## Time

- Relative: `from: -24h` or `from: now()-2h`.
- Alignment: `now()@h` is the top of the hour, `now()@d` is midnight. Offset first, then align: `now()-2h@h`. No space before `@`.
- Absolute ranges: `timeframe: "2026-01-01T00:00:00Z/2026-01-02T00:00:00Z"` (a quoted ISO 8601 string). `from: toTimestamp(...)` is wrong.

## Common mistakes

| Wrong | Right | Why |
|---|---|---|
| `timeseries p95 = percentile(m, 95)` | `timeseries p95 = percentile(m, 95), rollup: avg` | `percentile`, `median` and `percentRank` on metrics need `rollup:`. Without it you get an empty result, not an error. |
| `summarize p95 = percentile(duration, 95, rollup: avg)` | `summarize p95 = percentile(duration, 95)` | `rollup:` exists only in `timeseries`. In `summarize` it fails with `UNKNOWN_PARAMETER_DEFINED`. |
| `timeseries {a = percentile(m, 90), b = median(m)}, rollup: avg` | `timeseries {a = percentile(m, 90, rollup: avg), b = median(m, rollup: avg)}` | With several aggregations in `{}`, put `rollup:` inside each function. |
| `filter dt.davis.is_duplicate == false` | `filter not(dt.davis.is_duplicate)` | The form used throughout Dynatrace's problem examples. |
| `filter k8s.namespace.name == "ns"` on problems | `filter in(k8s.namespace.name, {"ns"})` | `k8s.*` fields are arrays on `dt.davis.problems`. `==` on an array matches nothing and gives no error. |
| `arrayContains(f, "v")` | `in(f, {"v"})` | `arrayContains` does not exist in DQL. |
| `iAny(f1[] == "a" AND f2[] == "b")` | `in(f1, "a") AND in(f2, "b")` | Iterating two arrays is pairwise by index, not every combination. |
| `arrayMax(a[] / b[])` | `fieldsAdd r = a[] / b[]` then `arrayMax(r)` | An iterative expression is not an array. Store it with `fieldsAdd` first. (Seen in practice; the docs describe iterative expressions in iterative-expressions.md.) |
| `arrayAvg(f[])` | `arrayAvg(f)` | `f[]` is element-wise; array functions take the array itself. |
| `timeseries x = avg(m)` then `arrayAvg(x)` just to get one number | `timeseries x = avg(m, scalar: true)` | `scalar: true` returns one value without building the array. |
| `filter host = "A"` | `filter host == "A"` | `=` is assignment. |
| `filter name == "*web*"` | `filter matchesValue(name, "*web*")` | `==` has no wildcards. |
| `filter log.level == "ERROR"` | `filter loglevel == "ERROR"` | The log field is `loglevel`. |
| `event.status == "OPEN"` | `event.status == "ACTIVE"` | Problem status is `ACTIVE` or `CLOSED`. |
| `by: {dt.entity.host}` | `by: {dt.smartscape.host}` | `dt.entity.*` is deprecated. Keep it only as a fallback for tenants without Smartscape on Grail. |
| `data record(key: "v")` | `data record(key = "v")` | `:` is for command parameters. |
| `timeseries sum(my.metric-name)` | `timeseries sum(\`my.metric-name\`)` | Keys with hyphens need backticks. |

## Sources

- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-dql-essentials/SKILL.md (pitfalls table, rollup, scalar, time alignment, smartscape deprecation)
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-dql-essentials/references/iterative-expressions.md
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-dql-essentials/references/dql/dql-commands.md
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-problems/SKILL.md (status values, duplicate filter)
- https://docs.dynatrace.com/docs/platform/grail/dynatrace-query-language

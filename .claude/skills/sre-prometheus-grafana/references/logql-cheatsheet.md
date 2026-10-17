# LogQL and logcli cheatsheet (generic, portable)

Sources (all fetched 2026-10-16; "latest" = Loki 3.7.x, verified against a local Loki v3.7.8 + logcli v3.7.8):

- Log queries: https://grafana.com/docs/loki/latest/query/log_queries/
- Metric queries: https://grafana.com/docs/loki/latest/query/metric_queries/
- Query best practices: https://grafana.com/docs/loki/latest/query/bp-query/
- logcli: https://grafana.com/docs/loki/latest/query/logcli/getting-started/
- Promtail EOL: https://grafana.com/docs/loki/latest/send-data/promtail/

Placeholders: `<svc>`, `<ns>`, `<loki-url>`. Stream labels such as `app`, `namespace`, `service_name` and `job` depend on your collector config.

## Write queries in this order (cheapest first)

1. **Narrow the time range** (`--since`, `--from/--to`, or the Grafana time picker). This matters most for cost (bp-query).
2. **Use the most specific stream selector**, e.g. `{app="<svc>",namespace="<ns>"}`. `=~`/`!~` here are **fully anchored**.
3. **Line filters** next: `|=`, `!=`, `|~`, `!~`. These are the fastest stage. Their regexes are **not** anchored, and `(?i)` makes them case-insensitive.
4. **Parsers** last: `| logfmt`, `| json`, `| pattern "<pattern>"`, `| regexp "<re>"`, `| unpack`. Use `json`/`logfmt` when you can (log_queries).
5. **Label filters / formatting** after parsing: `| status >= 500`, `| duration > 1s`, `| line_format "{{.msg}}"`.

## Log queries

```logql
{app="<svc>"} |~ "(?i)error"
{app="<svc>",namespace="<ns>"} |= "timeout" != "healthcheck"
{app="<svc>"} | logfmt | level="error" | status >= 500
{app="<svc>"} | json | duration > 1s | line_format "{{.msg}}"
{app="<svc>"} | logfmt | __error__=""
```

`__error__=""` drops lines the parser could not parse. A failed conversion in a label filter does not drop the line; it adds an `__error__` label instead (log_queries).

## Metric queries

```logql
sum by (app) (rate({app="<svc>"} |~ "(?i)error" [5m]))
sum by (level) (count_over_time({app="<svc>"} | logfmt [5m]))
sum by (app) (count_over_time({app="<svc>"} | logfmt | status >= 500 [5m])) / sum by (app) (count_over_time({app="<svc>"} | logfmt [5m]))
quantile_over_time(0.95, {app="<svc>"} | logfmt | unwrap duration(duration) | __error__="" [5m]) by (app)
topk(10, sum by (app) (bytes_over_time({namespace="<ns>"} [1h])))
```

- `sum by (level)` only works if `level` is a stream label or was extracted by a parser. Without `| logfmt`/`| json` it is empty.
- Use `unwrap` for numeric fields. `duration(label)` and `bytes(label)` convert units. Add `| __error__=""` after it so unparsable values are dropped (metric_queries).
- `offset` goes after the range: `count_over_time({app="<svc>"}[5m] offset 5m)`. Writing `... ) offset 5m` is **invalid** (metric_queries).

## logcli (read-only)

```bash
export LOKI_ADDR=<loki-url>          # or --addr; multi-tenant: --org-id; auth: --bearer-token / --username+--password
logcli labels                        # list label names
logcli series '{app="<svc>"}' --since=1h
logcli query  '{app="<svc>"} |~ "(?i)error"' --since=1h --limit=100      # default limit is 30 lines
logcli query  '{app="<svc>"} |= "error"' --from=2026-10-16T10:00:00Z --to=2026-10-16T11:00:00Z --limit=200 --output=raw
logcli instant-query 'sum by (app) (count_over_time({app="<svc>"} |= "error" [5m]))'
logcli series --analyze-labels '{namespace="<ns>"}' --since=1h          # find high-cardinality labels
```

Note: the logcli docs say "environment variables will always take precedence over command line arguments". Unset a stale `LOKI_ADDR` before you pass `--addr`.

## Deprecations

- **Promtail is EOL as of 2026-03-02**. New collection setups should use **Grafana Alloy**. Don't add Promtail configs to new runbooks (send-data/promtail).

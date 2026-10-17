# Safe operations: Prometheus, Alertmanager, Loki, Grafana

Everything in **Writes** needs explicit approval under `sre-safety-gates`: name the target, the exact change, the blast radius and the rollback. Reads come first.

Sources (all fetched 2026-10-16):

- Prometheus HTTP API (Prometheus 3.x): https://prometheus.io/docs/prometheus/latest/querying/api/
- Prometheus management API: https://prometheus.io/docs/prometheus/latest/management_api/
- Alertmanager v0.34.1 (`amtool --help`, README, `api/v2/openapi.yaml`): https://github.com/prometheus/alertmanager
- Grafana HTTP API overview (Grafana 13.x): https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/
- Grafana authentication: https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/authentication/
- Grafana service accounts: https://grafana.com/docs/grafana/latest/administration/service-accounts/ and the API at …/http-api/serviceaccount/
- API key migration: https://grafana.com/docs/grafana/latest/administration/service-accounts/migrate-api-keys/
- Dashboard API (new `/apis`): https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/dashboard/
- mcp-grafana v2.0.2 README: https://github.com/grafana/mcp-grafana

The commands below were run on 2026-10-16 against a local Prometheus 3.15.0 and Alertmanager 0.34.1 (behaviour noted inline).

## Read-only (no approval)

```bash
# Prometheus
curl -sG "$PROM_URL/api/v1/query" --data-urlencode 'query=up{job="<svc>"} == 0'
curl -sG "$PROM_URL/api/v1/query" --data-urlencode 'query=ALERTS{alertstate="firing"}'   # firing only
curl -s  "$PROM_URL/api/v1/alerts"         # all ACTIVE alerts: pending + firing
curl -s  "$PROM_URL/api/v1/rules"          # loaded rule groups and their health
curl -s  "$PROM_URL/api/v1/targets"        # scrape targets and their last error
curl -s  "$PROM_URL/api/v1/status/tsdb"    # cardinality stats (cheap)
promtool query instant "$PROM_URL" 'up{job="<svc>"}'
promtool check rules --lint=all --lint-fatal rules/*.yml
promtool test rules tests/*.yml
# Alertmanager (URL via --alertmanager.url or ~/.config/amtool/config.yml)
amtool alert query alertname="<name>" --alertmanager.url="$AM_URL"
amtool silence query --alertmanager.url="$AM_URL"
amtool silence query --within 2h --alertmanager.url="$AM_URL"   # expiring soon
amtool check-config alertmanager.yml
```

If your Prometheus needs auth, pass `-H "Authorization: Bearer $PROM_TOKEN"` to curl, or `--http.config.file=<file>` to promtool and amtool. Never paste tokens into commands that get logged.

## Writes (approval required)

### Alertmanager silences

1. **Preview what the matchers hit**, using the same matchers you plan to silence with:
   `amtool alert query alertname="<name>" service="<svc>" --alertmanager.url="$AM_URL"`
2. Create the silence with the narrowest equality matchers, a short duration, an owner and a ticket:
   `amtool silence add alertname="<name>" service="<svc>" --duration=1h --author="<you>" --comment="<ticket/incident>" --alertmanager.url="$AM_URL"`
   - amtool 0.34.1 refuses a silence with no comment ("comment required by config"). `--author` defaults to the local username, so set it explicitly.
   - Don't use empty, regex-only or `alertname`-only matchers in shared Alertmanagers: they silence every team's copy of that alert.
3. Record the returned ID. Check it with `amtool silence query <matchers>`, and **expire it when the work is done**: `amtool silence expire <silence-id>`.
4. API equivalents (Alertmanager v2): `POST /api/v2/silences` (create), `DELETE /api/v2/silence/{silenceID}` (expire). Both are writes.

### Prometheus config reload / shutdown

- `POST|PUT /-/reload` and `POST|PUT /-/quit` are **disabled unless Prometheus runs with `--web.enable-lifecycle`**. Without it they return 403 (tested). Treat reload as a deploy: run `promtool check config` and `promtool check rules` first, go through Git/CI, and have a rollback.
- In Kubernetes (Prometheus Operator) the operator reloads the server. Don't call `/-/reload` by hand.

### Prometheus admin TSDB APIs (destructive)

- `POST /api/v1/admin/tsdb/snapshot`, `POST /api/v1/admin/tsdb/delete_series`, `POST /api/v1/admin/tsdb/clean_tombstones`.
- They're only active with `--web.enable-admin-api`. Without it they return "admin APIs disabled" (tested). **Keep the flag off.** An agent must never call these: `delete_series` permanently deletes data.

### Grafana

- **Auth:** send `Authorization: Bearer <SERVICE_ACCOUNT_TOKEN>`. **API keys are deprecated**, and new setups can't create them, so migrate to service accounts (migrate-api-keys).
- **Least privilege:** use one service account per tool with the `Viewer` role (or a custom RBAC role with only the read actions it needs). Don't use `Editor`/`Admin` for agents. The mcp-grafana README suggests `Editor` "for convenience"; don't follow that for production.
- **Token lifetime:** tokens **never expire by default** (`secondsToLive: 0`). Create them with a lifetime, e.g. `POST /api/serviceaccounts/<id>/tokens {"name":"mcp-ro","secondsToLive":604800}`, and set the server's `token_expiration_day_limit`. Creating service accounts and tokens needs `serviceaccounts:create` / `serviceaccounts:write`, which is an admin task, so it isn't for the agent.
- **Write endpoints (approval required):**
  - Dashboards: `POST|PUT|DELETE /apis/dashboard.grafana.app/v1/namespaces/<namespace>/dashboards[/<uid>]`. The namespace is `default` for org 1 on OSS/on-prem, `org-<ORG_ID>` for other orgs, and `stacks-<STACK_ID>` on Grafana Cloud. The legacy `/api/dashboards/*` and `/api/folders/*` are **deprecated** in favour of `/apis/...` (HTTP API overview).
  - Alerting provisioning: `POST|PUT|DELETE /api/v1/provisioning/{alert-rules,contact-points,policies,mute-timings,templates}`. Use the `GET …/export` endpoints for read-only review.
  - Annotations, snapshots, folders, data sources: all writes.
- Legacy (dashboard) alerting was **removed in Grafana 11**. Use Grafana Alerting or Prometheus/Alertmanager rules.

### mcp-grafana (v2.0.2)

```json
{ "mcpServers": {
"grafana": {
  "command": "uvx", "args": ["mcp-grafana==<version>", "--disable-write", "--disable-admin"],
  "env": { "GRAFANA_URL": "https://grafana.example.com", "GRAFANA_SERVICE_ACCOUNT_TOKEN": "${GRAFANA_SA_TOKEN}" }
}
} }
```

- `--disable-write` removes the dashboard, folder, incident, alert-rule, silence, contact-point, annotation and snapshot write tools. It also removes the raw-SQL tools `query_sql` and `query_influxdb`, because those can run `DROP`/`DELETE`.
- `--enable-query` (or `--enable-write-tools=<tool>`) adds `query_sql`/`query_influxdb` back. Only use it when the **datasource credentials are themselves read-only**.
- `--disable-query` removes every datasource-query tool (metadata only). Use it when the agent should explore but not read data.
- Use `GRAFANA_SERVICE_ACCOUNT_TOKEN`, or `GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE` so rotated tokens are picked up. `GRAFANA_API_KEY` is deprecated.
- `--disable-write` isn't a security boundary on its own. The Viewer-role token is the real control. Also deny write tools in Claude Code permissions.

## Expensive queries (read-only, but they can hurt the backend)

- Always use a `job`/`namespace`/`app` selector and a bounded time range. In Loki, the time range matters most.
- Avoid `{__name__=~".+"}`, unanchored `=~".*foo.*"` on high-cardinality labels, and long ranges (`[30d]`) on raw series. Use recording rules or `/api/v1/status/tsdb`.
- For range queries, choose `step` so each series has at most 11,000 points (Prometheus 3.15 rejects more with "exceeded maximum resolution"; tested). Use `logcli --limit` (default 30) and `--since`.

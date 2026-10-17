# Read-only application key scopes

Sources (checked 2026-10-16):
- Scopes list: https://docs.datadoghq.com/api/latest/scopes/
- Scoped app keys: https://docs.datadoghq.com/account_management/api-app-keys/#scopes
- Role permissions: https://docs.datadoghq.com/account_management/rbac/permissions/

Create the app key on a **service account** with a read-only role, then also restrict the key's scopes.
Scopes can only narrow the owner's permissions; they never add to them.

Endpoint-to-scope mapping is verified against `security: AuthZ` in https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v1/openapi.yaml and https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v2/openapi.yaml (checked 2026-10-16). Scope names are also on https://docs.datadoghq.com/api/latest/scopes/.

| Scope | Needed for |
|---|---|
| `timeseries_query` | `GET /api/v1/query`, `POST /api/v2/query/timeseries` |
| `metrics_read` | `GET /api/v1/metrics`, `GET /api/v2/metrics` (verified) |
| `monitors_read` | `GET /api/v1/monitor`, `/api/v1/monitor/search`, `/api/v1/monitor/{id}` |
| `slos_read` | `GET /api/v1/slo`, `/api/v1/slo/{id}/history` |
| `logs_read_data` | `POST /api/v2/logs/events/search`, `GET /api/v2/logs/events` |
| `logs_read_index_data` | a role permission for reading indexed logs, not used as an endpoint AuthZ scope by the endpoints here (unverified as a needed app-key scope) |
| `apm_read` | `POST /api/v2/spans/events/search`, `GET /api/v2/spans/events` (verified; these ops have no x-permission, only AuthZ) |
| `apm_service_catalog_read` | Software Catalog / service definitions (endpoint mapping not checked) |
| `events_read` | `GET /api/v1/events`, `/api/v2/events` |
| `incident_read` | `GET /api/v2/incidents` |
| `dashboards_read` | `GET /api/v1/dashboard` (verified) |
| `hosts_read` | `GET /api/v1/hosts` |

Do **not** grant any `*_write`, `*_settings_write`, `monitors_downtime`, or `incident_write` scopes.

Key hygiene: keep keys in env vars (`DD_API_KEY`, `DD_APP_KEY`) or a secret manager. Never print them, commit them, or pass them in argv.
Rotate them, and prefer OAuth or a PAT/SAT for MCP (see `mcp-read-only.md`).

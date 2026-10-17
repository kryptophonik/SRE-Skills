# Read-only API endpoints and site hosts

Sources (checked 2026-10-16):
- API reference: https://docs.datadoghq.com/api/latest/
- Sites: https://docs.datadoghq.com/getting_started/site/
- Auth headers: https://docs.datadoghq.com/api/latest/authentication/
- Rate limits: https://docs.datadoghq.com/api/latest/rate-limits/

Base URL: `https://api.${DD_SITE}`. Headers: `DD-API-KEY`, `DD-APPLICATION-KEY`.

| Site | `DD_SITE` |
|---|---|
| US1 | `datadoghq.com` |
| US3 | `us3.datadoghq.com` |
| US5 | `us5.datadoghq.com` |
| EU1 | `datadoghq.eu` |
| AP1 | `ap1.datadoghq.com` |
| AP2 | `ap2.datadoghq.com` |
| UK1 | `uk1.datadoghq.com` |
| US1-FED | `ddog-gov.com` |
| US2-FED | `us2.ddog-gov.com` |

Site list: https://docs.datadoghq.com/getting_started/site/ (checked 2026-10-16); it matches the `site` enum in the v1/v2 OpenAPI `servers` (https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v1/openapi.yaml).

## Read endpoints

Scopes come from each operation's `security: AuthZ` in the OpenAPI specs (https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v1/openapi.yaml, https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v2/openapi.yaml).

| Method | Path | Purpose | Scope |
|---|---|---|---|
| GET | `/api/v1/validate` | check API key (API key only) | none (API key only) |
| GET | `/api/v1/query?from&to&query` | metric timeseries (seconds epoch) | `timeseries_query` |
| POST | `/api/v2/query/timeseries` | formulas and functions query (read-only POST) | `timeseries_query` |
| GET | `/api/v1/monitor` | list monitors (`monitor_tags`, `tags`, `name`, `page`, `page_size`) | `monitors_read` |
| GET | `/api/v1/monitor/search?query=status:alert` | search monitors by status, tag, etc. | `monitors_read` |
| GET | `/api/v1/monitor/{id}` | monitor details | `monitors_read` |
| GET | `/api/v1/slo` | list SLOs | `slos_read` |
| GET | `/api/v1/slo/{id}/history?from_ts&to_ts` | SLO history / error budget | `slos_read` |
| POST | `/api/v2/logs/events/search` | log search (read-only POST) | `logs_read_data` |
| GET | `/api/v2/logs/events` | log list (GET form) | `logs_read_data` (x-permission) |
| POST | `/api/v2/spans/events/search` | span search (read-only POST) | `apm_read` |
| GET | `/api/v2/events` | events | `events_read` |
| GET | `/api/v2/incidents` | incidents | `incident_read` |
| GET | `/api/v1/hosts` | hosts | `hosts_read` |

`group_states` on `GET /api/v1/monitor` only adds group detail to the response. It does **not** filter to alerting monitors; use `/monitor/search` for that.

## Writes (approval required; not used by these scripts)

POST/PUT/DELETE on `/api/v1/monitor*` (including `/mute`), `/api/v1/downtime` and `/api/v2/downtime`, `/api/v1/slo*`, `/api/v2/incidents*`, `/api/v1/events` (POST), `/api/v1/dashboard*`.

## Rate limits

Source: https://docs.datadoghq.com/api/latest/rate-limits/. Responses carry `X-RateLimit-Limit`, `X-RateLimit-Period`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` (seconds) and `X-RateLimit-Name`.
On HTTP 429, wait `X-RateLimit-Reset` seconds before retrying. Log and span searches are rate-limited per org, so keep windows short and `page.limit` small.

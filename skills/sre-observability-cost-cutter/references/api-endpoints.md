# API endpoints used by this skill

Checked live on 2026-10-18 against the Datadog API reference (docs.datadoghq.com) and the
OpenAPI specs it is generated from
([v1](https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v1/openapi.yaml),
[v2](https://github.com/DataDog/datadog-api-client-python/blob/master/.generator/schemas/v2/openapi.yaml)).
Descriptions below are summaries in our own words; follow the links for the vendor's text.
Nothing here was called against a real account (see the skill's Tested vs docs-only table).

Base URL: `https://api.<DD_SITE>`. Auth headers: `DD-API-KEY` and `DD-APPLICATION-KEY`
([authentication](https://docs.datadoghq.com/api/latest/authentication/)). Sites:
[site list](https://docs.datadoghq.com/getting_started/site/). 429 handling uses the
`X-RateLimit-Reset` header ([rate limits](https://docs.datadoghq.com/api/latest/rate-limits/)).

## Read calls made by `dd_cost_audit.py` (GET only)

| Saved as | Call | Parameters the script sends | Permission (from the endpoint page) | Notes | Doc |
|---|---|---|---|---|---|
| `usage_summary.json` | `GET /api/v1/usage/summary` | `start_month`, `end_month` (YYYY-MM) | `usage_read` | Parent-level orgs only. Fields read: `custom_ts_sum`, `infra_host_top99p_sum`, `apm_host_top99p_sum`, `container_avg_sum`, `ingested_events_bytes_agg_sum`, `trace_search_indexed_events_count_agg_sum`, `logs_by_retention.usage[]` | [link](https://docs.datadoghq.com/api/latest/usage-metering/#get-usage-across-your-account) |
| `estimated_cost.json` | `GET /api/v2/usage/estimated_cost` | `start_month`, `end_month` | `usage_read` **and** `billing_read` | Parent-level orgs only; current and previous month; delayed up to 72 hours. Fields read: `data[].attributes.date`, `charges[].product_name`, `charge_type`, `cost` | [link](https://docs.datadoghq.com/api/latest/usage-metering/#get-estimated-cost-across-your-account) |
| `top_avg_metrics.json` | `GET /api/v1/usage/top_avg_metrics` | `month`, `limit` (1-5000) | `usage_read` | Fields: `usage[].metric_name`, `avg_metric_hour`, `max_metric_hour`, `metric_category` | [link](https://docs.datadoghq.com/api/latest/usage-metering/#get-all-custom-metrics-by-hourly-average) |
| `metrics_unqueried.json` | `GET /api/v2/metrics` | `filter[queried]=false`, `filter[queried][window][seconds]` (max 15,552,000 = 180 days), `filter[configured]=false`, `filter[is_configurable]=true`, `include=metric_volumes`, `sort=-metric_volumes.indexed_volume`, `page[size]` (max 10,000) | `metrics_read` | Volumes arrive in `included[]` with `type: metric_volumes`, `attributes.indexed_volume` / `ingested_volume`. `sort` needs `page[size]` | [link](https://docs.datadoghq.com/api/latest/metrics/#get-a-list-of-metrics) |
| `metrics_by_volume.json` | `GET /api/v2/metrics` | same, without the `filter[queried]` pair | `metrics_read` | Top configurable, not-yet-configured metrics by indexed volume | [link](https://docs.datadoghq.com/api/latest/metrics/#get-a-list-of-metrics) |
| `log_indexes.json` | `GET /api/v1/logs/config/indexes` | none | `logs_read_config` | Fields: `name`, `filter.query`, `num_retention_days`, `num_flex_logs_retention_days`, `daily_limit`, `exclusion_filters[]` (`name`, `is_enabled`, `filter.query`, `filter.sample_rate`) | [link](https://docs.datadoghq.com/api/latest/logs-indexes/#get-all-indexes) |
| `logs_by_index.json` | `GET /api/v1/usage/logs_by_index` | `start_hr`, `end_hr` (YYYY-MM-DDThh, UTC) | `usage_read` | Indexed events per index per hour: `usage[].index_name`, `event_count`, `retention` | [link](https://docs.datadoghq.com/api/latest/usage-metering/#get-hourly-usage-for-logs-by-index) |
| `logs_ingest_by_index.json` | `GET /api/v1/query` | `from`, `to` (epoch seconds), `query=sum:datadog.estimated_usage.logs.ingested_events{*} by {datadog_index,datadog_is_excluded}.as_count().rollup(sum, 3600)` | `timeseries_query` | Usage metric and its `datadog_index` / `datadog_is_excluded` tags are described in [logs to metrics](https://docs.datadoghq.com/logs/log_configuration/logs_to_metrics/) and the [log management best practices guide](https://docs.datadoghq.com/logs/guide/best-practices-for-log-management/) | [link](https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-points) |
| `monitors.json` | `GET /api/v1/monitor` | `page`, `page_size` (max 1000), `with_downtimes=true` | `monitors_read` | Fields: `id`, `name`, `type`, `query`, `message`, `tags`, `priority`, `overall_state`, `created`, `modified`, `options.thresholds`, `options.notify_no_data`, `options.no_data_timeframe`, `options.silenced` (legacy). `with_downtimes=true` adds `matching_downtimes[]` (`id`, `start`, `end`, `scope`; POSIX seconds), the source of mute ages. The parameter and field names come from the vendor's generated API client; the reference page did not render them, and real responses are unverified | [link](https://docs.datadoghq.com/api/latest/monitors/#get-all-monitors) |
| `monitor_search.json` | `GET /api/v1/monitor/search` | `page`, `per_page` (script uses 100) | `monitors_read` | Only source of `last_triggered_ts`; paging uses `metadata.page_count`. A maximum `per_page` is not documented | [link](https://docs.datadoghq.com/api/latest/monitors/#monitors-search) |

Read calls the **report** asks the operator to run before a metric change:

| Call | Purpose | Permission | Doc |
|---|---|---|---|
| `GET /api/v1/metrics/{metric_name}` | metric `type`, needed in the tag configuration body | `metrics_read` | [link](https://docs.datadoghq.com/api/latest/metrics/#get-metric-metadata) |
| `GET /api/v2/metrics/{metric_name}/estimate?filter[groups]=a,b` | estimated series after keeping only tag keys `a,b`; answer in `data.attributes.estimated_output_series` | none listed on the page | [link](https://docs.datadoghq.com/api/latest/metrics/#tag-configuration-cardinality-estimator) |

## Read-only access setup

Create the keys on a service account whose role has only: `usage_read`, `billing_read` (only
if you want estimated cost), `metrics_read`, `timeseries_query`, `logs_read_config`,
`monitors_read`. Role permissions: [RBAC permissions](https://docs.datadoghq.com/account_management/rbac/permissions/).
Application key scopes: [scopes](https://docs.datadoghq.com/api/latest/scopes/).

`logs_read_config` is listed as a role permission but does not appear on the scopes page, so a
**scoped** application key may not be able to list log indexes (unverified without an account).
If that call returns 403, the report says the log index section is not supported with that key.
Two ways forward:

- An **unscoped** application key is acceptable only when it belongs to the dedicated read-only
  service account above. Never use a person's application key: it carries that person's full
  permissions.
- The fallback stays the saved-export route: someone allowed to read index configs saves
  `GET /api/v1/logs/config/indexes` as `log_indexes.json`, and the audit runs offline with
  `--input-dir`.

Listing downtimes directly (`GET /api/v2/downtime`) needs `monitors_downtime`, which also allows
scheduling and cancelling downtimes, so the audit reads mute ages from the monitor list instead.

The script does **not** check what a key is allowed to do. The operator confirms the service
account's role in the vendor UI before the run.

## Writes (only in the report, each behind the gate)

The report's `ddw` helper reads `DD_WRITE_API_KEY` / `DD_WRITE_APP_KEY`, never the audit's
`DD_API_KEY` / `DD_APP_KEY`, and refuses a body that still contains `<placeholder>` text.

| Change | Call | Permission (endpoint page or RBAC page) | Rollback | Doc |
|---|---|---|---|---|
| Metric tag allowlist | `POST /api/v2/metrics/{metric_name}/tags` body `data.type=manage_tags`, `data.id`, `attributes.metric_type` (required), `attributes.tags` (required), optional `exclude_tags_mode` | `metric_tags_write` | `DELETE /api/v2/metrics/{metric_name}/tags` | [create](https://docs.datadoghq.com/api/latest/metrics/#create-a-tag-configuration), [delete](https://docs.datadoghq.com/api/latest/metrics/#delete-a-tag-configuration) |
| Exclusion filter or retention | `PUT /api/v1/logs/config/indexes/{name}`. **Replaces the whole config**; body fields: `filter` (required), `exclusion_filters`, `num_retention_days`, `num_flex_logs_retention_days`, `daily_limit`, `daily_limit_reset`, `daily_limit_warning_threshold_percentage`, `disable_daily_limit`, `tags` | Not stated on the endpoint page. RBAC page: `logs_modify_indexes` (all index settings) or `logs_write_exclusion_filters` (exclusion filters only) | PUT the exported config back; aged-out logs do not return | [update](https://docs.datadoghq.com/api/latest/logs-indexes/#update-an-index), [exclusion filters](https://docs.datadoghq.com/logs/log_configuration/indexes/) |
| Trial mute | `POST /api/v2/downtime` body `data.type=downtime`, `attributes.scope` and `attributes.monitor_identifier` (required), `schedule.end` | `monitors_downtime` | `DELETE /api/v2/downtime/{downtime_id}` | [schedule](https://docs.datadoghq.com/api/latest/downtimes/#schedule-a-downtime), [cancel](https://docs.datadoghq.com/api/latest/downtimes/#cancel-a-downtime) |
| Delete monitor | `DELETE /api/v1/monitor/{monitor_id}` | `monitors_write` or `monitors_draft_write` | Re-create with `POST /api/v1/monitor` from the export (new id) | [delete](https://docs.datadoghq.com/api/latest/monitors/#delete-a-monitor), [create](https://docs.datadoghq.com/api/latest/monitors/#create-a-monitor) |

Metrics without Limits behaviour (allowlists, ingested vs indexed billing):
[Metrics without Limits](https://docs.datadoghq.com/metrics/metrics-without-limits/).

# Observability cost audit and savings plan

> **SYNTHETIC EXAMPLE DATA, not from a real account.** Built from test fixtures.

> **EXAMPLE REPORT built from fixture data.** Every number below is made up for testing. It is not a measurement of any real organization and not a savings claim.

> **Before you change anything:** test every change in a non-production org or on a low-risk index or metric first. The operator reviews and approves each change; nothing in this report is applied automatically. All savings are estimates, not guarantees. Actual savings depend on your contract, discounts and commitments. The audit script only sent read (GET) requests in testing; review it before giving it any key.

- Generated: offline from data pulled 2026-10-18T12:00:00Z
- Mode: offline (input dir `fixtures`)
- Usage month: 2026-09; unqueried window: 30 days; log window: 7 days
- Dollar figures: upper-bound estimates from your own estimated-cost API data

## Estimated cost by product

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

Source: estimated-cost API for 2026-09-01T00:00:00Z (charge_type=total rows). This is the vendor's running estimate, delayed by up to 72 hours. It is not an invoice.

| Product | Estimated cost |
|---|---|
| `infra_host` | $3,000 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| `custom_metrics` | $2,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| `apm_host` | $1,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| `logs_indexed_15day` | $1,200 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| `logs_ingested` | $1,000 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| `logs_indexed_30day` | $600 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| `logs_indexed_90day` | $200 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |

Category matching for upper bounds (matched by product name (confirm, or pass --product-map)): custom_metrics: `custom_metrics`; indexed_logs: `logs_indexed_15day`, `logs_indexed_30day`, `logs_indexed_90day`

## Usage inventory

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

| Usage | Value |
|---|---|
| Infrastructure hosts (top 99th percentile) (`infra_host_top99p_sum`) | 120 |
| APM hosts (top 99th percentile) (`apm_host_top99p_sum`) | 40 |
| Containers (average) (`container_avg_sum`) | 600 |
| Custom metrics (average per hour) (`custom_ts_sum`) | 50,000 |
| Ingested log bytes (`ingested_events_bytes_agg_sum`) | 5,000,000,000,000 |
| Indexed spans (`trace_search_indexed_events_count_agg_sum`) | 200,000,000 |
| Indexed logs, 15-day retention | 900,000,000 |
| Indexed logs, 30-day retention | 300,000,000 |

| Log index | Retention (days) | Indexed events in window | Enabled exclusion filters | Daily limit |
|---|---|---|---|---|
| `main` | 15 | 2,000,000 | 0 | none |
| `apps` | 30 | 1,200,000 | 0 | none |
| `audit` | 90 | 600,000 | 1 | 5000000 |
| `security` | 30 | 20,000 | 0 | none |

Top custom metrics by hourly average (2026-09):

| Metric | Avg per hour | Max per hour |
|---|---|---|
| `example.http.request.latency` | 9,000 | 12,000 |
| `example.legacy.batch.duration` | 6,000 | 6,500 |
| `example.queue.depth` | 2,500 | 3,000 |
| `example.debug.cache.hits` | 1,500 | 1,800 |

## Ranked savings plan

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

Every item here is a review flag, not a recommendation to cut: a threshold or a ranking put it on the list, and the owner decides whether to change anything.

Ranked by estimated upper-bound dollars, then share of the product's usage. Shares compare items within one product, not across products, until you fill in your contract rates.

| # | Item | Share of product usage | Estimated effect | Risk |
|---|---|---|---|---|
| 1 | Review: log index `main` has no active exclusion filter | 52.4% | upper bound $1,200/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Medium |
| 2 | Review: log index `apps` has no active exclusion filter | 31.4% | upper bound $590/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Medium |
| 3 | Review: high-cardinality custom metric `example.http.request.latency` (#1 by series) | 18.0% | upper bound $450/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Medium |
| 4 | Review: unqueried custom metric `example.legacy.batch.duration` (#1 by series) | 12.0% | upper bound $300/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Low to medium |
| 5 | Review: high-cardinality custom metric `example.queue.depth` (#3 by series) | 5.0% | upper bound $125/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Medium |
| 6 | Review: unqueried custom metric `example.debug.cache.hits` (#2 by series) | 3.0% | upper bound $75/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Low to medium |
| 7 | Review: high-cardinality custom metric `example.small.metric` (#5 by series) | 0.1% | upper bound $2/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Medium |
| 8 | Review: unqueried custom metric `example.tiny.unused` (#3 by series) | 0.0% | upper bound $1/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) | Low to medium |
| 9 | Review: log index `apps` keeps logs 30 days (check compliance first) | 31.4% | $ <fill in from contract> | High for the data, check compliance first |
| 10 | Review: log index `audit` keeps logs 90 days (check compliance first) | 15.7% | $ <fill in from contract> | High for the data, check compliance first |
| 11 | Review: log index `security` keeps logs 30 days (check compliance first) | 0.5% | $ <fill in from contract> | High for the data, check compliance first |

### Upper-bound savings totals

Sum of the items' upper bounds. Each metric and index carries at most one dollar figure, so nothing is counted twice. The achievable saving is lower.

| Category | Total upper bound |
|---|---|
| custom_metrics | $954/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| indexed_logs | $1,790/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) |
| **All priced items** | **$2,744/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-18)** |

**Savings are not guaranteed.** Actual savings depend on your contract, discounts and commitments.

Approved changes use this helper:

```bash
# Helper for approved changes only. It reads its own DD_WRITE_API_KEY / DD_WRITE_APP_KEY from your
# secret store and ignores the audit's read-only DD_API_KEY / DD_APP_KEY. It refuses a body that
# still contains <placeholder> text. Keys go to curl through a file descriptor, not argv.
ddw() {  # usage: ddw METHOD PATH  (JSON body, if any, on stdin)
  local body
  body=$(cat)
  if printf '%s' "$body" | grep -Eq '<[A-Za-z][^<>]*>'; then
    echo "ddw: refusing: the body still contains <placeholder> text; fill it in first" >&2
    return 1
  fi
  if [ -z "${DD_WRITE_API_KEY:-}" ] || [ -z "${DD_WRITE_APP_KEY:-}" ]; then
    echo "ddw: refusing: set DD_WRITE_API_KEY and DD_WRITE_APP_KEY (the read-only DD_API_KEY/DD_APP_KEY are never used for writes)" >&2
    return 1
  fi
  if [ -z "${DD_SITE:-}" ]; then
    echo "ddw: refusing: set DD_SITE" >&2
    return 1
  fi
  printf '%s' "$body" | curl -sS -X "$1" "https://api.${DD_SITE}$2" \
    -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_WRITE_API_KEY" "$DD_WRITE_APP_KEY") \
    -H 'Content-Type: application/json' --data-binary @-
}
```

### 1. Review: log index `main` has no active exclusion filter

- **Evidence:** 2,000,000 indexed events in the last 7 days (52.4% of all indexed events), retention 15 days, no enabled exclusion filter. Ingested in the window: 2,000,000, of which 0 were already excluded.
- **Estimated effect:** Saving = this index's indexed-log cost x the fraction your filter drops. Count the matching events in Log Explorer first. sample_rate is the fraction of matching logs that are excluded: for the trial window use 0.9 or lower, so at least 10% of matching logs are still indexed. 1.0 means none of the matching logs are kept in this index. The example filter ships disabled (is_enabled false) with placeholders the helper refuses to send; fill them in, apply, then enable it in a second approved change.
- **Upper-bound dollars (estimate, not guaranteed):** $1,200 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 100.0% of the 15-day tier's indexed events x $1,200 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated cost of `logs_indexed_15day`. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Excluded logs are not searchable in this index and cannot be re-indexed later, though they still feed live tail, archives and log-based metrics. Exclusion is the first matching filter only.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/main <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "<low-value query, e.g. status:debug service:<svc>>",
        "sample_rate": 0.9
      },
      "is_enabled": false,
      "name": "cost-cutter: <describe the low-value logs>"
    }
  ],
  "filter": {
    "query": "*"
  },
  "num_retention_days": 15,
  "tags": []
}
JSON
```

Rollback: put back the config as exported.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/main <<'JSON'
{
  "exclusion_filters": [],
  "filter": {
    "query": "*"
  },
  "num_retention_days": 15,
  "tags": []
}
JSON
```

### 2. Review: log index `apps` has no active exclusion filter

- **Evidence:** 1,200,000 indexed events in the last 7 days (31.4% of all indexed events), retention 30 days, no enabled exclusion filter. Ingested in the window: 1,200,000, of which 0 were already excluded.
- **Estimated effect:** Saving = this index's indexed-log cost x the fraction your filter drops. Count the matching events in Log Explorer first. sample_rate is the fraction of matching logs that are excluded: for the trial window use 0.9 or lower, so at least 10% of matching logs are still indexed. 1.0 means none of the matching logs are kept in this index. The example filter ships disabled (is_enabled false) with placeholders the helper refuses to send; fill them in, apply, then enable it in a second approved change.
- **Upper-bound dollars (estimate, not guaranteed):** $590 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 98.4% of the 30-day tier's indexed events x $600 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated cost of `logs_indexed_30day`. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Excluded logs are not searchable in this index and cannot be re-indexed later, though they still feed live tail, archives and log-based metrics. Exclusion is the first matching filter only.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/apps <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "status:debug",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop debug"
    },
    {
      "filter": {
        "query": "<low-value query, e.g. status:debug service:<svc>>",
        "sample_rate": 0.9
      },
      "is_enabled": false,
      "name": "cost-cutter: <describe the low-value logs>"
    }
  ],
  "filter": {
    "query": "service:example-*"
  },
  "num_retention_days": 30,
  "tags": []
}
JSON
```

Rollback: put back the config as exported.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/apps <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "status:debug",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop debug"
    }
  ],
  "filter": {
    "query": "service:example-*"
  },
  "num_retention_days": 30,
  "tags": []
}
JSON
```

### 3. Review: high-cardinality custom metric `example.http.request.latency` (#1 by series)

- **Evidence:** Ranked #1 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 9,000 (18.0% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $450 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 18.0% of custom metric average x $2,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/example.http.request.latency" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/example.http.request.latency/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/example.http.request.latency/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "example.http.request.latency",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/example.http.request.latency/tags </dev/null
```

### 4. Review: unqueried custom metric `example.legacy.batch.duration` (#1 by series)

- **Evidence:** Ranked #1 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 6,000 (12.0% of the month's custom metric average 50,000).
- **Estimated effect:** Upper bound: up to 6,000 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $300 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 12.0% of custom metric average x $2,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/example.legacy.batch.duration" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/example.legacy.batch.duration/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/example.legacy.batch.duration/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "example.legacy.batch.duration",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/example.legacy.batch.duration/tags </dev/null
```

### 5. Review: high-cardinality custom metric `example.queue.depth` (#3 by series)

- **Evidence:** Ranked #3 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 2,500 (5.0% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $125 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 5.0% of custom metric average x $2,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/example.queue.depth" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/example.queue.depth/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/example.queue.depth/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "example.queue.depth",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/example.queue.depth/tags </dev/null
```

### 6. Review: unqueried custom metric `example.debug.cache.hits` (#2 by series)

- **Evidence:** Ranked #2 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 1,500 (3.0% of the month's custom metric average 50,000).
- **Estimated effect:** Upper bound: up to 1,500 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $75 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 3.0% of custom metric average x $2,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/example.debug.cache.hits" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/example.debug.cache.hits/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/example.debug.cache.hits/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "example.debug.cache.hits",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/example.debug.cache.hits/tags </dev/null
```

### 7. Review: high-cardinality custom metric `example.small.metric` (#5 by series)

- **Evidence:** Ranked #5 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 50 (0.1% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $2 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 0.1% of custom metric average x $2,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/example.small.metric" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/example.small.metric/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/example.small.metric/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "example.small.metric",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/example.small.metric/tags </dev/null
```

### 8. Review: unqueried custom metric `example.tiny.unused` (#3 by series)

- **Evidence:** Ranked #3 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 20 (0.0% of the month's custom metric average 50,000).
- **Estimated effect:** Upper bound: up to 20 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $1 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) = 0.0% of custom metric average x $2,500 (estimated from this org's Datadog estimated-cost data pulled 2026-10-18) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/example.tiny.unused" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/example.tiny.unused/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/example.tiny.unused/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "example.tiny.unused",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/example.tiny.unused/tags </dev/null
```

### 9. Review: log index `apps` keeps logs 30 days (check compliance first)

- **Evidence:** Retention 30 days, over the 15-day review threshold, on an index holding 31.4% of indexed events (1,200,000 in 7 days). Check compliance first: audit, security, legal hold and contract terms may require this retention.
- **Estimated effect:** Depends on your contracted price per retention tier. Fill in: events x (current tier rate - new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.
- **Risk:** High for the data, check compliance first: logs older than the new retention become unsearchable and raising retention again does not bring them back. Check audit, security and legal hold needs.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/apps <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "status:debug",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop debug"
    }
  ],
  "filter": {
    "query": "service:example-*"
  },
  "num_retention_days": "<target days from your contract>",
  "tags": []
}
JSON
```

Rollback: put back the config as exported. This does not restore logs already aged out.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/apps <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "status:debug",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop debug"
    }
  ],
  "filter": {
    "query": "service:example-*"
  },
  "num_retention_days": 30,
  "tags": []
}
JSON
```

### 10. Review: log index `audit` keeps logs 90 days (check compliance first)

- **Evidence:** Retention 90 days, over the 15-day review threshold, on an index holding 15.7% of indexed events (600,000 in 7 days). Check compliance first: audit, security, legal hold and contract terms may require this retention.
- **Estimated effect:** Depends on your contracted price per retention tier. Fill in: events x (current tier rate - new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.
- **Risk:** High for the data, check compliance first: logs older than the new retention become unsearchable and raising retention again does not bring them back. Check audit, security and legal hold needs.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/audit <<'JSON'
{
  "daily_limit": 5000000,
  "exclusion_filters": [
    {
      "filter": {
        "query": "@http.url_details.path:/health",
        "sample_rate": 0.9
      },
      "is_enabled": true,
      "name": "sample health checks"
    }
  ],
  "filter": {
    "query": "source:audit"
  },
  "num_retention_days": "<target days from your contract>",
  "tags": []
}
JSON
```

Rollback: put back the config as exported. This does not restore logs already aged out.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/audit <<'JSON'
{
  "daily_limit": 5000000,
  "exclusion_filters": [
    {
      "filter": {
        "query": "@http.url_details.path:/health",
        "sample_rate": 0.9
      },
      "is_enabled": true,
      "name": "sample health checks"
    }
  ],
  "filter": {
    "query": "source:audit"
  },
  "num_retention_days": 90,
  "tags": []
}
JSON
```

### 11. Review: log index `security` keeps logs 30 days (check compliance first)

- **Evidence:** Retention 30 days, over the 15-day review threshold, on an index holding 0.5% of indexed events (20,000 in 7 days). Check compliance first: audit, security, legal hold and contract terms may require this retention.
- **Estimated effect:** Depends on your contracted price per retention tier. Fill in: events x (current tier rate - new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.
- **Risk:** High for the data, check compliance first: logs older than the new retention become unsearchable and raising retention again does not bring them back. Check audit, security and legal hold needs.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/security <<'JSON'
{
  "exclusion_filters": [],
  "filter": {
    "query": "source:security"
  },
  "num_retention_days": "<target days from your contract>",
  "tags": []
}
JSON
```

Rollback: put back the config as exported. This does not restore logs already aged out.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/security <<'JSON'
{
  "exclusion_filters": [],
  "filter": {
    "query": "source:security"
  },
  "num_retention_days": 30,
  "tags": []
}
JSON
```

## Monitor hygiene (no dollar claim)

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

Monitors are rarely billed one by one; these are review flags for alert noise and review load.

- Duplicate groups (same type, query and thresholds): 1
- Not triggered in 90 days and older than that: 3 (plus 0 rare-event monitors skipped)
- Muted-monitor check skipped: the monitor list had no downtime data (`matching_downtimes`), so this report can't say whether any monitors are muted.
- In No Data state: 1

### Duplicate: keep monitor 1001 "High CPU on {{host.name}}"

Query: `avg(last_5m):avg:system.cpu.user{env:prod,service:example-api} by {host} > 90`. Duplicates: 1002 "CPU high (copy)". Check that the notification targets of the duplicates are covered by the one you keep.

Trial first: mute monitor 1002 with a downtime for two weeks.

**Gate: approval required.**

```bash
ddw POST /api/v2/downtime <<'JSON'
{
  "data": {
    "attributes": {
      "message": "cost-cutter trial mute of a duplicate monitor",
      "monitor_identifier": {
        "monitor_id": 1002
      },
      "schedule": {
        "end": "<ISO-8601 end time, e.g. two weeks from now>"
      },
      "scope": "*"
    },
    "type": "downtime"
  }
}
JSON
```

Rollback of the mute: cancel the downtime using the id returned above.

**Gate: approval required.**

```bash
ddw DELETE "/api/v2/downtime/${DOWNTIME_ID:?id from the downtime response}" </dev/null
```

Then delete monitor 1002 (irreversible; links, SLOs and composites that use this id break).

**Gate: approval required.**

```bash
ddw DELETE /api/v1/monitor/1002 </dev/null
```

Rollback of the delete: re-create it from the exported definition (it gets a new id).

**Gate: approval required.**

```bash
ddw POST /api/v1/monitor <<'JSON'
{
  "message": "Duplicate of the CPU monitor @slack-example-alerts",
  "name": "CPU high (copy)",
  "options": {
    "notify_no_data": false,
    "thresholds": {
      "critical": 90,
      "warning": 80
    }
  },
  "query": "avg(last_5m):avg:system.cpu.user{service:example-api, env:prod} by {host} > 90",
  "tags": [
    "team:example"
  ],
  "type": "query alert"
}
JSON
```

### Not triggered recently (review, do not delete blindly)

A monitor that never fires may be well tuned, or broken (wrong scope, dead metric, impossible threshold). Ask the owner before muting or deleting; use the same gated downtime and delete steps as above.

| Monitor | Name | Type | Last triggered |
|---|---|---|---|
| 1004 | Queue depth growing | query alert | never (in search data) |
| 1005 | Latency anomaly | query alert | 2026-01-15 |
| 1006 | Batch job silent | query alert | never (in search data) |

### In No Data state

| Monitor | Name | Query |
|---|---|---|
| 1006 | Batch job silent | `max(last_30m):sum:example.legacy.batch.duration{env:prod,job IN (nightly,hourly)} > 3600` |

## Not covered and assumptions

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

- Upper bounds assume cost scales linearly with the share of usage. Commitments, tiers and minimums mean the real saving can be lower, or zero until the next renewal.
- Per-index ingest uses the estimated usage metric tagged by index; it is an estimate.
- APM, RUM, Synthetics and security products are listed in the inventory only.
- Monitor hygiene uses the monitor list and search APIs; it does not read monitor history. Mute ages come from the monitor list's matching_downtimes (requested with with_downtimes=true).
- The script does not check what the key is allowed to do. The operator confirms the service account's role in the Datadog UI before the run.

---

Savings are not guaranteed. Actual savings depend on your contract, discounts and commitments. Dollar figures in this report are estimated from this org's Datadog estimated-cost data pulled 2026-10-18; they are not an invoice or a quote. Test changes in non-production first; the operator approves every change.

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

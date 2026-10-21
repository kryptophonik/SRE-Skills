# Observability cost audit and savings plan

> **SYNTHETIC EXAMPLE DATA, not from a real account.** Example Corp is a fictional org invented for this demo. Every metric, index, monitor, volume and dollar amount was generated; none of it describes a real company, tenant or account.

> **Before you change anything:** test every change in a non-production org or on a low-risk index or metric first. The operator reviews and approves each change; nothing in this report is applied automatically. All savings are estimates, not guarantees. Actual savings depend on your contract, discounts and commitments. The audit script only sent read (GET) requests in testing; review it before giving it any key.

- Generated: offline from data pulled 2026-10-01T14:00:00Z
- Mode: offline (input dir `demo`)
- Usage month: 2026-09; unqueried window: 30 days; log window: 7 days
- Dollar figures: upper-bound estimates from your own estimated-cost API data

## Estimated cost by product

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

Source: estimated-cost API for 2026-09-01T00:00:00Z (charge_type=total rows). This is the vendor's running estimate, delayed by up to 72 hours. It is not an invoice.

| Product | Estimated cost |
|---|---|
| `infra_host` | $20,400 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `apm_host` | $9,975 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `custom_metrics` | $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `logs_indexed_15day` | $7,800 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `logs_indexed_30day` | $4,200 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `logs_ingested` | $3,800 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `indexed_spans` | $2,750 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `logs_indexed_90day` | $1,600 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `logs_indexed_3day` | $900 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| `synthetics_api_tests` | $600 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |

Category matching for upper bounds (matched by product name (confirm, or pass --product-map)): custom_metrics: `custom_metrics`; indexed_logs: `logs_indexed_3day`, `logs_indexed_15day`, `logs_indexed_30day`, `logs_indexed_90day`

## Usage inventory

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

| Usage | Value |
|---|---|
| Infrastructure hosts (top 99th percentile) (`infra_host_top99p_sum`) | 340 |
| APM hosts (top 99th percentile) (`apm_host_top99p_sum`) | 95 |
| Containers (average) (`container_avg_sum`) | 2,100 |
| Custom metrics (average per hour) (`custom_ts_sum`) | 182,000 |
| Ingested log bytes (`ingested_events_bytes_agg_sum`) | 38,000,000,000,000 |
| Indexed spans (`trace_search_indexed_events_count_agg_sum`) | 1,100,000,000 |
| Indexed logs, 3-day retention | 1,400,000,000 |
| Indexed logs, 15-day retention | 5,200,000,000 |
| Indexed logs, 30-day retention | 1,900,000,000 |
| Indexed logs, 90-day retention | 310,000,000 |

| Log index | Retention (days) | Indexed events in window | Enabled exclusion filters | Daily limit |
|---|---|---|---|---|
| `debug` | 3 | 335,856,795 | 0 | none |
| `main` | 15 | 277,847,507 | 0 | none |
| `web-access` | 15 | 238,646,247 | 0 | none |
| `cluster-events` | 30 | 116,134,606 | 0 | none |
| `payments` | 30 | 70,608,350 | 1 | 20000000 |
| `audit` | 90 | 15,894,883 | 1 | none |
| `security` | 90 | 6,725,819 | 0 | none |

Top custom metrics by hourly average (2026-09):

| Metric | Avg per hour | Max per hour |
|---|---|---|
| `demo.search.request.duration` | 16,000 | 20,000 |
| `demo.cart.request.duration` | 12,500 | 15,625 |
| `demo.legacy.importer.rows` | 11,000 | 13,750 |
| `demo.frontend.request.count` | 9,800 | 12,250 |
| `demo.debug.trace.samples` | 8,800 | 11,000 |
| `demo.frontend.worker.jobs` | 7,800 | 9,750 |
| `demo.catalog.request.duration` | 7,800 | 9,750 |
| `demo.pricing.request.duration` | 7,800 | 9,750 |
| `demo.pricing.db.query.time` | 7,800 | 9,750 |
| `demo.catalog.db.query.time` | 7,400 | 9,250 |

## Ranked savings plan

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

Every item here is a review flag, not a recommendation to cut: a threshold or a ranking put it on the list, and the owner decides whether to change anything.

Ranked by estimated upper-bound dollars, then share of the product's usage. Shares compare items within one product, not across products, until you fill in your contract rates.

| # | Item | Share of product usage | Estimated effect | Risk |
|---|---|---|---|---|
| 1 | Review: log index `main` has no active exclusion filter | 26.2% | upper bound $4,196/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 2 | Review: log index `web-access` has no active exclusion filter | 22.5% | upper bound $3,604/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 3 | Review: log index `cluster-events` has no active exclusion filter | 10.9% | upper bound $2,612/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 4 | Review: log index `debug` has no active exclusion filter | 31.6% | upper bound $900/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 5 | Review: high-cardinality custom metric `demo.search.request.duration` (#1 by series) | 8.8% | upper bound $800/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 6 | Review: high-cardinality custom metric `demo.cart.request.duration` (#2 by series) | 6.9% | upper bound $625/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 7 | Review: unqueried custom metric `demo.legacy.importer.rows` (#1 by series) | 6.0% | upper bound $550/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 8 | Review: high-cardinality custom metric `demo.frontend.request.count` (#4 by series) | 5.4% | upper bound $490/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 9 | Review: unqueried custom metric `demo.debug.trace.samples` (#2 by series) | 4.8% | upper bound $440/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 10 | Review: high-cardinality custom metric `demo.frontend.worker.jobs` (#6 by series) | 4.3% | upper bound $390/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 11 | Review: high-cardinality custom metric `demo.catalog.request.duration` (#7 by series) | 4.3% | upper bound $390/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 12 | Review: high-cardinality custom metric `demo.pricing.request.duration` (#8 by series) | 4.3% | upper bound $390/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 13 | Review: high-cardinality custom metric `demo.pricing.db.query.time` (#9 by series) | 4.3% | upper bound $390/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 14 | Review: high-cardinality custom metric `demo.catalog.db.query.time` (#10 by series) | 4.1% | upper bound $370/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Medium |
| 15 | Review: unqueried custom metric `demo.batch.reconcile.duration` (#3 by series) | 3.5% | upper bound $320/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 16 | Review: unqueried custom metric `demo.experiment.flag.evals` (#4 by series) | 2.4% | upper bound $215/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 17 | Review: unqueried custom metric `demo.legacy.importer.errors` (#5 by series) | 1.2% | upper bound $105/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 18 | Review: unqueried custom metric `demo.old.api.v1.calls` (#6 by series) | 0.9% | upper bound $85/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 19 | Review: unqueried custom metric `demo.tmp.migration.progress` (#7 by series) | 0.5% | upper bound $45/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 20 | Review: unqueried custom metric `demo.debug.gc.pauses` (#8 by series) | 0.2% | upper bound $18/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 21 | Review: unqueried custom metric `demo.sandbox.load.test` (#9 by series) | 0.0% | upper bound $3/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) | Low to medium |
| 22 | Review: log index `cluster-events` keeps logs 30 days (check compliance first) | 10.9% | $ <fill in from contract> | High for the data, check compliance first |
| 23 | Review: log index `payments` keeps logs 30 days (check compliance first) | 6.7% | $ <fill in from contract> | High for the data, check compliance first |
| 24 | Review: log index `audit` keeps logs 90 days (check compliance first) | 1.5% | $ <fill in from contract> | High for the data, check compliance first |
| 25 | Review: log index `security` keeps logs 90 days (check compliance first) | 0.6% | $ <fill in from contract> | High for the data, check compliance first |

### Upper-bound savings totals

Sum of the items' upper bounds. Each metric and index carries at most one dollar figure, so nothing is counted twice. The achievable saving is lower.

| Category | Total upper bound |
|---|---|
| custom_metrics | $5,626/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| indexed_logs | $11,312/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) |
| **All priced items** | **$16,937/mo (estimated from this org's Datadog estimated-cost data pulled 2026-10-01)** |

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

- **Evidence:** 277,847,507 indexed events in the last 7 days (26.2% of all indexed events), retention 15 days, no enabled exclusion filter. Ingested in the window: 277,847,507, of which 0 were already excluded.
- **Estimated effect:** Saving = this index's indexed-log cost x the fraction your filter drops. Count the matching events in Log Explorer first. sample_rate is the fraction of matching logs that are excluded: for the trial window use 0.9 or lower, so at least 10% of matching logs are still indexed. 1.0 means none of the matching logs are kept in this index. The example filter ships disabled (is_enabled false) with placeholders the helper refuses to send; fill them in, apply, then enable it in a second approved change.
- **Upper-bound dollars (estimate, not guaranteed):** $4,196 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 53.8% of the 15-day tier's indexed events x $7,800 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated cost of `logs_indexed_15day`. The real saving is lower: see Estimated effect.
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
  "tags": [
    "owner:platform"
  ]
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
  "tags": [
    "owner:platform"
  ]
}
JSON
```

### 2. Review: log index `web-access` has no active exclusion filter

- **Evidence:** 238,646,247 indexed events in the last 7 days (22.5% of all indexed events), retention 15 days, no enabled exclusion filter. Ingested in the window: 238,646,247, of which 0 were already excluded.
- **Estimated effect:** Saving = this index's indexed-log cost x the fraction your filter drops. Count the matching events in Log Explorer first. sample_rate is the fraction of matching logs that are excluded: for the trial window use 0.9 or lower, so at least 10% of matching logs are still indexed. 1.0 means none of the matching logs are kept in this index. The example filter ships disabled (is_enabled false) with placeholders the helper refuses to send; fill them in, apply, then enable it in a second approved change.
- **Upper-bound dollars (estimate, not guaranteed):** $3,604 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 46.2% of the 15-day tier's indexed events x $7,800 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated cost of `logs_indexed_15day`. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Excluded logs are not searchable in this index and cannot be re-indexed later, though they still feed live tail, archives and log-based metrics. Exclusion is the first matching filter only.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/web-access <<'JSON'
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
    "query": "source:web-proxy OR source:edge-proxy"
  },
  "num_retention_days": 15,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

Rollback: put back the config as exported.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/web-access <<'JSON'
{
  "exclusion_filters": [],
  "filter": {
    "query": "source:web-proxy OR source:edge-proxy"
  },
  "num_retention_days": 15,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

### 3. Review: log index `cluster-events` has no active exclusion filter

- **Evidence:** 116,134,606 indexed events in the last 7 days (10.9% of all indexed events), retention 30 days, no enabled exclusion filter. Ingested in the window: 116,134,606, of which 0 were already excluded.
- **Estimated effect:** Saving = this index's indexed-log cost x the fraction your filter drops. Count the matching events in Log Explorer first. sample_rate is the fraction of matching logs that are excluded: for the trial window use 0.9 or lower, so at least 10% of matching logs are still indexed. 1.0 means none of the matching logs are kept in this index. The example filter ships disabled (is_enabled false) with placeholders the helper refuses to send; fill them in, apply, then enable it in a second approved change.
- **Upper-bound dollars (estimate, not guaranteed):** $2,612 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 62.2% of the 30-day tier's indexed events x $4,200 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated cost of `logs_indexed_30day`. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Excluded logs are not searchable in this index and cannot be re-indexed later, though they still feed live tail, archives and log-based metrics. Exclusion is the first matching filter only.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/cluster-events <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "@reason:(Scheduled OR Pulled OR Created OR Started)",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop normal events"
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
    "query": "source:cluster-agent"
  },
  "num_retention_days": 30,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

Rollback: put back the config as exported.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/cluster-events <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "@reason:(Scheduled OR Pulled OR Created OR Started)",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop normal events"
    }
  ],
  "filter": {
    "query": "source:cluster-agent"
  },
  "num_retention_days": 30,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

### 4. Review: log index `debug` has no active exclusion filter

- **Evidence:** 335,856,795 indexed events in the last 7 days (31.6% of all indexed events), retention 3 days, no enabled exclusion filter. Ingested in the window: 335,856,795, of which 0 were already excluded.
- **Estimated effect:** Saving = this index's indexed-log cost x the fraction your filter drops. Count the matching events in Log Explorer first. sample_rate is the fraction of matching logs that are excluded: for the trial window use 0.9 or lower, so at least 10% of matching logs are still indexed. 1.0 means none of the matching logs are kept in this index. The example filter ships disabled (is_enabled false) with placeholders the helper refuses to send; fill them in, apply, then enable it in a second approved change.
- **Upper-bound dollars (estimate, not guaranteed):** $900 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 100.0% of the 3-day tier's indexed events x $900 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated cost of `logs_indexed_3day`. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Excluded logs are not searchable in this index and cannot be re-indexed later, though they still feed live tail, archives and log-based metrics. Exclusion is the first matching filter only.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/debug <<'JSON'
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
    "query": "status:debug"
  },
  "num_retention_days": 3,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

Rollback: put back the config as exported.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/debug <<'JSON'
{
  "exclusion_filters": [],
  "filter": {
    "query": "status:debug"
  },
  "num_retention_days": 3,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

### 5. Review: high-cardinality custom metric `demo.search.request.duration` (#1 by series)

- **Evidence:** Ranked #1 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 16,000 (8.8% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $800 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 8.8% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.search.request.duration" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.search.request.duration/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.search.request.duration/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.search.request.duration",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.search.request.duration/tags </dev/null
```

### 6. Review: high-cardinality custom metric `demo.cart.request.duration` (#2 by series)

- **Evidence:** Ranked #2 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 12,500 (6.9% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $625 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 6.9% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.cart.request.duration" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.cart.request.duration/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.cart.request.duration/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.cart.request.duration",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.cart.request.duration/tags </dev/null
```

### 7. Review: unqueried custom metric `demo.legacy.importer.rows` (#1 by series)

- **Evidence:** Ranked #1 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 11,000 (6.0% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 11,000 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $550 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 6.0% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.legacy.importer.rows" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.legacy.importer.rows/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.legacy.importer.rows/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.legacy.importer.rows",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.legacy.importer.rows/tags </dev/null
```

### 8. Review: high-cardinality custom metric `demo.frontend.request.count` (#4 by series)

- **Evidence:** Ranked #4 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 9,800 (5.4% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $490 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 5.4% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.frontend.request.count" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.frontend.request.count/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.frontend.request.count/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.frontend.request.count",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.frontend.request.count/tags </dev/null
```

### 9. Review: unqueried custom metric `demo.debug.trace.samples` (#2 by series)

- **Evidence:** Ranked #2 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 8,800 (4.8% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 8,800 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $440 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 4.8% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.debug.trace.samples" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.debug.trace.samples/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.debug.trace.samples/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.debug.trace.samples",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.debug.trace.samples/tags </dev/null
```

### 10. Review: high-cardinality custom metric `demo.frontend.worker.jobs` (#6 by series)

- **Evidence:** Ranked #6 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 7,800 (4.3% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $390 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 4.3% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.frontend.worker.jobs" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.frontend.worker.jobs/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.frontend.worker.jobs/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.frontend.worker.jobs",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.frontend.worker.jobs/tags </dev/null
```

### 11. Review: high-cardinality custom metric `demo.catalog.request.duration` (#7 by series)

- **Evidence:** Ranked #7 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 7,800 (4.3% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $390 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 4.3% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.catalog.request.duration" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.catalog.request.duration/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.catalog.request.duration/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.catalog.request.duration",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.catalog.request.duration/tags </dev/null
```

### 12. Review: high-cardinality custom metric `demo.pricing.request.duration` (#8 by series)

- **Evidence:** Ranked #8 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 7,800 (4.3% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $390 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 4.3% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.pricing.request.duration" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.pricing.request.duration/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.pricing.request.duration/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.pricing.request.duration",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.pricing.request.duration/tags </dev/null
```

### 13. Review: high-cardinality custom metric `demo.pricing.db.query.time` (#9 by series)

- **Evidence:** Ranked #9 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 7,800 (4.3% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $390 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 4.3% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.pricing.db.query.time" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.pricing.db.query.time/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.pricing.db.query.time/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.pricing.db.query.time",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.pricing.db.query.time/tags </dev/null
```

### 14. Review: high-cardinality custom metric `demo.catalog.db.query.time` (#10 by series)

- **Evidence:** Ranked #10 by indexed series (top 10 listed). In use, not configured with Metrics without Limits. Average indexed series: 7,400 (4.1% of custom metric average). Review which tag keys are actually queried.
- **Estimated effect:** Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the new series count, then subtract.
- **Upper-bound dollars (estimate, not guaranteed):** $370 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 4.1% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check the metric's related assets first.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.catalog.db.query.time" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.catalog.db.query.time/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.catalog.db.query.time/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.catalog.db.query.time",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.catalog.db.query.time/tags </dev/null
```

### 15. Review: unqueried custom metric `demo.batch.reconcile.duration` (#3 by series)

- **Evidence:** Ranked #3 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 6,400 (3.5% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 6,400 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $320 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 3.5% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.batch.reconcile.duration" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.batch.reconcile.duration/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.batch.reconcile.duration/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.batch.reconcile.duration",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.batch.reconcile.duration/tags </dev/null
```

### 16. Review: unqueried custom metric `demo.experiment.flag.evals` (#4 by series)

- **Evidence:** Ranked #4 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 4,300 (2.4% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 4,300 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $215 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 2.4% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.experiment.flag.evals" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.experiment.flag.evals/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.experiment.flag.evals/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.experiment.flag.evals",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.experiment.flag.evals/tags </dev/null
```

### 17. Review: unqueried custom metric `demo.legacy.importer.errors` (#5 by series)

- **Evidence:** Ranked #5 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 2,100 (1.2% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 2,100 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $105 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 1.2% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.legacy.importer.errors" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.legacy.importer.errors/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.legacy.importer.errors/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.legacy.importer.errors",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.legacy.importer.errors/tags </dev/null
```

### 18. Review: unqueried custom metric `demo.old.api.v1.calls` (#6 by series)

- **Evidence:** Ranked #6 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 1,700 (0.9% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 1,700 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $85 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 0.9% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.old.api.v1.calls" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.old.api.v1.calls/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.old.api.v1.calls/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.old.api.v1.calls",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.old.api.v1.calls/tags </dev/null
```

### 19. Review: unqueried custom metric `demo.tmp.migration.progress` (#7 by series)

- **Evidence:** Ranked #7 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 900 (0.5% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 900 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $45 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 0.5% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.tmp.migration.progress" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.tmp.migration.progress/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.tmp.migration.progress/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.tmp.migration.progress",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.tmp.migration.progress/tags </dev/null
```

### 20. Review: unqueried custom metric `demo.debug.gc.pauses` (#8 by series)

- **Evidence:** Ranked #8 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 350 (0.2% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 350 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $18 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 0.2% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.debug.gc.pauses" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.debug.gc.pauses/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.debug.gc.pauses/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.debug.gc.pauses",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.debug.gc.pauses/tags </dev/null
```

### 21. Review: unqueried custom metric `demo.sandbox.load.test` (#9 by series)

- **Evidence:** Ranked #9 by indexed series among unqueried metrics (top 10 listed). Not queried in the last 30 days (dashboards, monitors, notebooks, API) and not yet configured with Metrics without Limits. Average indexed series: 60 (0.0% of the month's custom metric average 182,000).
- **Estimated effect:** Upper bound: up to 60 indexed series fewer if you keep no tags or stop sending it. Measure the real effect with the read-only estimate call before changing it.
- **Upper-bound dollars (estimate, not guaranteed):** $3 per month (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) = 0.0% of custom metric average x $9,100 (estimated from this org's Datadog estimated-cost data pulled 2026-10-01) estimated custom-metric cost. The real saving is lower: see Estimated effect.
- **Risk:** Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. Configured metrics are also billed for ingested volume, so the net saving is smaller than the indexed drop.

Measure first (read-only). The metric type comes from the metadata call:

```bash
curl -sS -G "https://api.${DD_SITE}/api/v1/metrics/demo.sandbox.load.test" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") | jq .type
curl -sS -G "https://api.${DD_SITE}/api/v2/metrics/demo.sandbox.load.test/estimate" \
  -H @<(printf 'DD-API-KEY: %s\nDD-APPLICATION-KEY: %s\n' "$DD_API_KEY" "$DD_APP_KEY") \
  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' | jq .data.attributes.estimated_output_series
```

Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).

**Gate: approval required.**

```bash
ddw POST /api/v2/metrics/demo.sandbox.load.test/tags <<'JSON'
{
  "data": {
    "attributes": {
      "metric_type": "<gauge|count|rate|distribution>",
      "tags": [
        "<tag key to keep>",
        "<another tag key>"
      ]
    },
    "id": "demo.sandbox.load.test",
    "type": "manage_tags"
  }
}
JSON
```

Rollback: remove the tag configuration so all submitted tags are queryable again (data written while it was configured stays at the reduced tag set).

**Gate: approval required.**

```bash
ddw DELETE /api/v2/metrics/demo.sandbox.load.test/tags </dev/null
```

### 22. Review: log index `cluster-events` keeps logs 30 days (check compliance first)

- **Evidence:** Retention 30 days, over the 15-day review threshold, on an index holding 10.9% of indexed events (116,134,606 in 7 days). Check compliance first: audit, security, legal hold and contract terms may require this retention.
- **Estimated effect:** Depends on your contracted price per retention tier. Fill in: events x (current tier rate - new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.
- **Risk:** High for the data, check compliance first: logs older than the new retention become unsearchable and raising retention again does not bring them back. Check audit, security and legal hold needs.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/cluster-events <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "@reason:(Scheduled OR Pulled OR Created OR Started)",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop normal events"
    }
  ],
  "filter": {
    "query": "source:cluster-agent"
  },
  "num_retention_days": "<target days from your contract>",
  "tags": [
    "owner:platform"
  ]
}
JSON
```

Rollback: put back the config as exported. This does not restore logs already aged out.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/cluster-events <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "@reason:(Scheduled OR Pulled OR Created OR Started)",
        "sample_rate": 1.0
      },
      "is_enabled": false,
      "name": "drop normal events"
    }
  ],
  "filter": {
    "query": "source:cluster-agent"
  },
  "num_retention_days": 30,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

### 23. Review: log index `payments` keeps logs 30 days (check compliance first)

- **Evidence:** Retention 30 days, over the 15-day review threshold, on an index holding 6.7% of indexed events (70,608,350 in 7 days). Check compliance first: audit, security, legal hold and contract terms may require this retention.
- **Estimated effect:** Depends on your contracted price per retention tier. Fill in: events x (current tier rate - new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.
- **Risk:** High for the data, check compliance first: logs older than the new retention become unsearchable and raising retention again does not bring them back. Check audit, security and legal hold needs.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/payments <<'JSON'
{
  "daily_limit": 20000000,
  "exclusion_filters": [
    {
      "filter": {
        "query": "@http.status_code:[200 TO 299]",
        "sample_rate": 0.8
      },
      "is_enabled": true,
      "name": "sample 2xx"
    }
  ],
  "filter": {
    "query": "service:(cart OR accounts)"
  },
  "num_retention_days": "<target days from your contract>",
  "tags": [
    "owner:platform"
  ]
}
JSON
```

Rollback: put back the config as exported. This does not restore logs already aged out.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/payments <<'JSON'
{
  "daily_limit": 20000000,
  "exclusion_filters": [
    {
      "filter": {
        "query": "@http.status_code:[200 TO 299]",
        "sample_rate": 0.8
      },
      "is_enabled": true,
      "name": "sample 2xx"
    }
  ],
  "filter": {
    "query": "service:(cart OR accounts)"
  },
  "num_retention_days": 30,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

### 24. Review: log index `audit` keeps logs 90 days (check compliance first)

- **Evidence:** Retention 90 days, over the 15-day review threshold, on an index holding 1.5% of indexed events (15,894,883 in 7 days). Check compliance first: audit, security, legal hold and contract terms may require this retention.
- **Estimated effect:** Depends on your contracted price per retention tier. Fill in: events x (current tier rate - new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.
- **Risk:** High for the data, check compliance first: logs older than the new retention become unsearchable and raising retention again does not bring them back. Check audit, security and legal hold needs.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/audit <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "@http.url_details.path:/healthz",
        "sample_rate": 1.0
      },
      "is_enabled": true,
      "name": "drop health probes"
    }
  ],
  "filter": {
    "query": "source:audit"
  },
  "num_retention_days": "<target days from your contract>",
  "tags": [
    "owner:platform"
  ]
}
JSON
```

Rollback: put back the config as exported. This does not restore logs already aged out.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/audit <<'JSON'
{
  "exclusion_filters": [
    {
      "filter": {
        "query": "@http.url_details.path:/healthz",
        "sample_rate": 1.0
      },
      "is_enabled": true,
      "name": "drop health probes"
    }
  ],
  "filter": {
    "query": "source:audit"
  },
  "num_retention_days": 90,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

### 25. Review: log index `security` keeps logs 90 days (check compliance first)

- **Evidence:** Retention 90 days, over the 15-day review threshold, on an index holding 0.6% of indexed events (6,725,819 in 7 days). Check compliance first: audit, security, legal hold and contract terms may require this retention.
- **Estimated effect:** Depends on your contracted price per retention tier. Fill in: events x (current tier rate - new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.
- **Risk:** High for the data, check compliance first: logs older than the new retention become unsearchable and raising retention again does not bring them back. Check audit, security and legal hold needs.

Change: the index update **replaces the whole index config**, so this body is the current config with only the proposed field changed. Re-export the index right before applying and stop if it differs from the evidence here.

**Gate: approval required.**

```bash
ddw PUT /api/v1/logs/config/indexes/security <<'JSON'
{
  "exclusion_filters": [],
  "filter": {
    "query": "source:(firewall OR sign-in)"
  },
  "num_retention_days": "<target days from your contract>",
  "tags": [
    "owner:platform"
  ]
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
    "query": "source:(firewall OR sign-in)"
  },
  "num_retention_days": 90,
  "tags": [
    "owner:platform"
  ]
}
JSON
```

## Monitor hygiene (no dollar claim)

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

Monitors are rarely billed one by one; these are review flags for alert noise and review load.

- Duplicate groups (same type, query and thresholds): 2
- Not triggered in 90 days and older than that: 6 (plus 3 rare-event monitors skipped)
- Muted for more than 30 days: 1
- In No Data state: 3

### Duplicate: keep monitor 5002 "[cart] p95 latency high"

Query: `avg(last_10m):avg:demo.cart.request.duration{env:prod} by {service} > 0.8`. Duplicates: 5005 "[cart] p95 latency high (old)", 5006 "Cart latency - team view". Check that the notification targets of the duplicates are covered by the one you keep.

Trial first: mute monitor 5005 with a downtime for two weeks.

**Gate: approval required.**

```bash
ddw POST /api/v2/downtime <<'JSON'
{
  "data": {
    "attributes": {
      "message": "cost-cutter trial mute of a duplicate monitor",
      "monitor_identifier": {
        "monitor_id": 5005
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

Then delete monitor 5005 (irreversible; links, SLOs and composites that use this id break).

**Gate: approval required.**

```bash
ddw DELETE /api/v1/monitor/5005 </dev/null
```

Rollback of the delete: re-create it from the exported definition (it gets a new id).

**Gate: approval required.**

```bash
ddw POST /api/v1/monitor <<'JSON'
{
  "message": "copy kept from migration @oncall-alerts@example.com",
  "name": "[cart] p95 latency high (old)",
  "options": {
    "notify_no_data": false,
    "thresholds": {
      "critical": 0.8,
      "warning": 0.5
    }
  },
  "priority": 3,
  "query": "avg(last_10m):avg:demo.cart.request.duration{env:prod} by {service} > 0.8",
  "tags": [
    "team:demo-platform",
    "env:prod"
  ],
  "type": "query alert"
}
JSON
```

Trial first: mute monitor 5006 with a downtime for two weeks.

**Gate: approval required.**

```bash
ddw POST /api/v2/downtime <<'JSON'
{
  "data": {
    "attributes": {
      "message": "cost-cutter trial mute of a duplicate monitor",
      "monitor_identifier": {
        "monitor_id": 5006
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

Then delete monitor 5006 (irreversible; links, SLOs and composites that use this id break).

**Gate: approval required.**

```bash
ddw DELETE /api/v1/monitor/5006 </dev/null
```

Rollback of the delete: re-create it from the exported definition (it gets a new id).

**Gate: approval required.**

```bash
ddw POST /api/v1/monitor <<'JSON'
{
  "message": "team copy @oncall-cart@example.com",
  "name": "Cart latency - team view",
  "options": {
    "notify_no_data": false,
    "thresholds": {
      "critical": 0.8,
      "warning": 0.5
    }
  },
  "priority": 3,
  "query": "avg(last_10m):avg:demo.cart.request.duration{ env:prod } by {service} > 0.8",
  "tags": [
    "team:demo-platform",
    "env:prod"
  ],
  "type": "query alert"
}
JSON
```

### Duplicate: keep monitor 5007 "[accounts] error ratio"

Query: `sum(last_5m):sum:demo.accounts.request.count{env:prod,status:error}.as_count() / sum:demo.accounts.request.count{env:prod}.as_count() > 0.02`. Duplicates: 5010 "Accounts error ratio (dup)". Check that the notification targets of the duplicates are covered by the one you keep.

Trial first: mute monitor 5010 with a downtime for two weeks.

**Gate: approval required.**

```bash
ddw POST /api/v2/downtime <<'JSON'
{
  "data": {
    "attributes": {
      "message": "cost-cutter trial mute of a duplicate monitor",
      "monitor_identifier": {
        "monitor_id": 5010
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

Then delete monitor 5010 (irreversible; links, SLOs and composites that use this id break).

**Gate: approval required.**

```bash
ddw DELETE /api/v1/monitor/5010 </dev/null
```

Rollback of the delete: re-create it from the exported definition (it gets a new id).

**Gate: approval required.**

```bash
ddw POST /api/v1/monitor <<'JSON'
{
  "message": "duplicate",
  "name": "Accounts error ratio (dup)",
  "options": {
    "notify_no_data": false,
    "thresholds": {
      "critical": 0.02
    }
  },
  "priority": 3,
  "query": "sum(last_5m):sum:demo.accounts.request.count{status:error,env:prod}.as_count() / sum:demo.accounts.request.count{env:prod}.as_count() > 0.02",
  "tags": [
    "team:demo-platform",
    "env:prod"
  ],
  "type": "query alert"
}
JSON
```

### Not triggered recently (review, do not delete blindly)

A monitor that never fires may be well tuned, or broken (wrong scope, dead metric, impossible threshold). Ask the owner before muting or deleting; use the same gated downtime and delete steps as above.

| Monitor | Name | Type | Last triggered |
|---|---|---|---|
| 5011 | [notifications] queue lag | query alert | never (in search data) |
| 5012 | [inventory] worker jobs stalled | query alert | never (in search data) |
| 5013 | Legacy importer rows dropped | query alert | 2025-11-02 |
| 5014 | Old API v1 traffic spike | query alert | never (in search data) |
| 5015 | Migration progress stuck | query alert | 2026-03-12 |
| 5019 | Sandbox load test running | query alert | never (in search data) |

### Skipped: rare-event monitors

These have not triggered in the window, but their name, tags or query match a rare-event keyword (certificate expiry, disaster recovery, backups and similar), so staying quiet is expected. They are not flagged. Keywords: `cert`, `certificate`, `ssl`, `tls`, `expiry`, `expiration`, `expire`, `expires`, `disaster`, `dr`, `backup`, `backups`, `restore`, `failover` (change with --rare-event-keywords).

| Monitor | Name | Matched keywords |
|---|---|---|
| 5022 | TLS certificate expiry on www.example.com | certificate, expiry, tls |
| 5023 | Nightly database backup failed | backup |
| 5024 | Standby region replication lag | disaster |

### Muted for more than 30 days (review)

A long mute usually means the monitor is noisy, obsolete, or covering a known gap. Ask the owner whether to fix it, unmute it or retire it; any change uses the gated steps above.

| Monitor | Name | Muted since | How |
|---|---|---|---|
| 5025 | [search] indexer error rate | 2026-07-28 | downtime 900101 with no end |

### In No Data state

| Monitor | Name | Query |
|---|---|---|
| 5012 | [inventory] worker jobs stalled | `sum(last_30m):sum:demo.inventory.worker.jobs{env:prod}.as_count() < 1` |
| 5013 | Legacy importer rows dropped | `avg(last_1h):avg:demo.legacy.importer.rows{env:prod} < 10` |
| 5015 | Migration progress stuck | `change(avg(last_30m),1h_ago):avg:demo.tmp.migration.progress{env:prod} < 1` |

## Not covered and assumptions

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

- Upper bounds assume cost scales linearly with the share of usage. Commitments, tiers and minimums mean the real saving can be lower, or zero until the next renewal.
- Per-index ingest uses the estimated usage metric tagged by index; it is an estimate.
- APM, RUM, Synthetics and security products are listed in the inventory only.
- Monitor hygiene uses the monitor list and search APIs; it does not read monitor history. Mute ages come from the monitor list's matching_downtimes (requested with with_downtimes=true).
- The script does not check what the key is allowed to do. The operator confirms the service account's role in the Datadog UI before the run.

---

Savings are not guaranteed. Actual savings depend on your contract, discounts and commitments. Dollar figures in this report are estimated from this org's Datadog estimated-cost data pulled 2026-10-01; they are not an invoice or a quote. Test changes in non-production first; the operator approves every change.

> **SYNTHETIC EXAMPLE DATA, not from a real account.**

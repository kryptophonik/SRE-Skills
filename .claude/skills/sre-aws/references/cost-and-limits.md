# Cost, endpoints and plan requirements (AWS)

All items fetched live on 2026-10-16. Prices are US East and can change, so recheck the linked pages.

## Cost Explorer (`aws ce ...`)
- Endpoint: `https://ce.us-east-1.amazonaws.com` only. Always pass `--region us-east-1`. Source: https://docs.aws.amazon.com/cost-management/latest/userguide/ce-api.html
- Price: **$0.01 per API request** against the primary billing view, and $0.01 per source for custom billing views (a 5-source view costs $0.05 per request). Hourly granularity is billed separately. Source: https://aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/
- Practice: one MONTHLY or DAILY query per review, cache the JSON, and remember that `End` is exclusive. The response pages via `NextPageToken`, and each page is another billed request.

## CloudWatch Logs Insights (`aws logs start-query`)
- Billed **per GB of data scanned**. The free tier's 5 GB covers ingestion, archive and Insights scanned data combined. Source: https://aws.amazon.com/cloudwatch/pricing/ (Logs tab, "Logs Insights").
- Practice: query one log group over the shortest window, use `limit`, use `scripts/logs-insights-bounded.sh` (it calls `stop-query` on timeout), and avoid dashboards that rerun queries.
- Live Tail (`aws logs tail --follow`, StartLiveTail): 1,800 free minutes per month, then $0.01 per minute (same page).

## CloudWatch metrics APIs
- GetMetricData, GetInsightRuleReport and GetMetricWidgetImage are **always charged** and are not in the 1M free API requests. Other API requests are free for the first 1M, then billed per 1,000. Metrics Insights through the API costs $0.01 per 1,000 metrics analyzed, and is free in the console. Source: https://aws.amazon.com/cloudwatch/pricing/
- Practice: prefer `get-metric-statistics` for one metric, with a coarse `--period` and a short window.

## AWS Health (`aws health ...`)
- Plan: needs **Business Support+, Enterprise Support or Unified Operations**. Business, Enterprise On-Ramp and Enterprise are accepted only in Regions without the new plans or for accounts that haven't moved to them. Otherwise the call returns `SubscriptionRequiredException`. Source: https://docs.aws.amazon.com/health/latest/ug/health-api.html
- Endpoints: active `health.us-east-1.amazonaws.com`, passive `health.us-east-2.amazonaws.com` (eventually consistent), global `global.health.amazonaws.com`. Find the active one with `dig global.health.amazonaws.com | grep CNAME` and use that Region as `--region`. Same source.
- Organizational view: needs an organization with all features enabled and the management account, or a delegated administrator (the recommended practice). Events are kept 90 days. Source: https://docs.aws.amazon.com/health/latest/ug/aggregate-events.html
- `describe-events` is paginated. Use `--max-items`. Source: https://awscli.amazonaws.com/v2/documentation/api/latest/reference/health/describe-events.html (AWS CLI 2.38.1)

## DR restores
- RDS restores create a new billable DB instance. Storage and instance hours run until you delete it. MySQL and PostgreSQL default to `open-source-rds-extended-support`, which can add Extended Support charges on old major versions. Source: https://awscli.amazonaws.com/v2/documentation/api/latest/reference/rds/restore-db-instance-from-db-snapshot.html (AWS CLI 2.38.1)

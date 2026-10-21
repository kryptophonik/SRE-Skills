# Demo dataset: SYNTHETIC example data

**Everything in this folder is synthetic.** It describes Example Corp, a fictional organization
invented for this demo. No file here came from a real account, and no company, tenant, host,
metric, index, monitor, volume or dollar amount in it belongs to anyone. Metric names use a
`demo.` prefix, service names are generic words (`frontend`, `cart`, `catalog`, `search`,
`pricing`, `inventory`, `accounts`, `notifications`), and the only host and domain names are under
`example.com`, which is reserved for documentation.

The files mirror what a live run with `--save-dir` writes, one per read call the audit makes,
plus `audit_meta.json`, which marks the set as synthetic and fixes the "pulled" date, usage month
and evaluation date so the report is reproducible:

| File | Read call it stands in for |
|---|---|
| `usage_summary.json` | usage summary for 2026-09 |
| `estimated_cost.json` | estimated cost by product (committed, on-demand and total rows) |
| `top_avg_metrics.json` | custom metrics by hourly average |
| `metrics_unqueried.json` | configurable metrics not queried in 30 days, with volumes |
| `metrics_by_volume.json` | configurable metrics by indexed volume |
| `log_indexes.json` | 7 log indexes with retention, exclusion filters and a daily limit |
| `logs_by_index.json` | 7 days of hourly indexed-event counts per index |
| `logs_ingest_by_index.json` | the estimated ingest usage metric split by index and excluded/kept |
| `monitors.json` | 26 monitors (listed with `with_downtimes=true`): duplicates, never-triggered, rare-event (certificate expiry, backup, disaster recovery), one muted for 64 days and one for 6 days, No Data, log and anomaly monitors |
| `monitor_search.json` | last-triggered times for the same monitors |
| `audit_meta.json` | synthetic flag, label, pull date 2026-10-01, month 2026-09 |

## Run the demo

From the skill folder, write the report to a temp workspace (do **not** overwrite the tracked
`demo/demo-report.md`):

```bash
W="$(mktemp -d "${TMPDIR:-/tmp}/obcost-demo.XXXXXX")"
python3 scripts/dd_cost_audit.py --input-dir demo --dollar-estimates --out "$W/demo-report.md"
echo "wrote $W"
```

Omitting `--out` also creates a workspace under `${TMPDIR:-/tmp}` and prints `workspace: <path>`.

The committed [demo-report.md](demo-report.md) is a golden copy of that output; the test suite
regenerates it into a temp path and fails if it differs. The synthetic-data label sits at the top,
at the bottom and at the start of every top-level section, so any excerpt carries it. Every dollar
figure in it is a made-up example, labelled with its source and pull date; it is not a
measurement of any real organization and not a savings claim.

Maintainers refreshing the golden report (only when the demo inputs or report format change):

```bash
python3 scripts/dd_cost_audit.py --input-dir demo --dollar-estimates --out demo/demo-report.md
```

You can also try the converter on the demo monitors (also outside the repo):

```bash
W="$(mktemp -d "${TMPDIR:-/tmp}/obcost-conv.XXXXXX")"
python3 scripts/monitors_to_prom.py --monitors demo/monitors.json --out "$W/demo.rules.yml" --report "$W/demo-conversion.md"
echo "wrote $W"
```

---
name: sre-observability-cost-cutter
description: Use to reduce observability spend. Read-only usage and cost audit (works with Datadog), a ranked savings report with approval-gated changes and rollbacks, and conversion of metric monitors to Prometheus rules checked by promtool.
---

# Observability cost cutter

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).


Audits observability usage with read calls only, then writes a Markdown savings plan a team can hand to a manager: review flags with the biggest estimated savings first, each item with its evidence, an honest estimate, the risk, the exact change behind an approval gate, and its rollback. A second script converts selected metric monitors into Prometheus alerting rules and validates them with `promtool`, for teams moving some alerting to Prometheus. Works with Datadog today; no affiliation with or endorsement by any vendor.

> **Before you start:** test every change in a non-production org, or on one low-risk metric, index or monitor, first. The operator approves each change; nothing is applied automatically. Savings are estimates and are not guaranteed. The audit script sent only GET requests in our tests (an allow-list refuses anything else); review it before giving it a key.

Related skills: `sre-safety-gates` for the approval rules, `sre-datadog` for ad-hoc queries and key scoping, `sre-prometheus-grafana` for rule linting and safe Prometheus operations, `sre-slo-burn-rate-rules` if converted monitors should become SLO burn-rate alerts instead.

## Inputs

- **Live audit:** `DD_API_KEY`, `DD_APP_KEY` from a dedicated service account with a read-only role (`usage_read`, `metrics_read`, `timeseries_query`, `logs_read_config`, `monitors_read`; add `billing_read` for estimated cost), and `DD_SITE` (default `datadoghq.com`). A scoped application key may not be able to list log indexes. An unscoped application key is acceptable only when it belongs to that dedicated read-only service account, never a person's key. If index listing is not permitted, the report says the log index section is not supported with that key; fall back to the saved index export (`log_indexes.json` saved by someone allowed to read index configs, then `--input-dir`). The script does not check key permissions. Usage and cost endpoints only work from a parent-level org. Details: [references/api-endpoints.md](references/api-endpoints.md).
- **Offline audit:** a directory of exported JSON files named as in `INPUT_FILES` in the script (a live run with `--save-dir` produces exactly that set). Use this when keys cannot leave your network: they run the export, you run the report.
- **Contract rates (optional):** dollar figures are placeholders unless `--dollar-estimates` is set, and then they come only from the org's own estimated-cost API data. Every dollar figure is then labelled as estimated from that data with the date it was pulled (from `audit_meta.json`, which a live run writes into `--save-dir`; an export without it falls back to the file date of `estimated_cost.json`). The report adds per-category upper-bound totals, and states next to the totals and in the footer that savings are not guaranteed and that actual savings depend on the org's contract, discounts and commitments. Use `--product-map` when product names are not matched automatically.
- **Demo:** [demo/](demo/README.md) holds a synthetic export for Example Corp, a fictional org (hosts only under `example.com`). The demo report carries the label "SYNTHETIC EXAMPLE DATA, not from a real account" at the top, at the bottom and at the start of every top-level section, and so does [references/example-report.md](references/example-report.md). From the skill folder, write the report to a temp workspace (never into `demo/` or the repo):

  ```bash
  W="$(mktemp -d "${TMPDIR:-/tmp}/obcost-demo.XXXXXX")"
  python3 scripts/dd_cost_audit.py --input-dir demo --dollar-estimates --out "$W/demo-report.md"
  echo "wrote $W"
  ```

  Never present demo numbers as a real account's. Omitting `--out` also creates a workspace under `${TMPDIR:-/tmp}` and prints `workspace: <path>`.
- **Conversion:** a monitor export (JSON from `GET /api/v1/monitor`) and a mapping file from vendor metric names and tag keys to Prometheus metric and label names (example: `scripts/tests/fixtures/mapping.json`).
- **Tools:** Python 3 (stdlib only; tested on 3.13), `promtool` for rule checks, `jq` and `curl` only for the follow-up commands in the report.

## Steps

1. Confirm the target org and site. The operator checks the service account's role in the Datadog UI before the run and confirms it holds only the read permissions above; the script does not check key permissions. Never paste keys into chat; export them in the operator's shell.
2. Create a private workspace outside the repo, then run the audit. Raw responses and the report hold org usage data; keep them out of any checkout.

   ```bash
   W="$(mktemp -d "${TMPDIR:-/tmp}/obcost.XXXXXX")"
   python3 scripts/dd_cost_audit.py --save-dir "$W/raw" --report "$W/cost-audit-report.md" --json "$W/findings.json"
   echo "wrote $W"
   ```

   Or offline from an export: `python3 scripts/dd_cost_audit.py --input-dir "$W/raw" --report "$W/cost-audit-report.md"` (`--out` is an alias for `--report`). Omitting `--report` / `--out` (and `--save-dir` in live mode) creates a workspace under `${TMPDIR:-/tmp}` and prints `workspace: <path>`.
   Useful flags: `--month YYYY-MM` (default the month in `audit_meta.json`, else last month), `--as-of YYYY-MM-DD`, `--top 10`, `--unqueried-days 30` (max 180), `--log-days 7`, `--never-triggered-days 90`, `--rare-event-keywords <list>`, `--muted-days 30`, `--min-index-share 0.05`, `--retention-over 15`, `--target-retention <days>`, `--dollar-estimates`, `--product-map map.json`.
3. Read the report's "Data not available" table first. A 403 on log indexes means that section is not supported with this key: use the saved index export. A 403 on usage or cost means a child org or a missing permission; say so rather than guessing.
4. Review the ranked plan with the owner of each metric, index and monitor. For metric items, run the read-only estimate call the report prints with the tag keys they want to keep, and replace the upper bound with that number.
5. For each item the owner approves, fill in every `<placeholder>`, then run its gated block from a shell holding a separate write-capable key in `DD_WRITE_API_KEY` / `DD_WRITE_APP_KEY`. The `ddw` helper never uses `DD_API_KEY` / `DD_APP_KEY`, refuses to run without the write variables, and refuses a body that still contains `<placeholder>` text. Re-export a log index right before its PUT and stop if it changed. Record who approved what and when.
6. Verify after each change: the next audit run, the vendor's usage page, and that dashboards and monitors that used the metric or index still work. Keep the rollback block at hand for the observation window.
7. Migration path (optional): convert selected monitors and check the rules.

   ```bash
   python3 scripts/monitors_to_prom.py --monitors "$W/raw/monitors.json" --map mapping.json --ids 1001,1003 --out "$W/converted.rules.yml" --report "$W/conversion-report.md" --check
   ```

   Omitting `--out` / `--report` creates a workspace under `${TMPDIR:-/tmp}` and prints `workspace: <path>`. Read every "Check" and "Not translated" line in `$W/conversion-report.md`. v1 refuses, and lists under "Manual conversion needed", monitors whose queries are grouped by different tags (they need `on()`/`ignoring()` vector matching) and monitors with recovery thresholds (hysteresis: they do not map cleanly onto `keep_firing_for`, which holds an alert for a fixed time rather than until the value crosses a second level). Convert those by hand. Write a `promtool test rules` unit test for each rule you keep (pattern: `scripts/tests/fixtures/converted.test.yml`), then run old monitor and new rule in parallel and compare firing history before retiring the monitor. Translation table: [references/query-translation.md](references/query-translation.md).
8. Run the skill's own tests after any edit: `python3 scripts/tests/run_tests.py` (set `REQUIRE_PROMTOOL=1` in CI).

## Review thresholds

Thresholds and rankings raise **review flags**, not recommendations to cut. Every item title starts with "Review:" and the owner decides.

- **Custom metrics:** ranked by indexed series count; the top N (`--top`, default 10) of the unqueried list and of the in-use list are flagged. There is no fixed series cutoff.
- **Log indexes:** an index with at least `--min-index-share` (default 5%) of indexed events and no enabled exclusion filter is flagged. The example filter ships with `is_enabled: false` and placeholders. For the trial window use `sample_rate` 0.9 or lower; `sample_rate` is the fraction of matching logs excluded, so 1.0 means none of the matching logs are kept in the index.
- **Log retention:** every index keeping logs longer than `--retention-over` (default 15) days is flagged "check compliance first". No dollar figure is shown.
- **Monitors not triggered in `--never-triggered-days` (default 90):** monitors covering rare events are skipped and listed separately. A monitor is skipped when a word in its name, tags or query matches one of these keywords: `cert`, `certificate`, `ssl`, `tls`, `expiry`, `expiration`, `expire`, `expires`, `disaster`, `dr`, `backup`, `backups`, `restore`, `failover`. Replace the list with `--rare-event-keywords a,b,c`; an empty string skips none.
- **Muted monitors:** monitors muted for more than `--muted-days` (default 30) are flagged, from the monitor list's `matching_downtimes` (requested with `with_downtimes=true`), or from legacy `options.silenced` when the monitor was last modified before the cutoff. `matching_downtimes` is not verified on a real account; if no monitor in the export has the field at all, the check is skipped and the report says: "Muted-monitor check skipped: the monitor list had no downtime data (`matching_downtimes`), so this report can't say whether any monitors are muted." It never reports zero muted monitors in that case.

## Skill-specific gates
Read-only by default. Every write, delete, failover or restart sits in its own fenced block with the exact line `**Gate: approval required.**` directly above it. The pack's [sre-safety-gates](../sre-safety-gates/SKILL.md) rules apply on top.

- Script output goes under `${TMPDIR:-/tmp}` (a new `obcost-*` or `obcost-conv-*` directory) by default, never into the cwd or the skill tree. Keep any explicit `--report` / `--save-dir` / `--out` path outside the repo.
- `dd_cost_audit.py` only issues GET requests to the paths in `READ_PATHS`; any other path raises an error before a request is made. The test suite checks this against a mock server.
- Keys are read from the environment and only placed in request headers. They are never printed, saved or written to the report (tested with sentinel keys).
- The report prints every change as a gated block with a gated rollback block. Approved changes go through the `ddw` helper, which uses only `DD_WRITE_API_KEY` / `DD_WRITE_APP_KEY` (never the audit's read variables) and refuses bodies with `<placeholder>` text. Never widen the audit key.
- Log index updates replace the whole index config. The report builds the full body from the export; re-export first and stop if anything differs.
- Lowering log retention deletes searchable history and cannot be undone. Deleting a monitor breaks links, SLOs and composites that use its id; mute it with a downtime first.
- Loading converted rules into a production Prometheus is a change too:

**Gate: approval required.**

```text
Merge converted.rules.yml into the Prometheus rule config through the normal change process
(pull request, promtool check rules in CI, deploy). Keep the source monitors running until the
parallel run shows matching alerts. Rollback: revert that change.
```

## Output

All of these land in the workspace directory (`$W` or the path printed as `workspace:`), never in the skill tree or the repo:

- `cost-audit-report.md`: disclaimer, data-availability table, estimated cost by product (only from the org's own estimated-cost data), usage inventory (hosts, APM hosts, containers, custom metrics, log bytes, indexed spans, indexed logs by retention, per-index table, top custom metrics), ranked savings plan with gated changes and rollbacks, monitor hygiene (duplicates, not triggered recently, No Data) with no dollar claim, assumptions.
- `findings.json`: machine-readable items for tickets or dashboards.
- `raw/`: the raw read responses, as evidence and for offline re-runs.
- `converted.rules.yml` and `conversion-report.md`: rules plus per-monitor status (converted / converted with notes / skipped) and everything that did not translate.

Example output from the test fixtures (made-up numbers, labelled as an example): [references/example-report.md](references/example-report.md).

## Tested vs docs-only

| Part | Status | Where |
|---|---|---|
| Offline parsing of every input file, ranking, report and JSON output | tested | `scripts/tests/run_tests.py` on fixtures, 2026-10-18 |
| Live mode: GET-only allow-list, header auth, 429 retry, 403 handling, `--save-dir` and offline re-run giving identical findings, keys never in output | tested against a local mock server, not a real account | `run_tests.py` `LiveAgainstMock` |
| Every write block in the report is gated, bodies are valid JSON, bash blocks pass `shellcheck -S warning` | tested | `run_tests.py` `OfflineAudit` |
| `--dollar-estimates`: every dollar figure labelled with source and pull date, totals add up, not-guaranteed and contract statements next to totals and in footer, pull-date fallback | tested | `run_tests.py` `OfflineAudit` |
| Demo report regenerates byte for byte from `demo/` (written to a temp path, not back into `demo/`) and carries the synthetic-data label; a default run leaves the skill tree and `git status` clean | tested | `run_tests.py` `Demo` |
| `ddw` helper: ignores `DD_API_KEY`/`DD_APP_KEY` and refuses without the write variables, sends only the write keys, refuses every report body with `<placeholder>` text (run in bash against a fake `curl`) | tested | `run_tests.py` `WriteHelper` |
| Review thresholds: review wording, metrics ranked by series with `--top`, retention flag "check compliance first", exclusion example disabled with `sample_rate` 0.9, rare-event skip and its override, mutes over 30 days, 403 on log indexes reported with the export fallback | tested on fixtures and the demo | `run_tests.py` `OfflineAudit`, `Demo`, `AuditGuards` |
| Synthetic-data label at top, bottom and every top-level section of the demo and example reports | tested | `run_tests.py` |
| `with_downtimes=true` and `matching_downtimes` on the monitor list | docs-only (vendor's generated API client); not verified on a real account. If no monitor in the export has the field at all, the report says: "Muted-monitor check skipped: the monitor list had no downtime data (`matching_downtimes`), so this report can't say whether any monitors are muted." (tested) | api-endpoints.md |
| Monitor converter: translation table, refusals (including on()/ignoring() and recovery thresholds), templates, rule file passes `promtool check rules`, converted rules pass a `promtool test rules` unit test | tested with promtool 3.15.0 | `run_tests.py` `Converter` |
| Endpoint paths, parameters, permissions and response field names | docs-only | [references/api-endpoints.md](references/api-endpoints.md), checked 2026-10-18 |
| Real response shapes and volumes, paging on large orgs, product names in estimated-cost data (fixture names are invented) | not verified (no account) | first live run must confirm |
| Whether a scoped application key can list log indexes (`logs_read_config` is not on the scopes page) | not verified | api-endpoints.md |
| Maximum `per_page` for monitor search | not documented | script uses 100 |
| Whether an empty tag allowlist is accepted for a metric tag configuration | not verified | report uses explicit placeholders instead |
| Semantic match between a converted rule and the source monitor on real data | not verified | parallel run required (Step 7) |

## Stop rules

- Before the run, the operator checks the service account's role in the Datadog UI. Stop if it holds any write permission (any `*_write`, `monitors_downtime` or `logs_modify_indexes`) and ask for a read-only service account. The script does not check key permissions, so this check is the operator's.
- Stop if the org, site or account in the output is not the one the operator named.
- Stop before any gated block that lacks explicit approval for that exact block, or whose exported config no longer matches the evidence.
- Stop and roll back if dashboards, monitors or SLOs that used a changed metric or index break, or if usage does not drop as expected after the observation window.
- Stop and report rather than estimate when cost data is missing; never invent prices.
- Do not retire a source monitor until its converted rule has run in parallel and matched.

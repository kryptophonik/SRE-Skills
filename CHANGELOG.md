# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/). The version number lives only in `scripts/build-targets.py`.

## Planned

1. Queue/stream triage (Kafka, SQS, Pub/Sub lag and backlog).
2. Codex plugin packaging, once it's verified against the docs.

## [3.1.0] - 2026-10-18

### Added
- `sre-database-triage`: read-only triage for PostgreSQL, MySQL/MariaDB and Redis (locks, connections, replication lag, slow queries, memory and eviction), self-hosted and managed (RDS/Aurora, Cloud SQL, Azure, ElastiCache/MemoryDB, Memorystore). Bundles `db-ro.sh`, `db-snapshot.sh` (a redacted evidence bundle) and a test suite; every state-changing step is a separate gated block.
- `sre-expiry-audit`: TLS certificate (`cert-expiry.sh`, with `--chain` and IPv6) and domain (`domain-expiry.sh`, RDAP) expiry checks, plus cloud certificate and secret expiry.
- `sre-incident-communication`: an external status-page template with no names, bridge links or internal causes, and an Output section with severity and impact fields.
- `sre-postmortem-templates`: databases as an evidence source, and TTD, TTA and TTM (time to detect, acknowledge and mitigate) fields.
- `sre-aws`: a gated Aurora / Multi-AZ DB cluster failover to a named replica, with the lag check first and the Global Database commands called out.
- Evals: 22 dry-run cases from a simulated 3am incident and 4 more negative cases (10 of 42 trigger cases are negatives).

### Changed
- `sre-change-safety`: during an active SEV, impact-reducing changes (rollback to last known-good, flag off, scale up) may go ahead once the IC or the lone responder approves, logged in the timeline.
- `sre-incident-command` and `sre-engineer`: a lone paged responder is IC until handoff and pages a second person for SEV-1/2. The assistant is never IC, and the comms lead is a human who approves and sends.
- `sre-remediation-actions`: connection-pooler restart guidance (scoped `PAUSE`/`RESUME`, separate gated terminate and timeout blocks) and a risk/reversibility table for database actions.
- `sre-k8s-safe-remediation`: reuses a pinned target and a recent snapshot, adds the GitOps revert path, and pauses auto-sync before a bare undo.
- The validator requires the exact `**Gate: approval required.**` marker above every gated command.

### Fixed
- `cert-expiry.sh`: validates numeric arguments and passes the timeout safely, closing a command-injection path.

### Known gaps
- The InnoDB status size cap on a busy server hasn't been checked live.
- Managed-service commands, real TLS endpoints, Valkey and real MySQL replica values were checked against current docs, not against live services.

## [3.0.1] - 2026-10-17

### Changed
- README: skills table for all 34 skills, per-tool quick-start commands, the safety-gate flowchart, and an example 5xx walkthrough.

### Fixed
- `pd_audit_schedules.sh` computes its UTC +14 day window with python3. GNU `date -d` fails on macOS `/bin/bash` 3.2.
- `og_export.sh` still only GETs and creates `--out` mode 700; its test reads that mode without GNU `stat -c`.

## [3.0.0] - 2026-10-16

### Added
- A shared `sre-safety-gates` skill and an inline four-line gate block in every skill.
- Generic process skills (incident command, change safety, DR/backup test, capacity, cost, toil, dependency mapping, security triage, observability cookbook, on-call handoff and audit, and more).
- Read-only tool adapters: Kubernetes, AWS, Azure, GCP, Terraform, Dynatrace, Prometheus/Grafana, Datadog, PagerDuty/Opsgenie. Each comes with capped, read-only `scripts/` and `references/`.
- `sre-slo-burn-rate-rules` (burn-rate rule generator with tests), `sre-k8s-safe-remediation` (manual only) and `sre-oncall-audit`.
- Opt-in guardrails: the Terraform guard hook plus settings example, and the Kubernetes deny rules.
- Multi-tool packaging generated from `SKILL.md`: the Claude Code plugin and marketplace, the Gemini CLI extension (`GEMINI.md`), the Cursor always-on rule, `AGENTS.md` (Codex, Cursor, Grok, Copilot), `.github/copilot-instructions.md`, and a `skills/` mirror. CI checks they're up to date.
- Per-tool install docs (`docs/install/`), CONTRIBUTING, SECURITY.
- Codex `agents/openai.yaml` (`policy.allow_implicit_invocation: false`), generated for every `disable-model-invocation: true` skill.
- CI: Terraform guardrail tests (terraform 1.16) and a bash 3.2 job on macOS (`/bin/bash`).

### Changed
- Every skill name now has the `sre-` prefix. Descriptions are ≤250 characters and lead with the trigger.
- Unified placeholders (`<ns>`, `<env>`, `<ctx>`…), IC terminology, postmortem timing ("within 48 h of resolution") and SEV cadence.
- Merged `sre-debugging-tools` + `sre-performance-tools` into `sre-diagnostics`, and `sre-slo-templates` + `sre-alerting-templates` into `sre-slo-alerting`.
- Moved the MCP setup to `sre-safety-gates/references/mcp.md`.
- Datadog: MCP endpoint `https://mcp.<site>/v1/mcp`; burn rate `.over()` uses the SLO window; corrected the CPU-limit unit note.
- PagerDuty/Opsgenie paginators: `MAX_PAGES` cap and 429 backoff. All scripts are bash 3.2-compatible (tested with 3.2.57). Script paths in skills and references are relative to the skill folder, with no `${CLAUDE_SKILL_DIR}`. The Terraform tests need terraform 1.16+.

### Changed (Breaking): skill names

2.x shipped flat files at the repo root. 3.0.0 ships one folder per skill under `.claude/skills/`, and every name has the `sre-` prefix. Plugin installs namespace them as `/sre:<name>`.

| 2.x file | 3.0.0 skill |
|---|---|
| `sre_architect.md` | `sre-architect` |
| `sre_engineer.md` | `sre-engineer` |
| `sre_debugging_tools.md` | `sre-diagnostics` (merged) |
| `sre_performance_tools.md` | `sre-diagnostics` (merged) |
| `sre_slo_templates.md` | `sre-slo-alerting` (merged) |
| `sre_alerting_templates.md` | `sre-slo-alerting` (merged) |
| `sre_chaos_engineering.md` | `sre-chaos-engineering` (now manual only) |
| `sre_incident_communication.md` | `sre-incident-communication` |
| `sre_postmortem_templates.md` | `sre-postmortem-templates` |
| `sre_production_readiness.md` | `sre-production-readiness` |
| `sre_remediation_actions.md` | `sre-remediation-actions` (reference) |
| `sre_runbook_templates.md` | `sre-runbook-templates` |
| `sre_tools_catalog.md` | `sre-tools-catalog` (reference) |
| `router.md`, `manifest.md` | `SKILLS.md` (routing, human-facing) and `sre-safety-gates` |

Pre-release 3.0 names without the prefix map one-to-one by adding `sre-` (for example `k8s-triage` → `sre-k8s-triage`). The one exception is `dynatrace-sre` → `sre-dynatrace`.

### Removed
- The 2.x per-skill safety sections, replaced by the shared gates. No `.mcp.json` is shipped.

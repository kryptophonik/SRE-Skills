# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/). The version number lives only in `scripts/build-targets.py`.

## Planned

1. **Database/datastore triage** (`sre-database-triage`): Postgres/MySQL/Redis locks, replication lag, connection exhaustion, slow queries. Read-only, with the gate block.
2. Queue/stream triage (Kafka, SQS, Pub/Sub lag and backlog).
3. TLS/certificate expiry checks.
4. Codex plugin packaging, once it's verified against the docs.

## [3.0.0] - Unreleased

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
- README: skills table for all 34 skills, per-tool quick-start commands, the safety-gate flowchart, and an example 5xx walkthrough.
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

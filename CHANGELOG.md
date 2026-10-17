# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/). The version number lives only in `scripts/build-targets.py`.

## [3.0.0] - Unreleased

### Added
- A shared `sre-safety-gates` skill and an inline four-line gate block in every skill.
- Generic process skills (incident command, change safety, DR/backup test, capacity, cost, toil, dependency mapping, security triage, observability cookbook, on-call handoff and audit, and more).
- Read-only tool adapters: Kubernetes, AWS, Azure, GCP, Terraform, Dynatrace, Prometheus/Grafana, Datadog, PagerDuty/Opsgenie. Each comes with capped, read-only `scripts/` and `references/`.
- `sre-slo-burn-rate-rules` (burn-rate rule generator with tests), `sre-k8s-safe-remediation` (manual only) and `sre-oncall-audit`.
- Opt-in guardrails: the Terraform guard hook plus settings example, and the Kubernetes deny rules.
- Multi-tool packaging generated from `SKILL.md`: the Claude Code plugin and marketplace, the Gemini CLI extension (`GEMINI.md`), the Cursor always-on rule, `AGENTS.md` (Codex, Cursor, Grok, Copilot), `.github/copilot-instructions.md`, and a `skills/` mirror. CI checks they're up to date.
- Per-tool install docs (`docs/install/`), CONTRIBUTING, SECURITY.

### Changed
- Every skill name now has the `sre-` prefix. Descriptions are ≤250 characters and lead with the trigger.
- Unified placeholders (`<ns>`, `<env>`, `<ctx>`…), IC terminology, postmortem timing ("within 48 h of resolution") and SEV cadence.
- Merged `sre-debugging-tools` + `sre-performance-tools` into `sre-diagnostics`, and `sre-slo-templates` + `sre-alerting-templates` into `sre-slo-alerting`.
- Moved the MCP setup to `sre-safety-gates/references/mcp.md`.
- Datadog: MCP endpoint `https://mcp.<site>/v1/mcp`; burn rate `.over()` uses the SLO window; corrected the CPU-limit unit note.
- PagerDuty/Opsgenie paginators: `MAX_PAGES` cap and 429 backoff. The Kubernetes scripts are bash 3.2-compatible.

### Removed
- The 2.x per-skill safety sections, replaced by the shared gates. No `.mcp.json` is shipped.

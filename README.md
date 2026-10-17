# claude-sre: SRE skill pack with approval gates

Generic Site Reliability Engineering skills in the open [Agent Skills](https://agentskills.io/specification) format (`SKILL.md` folders). They cover incident command, read-only diagnosis, gated remediation, SLOs and burn-rate alerting, DR drills, capacity, cost, toil, and read-only adapters for Kubernetes, AWS, Azure, GCP, Terraform, Dynatrace, Prometheus/Grafana, Datadog and PagerDuty/Opsgenie.

Every skill follows one rule set: **read-only first → propose with risk and reversibility → explicit human approval → act → verify → stop and escalate if worse.** The full rules live in [`sre-safety-gates`](.claude/skills/sre-safety-gates/SKILL.md), and every skill also carries a short inline copy, so a partial install stays gated.

## Install

See **[INSTALL.md](INSTALL.md)**. It covers Claude Code, Gemini CLI, Cursor, Grok, Codex CLI and GitHub Copilot: whole pack or a single skill, project or personal, and how the gates stay attached in each tool.

Quick start (Claude Code plugin):

```text
/plugin marketplace add kryptophonik/claude-sre
/plugin install sre@claude-sre
```

Plugin skills are namespaced, for example `/sre:sre-incident-command`.

## What's inside

- **Skills:** `.claude/skills/<name>/SKILL.md`, the single source of truth. Routing, install profiles and the placeholder vocabulary are in [SKILLS.md](SKILLS.md).
- **Scripts and references:** inside each skill (`scripts/`, `references/`, `assets/`). Every script is read-only, requires an explicit target (context, profile, subscription, project), and caps its output.
- **Read-only MCP setup:** [sre-safety-gates/references/mcp.md](.claude/skills/sre-safety-gates/references/mcp.md). No `.mcp.json` is shipped, because enabled plugins start their MCP servers in every session.
- **Opt-in guardrails:** the Terraform guard hook and settings example (`sre-terraform/hooks`, `sre-terraform/assets`) and the Kubernetes deny rules (`sre-k8s-triage/references`). None are enabled automatically.
- **Generated per-tool files:** `.claude-plugin/`, `gemini-extension.json`, `GEMINI.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.cursor/rules/`, and the `skills/` mirror. They're produced by `python3 scripts/build-targets.py`, and CI fails if they're stale. Don't edit them by hand.

## Validate locally

```bash
python3 scripts/build-targets.py --check
python3 scripts/validate.py          # needs PyYAML
find .claude -name '*.sh' -exec bash -n {} \; && shellcheck -S warning $(find .claude -name '*.sh')
.claude/skills/sre-pagerduty-opsgenie/scripts/tests/run_tests.sh
```

## Project files

[CHANGELOG.md](CHANGELOG.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [LICENSE](LICENSE) (MIT)

The pack version is set once in `scripts/build-targets.py` (`PACK["version"]`) and written to the plugin and extension manifests.

# Install

Pick your tool:

| Tool | Guide | Native format used |
|---|---|---|
| Claude Code | [docs/install/claude-code.md](docs/install/claude-code.md) | Project skills, or a plugin with a marketplace |
| Gemini CLI | [docs/install/gemini-cli.md](docs/install/gemini-cli.md) | Extension (`gemini-extension.json` + `GEMINI.md` + `skills/`) |
| Cursor | [docs/install/cursor.md](docs/install/cursor.md) | Agent Skills + an always-on `.cursor/rules` rule |
| Grok | [docs/install/grok.md](docs/install/grok.md) | Reads Claude Code skills and plugins, plus `AGENTS.md` |
| Codex CLI | [docs/install/codex.md](docs/install/codex.md) | `.agents/skills` + `AGENTS.md` |
| GitHub Copilot | [docs/install/copilot.md](docs/install/copilot.md) | Agent Skills + `.github/copilot-instructions.md` |

Every guide covers the whole pack vs. a single skill, project vs. personal install, a verify step, and how the approval gates stay attached. Copy-based installs start from a clone: `git clone https://github.com/kryptophonik/claude-sre.git`, then run the commands from the folder that contains `claude-sre/`.

**Single-skill installs:** always copy `sre-safety-gates` too. Some skills depend on others (see "Install profiles" in [SKILLS.md](SKILLS.md)). For example, `sre-oncall-audit` uses the `sre-pagerduty-opsgenie` scripts, and `sre-slo-burn-rate-rules` uses the `sre-prometheus-grafana` generator. `gh skill install` installs only the skill you name, so run it for `sre-safety-gates` as well.

**Next:** [getting started](docs/getting-started.md): your first run, example prompts, and troubleshooting.

# Claude Code

Docs (checked 2026-10-16): skills https://code.claude.com/docs/en/skills · plugins https://code.claude.com/docs/en/plugins-reference · marketplaces https://code.claude.com/docs/en/plugin-marketplaces

## Whole pack as a plugin (recommended)

```text
/plugin marketplace add kryptophonik/claude-sre
/plugin install sre@claude-sre
```

Or from your shell: `claude plugin marketplace add kryptophonik/claude-sre`, then `claude plugin install sre@claude-sre`. The plugin loads the generated `skills/` mirror. Skills are namespaced (`/sre:sre-incident-command`), so they can't collide with your own. Install scope is user by default; pass `--scope project` to record it in the project settings.

## Whole pack as project skills

Commit the folder into your repo: `cp -r claude-sre/.claude/skills/sre-* <your-repo>/.claude/skills/`. Project skills also load in cloud sessions. Note that skill names aren't namespaced here, and a personal skill with the same name overrides a project one. Check for collisions with `/skills`.

## Personal install

`cp -r claude-sre/.claude/skills/sre-* ~/.claude/skills/`. Personal skills override project skills with the same name.

## Single skill

Copy `sre-safety-gates` plus the skill you want, plus anything it lists under "Requires" in [SKILLS.md](../../SKILLS.md). For example: `cp -r .claude/skills/{sre-safety-gates,sre-aws} ~/.claude/skills/`.

## How the gates stay attached

- `sre-safety-gates` ships in every install path, and every `SKILL.md` starts with an inline four-line gate block.
- `sre-chaos-engineering` and `sre-k8s-safe-remediation` set `disable-model-invocation: true`, so only you can start them.
- No skill sets `allowed-tools`, so nothing is pre-approved.
- Optional hard guardrails (hooks and permissions run outside the model): merge `.claude/skills/sre-terraform/assets/settings.example.json` and `.claude/skills/sre-k8s-triage/references/claude-settings-k8s-deny.json` into `.claude/settings.json`.
- No `.mcp.json` is shipped. Configure MCP servers read-only per [mcp.md](../../.claude/skills/sre-safety-gates/references/mcp.md).

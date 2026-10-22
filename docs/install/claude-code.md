# Claude Code

Docs (checked 2026-10-17): skills https://code.claude.com/docs/en/skills · plugins https://code.claude.com/docs/en/plugins-reference · marketplaces https://code.claude.com/docs/en/plugin-marketplaces

## Whole pack as a plugin (recommended)

No clone needed. Inside Claude Code:

```text
/plugin marketplace add kryptophonik/SRE-Skills
/plugin install sre@claude-sre
```

Or from your shell: `claude plugin marketplace add kryptophonik/SRE-Skills`, then `claude plugin install sre@claude-sre`. The plugin loads the generated `skills/` mirror. Install scope is user by default; pass `--scope project` to record it in the project settings.

**Plugin skills are namespaced.** Type `/sre:sre-incident-command`, not `/sre-incident-command`. The two manual-only skills are `/sre:sre-k8s-safe-remediation` and `/sre:sre-chaos-engineering`.

Verify:

```bash
claude plugin list                  # sre@claude-sre, enabled, with the version from CHANGELOG.md
claude plugin details sre@claude-sre   # lists every sre-* skill
```

Then start a new session and send a test prompt such as "pods in namespace payments are crashlooping since the last deploy". It should load `sre-k8s-triage`, and its first reply should contain only read-only commands.

## Before you start

Every copy command below runs from the folder that contains your clone, so clone once:

```bash
git clone https://github.com/kryptophonik/SRE-Skills.git
```

Then `cd` to the folder that holds `SRE-Skills/`. Replace `<your-repo>` with the path to the repository you want the skills in.

## Whole pack as project skills

```bash
mkdir -p <your-repo>/.claude/skills
cp -r SRE-Skills/.claude/skills/sre-* <your-repo>/.claude/skills/
```

Commit the folder. Project skills also load in cloud sessions. Names aren't namespaced here (`/sre-k8s-safe-remediation`), and a personal skill with the same name overrides a project one, so check for collisions with `/skills`.

## Personal install

```bash
mkdir -p ~/.claude/skills
cp -r SRE-Skills/.claude/skills/sre-* ~/.claude/skills/
```

Personal skills override project skills with the same name.

## Single skill

Always copy `sre-safety-gates` with it. For example, for `sre-aws`:

```bash
mkdir -p ~/.claude/skills
cp -r SRE-Skills/.claude/skills/sre-safety-gates SRE-Skills/.claude/skills/sre-aws ~/.claude/skills/
```

Some skills need another skill's scripts: `sre-oncall-audit` and `sre-oncall-handoff` need `sre-pagerduty-opsgenie`, `sre-slo-burn-rate-rules` needs `sre-prometheus-grafana`, and `sre-k8s-safe-remediation` needs `sre-k8s-triage`. The full list is under "Install profiles" in [SKILLS.md](../../SKILLS.md).

Verify a copy install: `ls ~/.claude/skills | grep '^sre-'` (or the project path) should list `sre-safety-gates` and every skill you copied. In a session, `/skills` lists them.

## How the gates stay attached

- `sre-safety-gates` ships in every install path, and every `SKILL.md` starts with an inline four-line gate block.
- `sre-chaos-engineering` and `sre-k8s-safe-remediation` set `disable-model-invocation: true`, so only you can start them.
- No skill sets `allowed-tools`, so nothing is pre-approved.
- Optional hard guardrails (hooks and permissions run outside the model): merge `.claude/skills/sre-terraform/assets/settings.example.json` and `.claude/skills/sre-k8s-triage/references/claude-settings-k8s-deny.json` into `.claude/settings.json`.
- No `.mcp.json` is shipped. Configure MCP servers read-only per [mcp.md](../../.claude/skills/sre-safety-gates/references/mcp.md).

## Upgrading

For a copy install, follow [upgrading.md](upgrading.md): 3.1.0 removes two skills, and their old folders must be deleted.

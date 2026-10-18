# Grok (Grok Build CLI)

Docs (checked 2026-10-17): https://docs.x.ai/build/features/skills-plugins-marketplaces · https://docs.x.ai/build/features/project-rules · https://docs.x.ai/build/cli/reference

You need the Grok Build CLI (`grok`) installed and signed in; see the CLI reference above. Grok discovers skills in `./.grok/skills/` (walked up to the repo root), `~/.grok/skills/`, `~/.agents/skills/` and enabled plugins. It reads Claude Code marketplaces, plugins, skills and instruction files natively, plus `AGENTS.md`. It honours `user-invocable` and `disable-model-invocation`. Note that Grok's `allowed-tools` neither grants nor restricts anything.

## Whole pack as a plugin

```bash
grok plugin marketplace add kryptophonik/claude-sre
grok plugin install sre@claude-sre
```

You can also install `sre` from the Marketplace tab in the TUI. If you already added the marketplace in Claude Code, Grok reads it automatically. To try it without installing, run `grok --plugin-dir <path-to-clone>`. **A plugin install ships no `AGENTS.md`,** so with a plugin alone, the inline gate block in each skill is what applies.

## Before you start

Every copy command below runs from the folder that contains your clone, so clone once:

```bash
git clone https://github.com/kryptophonik/claude-sre.git
```

Then `cd` to the folder that holds `claude-sre/`. Replace `<your-repo>` with the path to the repository you want the skills in.

## Whole pack as project skills

```bash
mkdir -p <your-repo>/.claude/skills
cp -r claude-sre/.claude/skills/sre-* <your-repo>/.claude/skills/
```

Grok reads `.claude/skills` through Claude compatibility; `.grok/skills/` works too. For the always-on gate rules:

`AGENTS.md` carries the always-on gate rules. Append it rather than copying over it, so an existing `AGENTS.md` isn't overwritten (run this once):

```bash
cat claude-sre/AGENTS.md >> <your-repo>/AGENTS.md
```

## Personal

```bash
mkdir -p ~/.grok/skills
cp -r claude-sre/.claude/skills/sre-* ~/.grok/skills/
```

## Single skill

```bash
mkdir -p ~/.grok/skills
cp -r claude-sre/.claude/skills/sre-safety-gates claude-sre/.claude/skills/<skill> ~/.grok/skills/
```

Some skills need another skill's scripts: `sre-oncall-audit` and `sre-oncall-handoff` need `sre-pagerduty-opsgenie`, `sre-slo-burn-rate-rules` needs `sre-prometheus-grafana`, and `sre-k8s-safe-remediation` needs `sre-k8s-triage`. The full list is under "Install profiles" in [SKILLS.md](../../SKILLS.md).

## Verify

Run `grok inspect` in the project. It should list the `sre-*` skills (or the `sre` plugin) and, for a project install, `AGENTS.md`. Then start a new session and send a test prompt such as "pods in namespace payments are crashlooping since the last deploy". It should load `sre-k8s-triage`, and its first reply should contain only read-only commands.

## How the gates stay attached

- **`user-invocable: false` hides a skill from you and from the model in Grok.** That affects `sre-safety-gates` and `sre-remediation-actions`, which never appear in Grok's skill list. Skills that need them still reach them through relative links, and each skill keeps its own inline gate block, so the gates still apply. For the full rules always in context, use a project install with `AGENTS.md`.
- `AGENTS.md` (and `.claude/rules`/`CLAUDE.md` if you add them) loads into every session in the repo.
- Every skill carries its own inline gate block.
- Manual-only skills stay manual (`disable-model-invocation`).
- Keep Grok's tool-approval prompts on as the hard control. Don't rely on `allowed-tools`, which doesn't restrict anything in Grok. The opt-in Terraform guard hook can be installed as a Grok hook (`.grok/hooks/`, needs `/hooks-trust`).

# Grok (Grok Build CLI)

Docs (checked 2026-10-16): https://docs.x.ai/build/features/skills-plugins-marketplaces · https://docs.x.ai/build/features/project-rules · https://docs.x.ai/build/cli/reference

Grok discovers skills in `./.grok/skills/` (walked up to the repo root), `~/.grok/skills/`, `~/.agents/skills/` and enabled plugins. It reads Claude Code marketplaces, plugins, skills and instruction files natively, plus `AGENTS.md`. It honours `user-invocable` and `disable-model-invocation`. Note that Grok's `allowed-tools` neither grants nor restricts anything.

## Whole pack

- **As a plugin:** run `grok plugin marketplace add kryptophonik/claude-sre`, then install `sre` from the TUI Marketplace tab or with `grok plugin install`. If you already added the marketplace in Claude Code, Grok reads it automatically. To try it without installing, run `grok --plugin-dir <path-to-clone>`. **A plugin install ships no `AGENTS.md`,** so the always-on gate text exists only in project installs. With a plugin alone, the inline gate block in each skill is what applies.
- **As project skills:** commit `.claude/skills/sre-*` (Grok reads `.claude/skills` through Claude compatibility) or copy them to `.grok/skills/`.

## Personal

Copy `.claude/skills/sre-*` to `~/.grok/skills/` (or `~/.agents/skills/`).

## Single skill

Copy `sre-safety-gates` plus the skill (and anything it requires).

## How the gates stay attached

- **`user-invocable: false` hides a skill from you and from the model in Grok.** That affects `sre-safety-gates` and `sre-remediation-actions`, which never appear in Grok's skill list. Skills that need them still reach them through relative links, and each skill keeps its own inline gate block, so the gates still apply. For the full rules always in context, use a project install with `AGENTS.md`.
- `AGENTS.md` (and `.claude/rules`/`CLAUDE.md` if you add them) loads into every session in the repo. Run `grok inspect` to confirm it's listed.
- Every skill carries its own inline gate block.
- Manual-only skills stay manual (`disable-model-invocation`).
- Keep Grok's tool-approval prompts on as the hard control. Don't rely on `allowed-tools`, which doesn't restrict anything in Grok. The opt-in Terraform guard hook can be installed as a Grok hook (`.grok/hooks/`, needs `/hooks-trust`).

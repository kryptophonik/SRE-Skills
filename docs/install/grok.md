# Grok (Grok Build CLI)

Docs (checked 2026-10-16): https://docs.x.ai/build/features/skills-plugins-marketplaces · https://docs.x.ai/build/features/project-rules · https://docs.x.ai/build/cli/reference

Grok discovers skills in `./.grok/skills/` (walked up to the repo root), `~/.grok/skills/`, `~/.agents/skills/` and enabled plugins. It reads Claude Code marketplaces, plugins, skills and instruction files natively, plus `AGENTS.md`. It honours `user-invocable` and `disable-model-invocation`. Note that Grok's `allowed-tools` neither grants nor restricts anything.

## Whole pack

- **As a plugin:** add this repo as a marketplace source (`[[marketplace.sources]]` in `~/.grok/config.toml`), then install `sre` from the TUI Marketplace tab. If you already added it in Claude Code, Grok reads that marketplace automatically. To try it without installing, run `grok --plugin-dir <path-to-clone>`.
- **As project skills:** commit `.claude/skills/sre-*` (Grok reads `.claude/skills` through Claude compatibility) or copy them to `.grok/skills/`.

## Personal

Copy `.claude/skills/sre-*` to `~/.grok/skills/` (or `~/.agents/skills/`).

## Single skill

Copy `sre-safety-gates` plus the skill (and anything it requires).

## How the gates stay attached

- `AGENTS.md` (and `.claude/rules`/`CLAUDE.md` if you add them) loads into every session in the repo. Run `grok inspect` to confirm it's listed.
- Every skill carries its own inline gate block.
- Manual-only skills stay manual (`disable-model-invocation`).
- Keep Grok's tool-approval prompts on as the hard control. Don't rely on `allowed-tools`, which doesn't restrict anything in Grok. The opt-in Terraform guard hook can be installed as a Grok hook (`.grok/hooks/`, needs `/hooks-trust`).

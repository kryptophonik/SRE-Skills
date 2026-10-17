# Cursor

Docs (checked 2026-10-16): skills https://cursor.com/docs/skills and https://cursor.com/help/customization/skills · rules https://cursor.com/docs/rules

Cursor discovers skills in `.cursor/skills/`, `.agents/skills/`, `~/.cursor/skills/` and `~/.agents/skills/`. For compatibility it also reads `.claude/skills/` and `~/.claude/skills/`. Project rules are `.mdc` files in `.cursor/rules/`, and `alwaysApply: true` puts a rule in every chat.

## Whole pack, project

Copy `.claude/skills/sre-*` and `.cursor/rules/sre-safety-gates.mdc` into your repo, keeping the same paths. Cursor reads `.claude/skills` directly, so no conversion is needed.

## Personal

Copy `.claude/skills/sre-*` to `~/.cursor/skills/` (or `~/.claude/skills/`). Add the gate text from `.cursor/rules/sre-safety-gates.mdc` as a User Rule (Customize → Rules), because user-level `.mdc` files aren't documented.

## Single skill

Copy `sre-safety-gates` plus the skill (and anything it requires) into `.cursor/skills/` or `.claude/skills/`.

## How the gates stay attached

- `.cursor/rules/sre-safety-gates.mdc` is `alwaysApply: true`, so the gates are in context for every chat in the project.
- `AGENTS.md` at the repo root repeats the gates. Cursor reads it too.
- Every skill carries its own inline gate block.
- `disable-model-invocation: true` (chaos, k8s safe remediation) is honoured by Cursor: those skills run only via `/skill-name`.

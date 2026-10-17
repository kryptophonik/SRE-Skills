# Gemini CLI

Docs (checked 2026-10-16): extensions reference https://geminicli.com/docs/extensions/reference/. Gemini CLI loads extensions from `~/.gemini/extensions`. Each extension needs `gemini-extension.json` at its root, and it bundles skills from `skills/<name>/SKILL.md` and context from `contextFileName`.

> The Gemini CLI docs say that for unpaid-tier and Google One users, Gemini CLI was replaced by Antigravity CLI on 2026-06-18. These steps apply wherever `gemini extensions` is available.

## Whole pack (extension)

```bash
gemini extensions install https://github.com/kryptophonik/claude-sre --ref <tag>
```

This installs the repo root as the extension: the generated `gemini-extension.json`, `GEMINI.md` (gates plus skill index) and `skills/`. Update it with `gemini extensions update sre`. Disable it for one workspace with `gemini extensions disable sre --scope workspace`.

## Project vs. personal

Extensions install for the user and are enabled globally. To scope one to a project, disable it at user scope and enable it with `--scope workspace` in that project. For a link-style dev install, use `gemini extensions link <path-to-clone>`.

## Single skill

Gemini CLI loads extensions as a whole. For one skill, fork the repo, delete the other `skills/<name>` folders but keep `sre-safety-gates`, and install your fork. Or use `gh skill install kryptophonik/claude-sre <skill> --agent gemini-cli` (GitHub CLI, see `gh skill install --help`).

## How the gates stay attached

- `GEMINI.md` is the extension context file, so the gate rules load in every session while the extension is enabled.
- Each skill carries its own inline gate block.
- Extensions can't auto-approve tools: Gemini CLI ignores `allow` decisions in extension policies, so writes still prompt.
- No MCP servers are declared in `gemini-extension.json`. Add read-only servers yourself per [mcp.md](../../.claude/skills/sre-safety-gates/references/mcp.md).

# Gemini CLI

Docs (checked 2026-10-16): extensions reference https://geminicli.com/docs/extensions/reference/. Gemini CLI loads extensions from `~/.gemini/extensions`. Each extension needs `gemini-extension.json` at its root, and it bundles skills from `skills/<name>/SKILL.md` and context from `contextFileName`.

> The Gemini CLI docs say that for unpaid-tier and Google One users, Gemini CLI was replaced by Antigravity CLI on 2026-06-18. These steps apply wherever `gemini extensions` is available.

## Whole pack (extension)

```bash
gemini extensions install https://github.com/kryptophonik/claude-sre --ref v3.0.0
```

The `v3.0.0` tag is created at release. Until then, omit `--ref` to install the default branch.

This installs the repo root as the extension: the generated `gemini-extension.json`, `GEMINI.md` (gates plus skill index) and `skills/`. Update it with `gemini extensions update sre`. Disable it for one workspace with `gemini extensions disable sre --scope workspace`.

## Project vs. personal

Extensions install for the user and are enabled globally. To scope one to a project, disable it at user scope and enable it with `--scope workspace` in that project. For a link-style dev install, use `gemini extensions link <path-to-clone>`.

## Single skill

Extensions load as a whole. For one skill, use Gemini's own skills command (https://geminicli.com/docs/cli/skills/), and install `sre-safety-gates` too:

```bash
gemini skills install https://github.com/kryptophonik/claude-sre.git --path skills/sre-safety-gates
gemini skills install https://github.com/kryptophonik/claude-sre.git --path skills/<skill> [--scope workspace]
```

`--scope` is `user` (the default) or `workspace`.

## How the gates stay attached

- `GEMINI.md` is the extension context file, so the gate rules load in every session while the extension is enabled.
- Each skill carries its own inline gate block.
- **Manual-only skills aren't enforced.** The Gemini skills docs don't mention `disable-model-invocation`, so `sre-chaos-engineering` and `sre-k8s-safe-remediation` can be activated by the model. However, every skill activation shows a consent prompt (name, purpose, directory) that you must approve. Decline it unless you started the skill yourself, and their text gates still require approval for each change.
- Extensions can't auto-approve tools: Gemini CLI ignores `allow` decisions in extension policies, so writes still prompt.
- No MCP servers are declared in `gemini-extension.json`. Add read-only servers yourself per [mcp.md](../../.claude/skills/sre-safety-gates/references/mcp.md).

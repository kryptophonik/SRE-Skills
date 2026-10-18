# Gemini CLI

Docs (checked 2026-10-17): extensions reference https://geminicli.com/docs/extensions/reference/ · skills https://geminicli.com/docs/cli/skills/. Gemini CLI loads extensions from `~/.gemini/extensions`. Each extension needs `gemini-extension.json` at its root, and it bundles skills from `skills/<name>/SKILL.md` and context from `contextFileName`.

> The Gemini CLI docs say that for unpaid-tier and Google One users, Gemini CLI was replaced by Antigravity CLI on 2026-06-18. These steps apply wherever `gemini extensions` is available.

## Whole pack (extension)

No clone needed:

```bash
gemini extensions install https://github.com/kryptophonik/claude-sre
```

Don't pass `--ref <tag>`: a pinned ref stays on that release, and `gemini extensions update sre` then reports "already up to date". Without `--ref` you get the default branch, and `update` moves you to the latest release. Add `--auto-update` to update automatically.

The install asks up to two questions:

1. **Trust the current folder.** Gemini asks whether to trust the workspace you ran the command from. Run it from your home folder or a project you already trust.
2. **Extension consent.** It prints every skill name and description (about 115 lines) and asks you to confirm. Pass `--consent` to skip this screen in scripts, once you've read it.

Without a terminal (for example in CI) an unanswered prompt waits forever, so use `--consent` there.

This installs the repo root as the extension: the generated `gemini-extension.json`, `GEMINI.md` (gates plus skill index) and `skills/`. Update with `gemini extensions update sre`. Disable it for one workspace with `gemini extensions disable sre --scope workspace`.

Verify:

```bash
gemini extensions list    # shows sre with the version from CHANGELOG.md
```

Then start a new session and send a test prompt such as "pods in namespace payments are crashlooping since the last deploy". It should load `sre-k8s-triage`, and its first reply should contain only read-only commands.

## Project vs. personal

Extensions install for the user and are enabled globally. To scope one to a project, disable it at user scope and enable it with `--scope workspace` in that project. For a link-style dev install, use `gemini extensions link <path-to-clone>`.

## Single skill

Extensions load as a whole. For one skill, use Gemini's own skills command and always install `sre-safety-gates` first:

```bash
gemini skills install https://github.com/kryptophonik/claude-sre.git --path skills/sre-safety-gates
gemini skills install https://github.com/kryptophonik/claude-sre.git --path skills/<skill>
```

Add `--scope workspace` for a project install (the default is `user`), and `--consent` to skip the confirmation prompt. Verify with `gemini skills list`. Some skills need another skill's scripts: `sre-oncall-audit` and `sre-oncall-handoff` need `sre-pagerduty-opsgenie`, `sre-slo-burn-rate-rules` needs `sre-prometheus-grafana`, and `sre-k8s-safe-remediation` needs `sre-k8s-triage`. The full list is under "Install profiles" in [SKILLS.md](../../SKILLS.md).

## How the gates stay attached

- `GEMINI.md` is the extension context file, so the gate rules load in every session while the extension is enabled.
- Each skill carries its own inline gate block.
- **Manual-only skills aren't enforced.** The Gemini skills docs don't mention `disable-model-invocation`, so `sre-chaos-engineering` and `sre-k8s-safe-remediation` can be activated by the model. However, every skill activation shows a consent prompt (name, purpose, directory) that you must approve. Decline it unless you started the skill yourself, and their text gates still require approval for each change.
- Extensions can't auto-approve tools: Gemini CLI ignores `allow` decisions in extension policies, so writes still prompt.
- No MCP servers are declared in `gemini-extension.json`. Add read-only servers yourself per [mcp.md](../../.claude/skills/sre-safety-gates/references/mcp.md).

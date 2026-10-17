# OpenAI Codex CLI

Docs (checked 2026-10-16): skills https://learn.chatgpt.com/docs/build-skills.md · AGENTS.md https://learn.chatgpt.com/docs/agent-configuration/agents-md · customization https://learn.chatgpt.com/docs/customization/overview

Codex reads repo skills from `.agents/skills` in each directory from the working directory up to the repo root, and user skills from `~/.agents/skills`. It reads `AGENTS.md` from the repo root down to the working directory, plus `~/.codex/AGENTS.md`. The default combined limit is 32 KiB.

## Whole pack, project

```bash
mkdir -p <your-repo>/.agents/skills
cp -r claude-sre/skills/sre-* <your-repo>/.agents/skills/
cp claude-sre/AGENTS.md <your-repo>/AGENTS.md     # or append its gate section to your existing AGENTS.md
```

## Personal

`cp -r claude-sre/skills/sre-* ~/.agents/skills/`, then add the gate section of `AGENTS.md` to `~/.codex/AGENTS.md`.

## Single skill

Copy `sre-safety-gates` plus the skill (and anything it requires), or run `gh skill install kryptophonik/claude-sre <skill> --agent codex`.

## How the gates stay attached

- `AGENTS.md` carries the gate rules and loads before any work.
- Every skill carries its own inline gate block.
- Codex doesn't document `disable-model-invocation`, so the manual-only skills (`sre-chaos-engineering`, `sre-k8s-safe-remediation`) may be picked implicitly. Their text still requires explicit approval. To keep them manual, leave them out of `.agents/skills`, or invoke them only with `$skill-name`.
- Use Codex's sandbox and approval modes (keep approvals on) as the hard control.

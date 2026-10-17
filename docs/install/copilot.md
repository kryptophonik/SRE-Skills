# GitHub Copilot

Docs (checked 2026-10-16): agent skills https://docs.github.com/en/copilot/concepts/agents/about-agent-skills · creating skills https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-skills · repository instructions https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions

Copilot reads project skills from `.github/skills`, `.claude/skills` or `.agents/skills`, and personal skills from `~/.copilot/skills` or `~/.agents/skills`. Skills work in the cloud agent, code review, Copilot CLI and agent mode in VS Code and JetBrains. Repository-wide instructions go in `.github/copilot-instructions.md`, and `AGENTS.md` is also read.

## Whole pack, project

Copy `.claude/skills/sre-*` (Copilot reads `.claude/skills` directly) and `.github/copilot-instructions.md` into your repo. If you already have a `copilot-instructions.md`, append the gate section.

## Personal

`cp -r claude-sre/skills/sre-* ~/.copilot/skills/`, or `gh skill install kryptophonik/claude-sre <skill> --scope user`.

## Single skill

Copy `sre-safety-gates` plus the skill (and anything it requires), or run `gh skill install kryptophonik/claude-sre <skill>`.

## How the gates stay attached

- `.github/copilot-instructions.md` and `AGENTS.md` carry the gate rules on every request in the repo.
- Every skill carries its own inline gate block.
- No skill sets `allowed-tools`, so Copilot prompts before running tools. Don't add `allowed-tools` to these skills.
- Manual-only behaviour (`disable-model-invocation`) isn't documented for Copilot, so the chaos and k8s remediation skills rely on their text gates. Leave them out if you need them strictly manual.

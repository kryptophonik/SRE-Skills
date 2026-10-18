# GitHub Copilot

Docs (checked 2026-10-16): agent skills https://docs.github.com/en/copilot/concepts/agents/about-agent-skills · creating skills https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-skills · repository instructions https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions

Copilot reads project skills from `.github/skills`, `.claude/skills` or `.agents/skills`, and personal skills from `~/.copilot/skills` or `~/.agents/skills`. Skills work in the cloud agent, code review, Copilot CLI and agent mode in VS Code and JetBrains. Repository-wide instructions go in `.github/copilot-instructions.md`, and `AGENTS.md` is also read.

## Before you start

Every copy command below runs from the folder that contains your clone, so clone once:

```bash
git clone https://github.com/kryptophonik/claude-sre.git
```

Then `cd` to the folder that holds `claude-sre/`. Replace `<your-repo>` with the path to the repository you want the skills in.

## Whole pack, project

```bash
mkdir -p <your-repo>/.claude/skills <your-repo>/.github
cp -r claude-sre/.claude/skills/sre-* <your-repo>/.claude/skills/
cat claude-sre/.github/copilot-instructions.md >> <your-repo>/.github/copilot-instructions.md   # appends (run once)
```

Optionally, add `AGENTS.md` too:

`AGENTS.md` carries the always-on gate rules. Append it rather than copying over it, so an existing `AGENTS.md` isn't overwritten (run this once):

```bash
cat claude-sre/AGENTS.md >> <your-repo>/AGENTS.md
```

## Personal

```bash
mkdir -p ~/.copilot/skills
cp -r claude-sre/skills/sre-* ~/.copilot/skills/
```

## Single skill

`gh skill install` installs only the skill you name, so run it for `sre-safety-gates` too (add `--scope user` for a personal install):

```bash
gh skill install kryptophonik/claude-sre sre-safety-gates
gh skill install kryptophonik/claude-sre <skill>
```

Some skills need another skill's scripts: `sre-oncall-audit` and `sre-oncall-handoff` need `sre-pagerduty-opsgenie`, `sre-slo-burn-rate-rules` needs `sre-prometheus-grafana`, and `sre-k8s-safe-remediation` needs `sre-k8s-triage`. The full list is under "Install profiles" in [SKILLS.md](../../SKILLS.md).

## Verify

`ls <your-repo>/.claude/skills | grep '^sre-'` (or `~/.copilot/skills`) lists the skills, and `<your-repo>/.github/copilot-instructions.md` contains the gate section. Then start a new session and send a test prompt such as "pods in namespace payments are crashlooping since the last deploy". It should load `sre-k8s-triage`, and its first reply should contain only read-only commands.

## How the gates stay attached

- `.github/copilot-instructions.md` carries the gate rules on every request in the repo, and so does `AGENTS.md` if you appended it.
- Every skill carries its own inline gate block.
- No skill sets `allowed-tools`, so Copilot prompts before running tools. Don't add `allowed-tools` to these skills.
- Manual-only behaviour (`disable-model-invocation`) isn't documented for Copilot, so the chaos and k8s remediation skills rely on their text gates. Leave them out if you need them strictly manual.

## Upgrading

For a copy install, follow [upgrading.md](upgrading.md): 3.1.0 removes two skills, and their old folders must be deleted.

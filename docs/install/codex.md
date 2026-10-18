# OpenAI Codex CLI

Docs (checked 2026-10-16): skills https://learn.chatgpt.com/docs/build-skills.md · AGENTS.md https://learn.chatgpt.com/docs/agent-configuration/agents-md · customization https://learn.chatgpt.com/docs/customization/overview

Codex reads repo skills from `.agents/skills` in each directory from the working directory up to the repo root, and user skills from `~/.agents/skills`. It reads `AGENTS.md` from the repo root down to the working directory, plus `~/.codex/AGENTS.md`. The default combined limit is 32 KiB.

## Before you start

Every copy command below runs from the folder that contains your clone, so clone once:

```bash
git clone https://github.com/kryptophonik/claude-sre.git
```

Then `cd` to the folder that holds `claude-sre/`. Replace `<your-repo>` with the path to the repository you want the skills in.

## Whole pack, project

```bash
mkdir -p <your-repo>/.agents/skills
cp -r claude-sre/skills/sre-* <your-repo>/.agents/skills/
cat claude-sre/AGENTS.md >> <your-repo>/AGENTS.md    # appends; never overwrites your AGENTS.md (run once)
```

## Personal

```bash
mkdir -p ~/.agents/skills ~/.codex
cp -r claude-sre/skills/sre-* ~/.agents/skills/
cat claude-sre/AGENTS.md >> ~/.codex/AGENTS.md       # run once
```

## Single skill

Copy `sre-safety-gates` with the skill:

```bash
mkdir -p <your-repo>/.agents/skills
cp -r claude-sre/skills/sre-safety-gates claude-sre/skills/<skill> <your-repo>/.agents/skills/
```

Or use `gh skill install`, which installs only the skill you name, so run it for `sre-safety-gates` too:

```bash
gh skill install kryptophonik/claude-sre sre-safety-gates --agent codex
gh skill install kryptophonik/claude-sre <skill> --agent codex
```

Some skills need another skill's scripts: `sre-oncall-audit` and `sre-oncall-handoff` need `sre-pagerduty-opsgenie`, `sre-slo-burn-rate-rules` needs `sre-prometheus-grafana`, and `sre-k8s-safe-remediation` needs `sre-k8s-triage`. The full list is under "Install profiles" in [SKILLS.md](../../SKILLS.md).

## Verify

`ls <your-repo>/.agents/skills | grep '^sre-'` lists the skills, and `grep -c 'Safety gates' <your-repo>/AGENTS.md` prints at least 1. Then start a new session and send a test prompt such as "pods in namespace payments are crashlooping since the last deploy". It should load `sre-k8s-triage`, and its first reply should contain only read-only commands.

## How the gates stay attached

- `AGENTS.md` carries the gate rules and loads before any work.
- Every skill carries its own inline gate block.
- Manual-only skills stay manual. `sre-chaos-engineering` and `sre-k8s-safe-remediation` ship `agents/openai.yaml` with `policy.allow_implicit_invocation: false`, generated from `disable-model-invocation: true`, so Codex runs them only when you name them (`$sre-chaos-engineering`, `$sre-k8s-safe-remediation`). Copy the whole skill folder, including `agents/`.
- Use Codex's sandbox and approval modes (keep approvals on) as the hard control.

## Upgrading

For a copy install, follow [upgrading.md](upgrading.md): 3.1.0 removes two skills, and their old folders must be deleted.

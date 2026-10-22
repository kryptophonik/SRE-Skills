# Cursor

Docs (checked 2026-10-16): skills https://cursor.com/docs/skills and https://cursor.com/help/customization/skills · rules https://cursor.com/docs/rules

Cursor discovers skills in `.cursor/skills/`, `.agents/skills/`, `~/.cursor/skills/` and `~/.agents/skills/`. For compatibility it also reads `.claude/skills/` and `~/.claude/skills/`. Project rules are `.mdc` files in `.cursor/rules/`, and `alwaysApply: true` puts a rule in every chat.

## Before you start

Every copy command below runs from the folder that contains your clone, so clone once:

```bash
git clone https://github.com/kryptophonik/SRE-Skills.git
```

Then `cd` to the folder that holds `SRE-Skills/`. Replace `<your-repo>` with the path to the repository you want the skills in.

## Whole pack, project

```bash
mkdir -p <your-repo>/.claude/skills <your-repo>/.cursor/rules
cp -r SRE-Skills/.claude/skills/sre-* <your-repo>/.claude/skills/
cp SRE-Skills/.cursor/rules/sre-safety-gates.mdc <your-repo>/.cursor/rules/
```

Cursor reads `.claude/skills` directly, so no conversion is needed. Optionally, add `AGENTS.md` too, which other tools in the same repo also read:

`AGENTS.md` carries the always-on gate rules. Append it rather than copying over it, so an existing `AGENTS.md` isn't overwritten (run this once):

```bash
cat SRE-Skills/AGENTS.md >> <your-repo>/AGENTS.md
```

## Personal

```bash
mkdir -p ~/.cursor/skills
cp -r SRE-Skills/.claude/skills/sre-* ~/.cursor/skills/
```

Then add the gate text from `SRE-Skills/.cursor/rules/sre-safety-gates.mdc` as a User Rule in Cursor's settings, because user-level `.mdc` files aren't documented.

## Single skill

```bash
mkdir -p <your-repo>/.claude/skills
cp -r SRE-Skills/.claude/skills/sre-safety-gates SRE-Skills/.claude/skills/<skill> <your-repo>/.claude/skills/
```

Some skills need another skill's scripts: `sre-oncall-audit` and `sre-oncall-handoff` need `sre-pagerduty-opsgenie`, `sre-slo-burn-rate-rules` needs `sre-prometheus-grafana`, and `sre-k8s-safe-remediation` needs `sre-k8s-triage`. The full list is under "Install profiles" in [SKILLS.md](../../SKILLS.md).

## Verify

`ls <your-repo>/.claude/skills | grep '^sre-'` (or `~/.cursor/skills`) lists the skills, and `<your-repo>/.cursor/rules/sre-safety-gates.mdc` exists. Then start a new session and send a test prompt such as "pods in namespace payments on kube context <ctx> are crashlooping since the last deploy" (use a real context name). It should load `sre-k8s-triage`, and its first reply should contain only read-only commands.

## How the gates stay attached

- `.cursor/rules/sre-safety-gates.mdc` is `alwaysApply: true`, so the gates are in context for every chat in the project.
- If you appended `AGENTS.md`, it repeats the gates, and Cursor reads it too.
- Every skill carries its own inline gate block.
- `disable-model-invocation: true` (chaos, k8s safe remediation) is honoured by Cursor: those skills run only via `/sre-chaos-engineering` and `/sre-k8s-safe-remediation`.

## Upgrading

For a copy install, follow [upgrading.md](upgrading.md): 3.1.0 removes two skills, and their old folders must be deleted.

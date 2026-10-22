# Getting started

This page is for an on-call engineer who has installed the pack (or is about to) and wants to know what to do next. It covers what to set up, a first run from start to finish, prompts to copy, the scripts you can run yourself, and what to do when something doesn't work.

## What the pack is

The pack is 37 SRE skills: plain Markdown playbooks (`SKILL.md` folders) that your AI coding tool loads when a task matches. Each skill tells the assistant how to do one job, for example Kubernetes triage, a slow database or a migration review: which read-only commands to run, what to check, and what to hand back. Every skill follows the same [safety gates](../.claude/skills/sre-safety-gates/SKILL.md): read-only first, then a proposal with risk and rollback, then your explicit approval before anything changes.

### How a skill gets picked

- **Auto (most skills).** You describe the problem in plain words. The tool compares your request with each skill's `description` and loads the one that fits. You don't need to name the skill, but you can ("use sre-k8s-triage").
- **Manual only (two skills).** `sre-k8s-safe-remediation` and `sre-chaos-engineering` set `disable-model-invocation: true`, so you start them yourself:

  | Tool | How to start a manual-only skill | Source |
  |---|---|---|
  | Claude Code, plugin install | `/sre:sre-k8s-safe-remediation` | [claude-code.md](install/claude-code.md) |
  | Claude Code, project or personal copy | `/sre-k8s-safe-remediation` | [claude-code.md](install/claude-code.md) |
  | Cursor | `/sre-k8s-safe-remediation` | [cursor.md](install/cursor.md) |
  | Codex CLI | `$sre-k8s-safe-remediation` | [codex.md](install/codex.md) |
  | Grok | A slash command (manual-only is honoured). Grok's [docs](https://docs.x.ai/build/features/skills-plugins-marketplaces) say skills appear as slash commands but don't show the name for plugin skills, so find it with `/skills` | [grok.md](install/grok.md) |
  | Gemini CLI, GitHub Copilot | Manual-only isn't enforced. Gemini asks you to consent to every skill activation: decline it unless you started the skill. Each skill's text gates still apply | [gemini-cli.md](install/gemini-cli.md), [copilot.md](install/copilot.md) |

- **Reference (two skills).** `sre-safety-gates` and `sre-remediation-actions` set `user-invocable: false`. You never call them; other skills read them.

The full list with each skill's description and invocation is the skills table in the [README](../README.md#skills). Routing (which skill handles which intent) is in [SKILLS.md](../SKILLS.md).

## Before you start

### 1. Install

Follow [INSTALL.md](../INSTALL.md) for your tool. Each guide ends with a verify step and a test prompt. If you install single skills, always add `sre-safety-gates`, and check the dependencies under "Install profiles" in [SKILLS.md](../SKILLS.md).

### 2. The command-line tools each skill family uses

The assistant runs commands with the CLIs already on your machine and the access you already have. Install only what matches your stack. This list comes from the skills' own text and scripts.

| Skills | Tools |
|---|---|
| `sre-k8s-triage`, `sre-k8s-safe-remediation` | `kubectl`, `helm` (for Helm releases) |
| `sre-k8s-upgrade-autopilot` | `kubectl`, `jq` 1.6 or later, bash 3.2 or later; optional `kubent`, `pluto`; plus `aws`, `gcloud` or `az` for the provider steps |
| `sre-aws` | `aws` |
| `sre-azure` | `az` |
| `sre-gcp` | `gcloud` (and `gke-gcloud-auth-plugin` for `kubectl` on GKE) |
| `sre-terraform` | `terraform`, `jq` |
| `sre-database-triage` | `psql`, `mysql` or `redis-cli` for your engine |
| `sre-migration-safety` | `python3` (the linter never connects to a database) |
| `sre-prometheus-grafana`, `sre-slo-burn-rate-rules` | `promtool`, `python3`, `curl`, `jq`; optional `amtool`, `logcli` |
| `sre-observability-cost-cutter` | `python3` (stdlib only), `promtool`; `jq` and `curl` for follow-up commands |
| `sre-datadog`, `sre-pagerduty-opsgenie`, `sre-oncall-handoff`, `sre-oncall-audit` | `curl`, `jq`, bash (or the vendor's MCP server, configured read-only) |

Skills with no CLI of their own (incident command, communication, postmortems, runbooks, readiness reviews) work from what you tell them and from the adapters above.

### 3. Read-only access only

Give the assistant read-only credentials. Never give it an admin, owner or superuser account. Each adapter says exactly which role to use:

- Kubernetes: a `view`-style role without Secrets or `exec`: [sre-k8s-triage rules](../.claude/skills/sre-k8s-triage/SKILL.md#rules) and [rbac-readonly.yaml](../.claude/skills/sre-k8s-triage/references/rbac-readonly.yaml).
- AWS: `ViewOnlyAccess` plus [readonly-iam-policy.json](../.claude/skills/sre-aws/references/readonly-iam-policy.json), not `ReadOnlyAccess` ([sre-aws rules](../.claude/skills/sre-aws/SKILL.md#rules)).
- Azure: Reader, Log Analytics Reader, never Contributor or Owner ([sre-azure minimal roles](../.claude/skills/sre-azure/SKILL.md#minimal-roles)).
- GCP: viewer roles, no service account keys ([sre-gcp rules](../.claude/skills/sre-gcp/SKILL.md#rules)).
- Databases: `pg_monitor`, MySQL `PROCESS` and friends, a Redis ACL user ([sre-database-triage rules](../.claude/skills/sre-database-triage/SKILL.md#rules)).
- Datadog, Dynatrace, Grafana and other MCP servers: configure them read-only per [mcp.md](../.claude/skills/sre-safety-gates/references/mcp.md) (also linked from [docs/mcp.md](mcp.md)). Datadog's MCP write access is on by default, so read [sre-datadog](../.claude/skills/sre-datadog/SKILL.md) first.
- PagerDuty and Opsgenie: a read-only API key in `PD_API_KEY` or `OG_API_KEY`, exported in your shell ([sre-pagerduty-opsgenie](../.claude/skills/sre-pagerduty-opsgenie/SKILL.md)).

### 4. Start somewhere safe

Try the pack first on a test cluster, a sandbox account or a staging database. A local [kind](https://kind.sigs.k8s.io/) cluster is enough for the walkthrough below.

## Your first run: a crash-looping pod on kind

You need Docker, `kind` and `kubectl`. You create the broken workload yourself, so the assistant has something to find. These setup commands change your local lab cluster only.

```bash
kind create cluster --name sre-lab                       # context: kind-sre-lab
kubectl --context kind-sre-lab create namespace demo
kubectl --context kind-sre-lab -n demo create deployment crashy --image=busybox:1.36 --replicas=2 -- sh -c 'echo starting; exit 1'
```

**Everything below is an illustrative example, not captured output.** Your assistant's wording will differ; the shape should not.

**1. You type** (naming the context and namespace, never relying on the current context):

```text
Pods in namespace demo on kube context kind-sre-lab are in CrashLoopBackOff. Help me triage.
```

**2. The assistant loads `sre-k8s-triage` and runs read-only commands only**, each with `--context` and `-n`:

```text
kubectl --context kind-sre-lab -n demo get pods -o wide
kubectl --context kind-sre-lab -n demo events --types=Warning | tail -n 50
kubectl --context kind-sre-lab -n demo describe pod crashy-<hash>
kubectl --context kind-sre-lab -n demo logs crashy-<hash> --previous --tail=50
```

It may also offer `bash scripts/k8s-triage-snapshot.sh --context kind-sre-lab -n demo` from the `sre-k8s-triage` folder, a bounded evidence bundle that never reads Secrets.

**3. It reports what it found:**

```text
Finding: deployment/crashy, 2/2 pods CrashLoopBackOff. Container exits with code 1 right after
printing "starting". No OOMKilled, no image pull error, no probe failures. The command itself fails.
```

**4. It proposes a fix, with risk and rollback, and stops:**

```text
Proposed action (not run):
  Real fix:    correct the container command in the manifest and ship it through Git/GitOps
  Stop-gap:    kubectl --context kind-sre-lab -n demo scale deployment/crashy --replicas=0
  Target:      context kind-sre-lab, namespace demo, deployment/crashy (no HPA, no GitOps owner found)
  Risk:        low (lab cluster, no traffic)
  Reversible:  yes
  Expected:    no crash-looping pods in demo
  Rollback:    kubectl --context kind-sre-lab -n demo scale deployment/crashy --replicas=2
Approval needed. Writes go through /sre-k8s-safe-remediation (plugin: /sre:sre-k8s-safe-remediation).
```

**5. You decide.** Nothing changes until you approve that specific action. For a Kubernetes write, start the manual-only skill yourself (syntax for your tool is in the table above). It pins the target, captures evidence, checks GitOps and HPA ownership, previews the change, and asks again before it runs exactly one command.

**6. It verifies:** `kubectl --context kind-sre-lab -n demo get deployment/crashy` and `kubectl --context kind-sre-lab -n demo events --types=Warning | tail -n 50` show no new restarts. If anything looks worse, it stops and tells you instead of trying another fix.

Clean up the lab with `kind delete cluster --name sre-lab`.

## Try these prompts

Replace the placeholders. Every prompt names its target, because the skills never assume a default context, account or database.

| Prompt | Skill |
|---|---|
| "Pods in namespace `<ns>` on kube context `<ctx>` are CrashLoopBackOff since the last deploy. Triage it read-only." | `sre-k8s-triage` |
| "Postgres `<db>` on host `<host>` has been slow for 20 minutes. Connections look high. Triage it read-only." | `sre-database-triage` |
| "Review `migrations/0042_add_index.sql` for PostgreSQL 16 before I merge it. The `orders` table is about 200 GB and busy." | `sre-migration-safety` |
| "Write Prometheus burn-rate alert rules for a 99.9% availability SLO on job `checkout`, using `http_requests_total` with `code=~\"5..\"` as errors." | `sre-slo-burn-rate-rules` |
| "Audit Datadog usage and cost for org `<org>` on site `datadoghq.com` and give me a ranked savings plan. Read-only." | `sre-observability-cost-cutter` |
| "Plan the upgrade of EKS cluster `<cluster>` in region `<region>`, kube context `<ctx>`, to 1.33." | `sre-k8s-upgrade-autopilot` |
| "Write my on-call handoff for team `<team>` for the last 12 hours from PagerDuty." | `sre-oncall-handoff` |
| "Incident `<id>` on `<svc>` is resolved. Draft a blameless postmortem with a timeline from PagerDuty and our deploy history." | `sre-postmortem-templates` |
| "Review the Terraform plan for root module `<root-module-dir>` in workspace `<workspace>`. Don't apply anything." | `sre-terraform` |

## Running the bundled scripts yourself

Several skills ship scripts you can run without an assistant. They're read-only, need an explicit target, and write their output outside the repo. Paths are relative to your clone (`SRE-Skills/`); after a copy install they're in the same place under your skills folder. Run each one from its skill folder, as shown.

**Kubernetes upgrade preflight** (`sre-k8s-upgrade-autopilot`). Exit 0 GO, 1 NO-GO, 2 refused, 3 unreachable.

```bash
cd SRE-Skills/.claude/skills/sre-k8s-upgrade-autopilot
bash scripts/upgrade-preflight.sh --context <ctx> --target 1.33
bash scripts/verify-step.sh --context <ctx> --expect-control-plane 1.33      # after each upgrade step
bash scripts/upgrade-preflight.sh --context demo --target 1.32 --fixtures tests/fixtures/kind-1.31   # recorded data, no cluster
```

**Kubernetes triage** (`sre-k8s-triage`). The preflight exits 1 if the identity can read Secrets, exec, port-forward or write, so an admin context (such as kind's default) fails it on purpose.

```bash
cd SRE-Skills/.claude/skills/sre-k8s-triage
bash scripts/k8s-preflight.sh --context <ctx> -n <ns>
bash scripts/k8s-triage-snapshot.sh --context <ctx> -n <ns>
```

**Migration lint** (`sre-migration-safety`). Never connects to a database. Exit 0 clean, 1 warnings, 2 blockers.

```bash
cd SRE-Skills/.claude/skills/sre-migration-safety
python3 scripts/migration-lint.py --engine pg <path-to>/migration.sql
python3 scripts/migration-lint.py --engine mysql --format json <path-to>/migrate.sql
```

**Observability cost audit** (`sre-observability-cost-cutter`). Try it on the synthetic demo data first. A live run needs read-only `DD_API_KEY`, `DD_APP_KEY` and `DD_SITE` exported in your shell; see the skill's Inputs.

```bash
cd SRE-Skills/.claude/skills/sre-observability-cost-cutter
W="$(mktemp -d "${TMPDIR:-/tmp}/obcost-demo.XXXXXX")"
python3 scripts/dd_cost_audit.py --input-dir demo --dollar-estimates --out "$W/demo-report.md"
```

**SLO burn-rate rules** (`sre-slo-burn-rate-rules` uses the generator in `sre-prometheus-grafana`):

```bash
cd SRE-Skills/.claude/skills/sre-prometheus-grafana
python3 scripts/gen-burn-rate-rules.py --slo-name checkout-availability --objective 0.999 \
  --errors 'http_requests_total{job="checkout",code=~"5.."}' --total 'http_requests_total{job="checkout"}' \
  --out /tmp/slo-checkout.rules.yml
promtool check rules --lint=all --lint-fatal /tmp/slo-checkout.rules.yml
```

**PagerDuty and Opsgenie** (`sre-pagerduty-opsgenie`). Export `PD_API_KEY` or `OG_API_KEY` in your shell first; set `PD_REGION=eu` or `OG_REGION=eu` for EU accounts.

```bash
cd SRE-Skills/.claude/skills/sre-pagerduty-opsgenie
bash scripts/pd_oncall.sh
bash scripts/pd_incidents.sh --since <ISO8601> --until <ISO8601>
bash scripts/og_oncall.sh --schedule <schedule-name>
```

Each script prints its usage with `--help`. The cloud, database, Datadog, Dynatrace and Terraform skills ship their own wrappers too; each skill's "Bundled scripts" section lists them.

## Safety: what it won't do without you

- **No change without your approval.** No prod-changing command, MCP write, kill, failover, rollback, scale, restart, Terraform apply, page or status-page post until you approve that specific action. A proposal always comes first, with the exact command, target, risk, reversibility and rollback.
- **Don't approve on autopilot.** Read the target in every proposal (context, namespace, account, database) before you say yes. "Yes to everything" defeats the gates.
- **Secrets never go in chat or commands.** Export keys in your own shell (`PD_API_KEY`, `DD_API_KEY`), use `~/.pgpass` or a MySQL defaults file, and keep evidence bundles, plan files and state out of the repo. The database wrapper refuses `PGPASSWORD`, `MYSQL_PWD` and password flags.
- **Keep your tool's own approval prompts on.** They're the hard control; the skill text is the soft one. Optional hard guardrails (the Terraform guard hook, Kubernetes deny rules) are described in each install guide.

## Troubleshooting

- **The skill doesn't trigger.** Start a new session after installing. Check the skill is installed (`/skills` in Claude Code, `gemini skills list`, `grok inspect`, or `ls` on the skills folder; each guide's Verify section has the exact command). Use the words in the skill's description ("CrashLoopBackOff", "migration", "burn-rate"), or name the skill. Manual-only skills never trigger on their own; start them yourself.
- **The assistant can't reach the cluster or account.** It uses your CLIs and credentials. Run the identity check yourself first: `kubectl config get-contexts <ctx>`, `aws sts get-caller-identity --profile <profile>`, `az account show`, `gcloud config list`. If the tool has no shell access, the skills print the commands for you to run and paste back.
- **A script refuses with "--context is required" (or similar).** That's deliberate: every script needs an explicit target and never uses your current context, profile or project. Add the flag it names.
- **The gates seem to be missing after a partial install.** Every skill carries a short inline gate block, so it stays gated. For the full rules in every session, install `sre-safety-gates` plus your tool's always-on file: `.cursor/rules/sre-safety-gates.mdc` (Cursor), `AGENTS.md` (Codex, Grok), `.github/copilot-instructions.md` (Copilot), `GEMINI.md` (Gemini extension). See "How the gates stay attached" in your tool's guide (listed in [INSTALL.md](../INSTALL.md)).
- **A skill can't find another skill's script.** Some skills use another skill's scripts (for example `sre-oncall-handoff` uses `sre-pagerduty-opsgenie`). Install both; see "Install profiles" in [SKILLS.md](../SKILLS.md).

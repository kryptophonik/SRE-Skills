# SRE Skill Pack — Index and Routing (single source of truth)

Each skill lives at `.claude/skills/<name>/SKILL.md`. Claude Code picks skills from each frontmatter `description`. **This table is guidance for humans and for keeping descriptions consistent — it is not executed.** Change a skill's scope and this table together.

Version: `3.0.0`

## Shared rules

- [sre-safety-gates](.claude/skills/sre-safety-gates/SKILL.md) applies to every skill: read-only first -> propose with risk/reversibility -> explicit approval before prod changes, MCP writes, or external posts -> act -> verify -> stop and escalate if worse.
- State assumptions; mark unknowns `[TBD]`. Tie advice to SLIs/SLOs. Every skill ends with its `Output` deliverable.
- MCP servers and read-only setup: [.claude/skills/sre-safety-gates/references/mcp.md](.claude/skills/sre-safety-gates/references/mcp.md).

## Placeholder vocabulary

Use these exact placeholders in every skill: `<ctx>` (kube context), `<ns>` (namespace), `<svc>` (service), `<env>`, `<cluster>`, `<profile>` and `<region>` (AWS), `<subscription-id>` and `<rg>` (Azure), `<PROJECT_ID>`, `<REGION>`, `<ZONE>` (GCP, upper-case to match Google docs), `<env-id>` (Dynatrace), `$DD_SITE` (Datadog). HTTP status label in PromQL examples is `code`; rename to `status` where your metrics use that.

## Naming

Every skill is prefixed `sre-` so it does not collide with or shadow other packs' skills (personal skills override project skills with the same name). Check for collisions with `/skills`.

## Routing (most specific first)

| Intent | Skill | Invocation |
|---|---|---|
| Incident declared/suspected, roles, severity, IC handoff | `sre-incident-command` | auto |
| Suspected compromise, leaked key, suspicious access | `sre-security-incident-triage` | auto |
| Debug a live issue, high 5xx/latency, remediate, run a runbook | `sre-engineer` | auto |
| Kubernetes workload unhealthy | `sre-k8s-triage` | auto |
| Investigation and profiling detail | `sre-diagnostics` | auto |
| Incident update / status page / exec summary drafts | `sre-incident-communication` | auto |
| Postmortem / RCA | `sre-postmortem-templates` | auto |
| Shift change summary | `sre-oncall-handoff` | auto |
| Deploy, migration, infra change safety | `sre-change-safety` | auto |
| SLOs, error budgets, alert rules, alert fatigue | `sre-slo-alerting` | auto |
| Write/update a runbook | `sre-runbook-templates` | auto |
| Production readiness / launch | `sre-production-readiness` | auto |
| Capacity, headroom, load tests | `sre-capacity-planning` | auto |
| Backup restore / DR drill | `sre-dr-backup-test` | auto |
| Dependencies, blast radius | `sre-dependency-mapping` | auto |
| Toil review | `sre-toil-review` | auto |
| Cloud or observability cost | `sre-cloud-cost-review` | auto |
| A correct query in any monitoring tool | `sre-observability-query-cookbook` | auto |
| Chaos experiment / game day | `sre-chaos-engineering` | **manual only** (`/sre-chaos-engineering`) |
| Design, reliability review, on-call program | `sre-architect` | auto |

### Tool adapters (load with the process skill)

| Tool | Skill |
|---|---|
| Dynatrace | `sre-dynatrace` |
| Prometheus, Alertmanager, Loki, Grafana | `sre-prometheus-grafana` |
| Datadog | `sre-datadog` |
| PagerDuty, Opsgenie | `sre-pagerduty-opsgenie` |
| Terraform | `sre-terraform` |
| AWS / Azure / GCP | `sre-aws` / `sre-azure` / `sre-gcp` |
| Kubernetes | `sre-k8s-triage` |

### Reference skills (Claude-only, `user-invocable: false`)

`sre-safety-gates`, `sre-remediation-actions`, `sre-tools-catalog`.

Not used as triggers (too broad): bare "fix", "scale", "restart", "tools", "logs", "metrics", "experiment", "performance".

## Changes from 2.x

- Merged `sre-debugging-tools` + `sre-performance-tools` -> `sre-diagnostics`; `sre-slo-templates` + `sre-alerting-templates` -> `sre-slo-alerting`.
- Safety gates moved to one shared skill.
- Added 11 generic skills and 8 tool adapters.

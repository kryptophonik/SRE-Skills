# SRE Skill Pack — Index and Routing (single source of truth)

This file replaces the old `manifest.md` and `router.md`. Each skill lives at
`.claude/skills/<name>/SKILL.md`; its frontmatter `description` is what Claude Code
actually uses to pick a skill. **The routing table below is guidance for humans and
for keeping descriptions consistent — it is not executed.** When you change a
skill's scope, update its `description` and this table together.

Version: `2.0.0`

## Skills, dependencies, and routing

Rules are listed most-specific first; the first matching row wins.

| # | Intent / example phrases | Skill | Uses |
|---|---|---|---|
| 1 | "incident update", "status update", "stakeholder comms", "executive summary" | `sre-incident-communication` | — |
| 2 | "postmortem", "incident review", "RCA", "retrospective" | `sre-postmortem-templates` | — |
| 3 | "production readiness", "PRR", "launch checklist", "go live" | `sre-production-readiness` | — |
| 4 | "define SLO", "error budget", "availability/latency target" | `sre-slo-templates` | — |
| 5 | "write/update runbook", "runbook for <alert>" | `sre-runbook-templates` | — |
| 6 | "design/review alerts", "alert fatigue", "burn-rate alert", "paging policy" | `sre-alerting-templates` | — |
| 7 | "chaos experiment", "fault injection", "game day" | `sre-chaos-engineering` | `sre-tools-catalog` |
| 8 | "debug/diagnose/investigate incident", "high 5xx/latency", "outage", "roll back deployment", "walk me through runbook" | `sre-engineer` | `sre-debugging-tools`, `sre-performance-tools`, `sre-remediation-actions`, `sre-runbook-templates`, `sre-incident-communication`, `sre-postmortem-templates`, `sre-chaos-engineering` |
| 9 | "which observability/monitoring tools", "compare Prometheus vs …" | `sre-tools-catalog` | — |
| 10 | "design observability", "reliability review", "SRE strategy" | `sre-architect` | `sre-tools-catalog`, `sre-slo-templates`, `sre-alerting-templates`, `sre-runbook-templates`, `sre-postmortem-templates`, `sre-chaos-engineering`, `sre-production-readiness`, `sre-engineer` |
| — | No clear match | Ask a clarifying question; default to `sre-architect` for design, `sre-engineer` for live problems | |

Reference skills (`sre-debugging-tools`, `sre-performance-tools`, `sre-remediation-actions`)
are normally loaded by `sre-engineer` rather than triggered directly.

Deliberately **not** used as triggers (too broad): bare "fix", "scale", "restart",
"tools", "logs", "metrics", "experiment", "performance", "incident".

## Global rules (all skills)

- **Safety gates:** read-only diagnosis -> propose with risk/reversibility -> explicit human
  approval before any prod-changing command or external post -> act -> verify -> stop and escalate if worse.
- State assumptions when context is missing; mark unknowns `[TBD]`.
- Tie recommendations to SLIs/SLOs; include validation (synthetic, chaos, load).
- Avoid vendor bias; optimize for on-call humans; blameless postmortems.
- Every skill ends with the deliverable defined in its `output` section.

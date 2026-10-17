# SRE Architect Skill Pack for Claude Code

**Principal-level Site Reliability Engineering capabilities at your fingertips.**

A unified SRE skill pack that equips Claude with observability design, SLO creation, alerting strategy, incident response, operational excellence guidance, and hands-on tactical execution.

---

## Overview

The SRE Architect Skill Pack provides a complete, modular SRE capability set for Claude Code. It includes two primary personas—**SRE Architect** (strategic) and **SRE Engineer** (tactical)—and specialized sub-skills for tools, SLOs, alerting, runbooks, debugging, performance, and remediation.

Whether you're designing observability for a new service, defining SLOs, fixing alert fatigue, debugging incidents, tuning performance, or creating runbooks, this skill pack delivers comprehensive SRE guidance tailored to your needs.

---

## Features

- **Dual-persona model** - Strategic Architect for design/reviews, tactical Engineer for debugging/execution
- **Principal-level SRE reasoning** - Get guidance grounded in real-world SRE practices
- **Modular sub-skills** - Specialized capabilities for tools, SLOs, alerting, runbooks, debugging, performance, remediation, **chaos engineering**, and **postmortems**
- **SLO-driven approach** - All recommendations tie back to service level objectives
- **On-call friendly** - Designs for humans under stress, minimizing alert fatigue
- **Intelligent routing** - Automatically directs requests to the appropriate skill
- **Validated guidance** - Recommendations include testing strategies (synthetic, chaos, load)
- **Hands-on execution** - Concrete commands and remediation actions

---

## Architecture

```
.claude/skills/
├── sre-safety-gates/            shared approval gates (reference)
├── Process skills               incident-command, sre-engineer, k8s-triage, sre-diagnostics,
│                                sre-incident-communication, sre-postmortem-templates, oncall-handoff,
│                                change-safety, sre-slo-alerting, sre-runbook-templates,
│                                sre-production-readiness, capacity-planning, dr-backup-test,
│                                dependency-mapping, toil-review, cloud-cost-review,
│                                security-incident-triage, observability-query-cookbook,
│                                sre-chaos-engineering (manual), sre-architect
├── Tool adapters                dynatrace-sre, prometheus-grafana, datadog, pagerduty-opsgenie,
│                                terraform, aws, azure, gcp
└── References                   sre-remediation-actions, sre-tools-catalog
```

---

## Components

| Path | Purpose |
|---|---|
| `SKILLS.md` | Index and routing guidance (single source of truth) |
| `.claude/skills/*/SKILL.md` | 31 skills: process, tool adapters, references |
| `.claude/skills/sre-safety-gates/references/mcp.md` | Verified MCP servers and read-only configuration (start every server read-only) |

---

## Installation

Claude Code loads skills from `<skills-dir>/<skill-name>/SKILL.md` (one level deep).
This repo ships them under `.claude/skills/`.

### Use in this repo / a project

Clone the repo (or copy `.claude/skills/` into your project). Starting Claude Code in
that directory loads all skills automatically.

```bash
git clone https://github.com/kryptophonik/claude-sre.git
cd claude-sre && claude
```

### Personal installation (all projects)

```bash
git clone https://github.com/kryptophonik/claude-sre.git
mkdir -p ~/.claude/skills
cp -r claude-sre/.claude/skills/* ~/.claude/skills/
```

### Verify installation

In Claude Code, ask `What skills are available?` or type `/` and look for the SRE
skills. Invoke one directly with its name, e.g. `/sre-slo-alerting`.

---

## Quick Start

The SRE Architect Pack activates automatically when you use SRE-related keywords. Try these prompts:

### Strategic Tasks (Architect)
### Production Readiness
```
Run a production readiness review for our new payment gateway.
```

### Observability Design
```
Design observability for our API gateway service.
```

### SLO Creation
```
Help me define SLOs for our checkout service.
```

### Alerting Strategy
```
We're experiencing alert fatigue. Can you help redesign our alerts?
```

### Reliability Review
```
Review the reliability of our microservices architecture.
```

### Tactical Tasks (Engineer)
### Incident Debugging & Comms
```
Help debug this incident. We're seeing high 5xx rates. Draft an initial announcement for Slack.
```

### Performance Issues
```
Our API is slow. Help me tune it.
```

### Remediation
```
How do I roll back the last deployment?
```

### Runbook Execution
```
Walk me through the runbook for database connection issues.
```

### Tooling
```
What tools should I use for metrics, logs, and traces in Kubernetes?
```


---

## When skills activate

Claude Code picks a skill from each `SKILL.md` frontmatter `description`. See
[SKILLS.md](SKILLS.md) for the routing table. Prod-changing actions and external posts
always require your explicit approval (see each skill's **Safety gates**).

---

## Core Behaviors

All responses follow these principles:

1. **User-impact first** - Focus on protecting user experience
2. **SLO-driven** - Tie recommendations to SLIs/SLOs
3. **Concrete steps** - Provide actionable guidance, not theory
4. **On-call friendly** - Design for humans under stress
5. **Validate everything** - Include testing strategies
6. **State assumptions** - Call out missing context

---

## License

MIT License - see LICENSE file for details.

---

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

---

## Version

3.0.0

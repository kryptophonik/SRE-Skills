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
├── sre-architect/            (strategic persona)
│   └── uses: tools-catalog, slo, alerting, runbook, postmortem, chaos, production-readiness
├── sre-engineer/             (tactical persona, approval-gated)
│   └── uses: debugging-tools, performance-tools, remediation-actions, runbook,
│             incident-communication, postmortem, chaos
└── sre-*/SKILL.md            (13 skills total; see SKILLS.md for routing)
```

---

## Components

| File | Purpose |
|------|---------|
| **SKILLS.md** | Index, dependencies, and routing guidance (single source of truth) |
| **.claude/skills/sre-architect/SKILL.md** | Strategic SRE architect persona and workflows |
| **.claude/skills/sre-engineer/SKILL.md** | Tactical SRE engineer persona and workflows |
| **.claude/skills/sre-tools-catalog/SKILL.md** | Tooling recommendations across all SRE domains |
| **.claude/skills/sre-slo-templates/SKILL.md** | SLO templates and error budget models |
| **.claude/skills/sre-alerting-templates/SKILL.md** | Alerting templates and taxonomy |
| **.claude/skills/sre-runbook-templates/SKILL.md** | Runbook skeletons for incidents |
| **.claude/skills/sre-postmortem-templates/SKILL.md** | Blameless postmortem templates and facilitation |
| **.claude/skills/sre-chaos-engineering/SKILL.md** | Chaos engineering workflows and experiments |
| **.claude/skills/sre-debugging-tools/SKILL.md** | Debugging workflows, log analysis, trace queries |
| **.claude/skills/sre-performance-tools/SKILL.md** | Profiling tools and tuning guidance |
| **.claude/skills/sre-remediation-actions/SKILL.md** | Recovery procedures and remediation patterns |
| **.claude/skills/sre-production-readiness/SKILL.md** | PRR checklists and templates |
| **.claude/skills/sre-incident-communication/SKILL.md** | Stakeholder comms templates |

---

## Installation

Claude Code loads skills from `<skills-dir>/<skill-name>/SKILL.md` (one level deep).
This repo ships them under `.claude/skills/`.

### Use in this repo / a project

Clone the repo (or copy `.claude/skills/` into your project). Starting Claude Code in
that directory loads all `sre-*` skills automatically.

```bash
git clone https://github.com/kryptophonik/claude-sre.git
cd claude-sre && claude
```

### Personal installation (all projects)

```bash
git clone https://github.com/kryptophonik/claude-sre.git
mkdir -p ~/.claude/skills
cp -r claude-sre/.claude/skills/sre-* ~/.claude/skills/
```

### Verify installation

In Claude Code, ask `What skills are available?` or type `/` and look for the `sre-*`
skills. Invoke one directly with its name, e.g. `/sre-slo-templates`.

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

2.0.0

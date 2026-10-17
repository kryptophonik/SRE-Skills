---
name: sre-chaos-engineering
description: "Designs and runs controlled chaos / fault-injection experiments and game days with hard no-go rules, approval and abort criteria. Uses Chaos Mesh, Gremlin, AWS FIS or similar only after approval; otherwise produces the plan. Manual invocation only. Not for live incident response."
disable-model-invocation: true
---

# Chaos Engineering Skill

## Safety gates (REQUIRED)
Follow [sre-safety-gates](../sre-safety-gates/SKILL.md) for every step. In short: read-only diagnosis -> propose with risk/reversibility -> **explicit human approval** before any prod change, MCP write, or external post -> act -> verify -> stop and escalate if worse.

## No-go rules

> if ANY is true, do not run — report why and stop

- Error budget for the target service is exhausted or burning above normal
- An active incident or ongoing change freeze exists
- No tested rollback / abort mechanism
- No named owner present for the full run
- No timebox (start/end window and max duration)
- No explicit human approval for this experiment, environment, and blast radius
- Observability for steady-state metrics is not working
- On-call and stakeholders not notified

## Chaos principles

- Build a hypothesis around steady-state behavior.
- Vary real-world events (server crashes, network latency).
- Prefer production-like environments; run in production only with explicit approval and smallest blast radius.
- Automate experiments to run continuously once proven safe.
- Minimize blast radius.

## Experiment workflow

### Steps

1. Check no_go_rules; stop if any apply.
2. Define 'Steady State': Metrics that indicate the system is healthy.
3. Formulate Hypothesis: 'If we do X, the system will still be Y'.
4. Design Experiment: Choose tool and parameters (use: sre-tools-catalog -> chaos).
5. Define Abort Criteria and rollback (see abort_criteria).
6. Propose plan: target, blast radius, owner, timebox, risk, rollback — get explicit approval.
7. Run Experiment within timebox; monitor abort criteria continuously.
8. Analyze: Compare results to hypothesis.
9. Improve Resilience: File fixes for any failures found.

## Abort criteria

> any trigger -> halt injection immediately, roll back, notify

- SLO burn rate exceeds agreed threshold (e.g., >2x normal)
- Error rate or p99 latency exceeds pre-agreed limit
- User-facing impact outside the planned blast radius
- Unexpected alerts in unrelated services
- Timebox expires
- Owner or on-call calls stop

## Common experiments

### Network

- **Latency:** Inject 200ms delay into service-to-service calls.
- **Packet Loss:** Drop 5% of incoming packets.
- **Partition:** Block traffic between two availability zones. (high risk)

### Infrastructure

- **Pod Kill:** Terminate one pod in a deployment.
- **Node Drain:** Simulate losing an entire cluster node. (high risk)
- **Resource Stress:** Force 90% CPU or Memory usage on a pod.

### Application

- **API Errors:** Return 500s for a percentage of requests.
- **Dependency Failure:** Simulate database or cache being unavailable. (high risk)

## Safety checks

- Always have a 'Stop' button (Abort condition) and test it first.
- Start with a small blast radius (1% of traffic or 1 instance).
- Ensure observability is working *before* starting the experiment.
- Notify stakeholders and on-call engineers.

## Output

- Experiment record: hypothesis, approval (who/when), blast radius, timebox, results, abort events, follow-up tickets

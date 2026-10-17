# Chaos Engineering Skill

## Safety gates (REQUIRED — read before anything else)

These gates apply to every step in this skill. Never skip or reorder them.

1. **Diagnose read-only first.** Use only read commands (`get`, `describe`, `logs`, `history`, dashboards, queries). Change nothing.
2. **Propose with risk and reversibility.** For each proposed action, state: exact command/change, target (env, cluster, namespace, service), risk (low/med/high), reversible (yes/no), expected effect, and rollback plan.
3. **Wait for explicit human approval.** Do NOT run any prod-changing command or send/post any external message until a human explicitly approves that specific action. Silence, "looks fine", or approval of a different action is not approval.
4. **Act.** Run exactly what was approved — nothing more. Prefer dry-run/diff output first.
5. **Verify.** Confirm error rate, latency, and saturation returned to baseline / within SLO; watch 5-15 min.
6. **Stop and escalate if worse.** If metrics degrade, the action fails, or the outcome is unexpected: stop, do not try further fixes on your own, roll back if approved, and escalate to the Incident Commander / on-call.
```yaml
name: sre_chaos_engineering
label: "Chaos Engineering"
description: >
  Design and run controlled fault-injection experiments to test system
  resilience. Use when planning or executing a chaos experiment / game day.
  Not for live incident response.

no_go_rules:   # if ANY is true, do not run — report why and stop
  - "Error budget for the target service is exhausted or burning above normal"
  - "An active incident or ongoing change freeze exists"
  - "No tested rollback / abort mechanism"
  - "No named owner present for the full run"
  - "No timebox (start/end window and max duration)"
  - "No explicit human approval for this experiment, environment, and blast radius"
  - "Observability for steady-state metrics is not working"
  - "On-call and stakeholders not notified"

chaos_principles:
  - "Build a hypothesis around steady-state behavior."
  - "Vary real-world events (server crashes, network latency)."
  - "Prefer production-like environments; run in production only with explicit approval and smallest blast radius."
  - "Automate experiments to run continuously once proven safe."
  - "Minimize blast radius."

experiment_workflow:
  steps:
    - "Check no_go_rules; stop if any apply."
    - "Define 'Steady State': Metrics that indicate the system is healthy."
    - "Formulate Hypothesis: 'If we do X, the system will still be Y'."
    - "Design Experiment: Choose tool and parameters (use: sre_tools_catalog -> chaos)."
    - "Define Abort Criteria and rollback (see abort_criteria)."
    - "Propose plan: target, blast radius, owner, timebox, risk, rollback — get explicit approval."
    - "Run Experiment within timebox; monitor abort criteria continuously."
    - "Analyze: Compare results to hypothesis."
    - "Improve Resilience: File fixes for any failures found."

abort_criteria:   # any trigger -> halt injection immediately, roll back, notify
  - "SLO burn rate exceeds agreed threshold (e.g., >2x normal)"
  - "Error rate or p99 latency exceeds pre-agreed limit"
  - "User-facing impact outside the planned blast radius"
  - "Unexpected alerts in unrelated services"
  - "Timebox expires"
  - "Owner or on-call calls stop"

common_experiments:
  network:
    - Latency: "Inject 200ms delay into service-to-service calls."
    - Packet Loss: "Drop 5% of incoming packets."
    - Partition: "Block traffic between two availability zones. (high risk)"
  infrastructure:
    - Pod Kill: "Terminate one pod in a deployment."
    - Node Drain: "Simulate losing an entire cluster node. (high risk)"
    - Resource Stress: "Force 90% CPU or Memory usage on a pod."
  application:
    - API Errors: "Return 500s for a percentage of requests."
    - Dependency Failure: "Simulate database or cache being unavailable. (high risk)"

safety_checks:
  - "Always have a 'Stop' button (Abort condition) and test it first."
  - "Start with a small blast radius (1% of traffic or 1 instance)."
  - "Ensure observability is working *before* starting the experiment."
  - "Notify stakeholders and on-call engineers."

output:
  - "Experiment record: hypothesis, approval (who/when), blast radius, timebox, results, abort events, follow-up tickets"
```

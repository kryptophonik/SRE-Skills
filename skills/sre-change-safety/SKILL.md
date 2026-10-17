---
name: sre-change-safety
description: "Use before, during or right after a deploy, migration or infra change: risk score, freeze and error-budget check, canary/progressive rollout, rollback plan, post-deploy verification."
---

# Change Safety

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

## Risk score

| Factor | Low (1) | Med (2) | High (3) |
|---|---|---|---|
| Blast radius | one service, canary | one region / many users | global / shared infra |
| Reversibility | instant rollback | rollback with effort | irreversible (data/schema migration, deletes) |
| Novelty | routine, automated | new config path | first time / manual |
| Timing | business hours, staffed | late day | Friday night, holiday, peak |
| Observability | SLO + alerts cover it | partial | blind |

Total 5–7 low, 8–11 med (peer review + canary), 12–15 high (approval from owner, staffed window, explicit rollback test).

## No-go rules

- Change freeze in effect without an approved exception.
- Error budget exhausted for the affected service (only reliability fixes go out).
- Active SEV-1/SEV-2 on the same service or shared dependency.
- No tested rollback plan, or irreversible step without backup.
- No owner watching during and after rollout.

## Workflow

1. **Describe** the change: what, where, why, linked PR/plan.
2. **Score risk** and check no-go rules.
3. **Pre-checks (read-only):** CI green, `terraform plan` reviewed (`sre-terraform`), dashboards and SLOs healthy, dependencies healthy.
4. **Plan rollout:** canary (1–5%) -> 25% -> 50% -> 100%, with bake time and gate metrics (error ratio, p95 latency, saturation).
5. **Get approval** for the plan.
6. **Roll out** step by step; check gates at each step. For Terraform, apply only the exact saved plan that was reviewed and approved.
7. **Roll back** immediately if a gate fails (follow `sre-remediation-actions`).
8. **Verify** 15–30 min after 100%; record result.

## Useful read-only commands

```bash
kubectl --context <ctx> -n <ns> rollout status deployment/<name> --timeout=60s
kubectl --context <ctx> -n <ns> rollout history deployment/<name>
kubectl argo rollouts --context <ctx> -n <ns> get rollout <name>   # Argo Rollouts plugin
terraform plan -input=false -out=<plan-file> && terraform show -no-color <plan-file>   # apply only this exact reviewed plan
```

## Change record template

```markdown
# Change: [title]
- **Owner / approver:** [names]
- **Risk score:** [n] ([low|med|high])
- **Window:** [start–end, timezone]
- **Rollout plan:** [steps + gate metrics]
- **Rollback plan:** [exact steps, tested? yes/no]
- **Result:** [success / rolled back — evidence links]
```

## Output

- Change record with risk score, go/no-go decision, rollout and rollback plan, verification result

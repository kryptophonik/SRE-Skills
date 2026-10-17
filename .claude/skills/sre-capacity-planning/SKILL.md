---
name: sre-capacity-planning
description: "Use before launches or peak events, or when saturation trends up: forecast demand from metrics, compute headroom, plan load tests, set scaling triggers. Read-only queries."
---

# Capacity Planning

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

## Workflow

1. **Pick the unit:** requests/s, jobs/min, active users, storage GB.
2. **Gather 30–90 days** of demand and saturation (CPU, memory, connections, queue depth, disk) per service. Use `sre-observability-query-cookbook` queries.
3. **Find the limit:** the resource that saturates first per unit of demand (from load tests or past peaks).
4. **Forecast:** growth trend + known events (launches, seasonality). Show low/expected/high.
5. **Headroom target:** default keep peak utilization ≤ 60–70% of the limit, and survive loss of one zone (N+1).
6. **Plan actions:** autoscaling bounds, reserved capacity, quota increases (cloud quotas take time), architecture fixes.
7. **Validate** with a load test (k6, Locust) in a production-like environment.

## Formulas

- Headroom % = (limit − current peak) / limit × 100
- Months until full = log(limit / current) / log(1 + monthly growth rate)
- Required instances = peak demand / safe per-instance throughput × (1 + zone-loss buffer)

## Read-only checks

```bash
kubectl --context <ctx> top nodes
kubectl --context <ctx> get hpa -A
aws service-quotas list-service-quotas --profile <profile> --region <region> --service-code ec2 --max-items 100
az vm list-usage --location <region> --subscription <subscription-id> -o table
gcloud compute regions describe <REGION> --project=<PROJECT_ID> --format="table(quotas.metric,quotas.limit,quotas.usage)"   # field paths: verify in your environment
```

## Output

- Capacity report: demand forecast, limiting resource, headroom now and at forecast peak, recommended actions with dates and owners, load-test plan

---
name: capacity-planning
description: "Capacity planning: forecast demand from historical metrics, compute headroom against saturation limits, plan load tests, set scaling triggers. Queries Dynatrace, Prometheus/Grafana, Datadog or cloud metrics read-only. Use before launches, peak events, or when saturation trends up."
---

# Capacity Planning

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post. Load tests against shared or prod environments need approval.

## Workflow

1. **Pick the unit:** requests/s, jobs/min, active users, storage GB.
2. **Gather 30–90 days** of demand and saturation (CPU, memory, connections, queue depth, disk) per service. Use `observability-query-cookbook` queries.
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
kubectl top nodes
kubectl get hpa -A
aws service-quotas list-service-quotas --service-code ec2
az vm list-usage --location <region> -o table
gcloud compute regions describe <region> --format="table(quotas.metric,quotas.limit,quotas.usage)"
```

## Output

- Capacity report: demand forecast, limiting resource, headroom now and at forecast peak, recommended actions with dates and owners, load-test plan

---
name: sre-dependency-mapping
description: "Use for PRRs, reliability reviews, incident blast radius or chaos planning: map upstream/downstream services, criticality, timeouts/retries and single points of failure. Read-only."
---

# Dependency Mapping

## Safety gates (REQUIRED)

Follow [sre-safety-gates](../sre-safety-gates/SKILL.md): read-only first; explicit approval before any prod change, MCP write, or external post.

## Workflow

1. **Discover (read-only):**
   - APM/topology: Dynatrace Smartscape (`sre-dynatrace`), Datadog service map (`sre-datadog`), Tempo service graph (`sre-prometheus-grafana`).
   - Config: Kubernetes Services/Ingress, env vars and config maps naming hosts, Terraform state outputs.
   - Ask owners to confirm; tools miss async (queues, batch, cron) links.
2. **Classify each dependency:** hard (request fails without it) vs. soft (degrades); sync vs. async.
3. **Record resilience settings:** timeout, retries (with backoff/jitter?), circuit breaker, fallback, SLO of the dependency.
4. **Find risks:** single points of failure, retry storms (retries × fan-out), missing timeouts, dependency SLO lower than ours, shared infra (one DB, one region).
5. **Blast radius:** for each critical dependency, which user journeys fail.

## Map template

```markdown
# Dependency map: [service]

| Dependency | Direction | Hard/soft | Sync/async | Timeout | Retries | Fallback | Owner | Dep SLO |
|---|---|---|---|---|---|---|---|---|

## Diagram
[mermaid or link]

## Risks
- [SPOF / missing timeout / retry storm] — impact — fix — owner
```

## Output

- Dependency table, diagram (Mermaid `graph LR` is fine), ranked risks with fixes

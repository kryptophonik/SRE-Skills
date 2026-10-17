---
name: sre-tools-catalog
description: "Recommends SRE tooling (metrics, logs, traces, alerting, on-call, chaos) with trade-offs. Use when choosing or comparing observability/reliability tools. Not for debugging a specific incident."
---

# SRE Tools Catalog

Categorized catalog of SRE tooling with guidance on selection.

**Last reviewed:** 2026-10-16 _(re-review quarterly; tool landscape changes fast)_

## Tools

### Metrics

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Prometheus | Standard for Kubernetes; highly dynamic environments. | Large ecosystem, powerful query language (PromQL), pull-based. | Difficult to scale long-term (needs Thanos/Mimir), single point of failure by default. |
| VictoriaMetrics | High-scale metrics with long-term storage requirements. | Extremely efficient, easy to scale, Prometheus compatible. | Smaller community than Prometheus. |
| Datadog Metrics | Managed service preferred; full-stack visibility. | Zero maintenance, great UI, easy correlation with other signals. | Expensive, vendor lock-in. |

### Tracing

| Name | When to use | Pros | Cons |
|---|---|---|---|
| OpenTelemetry | Standardizing instrumentation across multiple languages. | Vendor-neutral, industry standard, flexible. | Steep learning curve, still maturing. |
| Jaeger | Self-hosted distributed tracing. | Mature, well-supported, CNCF project. | Can be complex to operate at scale. |
| Tempo | Cost-effective tracing integrated with Grafana/Loki. | Low operational overhead, great integration. | Requires Object Storage. |

### Logging

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Loki | High-volume logs; index metadata only. | Very cost-effective, seamless integration with Grafana. | Search can be slower for full-text than Elasticsearch. |
| Elasticsearch/OpenSearch | Complex log analysis, full-text search requirements. | Powerful search capabilities, very mature. | Resource intensive, complex to manage at scale. |
| Fluent Bit / Vector | High-performance log collection and routing. | Lightweight, extremely fast, highly configurable. | Configuration can be complex. |

### Alerting

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Alertmanager | Using Prometheus/Thanos. | Native integration, handles deduplication/grouping well. | Static configuration; UI is basic. |
| Grafana Alerting | Visual alert management across multiple data sources. | Great UI, easy to set up, supports multi-cloud. | Can be confusing with many data sources. |
| PagerDuty / Opsgenie | Enterprise on-call management. | Robust schedules, escalation, mobile app, integrations. | Paid service. |

### SLO management

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Nobl9 | Enterprise-wide SLO management. | Deep SLO focus, integrations, great reporting. | Expensive, specialized tool. |
| Pyrra | Kubernetes-native, simple SLO management. | Integrates with Prometheus, simple CRDs. | Limited feature set compared to enterprise tools. |

### Chaos

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Chaos Mesh | Kubernetes-native chaos engineering. | Great UI, many experiment types, easy to use. | K8s only. |
| Gremlin | Enterprise chaos engineering platform. | Safety-first, robust, cross-platform. | Expensive, proprietary. |

### Load testing

| Name | When to use | Pros | Cons |
|---|---|---|---|
| k6 | Modern, developer-centric load testing (JS). | Easy to write, great CLI, OpenSource + Cloud. | Resource intensive for massive scale (compared to Locust). |
| Locust | Highly scalable, Python-based load testing. | Distributed by design, easy to scale horizontally. | Requires Python knowledge. |

### Kubernetes debugging

| Name | When to use | Pros |
|---|---|---|
| K9s | Terminal-based K8s management. | Very fast, efficient keyboard-driven UI. |
| Lens | GUI-based K8s management. | Visual, great for beginners and overview. |
| Stern | Tailing logs from multiple pods. | Simple, effective, regex support. |

### Incident management

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Incident.io / Rootly / FireHydrant | Orchestrating incident response within Slack/Teams. | Automates timeline creation, role assignment, and status updates. | Requires team adoption of specific chat workflows. |
| Statuspage.io / Cachet | External communication during outages. | Keeps users informed, reduces support ticket volume. | Requires manual or automated updates to remain useful. |

### Deployment safety

| Name | When to use | Pros | Cons |
|---|---|---|---|
| ArgoCD / Flux | GitOps-based continuous delivery. | Declarative, automated drift correction, history of changes. | Steep learning curve for GitOps patterns. |
| Flagger / Argo Rollouts | Automated Canary/Blue-Green deployments. | Reduces blast radius of bad deploys via automated analysis. | Requires mature metrics/observability to drive decisions. |

### Infrastructure as code

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Terraform / OpenTofu | Provisioning cloud infrastructure. | Industry standard, huge provider ecosystem, state management. | HCL can be restrictive; state file management is critical. |
| Pulumi | Infrastructure using general-purpose languages (TS, Python, Go). | Full power of programming languages (loops, abstractions, testing). | Higher complexity than declarative HCL. |

### Database observability

| Name | When to use | Pros | Cons |
|---|---|---|---|
| pganalyze / VividCortex | Deep Postgres/MySQL performance tuning. | Query-level visibility, execution plans, index recommendations. | Specific to database engines; usually a separate paid tool. |
| Percona Monitoring and Management (PMM) | Open-source database monitoring. | Comprehensive, supports multiple DB engines, free. | Another component to host and manage. |

### Finops cost management

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Kubecost | Visibility into Kubernetes spend. | Shows cost by namespace/label; helps with chargebacks. | Requires constant monitoring to drive actual savings. |
| CloudHealth / Vantage | Enterprise-wide cloud cost management. | Cross-cloud, anomaly detection, optimization suggestions. | Expensive for large environments. |

### Service catalog

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Backstage | Centralizing service ownership and documentation. | Extremely extensible, industry-leading developer portal. | High effort to set up and maintain the 'portal' itself. |
| OpsLevel / Cortex.io | Managed service maturity tracking. | Scorecards for reliability, easy to see ownership. | SaaS cost, less flexible than Backstage. |

### Security observability

| Name | When to use | Pros | Cons |
|---|---|---|---|
| Falco | Runtime security for Kubernetes. | Deep visibility into container syscalls, real-time alerting. | High volume of events; requires tuning. |
| Trivy | Vulnerability scanning in CI/CD. | Fast, easy to integrate, scans images and IaC. | Can produce many false positives or unfixable alerts. |

## Output

- Recommended stack per domain with rationale, trade-offs, and alternatives; note catalog last_reviewed date

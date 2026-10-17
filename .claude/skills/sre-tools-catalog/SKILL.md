---
name: sre-tools-catalog
description: "Recommends SRE tooling (metrics, logs, traces, alerting, on-call, chaos) with trade-offs. Use when choosing or comparing observability/reliability tools. Not for debugging a specific incident."
---

# SRE Tools Catalog

```yaml
name: sre-tools-catalog
label: "SRE Tools Catalog"
description: "Categorized catalog of SRE tooling with guidance on selection."
last_reviewed: "2026-10-16"   # re-review quarterly; tool landscape changes fast

tools:

  metrics:
    - name: "Prometheus"
      when_to_use: "Standard for Kubernetes; highly dynamic environments."
      pros: "Large ecosystem, powerful query language (PromQL), pull-based."
      cons: "Difficult to scale long-term (needs Thanos/Mimir), single point of failure by default."
    - name: "VictoriaMetrics"
      when_to_use: "High-scale metrics with long-term storage requirements."
      pros: "Extremely efficient, easy to scale, Prometheus compatible."
      cons: "Smaller community than Prometheus."
    - name: "Datadog Metrics"
      when_to_use: "Managed service preferred; full-stack visibility."
      pros: "Zero maintenance, great UI, easy correlation with other signals."
      cons: "Expensive, vendor lock-in."

  tracing:
    - name: "OpenTelemetry"
      when_to_use: "Standardizing instrumentation across multiple languages."
      pros: "Vendor-neutral, industry standard, flexible."
      cons: "Steep learning curve, still maturing."
    - name: "Jaeger"
      when_to_use: "Self-hosted distributed tracing."
      pros: "Mature, well-supported, CNCF project."
      cons: "Can be complex to operate at scale."
    - name: "Tempo"
      when_to_use: "Cost-effective tracing integrated with Grafana/Loki."
      pros: "Low operational overhead, great integration."
      cons: "Requires Object Storage."

  logging:
    - name: "Loki"
      when_to_use: "High-volume logs; index metadata only."
      pros: "Very cost-effective, seamless integration with Grafana."
      cons: "Search can be slower for full-text than Elasticsearch."
    - name: "Elasticsearch/OpenSearch"
      when_to_use: "Complex log analysis, full-text search requirements."
      pros: "Powerful search capabilities, very mature."
      cons: "Resource intensive, complex to manage at scale."
    - name: "Fluent Bit / Vector"
      when_to_use: "High-performance log collection and routing."
      pros: "Lightweight, extremely fast, highly configurable."
      cons: "Configuration can be complex."

  alerting:
    - name: "Alertmanager"
      when_to_use: "Using Prometheus/Thanos."
      pros: "Native integration, handles deduplication/grouping well."
      cons: "Static configuration; UI is basic."
    - name: "Grafana Alerting"
      when_to_use: "Visual alert management across multiple data sources."
      pros: "Great UI, easy to set up, supports multi-cloud."
      cons: "Can be confusing with many data sources."
    - name: "PagerDuty / Opsgenie"
      when_to_use: "Enterprise on-call management."
      pros: "Robust schedules, escalation, mobile app, integrations."
      cons: "Paid service."

  slo_management:
    - name: "Nobl9"
      when_to_use: "Enterprise-wide SLO management."
      pros: "Deep SLO focus, integrations, great reporting."
      cons: "Expensive, specialized tool."
    - name: "Pyrra"
      when_to_use: "Kubernetes-native, simple SLO management."
      pros: "Integrates with Prometheus, simple CRDs."
      cons: "Limited feature set compared to enterprise tools."

  chaos:
    - name: "Chaos Mesh"
      when_to_use: "Kubernetes-native chaos engineering."
      pros: "Great UI, many experiment types, easy to use."
      cons: "K8s only."
    - name: "Gremlin"
      when_to_use: "Enterprise chaos engineering platform."
      pros: "Safety-first, robust, cross-platform."
      cons: "Expensive, proprietary."

  load_testing:
    - name: "k6"
      when_to_use: "Modern, developer-centric load testing (JS)."
      pros: "Easy to write, great CLI, OpenSource + Cloud."
      cons: "Resource intensive for massive scale (compared to Locust)."
    - name: "Locust"
      when_to_use: "Highly scalable, Python-based load testing."
      pros: "Distributed by design, easy to scale horizontally."
      cons: "Requires Python knowledge."

  kubernetes_debugging:
    - name: "K9s"
      when_to_use: "Terminal-based K8s management."
      pros: "Very fast, efficient keyboard-driven UI."
    - name: "Lens"
      when_to_use: "GUI-based K8s management."
      pros: "Visual, great for beginners and overview."
    - name: "Stern"
      when_to_use: "Tailing logs from multiple pods."
      pros: "Simple, effective, regex support."

  incident_management:
    - name: "Incident.io / Rootly / FireHydrant"
      when_to_use: "Orchestrating incident response within Slack/Teams."
      pros: "Automates timeline creation, role assignment, and status updates."
      cons: "Requires team adoption of specific chat workflows."
    - name: "Statuspage.io / Cachet"
      when_to_use: "External communication during outages."
      pros: "Keeps users informed, reduces support ticket volume."
      cons: "Requires manual or automated updates to remain useful."

  deployment_safety:
    - name: "ArgoCD / Flux"
      when_to_use: "GitOps-based continuous delivery."
      pros: "Declarative, automated drift correction, history of changes."
      cons: "Steep learning curve for GitOps patterns."
    - name: "Flagger / Argo Rollouts"
      when_to_use: "Automated Canary/Blue-Green deployments."
      pros: "Reduces blast radius of bad deploys via automated analysis."
      cons: "Requires mature metrics/observability to drive decisions."

  infrastructure_as_code:
    - name: "Terraform / OpenTofu"
      when_to_use: "Provisioning cloud infrastructure."
      pros: "Industry standard, huge provider ecosystem, state management."
      cons: "HCL can be restrictive; state file management is critical."
    - name: "Pulumi"
      when_to_use: "Infrastructure using general-purpose languages (TS, Python, Go)."
      pros: "Full power of programming languages (loops, abstractions, testing)."
      cons: "Higher complexity than declarative HCL."

  database_observability:
    - name: "pganalyze / VividCortex"
      when_to_use: "Deep Postgres/MySQL performance tuning."
      pros: "Query-level visibility, execution plans, index recommendations."
      cons: "Specific to database engines; usually a separate paid tool."
    - name: "Percona Monitoring and Management (PMM)"
      when_to_use: "Open-source database monitoring."
      pros: "Comprehensive, supports multiple DB engines, free."
      cons: "Another component to host and manage."

  finops_cost_management:
    - name: "Kubecost"
      when_to_use: "Visibility into Kubernetes spend."
      pros: "Shows cost by namespace/label; helps with chargebacks."
      cons: "Requires constant monitoring to drive actual savings."
    - name: "CloudHealth / Vantage"
      when_to_use: "Enterprise-wide cloud cost management."
      pros: "Cross-cloud, anomaly detection, optimization suggestions."
      cons: "Expensive for large environments."

  service_catalog:
    - name: "Backstage"
      when_to_use: "Centralizing service ownership and documentation."
      pros: "Extremely extensible, industry-leading developer portal."
      cons: "High effort to set up and maintain the 'portal' itself."
    - name: "OpsLevel / Cortex.io"
      when_to_use: "Managed service maturity tracking."
      pros: "Scorecards for reliability, easy to see ownership."
      cons: "SaaS cost, less flexible than Backstage."

  security_observability:
    - name: "Falco"
      when_to_use: "Runtime security for Kubernetes."
      pros: "Deep visibility into container syscalls, real-time alerting."
      cons: "High volume of events; requires tuning."
    - name: "Trivy"
      when_to_use: "Vulnerability scanning in CI/CD."
      pros: "Fast, easy to integrate, scans images and IaC."
      cons: "Can produce many false positives or unfixable alerts."

output:
  - "Recommended stack per domain with rationale, trade-offs, and alternatives; note catalog last_reviewed date"
```

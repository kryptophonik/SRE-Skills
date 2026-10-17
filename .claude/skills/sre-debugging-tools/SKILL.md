---
name: sre-debugging-tools
description: "Reference of read-only debugging workflows, log/metric/trace queries (PromQL, Loki, TraceQL), and system commands for incident investigation. Use while diagnosing a live issue alongside sre-engineer."
---

# SRE Debugging Tools

```yaml
name: sre-debugging-tools
label: "Debugging Tools"
description: >
  Structured debugging workflows, log analysis patterns, metric inspection
  commands, and trace queries for incident investigation.

quick_checks:
  dashboards:
    - "Check Grafana/cloud dashboards for error spikes"
    - "Look for latency increases (p95, p99)"
    - "Check request rate changes"
    - "Verify dependency health"

  recent_changes:
    - "Review recent deployments (last 1-2 hours)"
    - "Check config changes"
    - "Review infrastructure changes"
    - "Check DNS/routing changes"

log_analysis:
  patterns:
    - "Filter by error level: level=error OR level=fatal"
    - "Filter by service: service=checkout"
    - "Filter by time: @timestamp > now-1h"
    - "Filter by status: status>=500"

  tools:
    - "Loki: logcli query '{service=\"api\"} |= \"error\"'"
    - "Elasticsearch: Kibana Discover"
    - "Cloud: CloudWatch Logs Insights, Log Analytics"

metric_queries:
  prometheus:
    - "Error ratio: sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))"
    - "Latency p95: histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))"
    - "Saturation: node_memory_MemAvailable_bytes"

  datadog:
    - "Errors: sum:trace.errors{env:prod}"
    - "Latency: avg:trace.duration{env:prod}"
    - "Saturation: system.mem.available"

trace_analysis:
  queries:
    - "Find slow traces: duration > 1s"
    - "Find error traces: error = true"
    - "Trace by trace ID: trace_id=<id>"

  tools:
    - "Jaeger: UI search and trace inspection"
    - "Tempo: TraceQL queries"
    - "Datadog: Trace search"

correlation_checks:
  - "Cross-reference errors with deploys"
  - "Check if latency correlates with load"
  - "Verify if errors are isolated to one region/zone"
  - "Check if all instances or subset affected"

hypothesis_testing:
  - "A/B test hypotheses with canary deployments"
  - "Use feature flags to toggle suspected code"
  - "Reproduce in staging if possible"
  - "Compare healthy vs unhealthy instances"

quick_commands:
  kubernetes:
    - "kubectl logs -f deployment/app -n prod"
    - "kubectl describe pod <pod-name>"
    - "kubectl get events -n prod --sort-by='.lastTimestamp'"
    - "kubectl top pod -n prod"

  system:
    - "top/htop for CPU/memory"
    - "iotop for I/O"
    - "ss -s / ss -tan for connection stats (replaces deprecated netstat)"
    - "ss -tulpn for listening ports"
    - "tcpdump -i <if> -c 1000 -w /tmp/cap.pcap '<narrow filter>' (see capture_warnings)"

capture_warnings:
  - "tcpdump/strace/perf add CPU and latency overhead on prod hosts; keep captures short (-c count or timeout 30s) and narrowly filtered."
  - "Packet captures and syscall traces can contain secrets, tokens, and customer PII: get approval in prod, store securely, delete after analysis, never paste raw into tickets/chat."
  - "Prefer metrics/logs/traces first; use captures only when they cannot answer the question."

output:
  - "Investigation log: queries run, findings, hypotheses confirmed/ruled out, evidence paths"
```

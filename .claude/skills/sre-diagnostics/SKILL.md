---
name: sre-diagnostics
description: "Read-only investigation and performance diagnosis for a live issue: quick checks, logs/metrics/traces queries, correlation, hypothesis testing, profiling (perf, pprof, py-spy, strace) and bottleneck identification. Runs kubectl/promtool/CLI read commands or MCP query tools (Dynatrace, Grafana, Datadog, Kubernetes) when available; otherwise gives the exact commands for the user to run. Use while diagnosing with sre-engineer."
---

# SRE Diagnostics

Structured, read-only debugging and performance investigation. Follows [sre-safety-gates](../sre-safety-gates/SKILL.md): profiling or capturing on prod needs approval.

For tool-specific queries see `observability-query-cookbook`, `dynatrace-sre`, `prometheus-grafana`, `datadog`, and `k8s-triage`.

## Part 1 — Debugging


## Quick checks

### Dashboards

- Check Grafana/cloud dashboards for error spikes
- Look for latency increases (p95, p99)
- Check request rate changes
- Verify dependency health

### Recent changes

- Review recent deployments (last 1-2 hours)
- Check config changes
- Review infrastructure changes
- Check DNS/routing changes

## Log analysis

### Patterns

- Filter by error level: level=error OR level=fatal
- Filter by service: service=checkout
- Filter by time: @timestamp > now-1h
- Filter by status: status>=500

### Tools

- Loki:

  ```bash
  logcli query '{service="api"} |= "error"'
  ```
- Elasticsearch: Kibana Discover
- Cloud: CloudWatch Logs Insights, Log Analytics

## Metric queries

### Prometheus

- Error ratio:

  ```promql
  sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
  ```
- Latency p95:

  ```promql
  histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
  ```
- Saturation:

  ```promql
  node_memory_MemAvailable_bytes
  ```

### Datadog

- Errors:

  ```text
  sum:trace.<span_name>.errors{env:prod,service:<svc>}.as_count()
  ```
- Latency:

  ```text
  p95:trace.<span_name>{env:prod,service:<svc>}
  ```
- Saturation:

  ```text
  avg:system.mem.usable{env:prod} by {host}
  # or system.mem.pct_usable
  ```

## Trace analysis

### Queries

- Find slow traces: duration > 1s
- Find error traces: error = true
- Trace by trace ID: trace_id=<id>

### Tools

- Jaeger: UI search and trace inspection
- Tempo: TraceQL queries
- Datadog: Trace search, e.g. `service:<svc> env:prod status:error @duration:>1s` via `POST /api/v2/spans/events/search` (read-only; see `datadog`)

## Correlation checks

- Cross-reference errors with deploys
- Check if latency correlates with load
- Verify if errors are isolated to one region/zone
- Check if all instances or subset affected

## Hypothesis testing

- A/B test hypotheses with canary deployments
- Use feature flags to toggle suspected code
- Reproduce in staging if possible
- Compare healthy vs unhealthy instances

## Quick commands

### Kubernetes

```bash
kubectl --context <ctx> -n prod logs -l app.kubernetes.io/name=<app> --prefix --all-containers --since=15m --tail=500
kubectl --context <ctx> -n prod describe pod <pod-name>
kubectl --context <ctx> -n prod events --types=Warning
kubectl --context <ctx> -n prod top pod   # needs metrics-server
```

### System

- top/htop for CPU/memory
- iotop for I/O
- ss -s / ss -tan for connection stats (replaces deprecated netstat)
- ss -tulpn for listening ports
```bash
tcpdump -i <if> -c 1000 -w /tmp/cap.pcap '<narrow filter>'  # see capture_warnings
```

## Capture warnings

- tcpdump/strace/perf add CPU and latency overhead on prod hosts; keep captures short (-c count or timeout 30s) and narrowly filtered.
- Packet captures and syscall traces can contain secrets, tokens, and customer PII: get approval in prod, store securely, delete after analysis, never paste raw into tickets/chat.
- Prefer metrics/logs/traces first; use captures only when they cannot answer the question.

## Part 2 — Performance


## Profiling tools

### CPU

- pprof: Go CPU profiling
- perf: Linux kernel profiling
- Flame graphs: Brendan Gregg's flamegraph.pl
- py-spy: Python profiling
- Java: Java Mission Control, JProfiler

### Memory

- pprof: Go memory profiling
- heap dumps: jmap, gcore
- valgrind: Memory leak detection
- jemalloc: Memory allocator profiling

### I/O

- iotop: I/O monitoring
- iostat -x: Disk statistics
- strace: System call tracing (HIGH overhead: can slow target 10x+; use -c summary, -p <pid> briefly, never long-running in prod without approval)
- bcc/eBPF: Advanced I/O profiling

## Bottleneck identification

### CPU bottleneck

#### Symptoms

- High CPU usage (>80%)
- High load average
- Process queue buildup

#### Investigation

- top/htop to identify process
- perf top for hot functions
- flame graph for call stack analysis

#### Remedies

- Horizontal scaling (add instances)
- Optimize hot code paths
- Caching
- Load shedding

### Memory bottleneck

#### Symptoms

- High memory usage
- OOM kills
- Swap usage

#### Investigation

- free -h for memory overview
- ps aux --sort=-%mem for top consumers
- heap dump for leak analysis

#### Remedies

- Vertical scaling (more RAM)
- Fix memory leaks
- Optimize data structures
- Connection pooling

### I/O bottleneck

#### Symptoms

- High iowait
- Slow disk operations
- Database connection exhaustion

#### Investigation

- iostat -x for disk stats
- iotop for process I/O
- Database query analysis (EXPLAIN, slow query log)

#### Remedies

- Faster storage (SSD, NVMe)
- Query optimization
- Indexing
- Caching layer

### Network bottleneck

#### Symptoms

- High network latency
- Packet loss
- Connection timeouts

#### Investigation

- ping/traceroute for path analysis
- ss -s / ss -tan for connection stats (netstat is deprecated)
- tcpdump -c 1000 with a narrow filter for packet capture (PII risk; see profiling_warnings)

#### Remedies

- Connection pooling
- CDN for static content
- Compression
- Regional deployment

## Tuning guidance

### Application

- Increase worker threads/processes
- Optimize database queries
- Implement caching (Redis, Memcached)
- Use connection pools
- Enable compression

### Database

- Add appropriate indexes
- Partition large tables
- Tune connection pool size
- Enable query cache
- Read replicas for scale

### Infrastructure

- Increase instance size
- Add more instances (horizontal scale)
- Use auto-scaling policies
- Optimize load balancer configuration

## Profiling workflow

### Steps

1. Establish baseline (benchmark)
2. Profile under load
3. Identify hot code paths
4. Optimize top bottlenecks
5. Validate improvement
6. Repeat

## Quick commands

### Profiling

- pprof:

  ```bash
  go tool pprof http://localhost:6060/debug/pprof/profile
  ```
- perf:

  ```bash
  perf record -F 99 -g -p <pid> -- sleep 30 && perf report  # short, sampled
  ```
- py-spy:

  ```bash
  py-spy top --pid <pid>
  ```
- Java:

  ```bash
  jcmd <pid> GC.heap_info
  ```

### Monitoring

- Prometheus: query rate metrics
- Statsd: emit timing metrics
- OpenTelemetry: distributed tracing

## Profiling warnings

- Profilers and tracers add load: use sampling (e.g., -F 99), short windows (<=30-60s), and one host/pod at a time.
- Get approval before profiling or tracing production processes.
- strace and tcpdump output can contain secrets, tokens, and PII: store securely, redact, delete after use.
- Stop immediately if latency or error rate rises during profiling.

## Output

- Investigation log: queries run, findings, hypotheses confirmed/ruled out, evidence paths
- Baseline vs. after metrics (p50/p95/p99, throughput, saturation)
- Identified bottleneck with evidence (profile/flame graph paths)
- Proposed change with risk/reversibility and test results

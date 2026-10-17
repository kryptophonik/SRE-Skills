---
name: sre-performance-tools
description: "Profiling and performance-tuning reference (perf, strace, flame graphs, bottleneck identification) with load and PII warnings. Use when investigating slowness or resource bottlenecks."
---

# SRE Performance Tools

```yaml
name: sre-performance-tools
label: "Performance Tools"
description: >
  Profiling tools, bottleneck identification techniques, and tuning guidance
  for optimizing system performance.

profiling_tools:
  cpu:
    - "pprof: Go CPU profiling"
    - "perf: Linux kernel profiling"
    - "Flame graphs: Brendan Gregg's flamegraph.pl"
    - "py-spy: Python profiling"
    - "Java: Java Mission Control, JProfiler"

  memory:
    - "pprof: Go memory profiling"
    - "heap dumps: jmap, gcore"
    - "valgrind: Memory leak detection"
    - "jemalloc: Memory allocator profiling"

  i_o:
    - "iotop: I/O monitoring"
    - "iostat -x: Disk statistics"
    - "strace: System call tracing (HIGH overhead: can slow target 10x+; use -c summary, -p <pid> briefly, never long-running in prod without approval)"
    - "bcc/eBPF: Advanced I/O profiling"

bottleneck_identification:
  cpu_bottleneck:
    symptoms:
      - "High CPU usage (>80%)"
      - "High load average"
      - "Process queue buildup"
    investigation:
      - "top/htop to identify process"
      - "perf top for hot functions"
      - "flame graph for call stack analysis"
    remedies:
      - "Horizontal scaling (add instances)"
      - "Optimize hot code paths"
      - "Caching"
      - "Load shedding"

  memory_bottleneck:
    symptoms:
      - "High memory usage"
      - "OOM kills"
      - "Swap usage"
    investigation:
      - "free -h for memory overview"
      - "ps aux --sort=-%mem for top consumers"
      - "heap dump for leak analysis"
    remedies:
      - "Vertical scaling (more RAM)"
      - "Fix memory leaks"
      - "Optimize data structures"
      - "Connection pooling"

  i_o_bottleneck:
    symptoms:
      - "High iowait"
      - "Slow disk operations"
      - "Database connection exhaustion"
    investigation:
      - "iostat -x for disk stats"
      - "iotop for process I/O"
      - "Database query analysis (EXPLAIN, slow query log)"
    remedies:
      - "Faster storage (SSD, NVMe)"
      - "Query optimization"
      - "Indexing"
      - "Caching layer"

  network_bottleneck:
    symptoms:
      - "High network latency"
      - "Packet loss"
      - "Connection timeouts"
    investigation:
      - "ping/traceroute for path analysis"
      - "ss -s / ss -tan for connection stats (netstat is deprecated)"
      - "tcpdump -c 1000 with a narrow filter for packet capture (PII risk; see profiling_warnings)"
    remedies:
      - "Connection pooling"
      - "CDN for static content"
      - "Compression"
      - "Regional deployment"

tuning_guidance:
  application:
    - "Increase worker threads/processes"
    - "Optimize database queries"
    - "Implement caching (Redis, Memcached)"
    - "Use connection pools"
    - "Enable compression"

  database:
    - "Add appropriate indexes"
    - "Partition large tables"
    - "Tune connection pool size"
    - "Enable query cache"
    - "Read replicas for scale"

  infrastructure:
    - "Increase instance size"
    - "Add more instances (horizontal scale)"
    - "Use auto-scaling policies"
    - "Optimize load balancer configuration"

profiling_workflow:
  steps:
    - "Establish baseline (benchmark)"
    - "Profile under load"
    - "Identify hot code paths"
    - "Optimize top bottlenecks"
    - "Validate improvement"
    - "Repeat"

quick_commands:
  profiling:
    - "pprof: go tool pprof http://localhost:6060/debug/pprof/profile"
    - "perf: perf record -F 99 -g -p <pid> -- sleep 30 && perf report (short, sampled)"
    - "py-spy: py-spy top --pid <pid>"
    - "Java: jcmd <pid> GC.heap_info"

  monitoring:
    - "Prometheus: query rate metrics"
    - "Statsd: emit timing metrics"
    - "OpenTelemetry: distributed tracing"

profiling_warnings:
  - "Profilers and tracers add load: use sampling (e.g., -F 99), short windows (<=30-60s), and one host/pod at a time."
  - "Get approval before profiling or tracing production processes."
  - "strace and tcpdump output can contain secrets, tokens, and PII: store securely, redact, delete after use."
  - "Stop immediately if latency or error rate rises during profiling."

output:
  - "Baseline vs. after metrics (p50/p95/p99, throughput, saturation)"
  - "Identified bottleneck with evidence (profile/flame graph paths)"
  - "Proposed change with risk/reversibility and test results"
```

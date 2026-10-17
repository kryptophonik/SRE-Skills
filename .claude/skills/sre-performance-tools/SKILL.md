---
name: sre-performance-tools
description: "Profiling and performance-tuning reference (perf, strace, flame graphs, bottleneck identification) with load and PII warnings. Use when investigating slowness or resource bottlenecks."
---

# SRE Performance Tools

Profiling tools, bottleneck identification techniques, and tuning guidance for optimizing system performance.

## Profiling tools

### Cpu

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

### I o

- iotop: I/O monitoring
- iostat -x: Disk statistics
- strace: System call tracing (HIGH overhead: can slow target 10x+; use -c summary, -p <pid> briefly, never long-running in prod without approval)
- bcc/eBPF: Advanced I/O profiling

## Bottleneck identification

### Cpu bottleneck

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

### I o bottleneck

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

- Baseline vs. after metrics (p50/p95/p99, throughput, saturation)
- Identified bottleneck with evidence (profile/flame graph paths)
- Proposed change with risk/reversibility and test results

---
name: sre-diagnostics
description: "Use to investigate a live issue read-only: logs/metrics/traces queries, correlation, hypothesis testing, profiling and bottleneck identification. Gives exact commands when tools are unavailable."
---

# SRE Diagnostics

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Structured, read-only debugging and performance investigation. Follows [sre-safety-gates](../sre-safety-gates/SKILL.md): profiling or capturing on prod needs approval.

For tool-specific queries see `sre-observability-query-cookbook`, `sre-dynatrace`, `sre-prometheus-grafana`, `sre-datadog`, and `sre-k8s-triage`. For database symptoms (slow queries, locks, connection exhaustion, replication lag, vacuum, Redis memory or latency) use `sre-database-triage`, which has the read-only queries per engine.

## Part 1 — Debugging


## Quick checks

### Dashboards

- Check Grafana/cloud dashboards for error spikes
- Look for latency increases (p95, p99)
- Check request rate changes
- Verify dependency health

### Recent changes

- Review recent deployments (last 1-2 hours); the read-only commands are in `sre-change-safety` ("Useful read-only commands")
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
  LOKI_ADDR=<loki-url> logcli query --since=1h --limit=100 '{app="<svc>"} |~ "(?i)error"'
  ```
- Elasticsearch: Kibana Discover
- Cloud: CloudWatch Logs Insights, Log Analytics

## Metric queries

### Prometheus

- Error ratio:

  ```promql
  # if your metrics label the HTTP status as `status` (not `code`), rename the label
  sum by (job) (rate(http_requests_total{job="<svc>",code=~"5.."}[5m]))
  / sum by (job) (rate(http_requests_total{job="<svc>"}[5m]))
  ```
- Latency p95:

  ```promql
  histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket{job="<svc>"}[5m])))
  ```
- Saturation (memory used ratio):

  ```promql
  1 - node_memory_MemAvailable_bytes{instance="<host:port>"} / node_memory_MemTotal_bytes{instance="<host:port>"}
  ```

### Datadog

- Errors:

  ```text
  sum:trace.<span_name>.errors{env:<env>,service:<svc>}.as_count()
  ```
- Latency:

  ```text
  p95:trace.<span_name>{env:<env>,service:<svc>}
  ```
- Saturation:

  ```text
  avg:system.mem.usable{env:<env>} by {host}
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
- Datadog: Trace search, e.g. `service:<svc> env:<env> status:error @duration:>1s` via `POST /api/v2/spans/events/search` (read-only; see `sre-datadog`)

## Correlation checks

- Cross-reference errors with deploys
- Check if latency correlates with load
- Verify if errors are isolated to one region/zone
- Check if all instances or subset affected

## Hypothesis testing

Read-only:

- Compare healthy vs unhealthy instances
- Reproduce in staging if possible

Proposals that change production. Give each one with risk and reversibility, then wait for approval:

**Gate: approval required.**

- Canary test: send a small share of traffic to a build with or without the suspected change and compare error rate and latency. This is a deploy and changes what users get.
- Feature-flag test: turn off the flag behind the suspected code path for a small cohort or everyone. This changes user-facing behavior.

## Quick commands

### Kubernetes

```bash
kubectl --context <ctx> -n <ns> logs -l app.kubernetes.io/name=<app> --prefix --all-containers --since=15m --tail=100 --max-log-requests=5 > /tmp/<app>.log   # summarize the file; do not dump it
kubectl --context <ctx> -n <ns> describe pod <pod-name>
kubectl --context <ctx> -n <ns> events --types=Warning | tail -n 50
kubectl --context <ctx> -n <ns> top pod   # needs metrics-server
```

### System

- top/htop for CPU/memory
- iotop for I/O
- ss -s / ss -tan for connection stats (replaces deprecated netstat)
- ss -tulpn for listening ports
```bash
tcpdump -i <if> -c 1000 -w /tmp/cap.pcap '<narrow filter>'  # see Capture warnings
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
- Database query analysis (plain `EXPLAIN`, slow query log): use `sre-database-triage`. `EXPLAIN ANALYZE` runs the statement for real, so don't run it on writes in prod

#### Remedies

- Faster storage (SSD, NVMe)
- Query optimization
- Indexing (proposal; see Tuning guidance, Database)
- Caching layer

### Network bottleneck

#### Symptoms

- High network latency
- Packet loss
- Connection timeouts

#### Investigation

- ping/traceroute for path analysis
- ss -s / ss -tan for connection stats (netstat is deprecated)
- tcpdump -c 1000 with a narrow filter for packet capture (PII risk; see Profiling warnings)

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

Triage database symptoms with `sre-database-triage` first. Everything below is a **proposal** for after triage, not an incident step.

- Tune connection pool size (application side)
- Read replicas for read scale (capacity work)
- Cache hot reads in the application or Redis. Don't enable the database query cache: MySQL 8.0 removed it ([What Is New in MySQL 8.0](https://dev.mysql.com/doc/refman/8.0/en/mysql-nutshell.html)), and in MariaDB it is off by default, serializes on one mutex and is invalidated by every write to a table ([MariaDB Query Cache](https://mariadb.com/kb/en/query-cache/)), so it hurts write-heavy workloads.
- Add an index, using the online form only. On PostgreSQL a plain `CREATE INDEX` blocks every write to the table until the build finishes, which on a busy primary is an outage ([CREATE INDEX](https://www.postgresql.org/docs/current/sql-createindex.html)).

**Gate: approval required.**

```sql
-- PostgreSQL: no write lock. Run outside BEGIN or any migration-tool transaction (psql autocommit on); it fails inside a transaction block.
CREATE INDEX CONCURRENTLY <index_name> ON <schema>.<table> (<column>);
```

**Gate: approval required.**

```sql
-- MySQL 8.0+ / MariaDB: fails with an error instead of falling back to a locking algorithm
ALTER TABLE <table> ADD INDEX <index_name> (<column>), ALGORITHM=INPLACE, LOCK=NONE;
```

Then check (read-only). A failed `CREATE INDEX CONCURRENTLY` leaves an `INVALID` index that is ignored by queries but still slows every write:

```sql
-- PostgreSQL 12+: build progress, then any invalid indexes left behind.
-- Run each through bash ../sre-database-triage/scripts/db-ro.sh pg -- "<query>" for timeouts and capped output.
SELECT pid, phase, blocks_done, blocks_total FROM pg_stat_progress_create_index LIMIT 20;
SELECT indexrelid::regclass AS invalid_index, indrelid::regclass AS on_table FROM pg_index WHERE NOT indisvalid LIMIT 20;
```

Dropping the invalid index before a retry is a separate write:

**Gate: approval required.**

```sql
-- Run outside BEGIN or any migration-tool transaction; it fails inside a transaction block.
DROP INDEX CONCURRENTLY <index_name>;
```

Caveats: `CONCURRENTLY` takes longer and waits for older transactions to finish first. MySQL/MariaDB online DDL still takes a brief exclusive metadata lock at the start and end, so one long-running transaction on the table stalls it and every query queues behind it; check for long transactions with `sre-database-triage` first. Index builds add I/O and CPU, and on MySQL replicas the build replays afterwards and can cause replication lag. Test with `EXPLAIN` on a staging copy and run off-peak.
- Partitioning an existing large table is design work, not incident remediation: it moves every row and needs a migration plan. Take it to a design review (`sre-engineer`, Design and reliability review) or `sre-capacity-planning`, never into an incident.

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

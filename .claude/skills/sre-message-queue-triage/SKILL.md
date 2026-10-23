---
name: sre-message-queue-triage
description: "Use when Kafka, RabbitMQ or SQS/SNS is backing up or dropping messages: consumer lag, DLQ growth, broker disk/under-replication, redelivery storms, poison-pill messages. Read-only; purge, rebalance and resize are gated."
---

# Message queue triage

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).

Process skills: `sre-incident-command` (roles, severity), `sre-engineer` / `sre-diagnostics` (the wider investigation), `sre-change-safety` (the deploy that preceded it), `sre-remediation-actions`. Managed queues: `sre-aws` (SQS/SNS/MSK), `sre-gcp` (Pub/Sub), `sre-azure` (Service Bus/Event Hubs) for provider-side metrics and health.

## Rules

- **Pin the target.** Every command names the cluster/vhost/queue/topic explicitly — never rely on a default bootstrap server, vhost, or region.
- **Read-only first.** Lag, depth, and consumer-group state are all queryable without touching data. Never consume-and-ack, purge, or republish to "test" something during triage.
- **A DLQ is evidence, not noise.** Read its contents (bounded, non-destructive peek) before proposing a purge — it's often the only record of what actually failed and why.
- **Message bodies may hold customer data or secrets.** Treat any peeked message body the way you'd treat a database query result: redact before pasting into tickets or chat, keep captures out of the repo.
- **Gated actions** (purge a queue/DLQ, pause/resume a consumer, trigger partition reassignment, resize a broker, change retention) appear only under `**Gate: approval required.**`, one command per block, run after evidence capture and a written proposal.
- **Never without explicit approval:** purging any queue or DLQ, force-deleting a topic/queue, triggering partition reassignment or leader election, changing retention/replication settings, scaling a broker cluster, redriving a DLQ back to the source queue in bulk.

## Decision tree by symptom

| Symptom | Likely cause | Check |
|---|---|---|
| Consumer lag growing, processing not keeping up | Slow/stuck consumer, undersized consumer group, downstream dependency slow | consumer-group lag per partition; is the consumer process actually running and healthy (hand off to `sre-k8s-triage`/`sre-diagnostics` if it's app-side) |
| DLQ filling | Poison-pill messages, a bad deploy, schema change, downstream 4xx/5xx | peek DLQ messages (bounded), correlate with recent deploys via `sre-change-safety` |
| Redelivery storm (same message reprocessed repeatedly) | Consumer acking too late / visibility timeout too short, retry loop with no backoff, broker thinks the consumer died | visibility timeout vs. actual processing time (SQS), prefetch/ack settings (RabbitMQ), `max.poll.interval.ms` (Kafka) |
| Broker disk pressure / under-replicated partitions | Retention too long for the ingest rate, a slow/down replica, log segments not compacting | per-broker disk usage, under-replicated partition count (Kafka), queue memory/disk alarms (RabbitMQ) |
| Producers blocking or erroring | Queue/topic at capacity, broker down, network partition | producer error rate and type, broker/cluster health |
| Messages disappearing with no trace | TTL/expiration shorter than expected, a consumer silently acking before processing (SQS `ReceiveMessage` + crash before ack extension) | retention/TTL config, consumer ack pattern |

## Read-only commands

### Kafka

```bash
kafka-consumer-groups.sh --bootstrap-server <broker> --describe --group <group>   # lag per partition
kafka-topics.sh --bootstrap-server <broker> --describe --topic <topic>            # replicas, ISR, under-replicated
kafka-log-dirs.sh --bootstrap-server <broker> --describe --topic-list <topic>     # per-broker disk usage by topic
kafka-broker-api-versions.sh --bootstrap-server <broker>                          # broker reachable at all
```

- `--describe --group` with a lag of 0 but a consumer not making progress on wall-clock time usually means the consumer died and the group hasn't rebalanced yet (check `max.poll.interval.ms` and session timeout).
- Under-replicated partitions (`Isr` shorter than `Replicas` in topic describe) point at a slow or down broker, not the consumer.

### RabbitMQ

```bash
rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers memory
rabbitmqctl list_consumers
rabbitmqctl list_unacked
rabbitmqctl cluster_status
```

- High `messages_unacknowledged` with few `consumers` means consumers are holding messages too long (slow processing, or a prefetch count set too high) — not a queue problem.
- `cluster_status` first if a queue's node is unreachable; node-down behaves very differently from queue backlog.

### SQS / SNS (AWS)

```bash
aws sqs get-queue-attributes --queue-url <url> --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed
aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage --dimensions Name=QueueName,Value=<queue> --start-time <start-ISO8601> --end-time <end-ISO8601> --period 60 --statistics Maximum
aws sqs get-queue-attributes --queue-url <dlq-url> --attribute-names ApproximateNumberOfMessages   # DLQ depth
```

Peek DLQ contents without removing them (bounded, non-destructive — `ReceiveMessage` with a short `VisibilityTimeout` and no delete):

```bash
aws sqs receive-message --queue-url <dlq-url> --max-number-of-messages 5 --visibility-timeout 5
```

- `ApproximateAgeOfOldestMessage` rising with stable `NumberOfMessages` usually means consumers stopped making progress, not an ingest spike.
- A redrive policy's `maxReceiveCount` reached is why a message landed in the DLQ — check the source queue's redrive policy before assuming it's an app bug.

## Fix order when the queue is the symptom, not the cause

Most queue pages during an incident are caused by a consumer-side change: a deploy that slowed processing, a downstream dependency that got slow or started erroring, or a config change to visibility timeout/prefetch. Order:

1. App-side rollback or config fix (gated in `sre-change-safety` / `sre-k8s-safe-remediation`).
2. Scale consumers (more workers/pods) if the backlog is a throughput problem, not a stuck-consumer problem.
3. Pause the producer at the source, if messages are being generated faster than they can ever be drained (propose only — usually a bigger decision than on-call should make alone).
4. DLQ redrive, one message or a small bounded batch at a time, only after the root cause is fixed — redriving into a queue that will just re-fail recreates the storm.
5. Broker/cluster resize or retention change: propose only, usually after the incident, with the queue/platform owner.

**Gate: approval required.**
```bash
aws sqs purge-queue --queue-url <url>
```

**Gate: approval required.**
```bash
rabbitmqctl purge_queue <queue>
```

**Gate: approval required.**
```bash
kafka-reassign-partitions.sh --bootstrap-server <broker> --reassignment-json-file <file>.json --execute
```

## Output

- Target (broker/cluster, vhost/queue/topic, managed or self-hosted), evidence (lag/depth/DLQ counts with timestamps), likely cause and confidence, proposed actions in fix order with risk/reversibility and the approver, verification result (lag trending down, DLQ depth stable or empty).

## Stop and escalate

- A broker/cluster is down or partitioned, not just backed up: escalate to the platform/infra owner immediately rather than triaging queue depth.
- A DLQ redrive would re-trigger the same failure at scale (root cause not yet fixed): don't redrive, report and wait.
- Producers are blocked and there's no safe way to shed load without dropping data: escalate for a product-level decision (which messages can be dropped, if any).

Last reviewed: 2026-10-23

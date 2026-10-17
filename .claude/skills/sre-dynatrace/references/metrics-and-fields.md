# Metric keys and fields

Keys below appear in Dynatrace's own dynatrace-for-ai skills. Units are listed only where the source states them; otherwise "verify". Check a metric exists in your tenant with:

```bash
dtctl query 'fieldsSnapshot metrics, by:{metric.key} | filter metric.key == "dt.host.cpu.usage" | fields field'
```

(Form taken from dt-migration. An empty result means the key is not in your tenant.)

## Services

| Key | Unit | Notes |
|---|---|---|
| `dt.service.request.count` | count | |
| `dt.service.request.failure_count` | count | Error ratio = failure_count / count |
| `dt.service.request.response_time` | microseconds | Divide by 1000 for ms. Percentiles need `rollup:`. |
| `dt.service.request.service_mesh.count` / `.failure_count` / `.response_time` | as above | Service-mesh variants (response_time in microseconds) |
| `dt.service.messaging.publish.count`, `.receive.count`, `.process.count`, `.process.failure_count` | count | Messaging services |

Split by `dt.service.name` or `dt.smartscape.service`.

## Hosts

| Key | Unit | Notes |
|---|---|---|
| `dt.host.cpu.usage` | percent (0-100) | |
| `dt.host.cpu.idle`, `.user`, `.system`, `.iowait` | verify (percent expected) | |
| `dt.host.memory.usage` | verify (percent expected) | |
| `dt.host.memory.used`, `dt.host.memory.avail.bytes` | verify (bytes expected) | |
| `dt.host.disk.used.percent` | percent | |
| `dt.host.net.nic.packets.rx` / `.tx`, `.errors_rx`, `.dropped_rx` | verify | |

## Processes

`dt.process.cpu.usage`, `dt.process.memory.usage`, `dt.process.memory.working_set_size`, `dt.process.handles.file_descriptors_percent_used`, `dt.process.io.bytes_read` / `bytes_written`. Units: verify.

## Kubernetes

| Key | Notes |
|---|---|
| `dt.kubernetes.container.cpu_usage` | Compare with `limits_cpu` for saturation. Unit: verify (millicores expected). |
| `dt.kubernetes.container.limits_cpu`, `.requests_cpu` | Unit: verify |
| `dt.kubernetes.container.cpu_throttled` | |
| `dt.kubernetes.container.memory_working_set`, `.requests_memory` | Unit: verify (bytes expected) |
| `dt.kubernetes.container.restarts` | count |
| `dt.kubernetes.container.oom_kills` | count. Empty when nothing was killed; treat null as 0 only if the workload is reporting. |
| `dt.kubernetes.pods`, `dt.kubernetes.node.pods_allocatable` | |
| `dt.kubernetes.persistentvolumeclaim.used` | |

Common dimensions: `k8s.cluster.name`, `k8s.namespace.name`, `k8s.workload.name`, `k8s.pod.name`.

## Fields by data object

**logs:** `timestamp`, `content`, `loglevel` (not `log.level`), `dt.smartscape.*` and `k8s.*` context fields. Run `fetch logs | limit 1` to see what your tenant adds.

**spans:** `duration` (summarize percentiles without `rollup:`), `dt.service.name`. Others: verify with `fetch spans | limit 1`.

**dt.davis.problems:**
`event.start`, `event.end`, `display_id` (P-xxxxx), `event.name`, `event.description`, `event.category`, `event.status` (`ACTIVE`/`CLOSED`), `dt.davis.is_duplicate`, `dt.davis.is_rootcause`, `dt.davis.affected_users_count`, `smartscape.affected_entities` (array of records; ids via `smartscape.affected_entities[][id]`, types via `[][type]`), `root_cause_entity_id`, `root_cause_entity_name`, `dt.smartscape.service` (may be an array), `k8s.*` (arrays: use `in()`).

**events:** `fetch events` holds deployment, config and Kubernetes events. Field names vary by event kind: verify with `fetch events | limit 1` or `describe`.

## Sources

- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-services/SKILL.md and https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-services/references/service-metrics.md
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-hosts/SKILL.md and https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-hosts/references/host-metrics.md, https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-hosts/references/container-monitoring.md
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-kubernetes/SKILL.md and https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-kubernetes/references/workload-health.md
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-obs-problems/SKILL.md (key fields reference)
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-dql-essentials/SKILL.md (loglevel, rollup)
- https://github.com/Dynatrace/dynatrace-for-ai/blob/main/skills/dt-migration/references/examples.md (fieldsSnapshot metric discovery)
- https://docs.dynatrace.com/docs/analyze-explore-automate/metrics/built-in-metrics-on-grail

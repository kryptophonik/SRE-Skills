# Redis triage (read-only)

Versions: Redis 7.2, 7.4 and 8.x. Valkey 7.2/8.x should behave the same for the commands here, but that is not verified: check on your engine. Last reviewed: 2026-10-17. Sources: SOURCES in [../SKILL.md](../SKILL.md).

Redis runs commands on one thread, so a single expensive diagnostic can become the outage. The wrapper allows only a short list of cheap or bounded commands (`INFO`, `SLOWLOG GET n<=128`, `LATENCY DOCTOR|LATEST|HISTORY`, `MEMORY DOCTOR|STATS`, `MEMORY USAGE <key>` without `SAMPLES`, `CLIENT LIST|INFO`, `SCAN … COUNT n<=1000`, `ROLE`, `DBSIZE`, `TYPE`/`TTL`/`PTTL`/`EXISTS`, `OBJECT ENCODING|FREQ|IDLETIME`, `CLUSTER INFO|NODES|SHARDS`, `LASTSAVE`), sets a 5 s connect timeout (`-t 5`, only when `redis-cli --help` lists `-t`: it is new in redis-cli 7.4, and 7.2 rejects it; the overall 15 s kill applies either way), caps output, and turns a server error (`NOPERM`, `WRONGPASS`, `ERR`; redis-cli itself exits 0 on them) into exit code 1. `CONFIG` is not allowed at all: `CONFIG GET` can return `requirepass`/`masterauth`. Commands this skill never runs are listed only in [destructive-commands.md](destructive-commands.md).

```bash
REDIS_HOST=<host> REDIS_PORT=6379 REDIS_USER=<ro-user> REDIS_TLS=1 bash scripts/db-ro.sh redis -- INFO server
```

Password: export `REDISCLI_AUTH` from your secret store (redis-cli reads it; the docs recommend it over `-a`). Never put the password on the command line. Prefer a replica for anything that walks the keyspace.

## Access (one-time setup by the cache owner, through normal change review)

`INFO`, `SLOWLOG`, `LATENCY` and `CLIENT LIST` are in the `@dangerous`/`@admin` ACL categories, so a category-based "read-only" user (`+@read`) cannot run them, and `+@read` would also allow reading values. Grant the exact commands instead:

```text
ACL SETUSER sre-ro on ><from-your-secret-store> resetkeys resetchannels -@all +info +ping +role +dbsize +time +lastsave +slowlog|get +slowlog|len +latency|doctor +latency|latest +latency|history +memory|doctor +memory|stats +memory|usage +client|list +client|info +scan +type +ttl +pttl +exists +object|encoding +object|freq +object|idletime +cluster|info +cluster|nodes +cluster|shards +readonly +strlen +hlen +llen +scard +zcard +xlen %R~*
```

- `%R~*` gives read-only key permission for `SCAN`/`TYPE`/`TTL`/`MEMORY USAGE`. No value-reading commands are granted; `STRLEN`/`HLEN`/`LLEN`/`SCARD`/`ZCARD`/`XLEN` return sizes only and are what `redis-cli --bigkeys` uses. `READONLY` is needed because redis-cli 8 sends it before `--bigkeys`/`--memkeys`.
- No `+config|get`: it returns any parameter, including `requirepass` and `masterauth`. `maxmemory_policy` is in `INFO memory`.
- Residual risk: `CLIENT LIST` shows client addresses and names, and `SLOWLOG GET` returns command arguments (key names and values, i.e. customer data). Treat both outputs as sensitive.
- ElastiCache and MemoryDB manage users through their own APIs (user and user-group resources with an access string). Memorystore for Redis has no ACL users at all (ACL is blocked): the AUTH string is full access, so the wrapper is the only guard there; prefer Cloud Monitoring metrics. See Managed services.

## 1. Latency and slow commands

```bash
bash scripts/db-ro.sh redis -- SLOWLOG GET 25
bash scripts/db-ro.sh redis -- SLOWLOG LEN
bash scripts/db-ro.sh redis -- LATENCY LATEST
bash scripts/db-ro.sh redis -- LATENCY DOCTOR
bash scripts/db-ro.sh redis -- INFO commandstats
bash scripts/db-ro.sh redis -- INFO stats
```

- `SLOWLOG` times are **microseconds**. Defaults: `slowlog-log-slower-than` 10000 (10 ms), `slowlog-max-len` 128. Entries contain the command arguments (key names and values): customer data, redact before sharing.
- `SLOWLOG` records execution time only (not network or queueing). Large `O(N)` commands on big keys (`HGETALL`, `SMEMBERS`, `LRANGE 0 -1`, `ZRANGE` on huge sets) and Lua scripts are the usual culprits.
- `LATENCY DOCTOR` only has data when the latency monitor is on (`latency-monitor-threshold` > 0; off by default); it says so when the monitor is off. Turning it on is a config change (gated, low risk, below); on Memorystore it cannot be set.
- `INFO stats`: `instantaneous_ops_per_sec`, `rejected_connections`, `expired_keys`, `evicted_keys`, `keyspace_hits/misses`.
- Client-side latency: `--latency` measures round trips from where you run it (it sends `PING`s, which the ACL allows). It runs until stopped, so bound it (add `--tls` only for TLS endpoints; macOS without `timeout`: press Ctrl-C after 10 s):

```bash
timeout 10 redis-cli -h <host> -p <port> --user <ro-user> --tls --no-auth-warning --latency
```

In the gated `redis-cli` lines, keep `--tls` for TLS endpoints (ElastiCache/MemoryDB with in-transit encryption, Azure, Memorystore with TLS; add `--cacert <ca.pem>` if the CA is not in the system store) and drop it for plain-TCP self-managed servers.

Proposal: enable the latency monitor (low risk, reversible: set it back to 0). Not available on Memorystore; on ElastiCache/MemoryDB use the parameter group.

**Gate: approval required.**
```bash
# admin user, not sre-ro; approval names the instance
redis-cli -h <host> -p <port> --user <admin> --tls --no-auth-warning CONFIG SET latency-monitor-threshold 100
```

## 2. Memory and eviction

```bash
bash scripts/db-ro.sh redis -- INFO memory
bash scripts/db-ro.sh redis -- MEMORY DOCTOR
bash scripts/db-ro.sh redis -- INFO keyspace
bash scripts/db-ro.sh redis -- MEMORY USAGE <key>
```

- `maxmemory_policy` and `maxmemory` are in `INFO memory`.
- `used_memory` near `maxmemory` with `evicted_keys` rising: the cache is full and evicting (expected for `allkeys-*` policies, data loss for a store that should not evict). With `noeviction`, writes fail with OOM errors while reads still work.
- `mem_fragmentation_ratio` mixes fragmentation with other process overhead; `allocator_frag_ratio` is the real external fragmentation number (redis.io `INFO`).
- `INFO clients` `connected_clients` and big output buffers (`CLIENT LIST` `omem`) can eat memory too (section 3).
- Finding big keys: sample with `SCAN` and `MEMORY USAGE <key>`, a few hundred keys at a time. The wrapper refuses `MEMORY USAGE ... SAMPLES`: `SAMPLES 0` walks every element of the key on the main thread.

```bash
bash scripts/db-ro.sh redis -- SCAN 0 MATCH '<prefix>:*' COUNT 100
```

A full keyspace walk with `redis-cli --bigkeys` or `--memkeys` is gated: it SCANs every key (plus `MEMORY USAGE` per key for `--memkeys`). Run it off-peak, on a replica, with `-i 0.1` (sleep 0.1 s per 100 SCAN calls).

**Gate: approval required.**
```bash
# on a REPLICA (check: bash scripts/db-ro.sh redis -- ROLE), off-peak; output may contain key names (customer data)
redis-cli -h <replica-host> -p <port> --user <ro-user> --tls --no-auth-warning --memkeys -i 0.1
```

Proposal: change the eviction policy or memory limit. Medium risk (wrong policy evicts data the app needs), reversible by setting it back; lost on restart unless persisted. Self-managed only; managed services use their parameter APIs (below).

**Gate: approval required.**
```bash
redis-cli -h <host> -p <port> --user <admin> --tls --no-auth-warning CONFIG SET maxmemory-policy <policy>
```

## 3. Connections and clients

```bash
bash scripts/db-ro.sh redis -- INFO clients
bash scripts/db-ro.sh redis -- CLIENT LIST TYPE normal
```

- `connected_clients` near `maxclients`, or `rejected_connections` rising in `INFO stats`: connection storm or leak from one app; group `CLIENT LIST` by `addr`/`name`. Fix the client pool first.
- `blocked_clients` high: clients waiting in `BLPOP`/`XREAD` etc.; usually normal.
- A client with a huge `omem`/`tot-mem` (a slow pub/sub subscriber, a replica that cannot keep up) is an eviction and OOM risk.

Proposal: disconnect one client by its id (from `CLIENT LIST`). Never by address pattern or by type, which can disconnect replicas or every app at once.

**Gate: approval required.**
```bash
redis-cli -h <host> -p <port> --user <admin> --tls --no-auth-warning CLIENT KILL ID <client-id>
```

Verify: `INFO clients` and the app's error rate. If the app reconnects and the problem returns, stop and fix the client side.

## 4. Replication and persistence

```bash
bash scripts/db-ro.sh redis -- ROLE
bash scripts/db-ro.sh redis -- INFO replication
bash scripts/db-ro.sh redis -- INFO persistence
```

- Replica: `master_link_status:down`, a growing `master_last_io_seconds_ago`, or `master_sync_in_progress:1` (full resync, which costs the primary a fork and memory).
- Primary: compare `master_repl_offset` with each `slaveN` `offset` for byte lag.
- `rdb_last_bgsave_status:err` or `aof_last_write_status:err` usually means disk full or fork failure (memory overcommit); `latest_fork_usec` shows how long the last fork stalled the server.

## 5. CPU

`INFO cpu` (`used_cpu_sys`, `used_cpu_user` deltas) plus `INFO commandstats` (`usec_per_call`) show which commands burn the main thread. A single hot key or a script loop shows as one command type dominating `commandstats`; a big key shows in `SLOWLOG`.

```bash
bash scripts/db-ro.sh redis -- INFO cpu
```

## Managed services

| | ElastiCache (Redis OSS / Valkey) and MemoryDB | Memorystore for Redis | Azure Cache for Redis (legacy: all tiers retire by 2028-09-30, Enterprise by 2027-03-31; migrate to Azure Managed Redis) |
|---|---|---|---|
| Blocked commands (besides several on the never-run list) | `CONFIG` (all), persistence and replication-control commands, `ACL SETUSER`/`LOAD`/`SAVE`/`DELUSER`, cluster slot commands. **Serverless** caches also block `SLOWLOG`, `LATENCY`, `MEMORY`, `OBJECT`, `CLIENT LIST`/`INFO`/`KILL`, `LASTSAVE`, `FUNCTION` and `SCRIPT KILL` (plus several never-run commands), so sections 1–3 mostly fail there: use `INFO` and the CloudWatch metrics below | `CONFIG`, `CLIENT`, `OBJECT`, `COMMAND`, `CLUSTER`, `ACL` (no ACL users: the AUTH string is full access), persistence commands; `LATENCY` works but `latency-monitor-threshold` cannot be set | `ACL`, `CLUSTER` writes, `CONFIG`, `MIGRATE`, `PSYNC`, `REPLCONF`, `SYNC`, and the persistence, replication-control and debug commands on the never-run list |
| Config changes | parameter group (`aws elasticache modify-cache-parameter-group`), gated | `gcloud redis instances update <instance> --region=<REGION> --update-redis-config maxmemory-policy=<policy>`, gated | portal / `az redis update`, gated |
| Metrics | CloudWatch `EngineCPUUtilization`, `DatabaseMemoryUsagePercentage`, `Evictions`, `CurrConnections`; serverless: `ElastiCacheProcessingUnits`, `BytesUsedForCache`, `SuccessfulReadRequestLatency`/`SuccessfulWriteRequestLatency` | Cloud Monitoring `redis.googleapis.com/stats/memory/usage_ratio`, `.../clients/connected` | Azure Monitor `usedmemorypercentage`, `serverLoad`, `evictedkeys` |
| Failover | ElastiCache `aws elasticache test-failover`; MemoryDB `aws memorydb failover-shard` (both testing APIs, below) | `gcloud redis instances failover <instance> --region=<REGION>` (Standard tier) | `az redis force-reboot --reboot-type PrimaryNode` (Standard/Premium: the replica takes over) |

Because these services rename or block commands, a refused or "unknown command" answer is expected, not a sign of a broken instance: switch to the provider's metrics.

Proposal: managed failover. Last resort; check replication health first (section 4), evidence captured, IC and cache owner approve. Writes in flight during the switch can be lost. Use only the one block for your platform; each is a separate approval.

ElastiCache and MemoryDB: AWS documents these as APIs for **testing** automatic failover, not as an operational tool, and may block them during large-scale events; ElastiCache allows at most 15 shards (node groups) per rolling 24 h. Prefer the service's automatic failover and an AWS support case; use them only with IC and owner approval.

ElastiCache (one shard):

**Gate: approval required.**
```bash
aws elasticache test-failover --profile <profile> --region <region> --replication-group-id <replication-group> --node-group-id <node-group>
```

MemoryDB (one shard):

**Gate: approval required.**
```bash
aws memorydb failover-shard --profile <profile> --region <region> --cluster-name <cluster> --shard-name <shard>
```

Memorystore for Redis (Standard tier; keep the default data-protection mode, never add a force-data-loss mode without its own explicit approval):

**Gate: approval required.**
```bash
gcloud redis instances failover <instance> --region=<REGION> --project=<PROJECT_ID>
```

Azure Cache for Redis (Standard/Premium; reboots the primary node so the replica takes over; data loss is possible):

**Gate: approval required.**
```bash
az redis force-reboot --subscription <subscription-id> --resource-group <rg> --name <cache> --reboot-type PrimaryNode
```

Verify: `ROLE` on the new primary, replicas reconnect (`INFO replication`), client errors recover.

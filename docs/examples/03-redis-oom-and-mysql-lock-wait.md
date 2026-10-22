# Example 3: Redis out of memory, plus a MySQL lock wait

**Skill:** [sre-database-triage](../../.claude/skills/sre-database-triage/SKILL.md), using [references/redis.md](../../.claude/skills/sre-database-triage/references/redis.md) and [references/mysql.md](../../.claude/skills/sre-database-triage/references/mysql.md).

> **What's real here.** Command output comes from a lab run on 2026-10-22 with Redis 7.4.11 (`redis:7.4`, redis-cli 7.4) and MySQL 8.4.13 (`mysql:8.4`, MariaDB 11.8 client). Long output is trimmed where you see `...`, and client addresses are replaced with `<app-host>`. Diagnoses and proposals are **written in the skill's format** by the operator. They show the shape of the answer, not a word-for-word model reply.

![Redis OOM triage, proposal and verification](images/03-redis-oom.png)

## What this shows

- Telling "the store is full" apart from "a command is slow", using only read-only commands.
- The Redis allowlist: `CONFIG`, `GET` and `MEMORY USAGE ... SAMPLES 0` are refused.
- Why the skill won't propose `allkeys-lru` when the data is sessions.
- A MySQL lock wait traced to an idle transaction, then a gated `KILL`.

## Lab setup (Docker only)

Put the admin password in a config file. Don't pass it as a command-line flag (it would show up in `ps`):

```console
$ printf 'requirepass %s\nmaxmemory 4mb\nmaxmemory-policy noeviction\nslowlog-log-slower-than 5000\n' "$(cat admin.pw)" > redis-lab.conf && chmod 600 redis-lab.conf
$ docker run -d --name redis-lab -p 127.0.0.1:56379:6379 -v "$PWD/redis-lab.conf:/usr/local/etc/redis/redis.conf:ro" redis:7.4 redis-server /usr/local/etc/redis/redis.conf
```

As admin, create the read-only user exactly as in redis.md "Access": `ACL SETUSER sre-ro on ><from-your-secret-store> resetkeys resetchannels -@all +info +ping +role ... %R~*`. Then point the wrapper at the lab:

```console
$ export REDIS_HOST=127.0.0.1 REDIS_PORT=56379 REDIS_USER=sre-ro REDISCLI_AUTH=<sre-ro password>
```

## What broke

A session service writes ~1 KB values with no TTL until the 4 MB limit:

```console
$ python3 -c 'for i in range(1, 8001): print(f"SET session:{i} " + "x" * 1000)' > load.txt
$ REDISCLI_AUTH=<admin password> redis-cli -h 127.0.0.1 -p 56379 --no-auth-warning < load.txt | sort | uniq -c | sort -rn | head -3
   5294 OOM command not allowed when used memory > 'maxmemory'.
   2706 OK
$ REDISCLI_AUTH=<admin password> redis-cli -h 127.0.0.1 -p 56379 --no-auth-warning SET cart:1 checkout-in-progress
OOM command not allowed when used memory > 'maxmemory'.
```

A CPU-heavy Lua script (`EVAL "local s=0 for i=1,3000000 do s=s+i end return s" 0`) also runs twice.

## What you'd type

> Redis at 127.0.0.1:56379 is rejecting writes with OOM errors and checkout is failing. Triage it.

## What the skill ran, and why

**1. Role and memory.** It checks this is the primary, then compares used memory with the limit and policy:

```console
$ bash scripts/db-ro.sh redis -- INFO memory | grep -E '^(used_memory_human|maxmemory_human|maxmemory_policy|mem_fragmentation_ratio):'
target: redis 127.0.0.1:56379 user=sre-ro tls=0
used_memory_human:4.06M
maxmemory_human:4.00M
maxmemory_policy:noeviction
mem_fragmentation_ratio:3.43
$ bash scripts/db-ro.sh redis -- INFO errorstats
errorstat_OOM:count=5295
$ bash scripts/db-ro.sh redis -- INFO keyspace
db0:keys=6001,expires=0,avg_ttl=0,subexpiry=0
$ bash scripts/db-ro.sh redis -- MEMORY USAGE session:17
1080
```

`MEMORY DOCTOR` gave no signal here. It declines to analyse instances under 5 MB ("Hi Sam, this instance is empty or is using very little memory..."), so the reference says to read `INFO memory` and `errorstats` instead.

**2. Slow commands, a separate problem:**

```console
$ bash scripts/db-ro.sh redis -- SLOWLOG GET 25
1
1792692551
17985
EVAL
local s=0 for i=1,3000000 do s=s+i end return s
...
$ bash scripts/db-ro.sh redis -- LATENCY DOCTOR
I'm sorry, Dave, I can't do that. Latency monitoring is disabled in this Redis instance. ...
```

**3. The guards hold:**

```console
$ bash scripts/db-ro.sh redis -- CONFIG GET maxmemory
REFUSED: Redis command 'CONFIG' is not on the read-only allowlist
[exit 3]
$ bash scripts/db-ro.sh redis -- MEMORY USAGE session:17 SAMPLES 0
REFUSED: MEMORY USAGE <key> only (no SAMPLES: SAMPLES 0 walks every element)
[exit 3]
$ redis-cli -h 127.0.0.1 -p 56379 --user sre-ro --no-auth-warning GET session:1
NOPERM User sre-ro has no permissions to run the 'get' command
```

Then `db-snapshot.sh redis ./incident/redis-oom/db-t0` saved the evidence (14 ok, 0 skipped).

## Diagnosis and approval stop (written in the skill's format)

```text
Finding:   used_memory 4.06M > maxmemory 4.00M, policy noeviction, evicted_keys 0, errorstat_OOM 5295.
           Reads work; every write fails. 6001 keys, session:* ~1080 bytes each, no TTLs (expires=0).
           Separately: 2x EVAL Lua loop at 17.5-18.0 ms each; latency monitor is off.
Cause:     session-svc writes sessions without a TTL into a 4 MB noeviction instance.
Fix order: 1) app-side: set a TTL on session:* writes (session-svc owner)
           2) config: raise the limit. Do NOT switch to allkeys-* (sessions are a store:
              eviction would log users out).
Proposed (NOT RUN), admin user, not sre-ro:
  A) CONFIG SET maxmemory 16mb                   Risk med  Reversible yes (4mb)  Lost on restart
  B) CONFIG SET latency-monitor-threshold 100    Risk low  Reversible yes (0)
>>> APPROVAL REQUIRED for A and B separately; each names this instance. <<<
```

## Approved action and verification

```console
$ REDISCLI_AUTH=<admin password> redis-cli -h 127.0.0.1 -p 56379 --no-auth-warning CONFIG SET maxmemory 16mb
OK
$ REDISCLI_AUTH=<admin password> redis-cli -h 127.0.0.1 -p 56379 --no-auth-warning CONFIG SET latency-monitor-threshold 100
OK
$ REDISCLI_AUTH=<admin password> redis-cli -h 127.0.0.1 -p 56379 --no-auth-warning SET cart:1 checkout-in-progress
OK
$ bash scripts/db-ro.sh redis -- INFO memory | grep -E '^(used_memory_human|maxmemory_human):'
used_memory_human:4.32M
maxmemory_human:16.00M
$ bash scripts/db-ro.sh redis -- LATENCY LATEST    # after one more heavy EVAL
command
1792692583
173
173
```

## Bonus: MySQL lock wait

![MySQL lock wait and gated KILL](images/03-mysql-lock-wait.png)

Setup: `docker run -d --name mysql-lab -p 127.0.0.1:53306:3306 -e MYSQL_ROOT_PASSWORD_FILE=/run/pw -v "$PWD/mysql-root.pw:/run/pw:ro" mysql:8.4`. Then create `sre_ro` as in mysql.md "Access" and a `shop.orders` table. Credentials go in `chmod 600` option files, never in `-p`. An idle transaction holds row 1, and a second update waits:

```console
$ (echo "BEGIN; UPDATE shop.orders SET status='refunding' WHERE id=1;"; sleep 120) | mysql --defaults-file=app.cnf &
$ mysql --defaults-file=app.cnf -e "UPDATE shop.orders SET status='shipped' WHERE id=1" &
$ export MYSQL_DEFAULTS_FILE=$PWD/sre_ro.cnf
$ bash scripts/db-ro.sh mysql -- "SELECT wait_started, wait_age, locked_table, locked_type, waiting_pid, ... FROM sys.x\$innodb_lock_waits ... LIMIT 20"
wait_started         wait_age  locked_table     locked_type  waiting_pid  waiting_query                                       blocking_pid  blocking_query  blocking_trx_age
2026-10-22 18:10:41  00:00:08  `shop`.`orders`  RECORD       11           UPDATE shop.orders SET status='shipped' WHERE id=1  10            NULL            00:00:09
```

`blocking_query NULL` with an open transaction means the blocker is idle, not busy. The proposal (written in the skill's format) was `KILL 10;` as an operator account, risk high, not reversible (its transaction rolls back), `>>> APPROVAL REQUIRED: names thread 10 only. <<<`. After approval:

```console
$ mysql --defaults-file=operator.cnf -e 'KILL 10'
$ bash scripts/db-ro.sh mysql -- "SELECT waiting_pid, blocking_pid FROM sys.x\$innodb_lock_waits LIMIT 20"
$ mysql --defaults-file=app.cnf -N -e 'SELECT id,status FROM shop.orders WHERE id=1'
1	shipped
```

The lock-wait query returned no rows: nothing is waiting any more.

## Cleanup

```console
$ docker rm -f redis-lab mysql-lab
$ rm -f redis-lab.conf load.txt *.cnf *.pw && rm -rf ./incident/redis-oom
```

## What to take from this

- `noeviction` plus no TTLs is a store that fills up. Raising the limit buys time. The fix is a TTL in the app.
- Pick eviction policy by what the data is. For sessions, evicting means logging users out.
- Check the latency monitor is on before an incident. `LATENCY DOCTOR` has nothing to say until it is.
- For MySQL, `sys.x$innodb_lock_waits` names the blocker. A `NULL` blocking query means an idle transaction: fix the app that left it open.

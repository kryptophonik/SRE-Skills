# Example 2: Postgres lock chain and connection exhaustion

**Skill:** [sre-database-triage](../../.claude/skills/sre-database-triage/SKILL.md), using [references/postgres.md](../../.claude/skills/sre-database-triage/references/postgres.md) and its scripts `db-ro.sh` (read-only wrapper) and `db-snapshot.sh` (evidence).

> **What's real here.** Command output comes from a lab run on 2026-10-22 with PostgreSQL 17.11 (`postgres:17` image) and psql 17. Long output is trimmed where you see `...`, and client addresses are replaced with `<app-host>`. Diagnoses and proposals are **written in the skill's format** by the operator. They show the shape of the answer, not a word-for-word model reply.

![Lock chain, proposal and terminate](images/02-postgres-lock-chain.png)

## What this shows

- Finding the session at the head of a lock chain, rather than killing whichever query looks slow.
- `db-ro.sh` refusing writes, even when the role is already read-only.
- Two approval stops: one for a single pid, one for a filtered group of leaked sessions.
- A real catch from this lab: a filtered terminate matched 0 rows until the operator role could read other users' session state.

## Lab setup (Docker only)

Start Postgres with a small connection limit so exhaustion is easy to reach. Put a password you generate in a file (never type it on the command line).

```console
$ docker run -d --name pg-lab -p 127.0.0.1:55432:5432 -e POSTGRES_PASSWORD_FILE=/run/pw -v "$PWD/pw:/run/pw:ro" postgres:17 \
    -c max_connections=20 -c reserved_connections=3 -c superuser_reserved_connections=3 -c log_lock_waits=on
```

Create the roles from the reference: a read-only triage role and a separate operator role. Run this as `postgres`, one statement at a time (`CREATE DATABASE` can't share a transaction):

```sql
CREATE ROLE sre_ro LOGIN CONNECTION LIMIT 3;
GRANT pg_monitor, pg_use_reserved_connections TO sre_ro;
ALTER ROLE sre_ro SET default_transaction_read_only = on;
ALTER ROLE sre_ro SET statement_timeout = '5s';
ALTER ROLE sre_ro SET lock_timeout = '1s';
ALTER ROLE sre_ro SET idle_in_transaction_session_timeout = '10s';
CREATE ROLE shop LOGIN;
CREATE ROLE ops LOGIN;
GRANT pg_signal_backend, pg_read_all_stats TO ops;
CREATE DATABASE shop OWNER shop;
```

As `shop`, in database `shop`:

```sql
CREATE TABLE orders (id int PRIMARY KEY, customer_id int, status text, total numeric(10,2), updated_at timestamptz DEFAULT now());
INSERT INTO orders SELECT g, g % 500, 'paid', (g % 97) + 0.99 FROM generate_series(1,50000) g;
CREATE TABLE customers (id int PRIMARY KEY, name text);
INSERT INTO customers SELECT g, 'customer-'||g FROM generate_series(1,500) g;
```

Set passwords with `ALTER ROLE ... PASSWORD` from a file, put them in a `chmod 600` pgpass file, and point the wrapper at the lab:

```console
$ export PGPASSFILE=$PWD/pgpass PGHOST=localhost PGPORT=55432 PGDATABASE=shop PGUSER=sre_ro
```

## What broke (part 1): a forgotten transaction holds a row lock

```console
$ (echo "BEGIN; UPDATE orders SET status='refunding' WHERE id=42;"; sleep 900) | PGAPPNAME=refund-worker PGUSER=shop psql -X -d shop &
$ PGAPPNAME=checkout-api PGUSER=shop psql -X -d shop -c "UPDATE orders SET status='shipped' WHERE id=42" &   # run twice
```

## What you'd type

> Checkout updates on the shop database (localhost:55432) are hanging. Find out why.

## What the skill ran, and why

**1. Confirm the target and the role.** Every `db-ro.sh` call prints the target first, so a wrong host is obvious.

```console
$ bash scripts/db-ro.sh pg -- "SELECT version(), current_user, pg_is_in_recovery() AS is_replica LIMIT 1"
target: pg host=localhost port=55432 db=shop user=sre_ro
 PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2) on x86_64-pc-linux-gnu, ... | sre_ro       | f
```

**2. Who is waiting, and on whom** (`pg_blocking_pids`, section 2 of the reference):

```console
$ bash scripts/db-ro.sh pg -- "SELECT pid, blocked_by, usename, application_name, wait_event, now() - query_start AS waiting, ... LIMIT 50"
 pid | blocked_by | usename | application_name |  wait_event   |     waiting     |                     query
-----+------------+---------+------------------+---------------+-----------------+------------------------------------------------
  71 | {70}       | shop    | checkout-api     | transactionid | 00:00:20.122768 | UPDATE orders SET status='shipped' WHERE id=42
  72 | {71}       | shop    | checkout-api     | tuple         | 00:00:20.115117 | UPDATE orders SET status='shipped' WHERE id=42
$ bash scripts/db-ro.sh pg -- "SELECT pid, usename, application_name, state, now() - xact_start AS xact_age, ... LIMIT 20"
 pid | usename | application_name |        state        |    xact_age     |                       query
-----+---------+------------------+---------------------+-----------------+---------------------------------------------------
  70 | shop    | refund-worker    | idle in transaction | 00:00:21.200397 | UPDATE orders SET status='refunding' WHERE id=42;
  71 | shop    | checkout-api     | active              | 00:00:20.200938 | UPDATE orders SET status='shipped' WHERE id=42
```

**3. The wrapper won't run writes**, so the assistant can't "just fix it":

```console
$ bash scripts/db-ro.sh pg -- "SELECT pg_terminate_backend(1)"
REFUSED: function PG_TERMINATE_BACKEND is not read-only (gated actions: references/postgres.md)
[exit 3]
$ bash scripts/db-ro.sh pg -- "UPDATE orders SET status='x' WHERE id=1"
REFUSED: first keyword 'UPDATE' is not SELECT/WITH/SHOW/EXPLAIN
[exit 3]
```

**4. Save evidence before any gated action:**

```console
$ bash scripts/db-snapshot.sh pg ./incident/pg-lock/db-t0
[skipped: top-statements failed, see ./incident/pg-lock/db-t0/17-top-statements.txt]
snapshot: ./incident/pg-lock/db-t0 (16 ok, 1 skipped)
```

The skipped file is expected: `pg_stat_statements` isn't installed in this lab.

## Diagnosis and approval stop (written in the skill's format)

```text
Finding:   lock chain 72 -> 71 -> 70. Head pid 70 (shop, refund-worker) is "idle in transaction"
           after UPDATE orders ... id=42 and is not blocked itself. Deadlocks 0.
Cause:     refund-worker opened a transaction and never committed (app bug). Confidence high.
Fix order: 1) app-side: fix or restart refund-worker  2) cancel: n/a (no running statement)
           3) terminate the one head pid.
Proposed (NOT RUN), as operator role ops, NOT through db-ro.sh:
  SELECT pg_terminate_backend(70, 5000);
  Risk: high   Reversible: no (refund-worker's uncommitted UPDATE is lost and must be retried)
  Verify: blocked query -> 0 rows
>>> APPROVAL REQUIRED: names pid 70 only. A new pid needs a new approval. <<<
```

## Approved action and verification

```console
$ PGUSER=ops psql -X -d shop -c 'SELECT pg_terminate_backend(70, 5000)'
 pg_terminate_backend
----------------------
 t
$ bash scripts/db-ro.sh pg -- "SELECT pid, blocked_by, ... LIMIT 50"
(0 rows)
$ PGUSER=shop psql -X -d shop -Atc "SELECT id, status FROM orders WHERE id=42"
42|shipped
```

## What broke (part 2): a leaky pool holds every normal slot

13 app sessions open a transaction and never finish. With 20 slots minus 3 + 3 reserved, only 14 are left for normal users:

```console
$ for i in $(seq 13); do (echo "BEGIN; SELECT count(*) FROM orders WHERE customer_id=$i;"; sleep 600) | PGAPPNAME=orders-api PGUSER=shop psql -X -q -d shop >/dev/null & done
$ PGAPPNAME=checkout-api PGUSER=shop psql -X -d shop -c 'select 1'
connection to server at "localhost" (127.0.0.1), port 55432 failed: FATAL:  remaining connection slots are reserved for roles with privileges of the "pg_use_reserved_connections" role
```

![Connection exhaustion and the operator-role finding](images/02-postgres-conn-exhaustion.png)

The triage role still gets in through a reserved slot (`pg_use_reserved_connections`):

```console
$ bash scripts/db-ro.sh pg -- "SELECT state, wait_event_type, usename, application_name, count(*) AS n FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1, 2, 3, 4 ORDER BY n DESC LIMIT 50"
        state        | wait_event_type | usename | application_name | n
---------------------+-----------------+---------+------------------+----
 idle in transaction | Client          | shop    | orders-api       | 13
 active              |                 | sre_ro  | sre-db-ro        |  1
```

Before proposing a filtered terminate, the skill previews how many sessions the filter matches. The reference uses 5 minutes, which matched 0 of these young sessions; the lab used 10 seconds:

```console
$ bash scripts/db-ro.sh pg -- "SELECT count(*) FROM pg_stat_activity WHERE ... AND application_name = 'orders-api' AND state = 'idle in transaction' AND now() - state_change > interval '10 seconds' LIMIT 1"
 count
-------
    13
```

The proposal (written in the skill's format) names the app, the user and the previewed count, then stops with `>>> APPROVAL REQUIRED: names app orders-api, user shop, count 13. <<<`.

## The catch: the operator role couldn't see what to kill

In the first run, `ops` had only `pg_signal_backend`, and the approved terminate matched **0 rows**. Postgres hides other users' `state` from roles without `pg_read_all_stats`, so the filter never matched. The reference now says to grant both (that's the setup above). A re-run on a fresh container (5 leaked sessions) shows both sides:

```console
$ -- as ops (pg_signal_backend + pg_read_all_stats): approved terminate
 pid | pg_terminate_backend
-----+----------------------
  93 | t
 101 | t
 110 | t
 118 | t
 126 | t
(5 rows)
$ -- verify
 idle_in_txn
-------------
           0
$ -- control: REVOKE pg_read_all_stats FROM ops, same terminate
(0 rows)
```

In the original run, after the grant, the same statement ended all 13 sessions. Then `client_conns` dropped to 1 and checkout connected again (`select 1` returned `1`).

## Cleanup

```console
$ kill %1 2>/dev/null; docker rm -f pg-lab
$ rm -rf ./incident/pg-lock ./incident/pg-conn pgpass pw   # snapshots and lab secrets
```

## What to take from this

- Terminate the head of the chain, not the waiters. Here, one pid freed two queued requests.
- Always preview a filtered terminate's count. Then check the count the terminate actually returns: "0 rows" means it did nothing.
- Give the operator role `pg_signal_backend` **and** `pg_read_all_stats`, and keep the triage role read-only.
- Terminating sessions treats the symptom. The fix is in the app (commit or roll back, smaller pool, `idle_in_transaction_session_timeout`).

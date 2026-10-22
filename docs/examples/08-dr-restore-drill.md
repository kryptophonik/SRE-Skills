# Example 8: a DR restore drill, timed and validated against RTO and RPO

**Skill:** [sre-dr-backup-test](../../.claude/skills/sre-dr-backup-test/SKILL.md), workflow steps 1 to 8 and its drill-record template.

> **What's real here.** Command output comes from a lab run on 2026-10-22 with PostgreSQL 17.11 (`postgres:17`, pg_dump and pg_restore 17.11) in Docker 26. Long output is trimmed where you see `...`, lab paths are shortened to `backups/`, and containers are named `pg-lab` and `pg-lab-drtest`. The scope, plan and drill record are **written in the skill's format** by the operator. They show the shape of the answer, not a word-for-word model reply.

![Restore, validation and drill record](images/08-restore-validate-record.png)

## What this shows

- A drill restores into a **new, isolated** target, never over the source.
- Validation goes beyond "the restore exited 0": counts against the manifest, a checksum of the rows, a known record and an app-style query.
- Two honest findings: the archive header's timestamp was wrong by an hour, and the "newest row" method understated the recovery point.
- Cleanup is gated too, and checks a name and a label before deleting anything.

The skill's own restore commands cover AWS, Azure, GCP and Velero. This lab applies the same workflow to a self-managed Postgres, with `pg_dump -Fc` as the "backup system".

## Lab setup (Docker only)

The source is the `shop` database from [example 2](02-postgres-locks-and-connections.md). A standalone source works too: run `postgres:17` as `pg-lab` and load the `orders` and `customers` tables from that page. Then take the "nightly" backup with a checksum and a manifest:

```console
$ TS=$(date -u +%Y%m%dT%H%M%SZ); mkdir -p backups
$ docker exec pg-lab pg_dump -U postgres -Fc -d shop -f /tmp/shop.dump && docker cp pg-lab:/tmp/shop.dump backups/shop-$TS.dump
$ (cd backups && sha256sum shop-$TS.dump > shop-$TS.dump.sha256)
$ docker exec pg-lab psql -U postgres -d shop -Atc "select 'orders='||count(*)||' customers='||(select count(*) from customers)||' max_updated_at='||max(updated_at) from orders" | tee backups/shop-$TS.manifest
orders=50000 customers=500 max_updated_at=2026-10-22 17:59:15.13291+00
```

Then, after the backup, the app writes 25 more orders, which the backup can't contain:

```console
$ docker exec pg-lab psql -U postgres -d shop -c "insert into orders select g, 1+g%500, 'new', 19.99, now() from generate_series(50001,50025) g"
INSERT 0 25
```

## What broke

Nothing yet, and that's the point. A backup you've never restored is a hope, not a backup. The drill shows whether you can meet the targets: RTO 10 minutes and RPO 24 hours.

## What you'd type

> Run a restore drill for the shop Postgres from the latest pg_dump in backups/. Targets: RTO 10 min, RPO 24 h.

## What the skill ran, and why

**1-2. Scope and inventory, read-only.** Is the backup there, intact and what we think it is?

```console
$ cd backups && sha256sum -c *.sha256 && cat *.manifest
shop-20261022T181916Z.dump: OK
orders=50000 customers=500 max_updated_at=2026-10-22 17:59:15.13291+00
$ pg_restore -l shop-*.dump | grep -E 'TABLE DATA|Archive|Format|Dumped from'
; Archive created at 2026-10-22 19:19:16 EDT
;     Format: CUSTOM
;     Dumped from database version: 17.11 (Debian 17.11-1.pgdg13+2)
3428; 0 16399 TABLE DATA public customers shop
3427; 0 16391 TABLE DATA public orders shop
```

The header says 19:19 EDT, but the dump ran at 18:19:16 UTC (14:19 EDT). pg_dump ran in a UTC container and the header stores a zone-less local time, which the host then misreads. Take the backup time from the manifest or object metadata, not the archive header.

## The approval stop (written in the skill's format)

```text
Restore type: full DB (logical) from shop-<ts>.dump to a NEW container pg-lab-drtest
  - docker run --network none (can't receive prod traffic or reach prod), no published ports,
    label purpose=dr-drill; never touches pg-lab.
Validation: row counts vs the manifest; md5 of all orders rows (id <= 50000) vs source; order 42;
  newest updated_at; app-style smoke query (top customer by spend).
Cleanup: docker rm -f only if the name ends in -drtest AND label purpose=dr-drill (after approval).
Risk: low (new isolated target). Reversible: yes (delete the drill container).
>>> APPROVAL REQUIRED: restore to pg-lab-drtest <<<
```

## Approved action: restore (the timer starts)

```console
$ date '+drill start %FT%T%z'; docker run -d --name pg-lab-drtest --network none --label purpose=dr-drill -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17
drill start 2026-10-22T14:19:43-0400
$ docker exec pg-lab-drtest pg_isready -U postgres
/var/run/postgresql:5432 - accepting connections
$ docker cp backups/shop-20261022T181916Z.dump pg-lab-drtest:/tmp/shop.dump && docker exec pg-lab-drtest createdb -U postgres shop && docker exec pg-lab-drtest pg_restore -U postgres -d shop --no-owner --exit-on-error /tmp/shop.dump && echo restore-ok
restore-ok
$ date '+restore done %FT%T%z'
restore done 2026-10-22T14:19:45-0400
```

Trust auth is acceptable only because the container has no network at all.

## Verification

The same query runs on the source and on the restore:

```console
$ docker exec pg-lab psql ... | sed 's/^/SOURCE  /'
SOURCE  orders=50025 customers=500 max_updated_at=2026-10-22 18:19:19.984826+00 orders_md5=2a54aa2da7da3bb908f697bd40b04307 order42=shipped
$ docker exec pg-lab-drtest psql ... | sed 's/^/DRTEST  /'
DRTEST  orders=50000 customers=500 max_updated_at=2026-10-22 17:59:15.13291+00 orders_md5=2a54aa2da7da3bb908f697bd40b04307 order42=shipped
$ docker exec pg-lab-drtest psql -U postgres -d shop -Atc "select c.id, sum(o.total) from orders o join customers c on c.id=o.customer_id group by 1 order by 2 desc limit 1"
357|4998.00
$ docker inspect pg-lab-drtest --format 'network={{.HostConfig.NetworkMode}} ports={{json .NetworkSettings.Ports}} label={{index .Config.Labels "purpose"}}'
network=none ports={} label=dr-drill
$ docker exec pg-lab psql -U postgres -d shop -Atc "select 'source rows not in backup: '||count(*)||', newest '||max(updated_at) from orders where id>50000"
source rows not in backup: 25, newest 2026-10-22 18:19:19.984826+00
```

The query (`...`) builds one line with counts, the newest `updated_at`, an md5 over `id:customer_id:status:total` for `id <= 50000`, and order 42's status.

The md5 matches, and the 25 missing rows are exactly the ones written after the backup. The newest `updated_at` in the restore is 17:59 UTC, 20 minutes older than the real backup time. Order 42's later change (example 2) didn't bump `updated_at`. So "newest timestamp" understates the recovery point here. The real recovery point is the backup time, which the checksum confirms.

## The drill record (written in the skill's format, from the SKILL.md template)

```text
# DR drill: shop (lab Postgres 17) — 2026-10-22
- Scenario: full logical restore from pg_dump -Fc into new isolated container pg-lab-drtest (--network none)
- Targets: RTO 10 min / RPO 24 h
- Achieved: RTO 2 s restore, 34 s including validation / RPO = backup time 2026-10-22 14:19:16 EDT;
  25 orders written after it are not in the backup, as expected for a nightly dump — pass
- Validation: orders 50000 = manifest; customers 500 = 500; md5 of orders id<=50000 identical on both;
  order 42 = shipped on both; smoke query OK; target network=none, no ports; dump sha256 OK
- Issues found: (1) archive header time off by 1 h across time zones -> use the manifest time;
  (2) updated_at not maintained on UPDATE -> the newest-timestamp RPO method understates the recovery point;
  (3) only a small dataset tested; a drill at full size is still pending
- Approved by: Mike May (lab), 2026-10-22 14:19 EDT
```

## Cleanup (gated, with a guard)

```console
$ n=pg-lab-drtest; [[ $n == *-drtest ]] && [[ $(docker inspect -f '{{index .Config.Labels "purpose"}}' $n) == dr-drill ]] && docker rm -f $n
pg-lab-drtest
$ docker ps -a --format '{{.Names}}' | grep -c drtest; docker ps --format '{{.Names}} {{.Status}}' | grep pg-lab
0
pg-lab Up 21 minutes
```

The source is untouched. Remove it and the backups when you're done: `docker rm -f pg-lab && rm -rf backups`.

## What to take from this

- Restore into something new and isolated (`--network none` here). A drill must never be able to touch production.
- "Restore succeeded" isn't validation. Compare counts, a checksum, a known record and a real query against the source.
- Measure RTO from your own timestamps, and RPO from the backup's real time. Don't trust archive headers or `updated_at`.
- Write the record even when the drill passes. The issues list is what improves the next drill.

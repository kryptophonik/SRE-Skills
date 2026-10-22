---
name: sre-migration-safety
description: Review a SQL schema migration for PostgreSQL or MySQL/MariaDB before it merges. Says which statements lock, rewrite or block writes, and gives the safe pattern for each. Never connects to production.
---

# Migration safety reviewer

## Safety gates (REQUIRED)

1. Read-only diagnosis first.
2. Propose each change with risk (low/med/high) and reversibility.
3. Wait for explicit human approval before any prod-changing command, MCP write tool, or external post.
4. Act only as approved, verify, and stop and escalate if anything gets worse.

Full rules: [sre-safety-gates](../sre-safety-gates/SKILL.md). Read-only MCP setup: [sre-safety-gates/references/mcp.md](../sre-safety-gates/references/mcp.md).


Reviews a schema migration (a SQL file, a pull request diff, or the SQL a migration tool prints) and reports, statement by statement, the lock it takes, whether it rewrites or scans the table, and a safer way to get the same result. Every claim the checker makes about lock behaviour is backed by a test that ran on real PostgreSQL 13–17, MySQL 8.0/8.4 and MariaDB 10.11/11.8 servers. The result is a review a team can paste into the pull request.

Test in non-production first. The operator approves every change, and this skill never runs a migration.

## Inputs

- The migration SQL. For ORM tools, get the SQL they will run, not the model code: `python manage.py sqlmigrate <app> <migration>` for Django, `alembic upgrade <rev> --sql` for Alembic, `liquibase update-sql` for Liquibase, or the raw `.sql` file.
- The engine: PostgreSQL, or MySQL/MariaDB with InnoDB.
- The engine's major version, if known. Some rules depend on it (noted per rule).
- Roughly how big and how busy the affected tables are. Ask once if unknown; a lock on an empty table doesn't matter, and on a hot 500 GB table it is an outage.

## Steps

1. Save the SQL to a file, then run the checker. It only reads the file.

   ```bash
   python3 scripts/migration-lint.py --engine pg migration.sql
   python3 scripts/migration-lint.py --engine mysql --format json migration.sql
   ```

   Exit code 2 means at least one blocker, 1 means warnings only, 0 means nothing found (or info only). Exit 3 means the checker couldn't run: bad arguments, or a file it can't read. Paths are relative to the current folder, so give an absolute path if you `cd` into the skill folder first. Treat 3 as a failed review, never as a pass.
2. For each finding, check it against the table sizes and traffic from the inputs. Downgrade a finding only when the table is small or idle, and say so.
3. Read the static checker's blind spots in [references/rules.md](references/rules.md) and review the SQL by hand for them: triggers, partitioned tables, enum changes, and anything the migration tool wraps in its own transaction.
4. Write the review in the format under **Output**: one entry per risky statement with the rewritten, safe SQL.
5. Optional, for a change you can't settle from the rules: reproduce it on a throwaway or staging server with the proof scripts (see **Skill-specific gates**). They create a scratch database, test the lock and rewrite behaviour, and drop it.

## Skill-specific gates
Read-only by default. The checker never connects to a database.

The proof scripts write to the server they point at. They create and drop a database named `migration_proof_<pid>` and refuse to start unless `MIGPROOF_SCRATCH_OK=yes` is set. Never point them at production.

PostgreSQL:

**Gate: approval required.**
```bash
MIGPROOF_SCRATCH_OK=yes PGHOST=<staging-host> PGUSER=<role-with-createdb> PGPASSFILE=<path> bash scripts/proof-pg.sh
```

MySQL or MariaDB:

**Gate: approval required.**
```bash
MIGPROOF_SCRATCH_OK=yes MYSQL_DEFAULTS=<option-file> bash scripts/proof-mysql.sh
```

The safe SQL this skill suggests is still a schema change. The team runs it through its normal deploy process; this skill doesn't apply it.

## Output

For each risky statement:

- **Where:** file and line.
- **Problem:** the lock, and whether it blocks reads, writes or both, rewrites, or scans.
- **Safe version:** the replacement SQL, split into separate migrations where needed (for example, `CREATE INDEX CONCURRENTLY` in its own non-transactional migration).
- **Severity:** blocker (will block writes or fail on a real table), warn (risky on a busy table), info.

End with a verdict (safe to merge / merge with changes / don't merge) and the order to apply the changes. Expand-and-contract changes (renames, type changes, drops) list each deploy step.

## Tested vs docs-only

| Part | Status | Where |
|---|---|---|
| Checker rules and statement splitting | tested | `python3 scripts/tests/test_lint.py`, 39 checks on bad and safe fixtures |
| PostgreSQL lock modes, rewrites, NOT NULL shortcut, CONCURRENTLY, lock queueing | tested | `scripts/proof-pg.sh`, 19/19 on PostgreSQL 13.23, 14.24, 15.19, 16.15, 17.11 |
| MySQL/MariaDB INSTANT and INPLACE limits, foreign keys, metadata-lock queueing | tested | `scripts/proof-mysql.sh`, 11/11 on MySQL 8.0.46, 8.4.11 and MariaDB 10.11.19, 11.8.9 |
| Managed services (RDS, Aurora, Cloud SQL, Azure) | docs-only | Same engines and lock rules; not run on a managed instance |
| `gh-ost`, `pt-online-schema-change`, `pg_repack` | docs-only | Suggested as alternatives; not run here |
| Real table sizes and timings | not tested | Lab tables are small; lock behaviour is the same, durations are not |

## Stop rules

- Stop and say so if you can't get the SQL the tool will actually run. Don't review ORM model code by guessing what it generates.
- Stop if anyone asks you to run the migration, `VACUUM FULL`, `pg_repack`, or `gh-ost` against a real database. Hand back the plan; the team applies it.
- Never run the proof scripts against a database that holds real data.
- If the engine isn't PostgreSQL or MySQL/MariaDB with InnoDB, say the checker doesn't cover it and review by hand, marking the review as not tool-checked.

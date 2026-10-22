#!/usr/bin/env python3
"""Static safety review of a SQL migration for PostgreSQL or MySQL/MariaDB (InnoDB).

Reads SQL files (or stdin), splits them into statements and reports, per statement,
the lock it takes, whether it rewrites or scans the table, and a safer pattern.
It never connects to a database. Exit code: 0 clean or info only, 1 warnings, 2 blockers,
3 usage or input error (bad arguments, file missing or unreadable).

  python3 scripts/migration-lint.py --engine pg migrations/0042_add_index.sql
  python3 scripts/migration-lint.py --engine mysql --format json migrate.sql
"""
import argparse, json, os, re, sys

SEV_ORDER = {'blocker': 3, 'warn': 2, 'info': 1}
EXIT_INPUT = 3  # distinct from 1 (warnings) and 2 (blockers)

_ID = r'"?([A-Za-z_][\w$]*)"?'
_TBL = r'ALTER TABLE (?:IF EXISTS )?(?:ONLY )?(?:"?[A-Za-z_][\w$]*"?\.)?' + _ID

def track_checks(stmt, ctx):
    """Remember CHECK constraints added earlier in the same input, and which (table, column)
    a validated CHECK (col IS NOT NULL) covers, so the safe NOT NULL pattern isn't flagged."""
    u = norm(stmt).upper()
    t = re.match(_TBL, u)
    if not t: return
    table = t.group(1).lower()
    for m in re.finditer(r'ADD CONSTRAINT ' + _ID + r' CHECK \(\s*\(?\s*' + _ID + r'\s*\)?\s+IS NOT NULL\s*\)( NOT VALID)?', u):
        name, col = m.group(1).lower(), m.group(2).lower()
        ctx['checks'][name] = (table, col)
        if not m.group(3): ctx['notnull_ok'].add((table, col))
    for m in re.finditer(r'ADD CONSTRAINT ' + _ID + r' CHECK\b', u):
        ctx['checks'].setdefault(m.group(1).lower(), (table, None))
    for m in re.finditer(r'VALIDATE CONSTRAINT ' + _ID, u):
        tc = ctx['checks'].get(m.group(1).lower())
        if tc and tc[1]: ctx['notnull_ok'].add(tc)


def split_statements(sql):
    """Split on ; outside quotes, comments and dollar quotes. Returns [(line_no, text)]."""
    out, buf, i, n, line, start = [], [], 0, len(sql), 1, None
    while i < n:
        c = sql[i]
        if c == '\n': line += 1
        if sql.startswith('--', i) or (c == '#' and _mysql_hash_ok(sql, i)):
            j = sql.find('\n', i); j = n if j < 0 else j
            i = j; continue
        if sql.startswith('/*', i):
            j = sql.find('*/', i + 2); j = n if j < 0 else j + 2
            line += sql.count('\n', i, j); i = j; buf.append(' '); continue
        if c in "'\"`":
            j = i + 1
            while j < n and not (sql[j] == c and sql[j - 1] != '\\'):
                j += 1
            seg = sql[i:j + 1]; line += seg.count('\n')
            if start is None: start = line - seg.count('\n')
            buf.append(seg); i = j + 1; continue
        m = re.match(r'\$[A-Za-z_]*\$', sql[i:]) if c == '$' else None
        if m:
            tag = m.group(0); j = sql.find(tag, i + len(tag)); j = n if j < 0 else j + len(tag)
            seg = sql[i:j]; line += seg.count('\n')
            if start is None: start = line - seg.count('\n')
            buf.append(seg); i = j; continue
        if c == ';':
            t = ''.join(buf).strip()
            if t: out.append((start, t))
            buf, start = [], None; i += 1; continue
        if start is None and not c.isspace(): start = line
        buf.append(c); i += 1
    t = ''.join(buf).strip()
    if t: out.append((start, t))
    return out

_MYSQL = False
def _mysql_hash_ok(sql, i): return _MYSQL

def norm(s): return re.sub(r'\s+', ' ', s).strip()

# Volatile defaults force a table rewrite on ADD COLUMN (PG 11+ stores non-volatile defaults in the catalog).
PG_VOLATILE = r'(clock_timestamp|random|gen_random_uuid|uuid_generate_v\d|timeofday|nextval|txid_current|statement_timestamp)\s*\('

def pg_rules(stmt, ctx):
    s = norm(stmt); u = s.upper(); f = []
    def add(rule, sev, lock, effect, fix): f.append(dict(rule=rule, severity=sev, lock=lock, effect=effect, fix=fix))
    alter = re.match(r'ALTER TABLE (?:IF EXISTS )?(?:ONLY )?', u)
    if re.match(r'CREATE (UNIQUE )?INDEX ', u) and ' CONCURRENTLY ' not in f' {u} ':
        add('PG-IDX-LOCK', 'blocker', 'SHARE on the table', 'blocks INSERT/UPDATE/DELETE for the whole build',
            'CREATE INDEX CONCURRENTLY ... (outside a transaction block; check for an INVALID index if it fails and DROP INDEX CONCURRENTLY it)')
    if re.match(r'(CREATE (UNIQUE )?INDEX|DROP INDEX|REINDEX)\b.* CONCURRENTLY\b', u) and ctx['in_txn']:
        add('PG-CONC-IN-TXN', 'blocker', 'none (statement errors)', 'CONCURRENTLY cannot run inside a transaction block; the migration fails',
            'run this statement on its own, outside BEGIN/COMMIT; most migration tools have a no-transaction flag for it')
    if re.match(r'DROP INDEX ', u) and 'CONCURRENTLY' not in u:
        add('PG-DROPIDX-LOCK', 'warn', 'ACCESS EXCLUSIVE on the table', 'blocks reads and writes while it waits for and holds the lock',
            'DROP INDEX CONCURRENTLY ... (outside a transaction block)')
    if re.match(r'REINDEX ', u) and 'CONCURRENTLY' not in u:
        add('PG-REINDEX-LOCK', 'blocker', 'SHARE on the table (ACCESS EXCLUSIVE on the index)', 'blocks writes, and reads that use the index',
            'REINDEX INDEX CONCURRENTLY ... (PostgreSQL 12+, outside a transaction block)')
    if re.match(r'(VACUUM (\(.*FULL.*\)|FULL)|CLUSTER)\b', u):
        add('PG-REWRITE-CMD', 'blocker', 'ACCESS EXCLUSIVE', 'rewrites the whole table; blocks all reads and writes',
            'do not run in a migration; use pg_repack (extension) for online bloat removal, behind an approval gate')
    if re.match(r'REFRESH MATERIALIZED VIEW ', u) and 'CONCURRENTLY' not in u:
        add('PG-MATVIEW-LOCK', 'warn', 'ACCESS EXCLUSIVE on the view', 'blocks reads of the view during refresh',
            'REFRESH MATERIALIZED VIEW CONCURRENTLY ... (needs a unique index on the view)')
    if alter:
        for m in re.finditer(r'ADD (?:COLUMN )?(?:IF NOT EXISTS )?("?[\w]+"?) ([^,]+)', s, re.I):
            col = m.group(2)
            if re.match(r'(CONSTRAINT|PRIMARY|UNIQUE|FOREIGN|CHECK|EXCLUDE)\b', m.group(1), re.I): continue
            if re.search(PG_VOLATILE, col, re.I) or re.search(r'\b(BIG|SMALL)?SERIAL\b', col, re.I):
                add('PG-ADDCOL-REWRITE', 'blocker', 'ACCESS EXCLUSIVE', 'volatile default or serial: rewrites every row while holding the lock',
                    'add the column with no default (or a constant), backfill in batches, then SET DEFAULT')
            if re.search(r'GENERATED ALWAYS AS \(.*\) STORED', col, re.I):
                add('PG-ADDCOL-GENERATED', 'blocker', 'ACCESS EXCLUSIVE', 'stored generated column: rewrites every row',
                    'add a plain column, backfill in batches, keep it in sync with a trigger or the application')
            if re.search(r'\bNOT NULL\b', col, re.I) and not re.search(r'\bDEFAULT\b', col, re.I):
                add('PG-ADDCOL-NOTNULL', 'blocker', 'ACCESS EXCLUSIVE', 'fails on a table that already has rows',
                    'add it nullable, backfill, then use the NOT NULL steps (CHECK ... NOT VALID, VALIDATE, SET NOT NULL)')
        m_type = re.search(r'ALTER (?:COLUMN )?"?\w+"? (?:SET DATA )?TYPE (\S+(?: VARYING)?)', u)
        if m_type:
            target = m_type.group(1)
            maybe_safe = re.match(r'(TEXT|VARCHAR|CHARACTER VARYING)\b', target) and ' USING ' not in f' {u} '
            if maybe_safe:
                add('PG-ALTER-TYPE', 'warn', 'ACCESS EXCLUSIVE (brief if no rewrite)', 'no rewrite when widening a varchar or going from varchar to text; shrinking a varchar or converting from another type rewrites or scans the table',
                    "check the current column type; keep SET lock_timeout before it, since the lock is still ACCESS EXCLUSIVE")
            else:
                add('PG-ALTER-TYPE', 'blocker', 'ACCESS EXCLUSIVE', 'usually rewrites the table and rebuilds its indexes',
                    'add a new column, backfill in batches, dual-write, then swap names in a short transaction; run the lab proof to check a specific change')
        m_nn = re.search(r'ALTER (?:COLUMN )?' + _ID + r' SET NOT NULL', u)
        m_tb = re.match(_TBL, u)
        covered = m_nn and m_tb and (m_tb.group(1).lower(), m_nn.group(1).lower()) in ctx['notnull_ok']
        if covered:
            add('PG-SET-NOTNULL-COVERED', 'info', 'ACCESS EXCLUSIVE (brief)', 'a validated CHECK (col IS NOT NULL) earlier in this file covers it, so PostgreSQL 12+ skips the table scan',
                'on PostgreSQL 11 or older it still scans; keep SET lock_timeout before it')
        elif m_nn:
            add('PG-SET-NOTNULL', 'warn', 'ACCESS EXCLUSIVE', 'scans the whole table under the lock unless a validated CHECK (col IS NOT NULL) already exists',
                'ADD CONSTRAINT c CHECK (col IS NOT NULL) NOT VALID; VALIDATE CONSTRAINT c; then SET NOT NULL (PostgreSQL 12+ skips the scan); then drop c')
        if re.search(r'ADD (CONSTRAINT \S+ )?FOREIGN KEY', u) and 'NOT VALID' not in u:
            add('PG-FK-VALIDATE', 'blocker', 'SHARE ROW EXCLUSIVE on both tables', 'scans the table to check every row; blocks writes on both tables',
                'ADD CONSTRAINT ... FOREIGN KEY ... NOT VALID; then ALTER TABLE ... VALIDATE CONSTRAINT ... in a separate statement')
        if re.search(r'ADD (CONSTRAINT \S+ )?CHECK\b', u) and 'NOT VALID' not in u:
            add('PG-CHECK-VALIDATE', 'blocker', 'ACCESS EXCLUSIVE', 'scans every row while holding the lock',
                'ADD CONSTRAINT ... CHECK (...) NOT VALID; then VALIDATE CONSTRAINT ... separately')
        if re.search(r'ADD (CONSTRAINT \S+ )?(UNIQUE|PRIMARY KEY)\b', u) and 'USING INDEX' not in u:
            add('PG-UNIQUE-BUILD', 'blocker', 'ACCESS EXCLUSIVE', 'builds the index while holding the lock',
                'CREATE UNIQUE INDEX CONCURRENTLY idx ...; then ALTER TABLE ... ADD CONSTRAINT c UNIQUE USING INDEX idx')
        dropped = [x.lower() for x in re.findall(r'\bDROP CONSTRAINT (?:IF EXISTS )?' + _ID, u)]
        only_known_checks = dropped and all(x in ctx['checks'] for x in dropped) and not re.search(r'\bDROP COLUMN\b', u)
        if re.search(r'\bDROP (COLUMN|CONSTRAINT)\b', u) and not only_known_checks:
            add('PG-DROP', 'warn', 'ACCESS EXCLUSIVE', 'destructive and irreversible without a restore; running app versions may still read it',
                'deploy code that no longer uses it first; keep this behind an approval gate with a tested backup')
        if re.search(r'\bRENAME\b', u):
            add('PG-RENAME', 'warn', 'ACCESS EXCLUSIVE (brief)', 'breaks running app versions that use the old name',
                'expand and contract: add the new name, dual-write, move readers, then drop the old one')
        if re.search(r'\b(SET (LOGGED|UNLOGGED)|SET TABLESPACE)\b', u):
            add('PG-REWRITE-ALTER', 'blocker', 'ACCESS EXCLUSIVE', 'rewrites the whole table', 'avoid in a migration; plan a maintenance window')
        validate_only = re.fullmatch(r'ALTER TABLE \S+ VALIDATE CONSTRAINT \S+', u)
        if not validate_only and not ctx['lock_timeout']:
            add('PG-NO-LOCK-TIMEOUT', 'warn', 'queues for ACCESS EXCLUSIVE', 'while it waits behind a long query, every new query on the table queues behind it',
                "SET lock_timeout = '5s'; before the ALTER (and retry on failure)")
    if re.match(r'DROP TABLE |TRUNCATE ', u):
        add('PG-DROP-TABLE', 'blocker', 'ACCESS EXCLUSIVE', 'destructive and irreversible without a restore',
            'never in an automatic migration; behind an approval gate with a tested backup')
    if re.match(r'(UPDATE|DELETE FROM) ', u) and ' WHERE ' not in f' {u} ':
        add('PG-DML-ALL-ROWS', 'warn', 'ROW EXCLUSIVE + row locks on every row', 'one long transaction: locks every row, bloats the table, lags replicas',
            'backfill in batches of a few thousand rows by primary key, committing between batches')
    return f

MY_COPY = [
    (r'\b(MODIFY|CHANGE) (COLUMN )?', 'MY-COLUMN-TYPE', 'column type or definition change usually needs ALGORITHM=COPY: rebuilds the table and blocks writes',
     'append ALGORITHM=INPLACE, LOCK=NONE (MySQL refuses instead of silently copying); if refused, use gh-ost or pt-online-schema-change'),
    (r'CONVERT TO CHARACTER SET', 'MY-CHARSET', 'rebuilds the table with COPY; blocks writes', 'use gh-ost or pt-online-schema-change'),
    (r'(DROP|ADD) PRIMARY KEY', 'MY-PK', 'rebuilds the whole table; dropping a primary key without adding one needs COPY', 'use gh-ost or pt-online-schema-change'),
    (r'ADD (FULLTEXT|SPATIAL)', 'MY-FTS', 'FULLTEXT/SPATIAL index builds do not allow concurrent writes (LOCK=SHARED at best)', 'build during low traffic or with gh-ost'),
]

def my_rules(stmt, ctx):
    s = norm(stmt); u = s.upper(); f = []
    def add(rule, sev, lock, effect, fix): f.append(dict(rule=rule, severity=sev, lock=lock, effect=effect, fix=fix))
    if re.match(r'(ALTER TABLE|CREATE (UNIQUE |FULLTEXT |SPATIAL )?INDEX|DROP INDEX|OPTIMIZE TABLE|RENAME TABLE)\b', u):
        if not ctx['lock_wait_timeout']:
            add('MY-NO-LOCK-WAIT-TIMEOUT', 'warn', 'exclusive metadata lock (brief, at start and end)', 'waits behind any open transaction on the table, and every new query queues behind it (default lock_wait_timeout is one year on MySQL, one day on MariaDB)',
                'SET SESSION lock_wait_timeout = 5; before the DDL (and retry on failure)')
        explicit = re.search(r'ALGORITHM\s*=\s*(INSTANT|INPLACE)', u)
        if re.match(r'ALTER TABLE', u):
            for rx, rule, effect, fix in MY_COPY:
                if re.search(rx, u) and not explicit:
                    add(rule, 'blocker', 'shared or exclusive table lock for the copy', effect, fix)
            if re.search(r'ALGORITHM\s*=\s*COPY', u):
                add('MY-ALG-COPY', 'blocker', 'blocks writes', 'explicit ALGORITHM=COPY rebuilds the table', 'use gh-ost or pt-online-schema-change')
            if re.search(r'ADD (CONSTRAINT \S+ )?FOREIGN KEY', u) and not ctx['fk_checks_off']:
                add('MY-FK-COPY', 'blocker', 'blocks writes', 'with foreign_key_checks=1, adding a foreign key needs ALGORITHM=COPY',
                    'first run an orphan check (SELECT 1 FROM child c LEFT JOIN parent p ON p.id = c.parent_id WHERE c.parent_id IS NOT NULL AND p.id IS NULL LIMIT 1) and stop if it returns a row; then, as one gated step in one session: SET SESSION foreign_key_checks = 0; the ALTER with ALGORITHM=INPLACE, LOCK=NONE; SET SESSION foreign_key_checks = 1. With checks off, MySQL does not check existing rows. gh-ost does not support foreign keys')
            if re.search(r'\bADD (COLUMN )?`?\w+`? ', u) and not re.search(r'ADD (CONSTRAINT|INDEX|KEY|UNIQUE|PRIMARY|FOREIGN|FULLTEXT|SPATIAL)', u) and not explicit:
                add('MY-ADDCOL-ALGO', 'info', 'depends on algorithm', 'MySQL 8.0.29+ allows INSTANT at any column position (8.0.12 to 8.0.28: last column only); a table allows 64 instant add/drop row versions (255 from 9.1) before INSTANT is refused until a rebuild, see INFORMATION_SCHEMA.INNODB_TABLES.TOTAL_ROW_VERSIONS; without an explicit algorithm MySQL silently falls back to INPLACE or COPY',
                    'append ALGORITHM=INSTANT so the statement fails instead of rebuilding if it cannot be instant')
            if re.search(r'\bDROP (COLUMN )?`?\w+`?', u) and not re.search(r'DROP (INDEX|KEY|PRIMARY|FOREIGN|CONSTRAINT|CHECK)', u):
                add('MY-DROP-COLUMN', 'warn', 'rebuild (INSTANT in 8.0.29+)', 'destructive and irreversible without a restore; running app versions may still read it',
                    'deploy code that no longer uses it first; keep this behind an approval gate with a tested backup')
            if re.search(r'\bRENAME\b', u):
                add('MY-RENAME', 'warn', 'metadata lock (brief)', 'breaks running app versions that use the old name', 'expand and contract instead of renaming')
        if re.match(r'OPTIMIZE TABLE', u):
            add('MY-OPTIMIZE', 'warn', 'brief exclusive lock, then online rebuild', 'rebuilds the whole table; heavy I/O and replica lag', 'run off-peak, never in an automatic migration')
    if re.match(r'(DROP TABLE|TRUNCATE)\b', u):
        add('MY-DROP-TABLE', 'blocker', 'exclusive metadata lock', 'destructive and irreversible without a restore', 'never in an automatic migration; behind an approval gate with a tested backup')
    if re.match(r'(UPDATE|DELETE FROM) ', u) and ' WHERE ' not in f' {u} ':
        add('MY-DML-ALL-ROWS', 'warn', 'row locks on every row', 'one long transaction: undo log growth, replica lag', 'batch by primary key with LIMIT, committing between batches')
    return f

def review(sql, engine):
    global _MYSQL; _MYSQL = engine == 'mysql'
    ctx = dict(in_txn=False, lock_timeout=False, lock_wait_timeout=False, fk_checks_off=False, checks={}, notnull_ok=set())
    results = []
    for line, stmt in split_statements(sql):
        u = norm(stmt).upper()
        if re.match(r'(BEGIN|START TRANSACTION)\b', u): ctx['in_txn'] = True
        if re.match(r'(COMMIT|ROLLBACK|END)\b', u): ctx['in_txn'] = False
        if re.match(r"SET (LOCAL |SESSION )?LOCK_TIMEOUT\s*(=|TO)\s*'?(?!0'?\b)\d", u): ctx['lock_timeout'] = True
        if re.match(r"SET (SESSION )?LOCK_WAIT_TIMEOUT\s*=\s*\d", u): ctx['lock_wait_timeout'] = True
        if re.match(r'SET (SESSION )?FOREIGN_KEY_CHECKS\s*=\s*(0|OFF)', u): ctx['fk_checks_off'] = True
        found = (pg_rules if engine == 'pg' else my_rules)(stmt, ctx)
        if engine == 'pg': track_checks(stmt, ctx)
        if found: results.append(dict(line=line, statement=norm(stmt)[:160], findings=found))
    return results

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--engine', choices=['pg', 'mysql'], required=True, help='pg = PostgreSQL; mysql = MySQL or MariaDB (InnoDB)')
    ap.add_argument('--format', choices=['text', 'json'], default='text')
    ap.add_argument('files', nargs='*', help='SQL files; reads stdin when none')
    ap.error = lambda msg: (ap.print_usage(sys.stderr), print(f'migration-lint: error: {msg}', file=sys.stderr), sys.exit(EXIT_INPUT))
    a = ap.parse_args()
    srcs = []
    for p in a.files:
        try:
            with open(p, encoding='utf-8') as fh: srcs.append((p, fh.read()))
        except (OSError, UnicodeDecodeError) as e:
            print(f'migration-lint: error: cannot read {p}: {getattr(e, "strerror", None) or e} (paths are relative to {os.getcwd()})', file=sys.stderr)
            sys.exit(EXIT_INPUT)
    srcs = srcs or [('<stdin>', sys.stdin.read())]
    report, worst = [], 0
    for path, sql in srcs:
        for r in review(sql, a.engine):
            r['file'] = path; report.append(r)
            worst = max([worst] + [SEV_ORDER[x['severity']] for x in r['findings']])
    if a.format == 'json':
        print(json.dumps(report, indent=2))
    else:
        if not report: print('no findings')
        for r in report:
            print(f"{r['file']}:{r['line']}: {r['statement']}")
            for x in r['findings']:
                print(f"  [{x['severity'].upper()}] {x['rule']}: {x['effect']}\n    lock: {x['lock']}\n    safer: {x['fix']}")
    sys.exit(2 if worst == 3 else 1 if worst == 2 else 0)

if __name__ == '__main__':
    main()

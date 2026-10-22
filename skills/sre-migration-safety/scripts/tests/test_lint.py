#!/usr/bin/env python3
"""Unit tests for migration-lint.py: every bad pattern is caught, every safe pattern passes.
Run from the skill folder: python3 scripts/tests/test_lint.py"""
import importlib.util, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('lint', os.path.join(HERE, '..', 'migration-lint.py'))
lint = importlib.util.module_from_spec(spec); spec.loader.exec_module(lint)
fx = lambda n: open(os.path.join(HERE, 'fixtures', n)).read()
def rules(sql, engine): return [f['rule'] for r in lint.review(sql, engine) for f in r['findings']]
def sevs(sql, engine): return {f['severity'] for r in lint.review(sql, engine) for f in r['findings']}
ok = fail = 0
def check(name, cond):
    global ok, fail
    if cond: ok += 1
    else: fail += 1; print('FAIL', name)

pg_bad = rules(fx('pg_bad.sql'), 'pg')
for r in ['PG-IDX-LOCK', 'PG-ADDCOL-REWRITE', 'PG-ADDCOL-NOTNULL', 'PG-ALTER-TYPE', 'PG-SET-NOTNULL', 'PG-FK-VALIDATE',
          'PG-CHECK-VALIDATE', 'PG-UNIQUE-BUILD', 'PG-RENAME', 'PG-DROP', 'PG-DML-ALL-ROWS', 'PG-CONC-IN-TXN',
          'PG-DROPIDX-LOCK', 'PG-REINDEX-LOCK', 'PG-REWRITE-CMD', 'PG-MATVIEW-LOCK', 'PG-DROP-TABLE', 'PG-NO-LOCK-TIMEOUT']:
    check(f'pg_bad flags {r}', r in pg_bad)
check('pg bigserial is a rewrite', pg_bad.count('PG-ADDCOL-REWRITE') == 2)
check('pg VACUUM FULL and CLUSTER both flagged', pg_bad.count('PG-REWRITE-CMD') == 2)
pg_good = lint.review(fx('pg_good.sql'), 'pg')
check('pg_good has no findings', pg_good == [])
if pg_good: print(pg_good)
check('pg_good: 16 statements split (strings and $$ bodies kept whole)', len(lint.split_statements(fx('pg_good.sql'))) == 16)

my_bad = rules(fx('mysql_bad.sql'), 'mysql')
for r in ['MY-COLUMN-TYPE', 'MY-CHARSET', 'MY-PK', 'MY-FTS', 'MY-FK-COPY', 'MY-ALG-COPY', 'MY-DROP-COLUMN',
          'MY-RENAME', 'MY-OPTIMIZE', 'MY-DML-ALL-ROWS', 'MY-DROP-TABLE', 'MY-NO-LOCK-WAIT-TIMEOUT']:
    check(f'mysql_bad flags {r}', r in my_bad)
lint._MYSQL = True
check('mysql hash comment ignored', len(lint.split_statements(fx('mysql_bad.sql'))) == 11)
my_good = lint.review(fx('mysql_good.sql'), 'mysql')
check('mysql_good has no findings', my_good == [])
if my_good: print(my_good)
check('fk_checks=0 allows INPLACE FK', 'MY-FK-COPY' not in rules('SET foreign_key_checks=0; ALTER TABLE t ADD CONSTRAINT f FOREIGN KEY (a) REFERENCES p(id);', 'mysql'))
check('lock_timeout 0 does not count', 'PG-NO-LOCK-TIMEOUT' in rules("SET lock_timeout = 0; ALTER TABLE t ADD COLUMN a int;", 'pg'))
check('pg_bad has blockers', 'blocker' in sevs(fx('pg_bad.sql'), 'pg'))
def type_sev(sql): return {f['severity'] for r in lint.review(sql, 'pg') for f in r['findings'] if f['rule'] == 'PG-ALTER-TYPE'}
for sql, want in [("ALTER TABLE t ALTER COLUMN name TYPE varchar(50);", 'warn'), ("ALTER TABLE t ALTER COLUMN name TYPE text;", 'warn'),
                  ("ALTER TABLE t ALTER COLUMN name TYPE character varying(80);", 'warn'), ("ALTER TABLE t ALTER COLUMN id TYPE bigint;", 'blocker'),
                  ("ALTER TABLE t ALTER COLUMN n TYPE text USING n::text;", 'blocker')]:
    check(f'type severity {want}: {sql}', type_sev(sql) == {want})

# Safe NOT NULL pattern in one file: validated CHECK covers SET NOT NULL; dropping that helper CHECK is not destructive.
NN = ("SET lock_timeout = '5s';\nALTER TABLE orders ADD CONSTRAINT orders_status_nn CHECK (status IS NOT NULL) NOT VALID;\n"
      "ALTER TABLE orders VALIDATE CONSTRAINT orders_status_nn;\nALTER TABLE orders ALTER COLUMN status SET NOT NULL;\n"
      "ALTER TABLE orders DROP CONSTRAINT orders_status_nn;\n")
check('validated CHECK covers SET NOT NULL', rules(NN, 'pg') == ['PG-SET-NOTNULL-COVERED'] and sevs(NN, 'pg') == {'info'})
check('NOT VALID without VALIDATE still warns', 'PG-SET-NOTNULL' in rules(NN.replace("ALTER TABLE orders VALIDATE CONSTRAINT orders_status_nn;\n", ''), 'pg'))
check('CHECK on another column does not cover', 'PG-SET-NOTNULL' in rules(NN.replace('COLUMN status SET', 'COLUMN region SET'), 'pg'))
check('CHECK on another table does not cover', 'PG-SET-NOTNULL' in rules(NN.replace('TABLE orders ALTER COLUMN', 'TABLE users ALTER COLUMN'), 'pg'))
check('CHECK added without NOT VALID covers (but is itself a blocker)', 'PG-SET-NOTNULL-COVERED' in rules(NN.replace(' NOT VALID', ''), 'pg'))
check('drop of unknown constraint is still PG-DROP', 'PG-DROP' in rules("SET lock_timeout='5s'; ALTER TABLE t DROP CONSTRAINT t_pkey;", 'pg'))
check('drop of in-file CHECK plus a column is still PG-DROP', 'PG-DROP' in rules(NN + "ALTER TABLE orders DROP CONSTRAINT orders_status_nn, DROP COLUMN legacy;", 'pg'))
check('quoted and schema-qualified names', rules(NN.replace('TABLE orders', 'TABLE public."orders"'), 'pg') == ['PG-SET-NOTNULL-COVERED'])

# CLI: input errors exit 3, distinct from 1 (warnings) and 2 (blockers); no traceback.
import subprocess
LINT = os.path.join(HERE, '..', 'migration-lint.py')
r = subprocess.run([sys.executable, LINT, '--engine', 'pg', os.path.join(HERE, 'no-such-file.sql')], capture_output=True, text=True)
check('missing file exits 3 with a clear error', r.returncode == 3 and 'cannot read' in r.stderr and 'Traceback' not in r.stderr and r.stdout == '')
r = subprocess.run([sys.executable, LINT, '--engine', 'bogus'], capture_output=True, text=True)
check('bad arguments exit 3, not 2', r.returncode == 3)
r = subprocess.run([sys.executable, LINT, '--engine', 'pg', os.path.join(HERE, 'fixtures', 'pg_bad.sql')], capture_output=True, text=True)
check('blockers still exit 2', r.returncode == 2)
print(f'{ok}/{ok + fail} passed'); sys.exit(1 if fail else 0)

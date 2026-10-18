#!/usr/bin/env python3
"""Fixture tests for the content checks in scripts/validate.py. Run from the repo root."""
import os, shutil, subprocess, sys, tempfile
BAD = {  # each line must be flagged
  'redis-cli -h h KEYS *': 'KEYS',
  'redis-cli -h h MONITOR': 'MONITOR',
  'redis-cli -a hunter2 INFO': 'inline Redis password',
  'mysql -u root -psecret -e "select 1"': 'inline MySQL password',
  'PGPASSWORD=hunter2 psql -h db': 'inline Postgres password',
  'REDISCLI_AUTH=hunter2 redis-cli INFO': 'inline Redis password',
  'psql postgres://app:hunter2@db:5432/app': 'connection URI',
  'redis-cli -u redis://:hunter2@cache:6379': 'connection URI',
  'SELECT * FROM information_schema.innodb_lock_waits;': 'removed in MySQL 8.0',
  'SELECT pg_terminate_backend(123);': 'approval/gate',
  'scripts/x.sh --since 1h': 'call scripts as',
}
GOOD = [  # each line must pass
  'mysql -u dbmonitor -p -h db', 'mysql -h db -P 3306 -u dbmonitor -p',
  'PGPASSFILE=~/.pgpass psql -h db', 'psql postgres://app@db:5432/app',
  'psql "postgres://app:<password>@db/app"', 'redis-cli --scan --pattern "sess:*" --count 100',
  'REDISCLI_AUTH="$(cat /run/secrets/redis)" redis-cli INFO',
]
root = os.getcwd(); tmp = tempfile.mkdtemp()
try:
  shutil.copytree(root, os.path.join(tmp, 'r'), ignore=shutil.ignore_patterns('.git', 'node_modules'))
  r = os.path.join(tmp, 'r'); d = os.path.join(r, '.claude/skills/sre-engineer/references')
  def run(lines, gated_ok=False):
    body = ''.join(f'```bash\n{l}\n```\n\nSome prose.\n\nMore prose.\n\nEven more.\n\nAnd more.\n\n' for l in lines)
    open(os.path.join(d, 'zz-fixture.md'), 'w').write(body)
    return subprocess.run([sys.executable, 'scripts/validate.py'], cwd=r, capture_output=True, text=True).stdout
  fails = 0
  for line, why in BAD.items():
    out = run([line])
    if 'zz-fixture.md' not in out or why not in out: print('MISSED', line); fails += 1
  out = run(GOOD)
  for l in out.splitlines():
    if 'zz-fixture.md' in l: print('FALSE POSITIVE', l); fails += 1
  open(os.path.join(d, 'zz-fixture.md'), 'w').write('**Gate: approval required.**\n\n```sql\nSELECT pg_cancel_backend(123);\n```\n')
  out = subprocess.run([sys.executable, 'scripts/validate.py'], cwd=r, capture_output=True, text=True).stdout
  if 'zz-fixture.md' in out: print('GATED BLOCK REJECTED', out); fails += 1
  os.remove(os.path.join(d, 'zz-fixture.md'))
  dc = os.path.join(r, '.claude/skills/sre-engineer/references/destructive-commands.md')
  open(dc, 'w').write('```bash\nredis-cli FLUSHALL\nredis-cli KEYS *\n```\n')
  out = subprocess.run([sys.executable, 'scripts/validate.py'], cwd=r, capture_output=True, text=True).stdout
  if 'destructive-commands.md' in out: print('NEVER-RUN REFERENCE FLAGGED', out); fails += 1
  di = os.path.join(r, 'docs/install/zz-fixture.md')
  INSTALL_BAD = {
    '```bash\ngemini extensions install https://example.test/x --ref v3.0.0\n```\n': 'never updates',
    '```bash\ncp -r a/sre-* ~/.claude/skills/\n```\n': 'needs mkdir -p',
    '```bash\nmkdir -p ~/s\ncp -r a/{x,y} ~/s/\n```\n': 'brace expansion',
    '```bash\ncp claude-sre/AGENTS.md repo/AGENTS.md\n```\n': 'overwrites an existing AGENTS.md',
    'Run `cp -r a ~/.claude/skills/` now.\n': 'fenced block',
  }
  for body, why in INSTALL_BAD.items():
    open(di, 'w').write(body)
    out = subprocess.run([sys.executable, 'scripts/validate.py'], cwd=r, capture_output=True, text=True).stdout
    if 'zz-fixture.md' not in out: print('MISSED install', why); fails += 1
  open(di, 'w').write('```bash\nmkdir -p ~/.claude/skills\ncp -r a/sre-x a/sre-y ~/.claude/skills/\ncat a/AGENTS.md >> repo/AGENTS.md\n```\n')
  out = subprocess.run([sys.executable, 'scripts/validate.py'], cwd=r, capture_output=True, text=True).stdout
  if 'zz-fixture.md' in out: print('INSTALL FALSE POSITIVE', out); fails += 1
  os.remove(di)
  open(os.path.join(d, 'zz-fixture.md'), 'w').write('Tell the user to run `/sre-chaos-engineering`.\n')
  out = subprocess.run([sys.executable, 'scripts/validate.py'], cwd=r, capture_output=True, text=True).stdout
  if 'plugin form' not in out: print('MISSED un-namespaced manual command'); fails += 1
  os.remove(os.path.join(d, 'zz-fixture.md'))
  extra = len(INSTALL_BAD) + 2
  print(f'{len(BAD) + len(GOOD) + 2 + extra - fails} ok, {fails} failed'); sys.exit(1 if fails else 0)
finally:
  shutil.rmtree(tmp)

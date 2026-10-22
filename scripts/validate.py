#!/usr/bin/env python3
"""Validate the pack: frontmatter, description length, gate block, links, fences, JSON/YAML/TOML, no nested skills, no .mcp.json.
Requires PyYAML (pip install pyyaml) and Python 3.11+ (tomllib). Run from the repo root."""
import yaml,re,glob,json,os,tomllib
md=glob.glob('.claude/skills/**/*.md',recursive=True)+glob.glob('*.md')+glob.glob('docs/**/*.md',recursive=True)
for p in md:
  s=open(p).read(); assert s.count('```')%2==0,('fence',p)
  for l in re.findall(r'\]\(([^)#\s]+)(?:#[^)]*)?\)',s):
    if l.startswith(('http','mailto')): continue
    assert os.path.exists(os.path.join(os.path.dirname(p),l)),('link',p,l)
  for b in re.findall(r'```json\n(.*?)```',s,re.S): json.loads(b)
  for b in re.findall(r'```yaml\n(.*?)```',s,re.S): yaml.safe_load(b)
  for b in re.findall(r'```toml\n(.*?)```',s,re.S): tomllib.loads(b)
names=set()
for p in glob.glob('.claude/skills/*/SKILL.md'):
  s=open(p).read(); d=yaml.safe_load(re.match(r'---\n(.*?)\n---\n',s,re.S).group(1))
  n=p.split('/')[2]; assert d['name']==n and re.fullmatch(r'[a-z0-9-]+',n),p
  assert len(d['description'])<=250,(p,len(d['description'])); names.add(n)
  assert '## Safety gates' in s or n=='sre-safety-gates',('gate',p)
assert not glob.glob('.claude/skills/*/*/SKILL.md') and not glob.glob('.claude/skills/*/*/*/SKILL.md'),'nested skill'
for p in glob.glob('.claude/skills/**/*.json',recursive=True)+glob.glob('.claude-plugin/*.json'): json.load(open(p))
for p in glob.glob('.claude/skills/**/*.y*ml',recursive=True): list(yaml.safe_load_all(open(p)))
for p in glob.glob('.claude/skills/**/*.toml',recursive=True): tomllib.load(open(p,'rb'))
assert not os.path.exists('.mcp.json')
print('valid',len(names),'skills')

# --- 3.1 content checks -------------------------------------------------------
# Every check below reads only "runnable" text: fenced code blocks and inline `code`
# spans in skill Markdown, plus bundled scripts. Prose and tables that merely name a
# command are fine. Files that exist to list what NOT to run are allowlisted.
NEVER_RUN_DOCS = ('destructive-commands.md', 'dangerous-commands.md', 'write-command-risk.md')
CALL = re.compile(r'^(?:[A-Z_][A-Z0-9_]*=\S+ +)*(?P<runner>bash +|python3 +)?(?P<dot>\./)?'
                  r'(?P<path>(?:\.\./[a-z0-9-]+/)?scripts/[\w.-]+\.(?P<ext>sh|py))(?P<rest>\b.*)$')
FORBIDDEN = [  # never runnable outside a never-run reference
  (re.compile(r'\brm\s+(?:-\w+\s+)*-\w*(?:r\w*f|f\w*r)\w*\b[^;&|]*\$(?!\{\w+:\?)(?:\{?\w|\()'), 'rm -rf with an unguarded variable: an empty value deletes the wrong tree; use ${VAR:?msg} or rm -f on files plus rmdir'),
  (re.compile(r'\bKEYS\s+\*|\bkeys\s+\*'), 'Redis KEYS * blocks the server; use SCAN or redis-cli --bigkeys/--memkeys'),
  (re.compile(r'redis-cli\b.*(?<![\w-])MONITOR(?![\w-])|^\s*MONITOR\s*$', re.I), 'Redis MONITOR on a primary halves throughput; use SLOWLOG GET / LATENCY DOCTOR'),
  (re.compile(r'information_schema\.innodb_lock_waits', re.I), 'removed in MySQL 8.0; use sys.innodb_lock_waits'),
  (re.compile(r'redis-cli\b[^|]*\s-a\s+(?!<)'), 'inline Redis password; use REDISCLI_AUTH'),
  (re.compile(r'\bmysql(admin)?\b[^|]*\s-p(?!\s|$|<)\S'), 'inline MySQL password; use --defaults-extra-file'),
  (re.compile(r'PGPASSWORD=(?!<|\$|")\S'), 'inline Postgres password; use PGPASSFILE'),
  (re.compile(r'REDISCLI_AUTH=(?!<|\$|")\S'), 'inline Redis password; export REDISCLI_AUTH from a secret store, not on the command line'),
  (re.compile(r'\b(?:postgres(?:ql)?|mysql|mariadb|rediss?)://[^\s:/@]*:(?!<)[^\s@/]+@'), 'password in a connection URI; use PGPASSFILE, --defaults-extra-file or REDISCLI_AUTH'),
]
GATED = re.compile(r'pg_terminate_backend|pg_cancel_backend|pg_drop_replication_slot|^\s*KILL\b|rds_kill|az_kill|CLIENT\s+KILL|\bFLUSH(ALL|DB)\b|\bCONFIG\s+SET\b|ALTER\s+SYSTEM|SET\s+GLOBAL|(^|redis-cli.*\s)(CLUSTER\s+|SENTINEL\s+)?FAILOVER\b|VACUUM\s+FULL|failover-db-cluster|failover-global-cluster|switchover-global-cluster|reboot-db-instance|instances\s+failover|restart\b.*--failover|failover-shard|test-failover|force-reboot', re.I)

def runnable(path):
  """Yield (line_no, text, in_fence, preceding_context) for fenced lines and inline code spans."""
  lines = open(path).read().split('\n'); fence = False; start = 0
  for i, line in enumerate(lines):
    if line.lstrip().startswith('```'):
      fence = not fence; start = i; continue
    ctx = '\n'.join(lines[max(0, (start if fence else i) - 8):i])  # a fenced block shares the note above it
    if fence: yield i + 1, line.strip(), True, ctx
    else:
      for span in re.findall(r'`([^`]+)`', line):
        if not line.lstrip().startswith('|'): yield i + 1, span.strip(), False, ctx + '\n' + line


def gate_above(path, line_no):
  """True when the nearest non-blank line above this line's fence opening is exactly the gate marker."""
  L = open(path).read().split('\n'); i = line_no - 1
  while i >= 0 and not L[i].lstrip().startswith('```'): i -= 1
  j = i - 1
  while j >= 0 and not L[j].strip(): j -= 1
  return j >= 0 and L[j].strip() == '**Gate: approval required.**'

errors = []
for p in glob.glob('.claude/skills/**/*.md', recursive=True):
  skill_dir = os.path.join(*p.split('/')[:3])
  never_run = os.path.basename(p) in NEVER_RUN_DOCS
  for n, t, fence, ctx in runnable(p):
    m = CALL.match(t)
    if m:
      want = 'bash' if m['ext'] == 'sh' else 'python3'
      invoked = m['dot'] or m['runner'] or m['rest'].strip() or fence or re.match(r'[A-Z_]+=', t)
      if invoked and (m['runner'] or '').strip() != want:
        errors.append(f'{p}:{n}: call scripts as `{want} {m["path"]}` (works without +x and on any shell)')
      if invoked and not os.path.exists(os.path.join(skill_dir, m['path'])):
        errors.append(f'{p}:{n}: {m["path"]} not found relative to {skill_dir}')
    if never_run: continue
    if re.search(r'(^|\s)"?\$\{?S\}?"?/\S+\.(sh|py)', t): errors.append(f'{p}:{n}: call scripts as `bash scripts/<name>.sh`, not through $S')
    if re.search(r'\bkubectl\b.*\sevents\b.*\s(--watch|-w)\b', t): errors.append(f'{p}:{n}: kubectl events --watch never ends; drop it')
    elif re.search(r'\bkubectl\b.*\sevents\b\s+\S', t) and not re.search(r'\|\s*(tail|head)\b|--help', t):
      errors.append(f'{p}:{n}: kubectl events has no limit flag; pipe it to | tail -n 50')
    for rx, why in FORBIDDEN:
      if rx.search(t) and not ('innodb_lock_waits' in why and re.search(r'mariadb', ctx + t, re.I)): errors.append(f'{p}:{n}: {why}')
    if fence and GATED.search(t) and not gate_above(p, n):
      errors.append(f'{p}:{n}: state-changing command needs the exact marker **Gate: approval required.** on the line directly above its block')
for p in glob.glob('.claude/skills/**/scripts/**/*', recursive=True):
  if not os.path.isfile(p) or '/tests/' in p: continue
  for n, line in enumerate(open(p, errors='replace'), 1):
    if line.lstrip().startswith('#'): continue
    for rx, why in FORBIDDEN:
      if rx.search(line) and not ('innodb_lock_waits' in why and re.search(r'mariadb', line, re.I)): errors.append(f'{p}:{n}: {why}')

# README skills table must match the skills on disk, description for description.
readme = open('README.md').read()
rows = dict(re.findall(r'^\| \[`([a-z0-9-]+)`\]\(\.claude/skills/[a-z0-9-]+/SKILL\.md\) \| (.*?) \| [^|]+ \|$', readme, re.M))
descs = {n: yaml.safe_load(re.match(r'---\n(.*?)\n---\n', open(f'.claude/skills/{n}/SKILL.md').read(), re.S).group(1))['description'] for n in names}
for n in sorted(names ^ set(rows)): errors.append(f'README.md: skills table and .claude/skills disagree on {n}')
for n in names & set(rows):
  if rows[n] != descs[n]: errors.append(f'README.md: description for {n} does not match its SKILL.md')
m = re.search(r'All (\d+) skills', readme)
if m and int(m[1]) != len(names): errors.append(f'README.md says {m[1]} skills, pack has {len(names)}')

# Trigger eval cases must name real skills (the model-graded run lives in evals/run_triggers.py).
if os.path.exists('evals/triggers.yaml'):
  cases = yaml.safe_load(open('evals/triggers.yaml'))['cases']; ids = set()
  for c in cases:
    assert c['id'] not in ids, ('duplicate eval id', c['id']); ids.add(c['id'])
    for k in ('expect', 'forbid'):
      for s in c.get(k, []):
        if s != 'none' and s not in names: errors.append(f'evals/triggers.yaml {c["id"]}: unknown skill {s} in {k}')
    if not c.get('expect'): errors.append(f'evals/triggers.yaml {c["id"]}: needs expect (use [none] for negatives)')

# Install docs: commands must work on a fresh machine, copied literally.
install_docs = ['README.md', 'INSTALL.md'] + sorted(glob.glob('docs/install/*.md'))
for p in install_docs:
  lines = open(p).read().split('\n'); fence = False; made = set()
  for i, line in enumerate(lines, 1):
    t = line.strip()
    if t.startswith('```'):
      fence = not fence; made = set(); continue
    if re.search(r'--ref\s+v\d', line): errors.append(f'{p}:{i}: don\'t pin --ref to a tag; a pinned ref never updates')
    if not fence:
      for span in re.findall(r'`([^`]+)`', line):
        if re.match(r'(cp|mkdir)\s', span): errors.append(f'{p}:{i}: put copy commands in a fenced block with mkdir -p, not inline')
      continue
    if t.startswith('mkdir -p '): made.update(x.rstrip('/') for x in t.split()[2:])
    if t.startswith('cp '):
      args = t.split('#')[0].split()
      if re.search(r'\{[^}]*,', t): errors.append(f'{p}:{i}: brace expansion fails in sh; list each path')
      if args[-1].endswith('AGENTS.md'): errors.append(f'{p}:{i}: cp overwrites an existing AGENTS.md; append with cat >>')
      elif args[-1].endswith('/') and args[-1].rstrip('/') not in made: errors.append(f'{p}:{i}: {args[-1]} needs mkdir -p earlier in the same block')

# Manual-only skills: every slash command in skill text also names the plugin form.
manual = [n for n in names if yaml.safe_load(re.match(r'---\n(.*?)\n---\n', open(f'.claude/skills/{n}/SKILL.md').read(), re.S).group(1)).get('disable-model-invocation')]
for p in glob.glob('.claude/skills/**/*.md', recursive=True) + ['SKILLS.md']:
  for i, line in enumerate(open(p), 1):
    for n in manual:
      if f'`/{n}`' in line and f'/sre:{n}' not in line:
        errors.append(f'{p}:{i}: /{n} also needs the Claude plugin form /sre:{n}')

# Images live only in docs/examples/images and stay small: the Claude plugin (source "./")
# copies the whole repo, and skill folders are mirrored for every tool.
IMG_DIR, IMG_MAX, IMG_TOTAL = 'docs/examples/images/', 100_000, 1_000_000
imgs = [os.path.relpath(os.path.join(dp, f)) for dp, dn, fs in os.walk('.') if not dp.startswith('./.git')
        for f in fs if f.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'))]
for p in imgs:
  if not p.startswith(IMG_DIR): errors.append(f'{p}: images belong only under {IMG_DIR} (never in skill folders or mirrors)')
  elif os.path.getsize(p) > IMG_MAX: errors.append(f'{p}: image too large ({os.path.getsize(p)} bytes > {IMG_MAX}); use a palette PNG')
if sum(os.path.getsize(p) for p in imgs) > IMG_TOTAL: errors.append(f'images total over {IMG_TOTAL} bytes')

if errors:
  print('\n'.join(errors)); raise SystemExit(f'{len(errors)} content error(s)')
print('content checks ok')

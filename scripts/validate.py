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

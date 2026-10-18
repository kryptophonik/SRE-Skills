#!/usr/bin/env python3
"""Model-graded trigger evals for the SRE pack (nightly or manual; not per-commit).

For each case in evals/triggers.yaml the model sees only skill names and descriptions,
the same thing an agent sees before it loads a skill, and picks the skills it would load.
A case passes when the pick includes an `expect` skill (or is empty for [none]) and no
`forbid` skill. Manual-only skills are excluded from the menu, as the tools exclude them.

Backends (pick one):
  --cmd "claude -p"          pipe the prompt to any CLI that prints the reply (claude, gemini, codex exec)
  ANTHROPIC_API_KEY + EVAL_MODEL   call the Anthropic Messages API directly (stdlib only)

Usage: python3 evals/run_triggers.py [--cmd CMD] [--threshold 0.85] [--only ID]
Exit 1 when the pass rate is below the threshold or any forbid case fails.
Requires PyYAML.
"""
import argparse, glob, json, os, re, shlex, subprocess, sys, urllib.request
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def skills():
    out = {}
    for p in sorted(glob.glob(os.path.join(ROOT, '.claude/skills/*/SKILL.md'))):
        fm = yaml.safe_load(re.match(r'---\n(.*?)\n---\n', open(p).read(), re.S).group(1))
        out[fm['name']] = fm
    return out

def menu(sk):
    return '\n'.join(f"- {n}: {fm['description']}" for n, fm in sk.items()
                     if not fm.get('disable-model-invocation'))

ASK = """You are a coding agent with these skills installed. Each line is a skill name and its description.
Load a skill only when its description fits the user's request.

{menu}

User request: {prompt}

Reply with JSON only: {{"skills": ["<name>", ...]}}. Use an empty list when no skill fits."""

def ask(text, cmd):
    if cmd:
        r = subprocess.run(shlex.split(cmd), input=text, capture_output=True, text=True, timeout=180)
        return r.stdout
    key, model = os.environ.get('ANTHROPIC_API_KEY'), os.environ.get('EVAL_MODEL')
    if not key or not model:
        sys.exit('set --cmd, or ANTHROPIC_API_KEY and EVAL_MODEL')
    req = urllib.request.Request('https://api.anthropic.com/v1/messages', method='POST',
        headers={'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
        data=json.dumps({'model': model, 'max_tokens': 300,
                         'messages': [{'role': 'user', 'content': text}]}).encode())
    with urllib.request.urlopen(req, timeout=120) as r:
        return ''.join(b.get('text', '') for b in json.load(r)['content'])

def picked(reply):
    m = re.search(r'\{.*\}', reply, re.S)
    try: return set(json.loads(m.group(0))['skills']) if m else None
    except (ValueError, KeyError): return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cmd'); ap.add_argument('--threshold', type=float, default=0.85); ap.add_argument('--only')
    a = ap.parse_args()
    sk = skills(); m = menu(sk)
    cases = yaml.safe_load(open(os.path.join(ROOT, 'evals/triggers.yaml')))['cases']
    if a.only: cases = [c for c in cases if c['id'] == a.only]
    passed = forbid_fail = 0
    for c in cases:
        got = picked(ask(ASK.format(menu=m, prompt=c['prompt']), a.cmd))
        exp = set(c['expect']); bad = set(c.get('forbid', [])) & (got or set())
        if got is None: ok, why = False, 'unparseable reply'
        elif bad: ok, why = False, f'forbidden {sorted(bad)}'; forbid_fail += 1
        elif not got: ok, why = 'none' in exp, 'loaded nothing'
        else: ok, why = bool(got & exp), f'loaded {sorted(got)}'
        passed += ok
        print(f"{'PASS' if ok else 'FAIL'} {c['id']}: {why}")
    rate = passed / max(len(cases), 1)
    print(f'\n{passed}/{len(cases)} passed ({rate:.0%}), threshold {a.threshold:.0%}, forbidden loads {forbid_fail}')
    sys.exit(0 if rate >= a.threshold and not forbid_fail else 1)

if __name__ == '__main__':
    main()

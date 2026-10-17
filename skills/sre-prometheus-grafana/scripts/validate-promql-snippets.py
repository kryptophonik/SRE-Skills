#!/usr/bin/env python3
"""Syntax-check every ```promql fenced block in Markdown files with promtool.

Each block is split into expressions on blank lines, full-line '#' comments and
trailing '# comment' lines. The expressions are wrapped as recording rules in a temp file and run through
`promtool check rules --lint=all` (rule format:
https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/, Prometheus 3.x;
tested 2026-10-16 with promtool 3.15.0). Placeholders like <svc> inside label values are fine.

Usage: validate-promql-snippets.py [--promtool PATH] FILE.md [FILE.md ...]
Read-only on the input files; writes only a temp file. Exit 0 = all blocks parse.
"""
import argparse, os, re, subprocess, sys, tempfile

def extract(text):
    out = []
    for block in re.findall(r"```promql\n(.*?)```", text, re.S):
        cur = []
        for line in block.split("\n"):
            s = line.strip()
            if not s or s.startswith("#"):
                if cur: out.append("\n".join(cur)); cur = []
                continue
            m = re.match(r"^(.*?)\s+#.*$", line)
            if m:
                cur.append(m.group(1)); out.append("\n".join(cur)); cur = []
            else:
                cur.append(line)
        if cur: out.append("\n".join(cur))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--promtool", default=os.environ.get("PROMTOOL", "promtool"))
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    rc = 0
    for f in a.files:
        exprs = extract(open(f, encoding="utf-8").read())
        if not exprs:
            print(f"{f}: no promql blocks"); continue
        lines = ["groups:", "  - name: snippets", "    rules:"]
        for i, e in enumerate(exprs):
            lines += [f"      - record: snippet:expr{i}:check", "        expr: |"] + ["          " + l for l in e.split("\n")]
        with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False) as t:
            t.write("\n".join(lines) + "\n")
        p = subprocess.run([a.promtool, "check", "rules", "--lint=all", t.name], capture_output=True, text=True)
        os.unlink(t.name)
        if p.returncode == 0:
            print(f"{f}: OK ({len(exprs)} expressions)")
        else:
            rc = 1
            print(f"{f}: FAILED")
            for m in re.finditer(r"expr(\d+):check\": could not parse expression: (.*)", p.stdout + p.stderr):
                print(f"  expression #{int(m.group(1))+1}: {m.group(2)}\n    {exprs[int(m.group(1))].splitlines()[0]}")
            if "could not parse" not in p.stdout + p.stderr:
                print(p.stdout + p.stderr)
    return rc

if __name__ == "__main__":
    sys.exit(main())

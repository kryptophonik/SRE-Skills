#!/usr/bin/env python3
"""Convert metric monitors (exported from Datadog) into Prometheus alerting rules.

Reads a monitor export (the JSON list from the read-only monitor list call, one monitor
object, or {"monitors": [...]}) and writes a rule file plus a conversion report that says,
per monitor, what translated, what was approximated and what did not translate.
It only reads local files and writes local files. Validate the output with promtool
(--check does that when promtool is on PATH or given with --promtool).

"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

AGGS = ("avg", "sum", "min", "max")
SUPPORTED_TYPES = ("metric alert", "query alert")
UNSUPPORTED_FUNCS = {
    "anomalies": "anomaly detection has no PromQL equivalent; consider a recording rule plus a static band",
    "forecast": "forecast monitors have no direct equivalent (predict_linear covers only linear trends)",
    "outliers": "outlier detection has no PromQL equivalent",
    "top": "top() ranking inside a monitor does not map to an alert expression; use topk in a dashboard",
    "cumsum": "cumulative sums over the query window do not map cleanly",
    "integral": "integral over the query window does not map cleanly",
    "robust_trend": "regression functions do not translate",
    "trend_line": "regression functions do not translate",
    "piecewise_constant": "regression functions do not translate",
    "ewma_3": "smoothing functions do not translate exactly", "ewma_5": "smoothing functions do not translate exactly",
    "ewma_10": "smoothing functions do not translate exactly", "ewma_20": "smoothing functions do not translate exactly",
    "median_3": "smoothing functions do not translate exactly", "median_5": "smoothing functions do not translate exactly",
    "median_7": "smoothing functions do not translate exactly", "median_9": "smoothing functions do not translate exactly",
    "count_nonzero": "count functions over groups need a hand-written count by()",
    "count_not_null": "count functions over groups need a hand-written count by()",
    "diff": "diff() between points needs a hand-written delta()/idelta() choice",
    "derivative": "derivative() needs a hand-written deriv() choice",
    "monotonic_diff": "monotonic_diff() needs a hand-written increase() choice",
}
OFFSET_FUNCS = {"hour_before": "1h", "day_before": "1d", "week_before": "1w", "month_before": "4w"}
UNTRANSLATED_OPTIONS = {
    "evaluation_delay": "evaluation delay (closest: a rule-group query_offset)",
    "new_host_delay": "new host delay", "new_group_delay": "new group delay",
    "renotify_interval": "re-notification (set repeat_interval in Alertmanager)",
    "escalation_message": "escalation message", "timeout_h": "auto-resolve timeout",
    "notify_audit": "audit notifications", "require_full_window": "require full window",
    "min_failure_duration": "minimum failure duration (closest: for:)",
}

class Unsupported(Exception):
    pass

# ----------------------------------------------------------------------------- parsing
class Parser:
    def __init__(self, s):
        self.s, self.i = s, 0

    def ws(self):
        while self.i < len(self.s) and self.s[self.i].isspace():
            self.i += 1

    def peek(self, n=1):
        self.ws()
        return self.s[self.i:self.i + n]

    def expect(self, ch):
        self.ws()
        if not self.s.startswith(ch, self.i):
            raise Unsupported(f"could not parse query near '{self.s[self.i:self.i + 20]}' (expected '{ch}')")
        self.i += len(ch)

    def braces(self):
        self.expect("{")
        depth, start = 1, self.i
        while self.i < len(self.s) and depth:
            depth += {"{": 1, "}": -1}.get(self.s[self.i], 0)
            self.i += 1
        if depth:
            raise Unsupported("unbalanced braces in query")
        return self.s[start:self.i - 1]

    def expr(self):
        node = self.term()
        while self.peek() in ("+", "-", "*", "/"):
            op = self.peek()
            self.i += 1
            node = ("bin", op, node, self.term())
        return node

    def term(self):
        self.ws()
        if self.peek() == "(":
            self.i += 1
            e = self.expr()
            self.expect(")")
            return ("paren", e)
        m = re.compile(r"-?\d+(\.\d+)?([eE][-+]?\d+)?").match(self.s, self.i)
        if m:
            self.i = m.end()
            return ("num", m.group(0))
        m = re.compile(r"[A-Za-z_][\w.]*").match(self.s, self.i)
        if not m:
            raise Unsupported(f"could not parse query near '{self.s[self.i:self.i + 20]}'")
        name = m.group(0)
        self.i = m.end()
        if name in AGGS and self.peek() == ":":
            return self.query(name)
        if self.peek() == "(":
            self.i += 1
            args = [self.arg()]
            while self.peek() == ",":
                self.i += 1
                args.append(self.arg())
            self.expect(")")
            return ("func", name, args)
        raise Unsupported(f"unexpected token '{name}' (bare metric names without an aggregator are not supported)")

    def arg(self):
        self.ws()
        m = re.compile(r"'[^']*'|\"[^\"]*\"").match(self.s, self.i)
        if m:
            self.i = m.end()
            return ("str", m.group(0)[1:-1])
        return self.expr()

    def query(self, sagg):
        self.expect(":")
        self.ws()
        m = re.compile(r"[A-Za-z_][\w.]*").match(self.s, self.i)
        if not m:
            raise Unsupported("missing metric name after the space aggregator")
        metric = m.group(0)
        self.i = m.end()
        scope = self.braces()
        by = []
        self.ws()
        if re.compile(r"by\s*\{").match(self.s, self.i):
            self.i += 2
            by = [k.strip() for k in self.braces().split(",") if k.strip()]
        mods = []
        while True:
            m = re.compile(r"\.(as_count|as_rate)\(\)").match(self.s, self.i)
            if m:
                mods.append(m.group(1))
                self.i = m.end()
                continue
            m = re.compile(r"\.(rollup|fill)\(([^)]*)\)").match(self.s, self.i)
            if m:
                mods.append(f"{m.group(1)}({m.group(2)})")
                self.i = m.end()
                continue
            break
        return ("query", sagg, metric, scope, by, mods)

HEADER = re.compile(
    r"^\s*(?:(?P<chg>change|pct_change)\(\s*(?P<ctagg>avg|sum|min|max)\(\s*(?P<cwin>last_\w+)\s*\)\s*,\s*(?P<shift>\w+_ago)\s*\)"
    r"|(?P<tagg>[a-z_]+)\(\s*(?P<win>last_\w+)\s*\))\s*:(?P<body>.*)$", re.S)
THRESH = re.compile(r"^(?P<expr>.*?)\s*(?P<op><=|>=|==|!=|<|>)\s*(?P<val>-?\d+(\.\d+)?([eE][-+]?\d+)?)\s*$", re.S)

def duration(win):
    m = re.fullmatch(r"last_(\d+)([mhdw])", win)
    if not m:
        raise Unsupported(f"unsupported time window '{win}'")
    return m.group(1) + m.group(2)

def shift_duration(s):
    m = re.fullmatch(r"(\d+)([mhdw])_ago", s)
    if not m:
        raise Unsupported(f"unsupported timeshift '{s}'")
    return m.group(1) + m.group(2)

# ----------------------------------------------------------------------------- emitting
def prom_label(key, mapping):
    out = mapping.get("labels", {}).get(key, key)
    out = re.sub(r"[^A-Za-z0-9_]", "_", out)
    return "_" + out if out[:1].isdigit() else out

def prom_str(v):
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'

def value_regex(values):
    parts = []
    for v in values:
        parts.append(re.escape(v).replace("\\*", ".*"))
    return "|".join(parts)

def scope_matchers(scope, mapping, notes):
    items, depth, cur = [], 0, ""
    for ch in scope:
        depth += {"(": 1, ")": -1}.get(ch, 0)
        if ch == "," and depth == 0:
            items.append(cur)
            cur = ""
        else:
            cur += ch
    items.append(cur)
    out = []
    for raw in (x.strip() for x in items):
        if raw in ("", "*"):
            continue
        m = re.fullmatch(r"(?P<k>[^\s:!]+)\s+(?P<neg>NOT\s+)?IN\s*\((?P<v>[^)]*)\)", raw, re.I)
        if m:
            vals = [v.strip() for v in m.group("v").split(",") if v.strip()]
            out.append(f"{prom_label(m.group('k'), mapping)}{'!~' if m.group('neg') else '=~'}{prom_str(value_regex(vals))}")
            continue
        if re.search(r"\s(AND|OR)\s|^\(|^NOT\s", raw, re.I):
            raise Unsupported(f"boolean scope '{raw}' needs hand translation")
        neg = raw.startswith("!") or raw.startswith("-")
        body = raw[1:] if neg else raw
        if ":" not in body:
            raise Unsupported(f"tag '{raw}' has no key; Prometheus labels always have a name")
        k, v = body.split(":", 1)
        lab = prom_label(k, mapping)
        if "*" in v:
            out.append(f"{lab}{'!~' if neg else '=~'}{prom_str(value_regex([v]))}")
        else:
            out.append(f"{lab}{'!=' if neg else '='}{prom_str(v)}")
        if k not in mapping.get("labels", {}):
            notes.add(f"tag key `{k}` kept as label `{lab}`; add it to the labels map if your label differs")
    return out

def metric_name(dd, mapping, notes):
    entry = mapping.get("metrics", {}).get(dd)
    if isinstance(entry, str):
        return entry, False
    if isinstance(entry, dict):
        return entry["name"], bool(entry.get("counter"))
    notes.add(f"metric `{dd}` auto-renamed to `{re.sub(r'[^A-Za-z0-9_:]', '_', dd)}`; map it to your real metric name")
    return re.sub(r"[^A-Za-z0-9_:]", "_", dd), False

class Emitter:
    def __init__(self, mapping, window, tagg, rate_window):
        self.mapping, self.window, self.tagg, self.rate_window = mapping, window, tagg, rate_window
        self.notes, self.approx = set(), []
        self.by_sets = []
        self.metrics = []  # (prom name, matchers) for absent() rules

    def selector(self, q, offset=None):
        _, sagg, metric, scope, by, mods = q
        name, counter = metric_name(metric, self.mapping, self.notes)
        matchers = scope_matchers(scope, self.mapping, self.notes)
        self.metrics.append((name, matchers))
        sel = name + ("{" + ",".join(matchers) + "}" if matchers else "")
        for mo in mods:
            if mo.startswith(("rollup", "fill")):
                self.approx.append(f".{mo} ignored; Prometheus uses its own step and lookback")
        return sel, counter, (f" offset {offset}" if offset else "")

    def aggregate(self, q, inner):
        sagg, by = q[1], q[4]
        labels = [prom_label(k, self.mapping) for k in by]
        self.by_sets.append(tuple(sorted(labels)))
        return f"{sagg} by ({', '.join(labels)}) ({inner})" if labels else f"{sagg}({inner})"

    def count_path(self, node, offset=None):
        t = node[0]
        if t == "num":
            return node[1]
        if t == "paren":
            return "(" + self.count_path(node[1], offset) + ")"
        if t == "bin":
            return f"{self.count_path(node[2], offset)} {node[1]} {self.count_path(node[3], offset)}"
        if t == "query":
            if "as_count" not in node[5]:
                raise Unsupported("mixes .as_count() with queries that have no .as_count(); translate by hand")
            sel, _, off = self.selector(node, offset)
            return self.aggregate(node, f"increase({sel}[{self.window}]{off})")
        return self.func(node, offset, self.count_path)

    def classic(self, node, offset=None):
        t = node[0]
        if t == "num":
            return node[1]
        if t == "paren":
            return "(" + self.classic(node[1], offset) + ")"
        if t == "bin":
            return f"{self.classic(node[2], offset)} {node[1]} {self.classic(node[3], offset)}"
        if t == "query":
            sel, counter, off = self.selector(node, offset)
            if "as_rate" in node[5] or counter:
                if counter and "as_rate" not in node[5]:
                    self.approx.append(f"`{node[2]}` is mapped to a counter, so it is wrapped in rate()")
                return self.aggregate(node, f"rate({sel}[{self.rate_window}]{off})")
            return self.aggregate(node, sel + off)
        return self.func(node, offset, self.classic)

    def func(self, node, offset, walk):
        if node[0] == "str":
            raise Unsupported("unexpected string argument")
        _, name, args = node
        if name in UNSUPPORTED_FUNCS:
            raise Unsupported(f"{name}(): {UNSUPPORTED_FUNCS[name]}")
        if name in ("abs", "log2", "log10"):
            return f"{name}({walk(args[0], offset)})"
        if name in OFFSET_FUNCS:
            return walk(args[0], OFFSET_FUNCS[name])
        if name == "timeshift" and len(args) == 2 and args[1][0] == "num" and float(args[1][1]) < 0:
            return walk(args[0], f"{int(-float(args[1][1]))}s")
        if name == "per_second" and args[0][0] == "query":
            q = args[0]
            return walk(q[:5] + (q[5] + ["as_rate"],), offset)
        if name == "default_zero":
            self.approx.append("default_zero() became `or vector(0)`, which only fills when the whole result is empty")
            return f"({walk(args[0], offset)}) or vector(0)"
        raise Unsupported(f"{name}() is not in the translation table")

def walk_queries(node):
    if node[0] == "query":
        yield node
    elif node[0] in ("paren",):
        yield from walk_queries(node[1])
    elif node[0] == "bin":
        yield from walk_queries(node[2])
        yield from walk_queries(node[3])
    elif node[0] == "func":
        for a in node[2]:
            if a[0] != "str":
                yield from walk_queries(a)

MANUAL = "manual conversion needed (v1 refuses this): "
RECOVERY_REASON = (MANUAL + "recovery thresholds (critical_recovery / warning_recovery) are not converted. They do "
                   "not map cleanly onto keep_firing_for: keep_firing_for holds an alert for a fixed time, while a "
                   "recovery threshold holds it until the value crosses a second level. The closer match is a "
                   "hysteresis expression, which v1 does not generate; write it by hand")

def convert_query(query, mapping, rate_window="2m"):
    """Return (expr_without_threshold, op, threshold, notes, approximations, by_labels, metrics)."""
    h = HEADER.match(query or "")
    if not h:
        raise Unsupported("query does not start with time_aggr(last_N): (formula or unknown monitor query form)")
    body = h.group("body")
    t = THRESH.match(body)
    if not t:
        raise Unsupported("no numeric threshold at the end of the query (dynamic thresholds do not translate)")
    tree = Parser(t.group("expr"))
    node = tree.expr()
    tree.ws()
    if tree.i != len(tree.s):
        raise Unsupported(f"could not parse query tail '{tree.s[tree.i:][:30]}'")
    queries = list(walk_queries(node))
    if not queries:
        raise Unsupported("no metric query found")
    tagg = h.group("ctagg") or h.group("tagg")
    if tagg not in AGGS:
        raise Unsupported(f"time aggregator '{tagg}' is not supported (avg, sum, min, max only)")
    window = duration(h.group("cwin") or h.group("win"))
    em = Emitter(mapping, window, tagg, rate_window)
    as_count = any("as_count" in q[5] for q in queries)
    if h.group("chg"):
        if as_count:
            raise Unsupported("change alerts with .as_count() need hand translation")
        shift = shift_duration(h.group("shift"))
        now, before = em.classic(node), em.classic(node, shift)
        inner = (f"({now}) - ({before})" if h.group("chg") == "change"
                 else f"(({now}) - ({before})) / ({before}) * 100")
        expr = f"{tagg}_over_time(({inner})[{window}:])"
        em.approx.append(f"{h.group('chg')} alert: point-by-point difference against {shift} ago, then {tagg} over "
                         f"{window}; compare against the source monitor during the parallel run")
    elif as_count:
        if tagg != "sum":
            raise Unsupported(".as_count() monitors only make sense with sum() time aggregation")
        # Count path: time aggregation is applied to each query before the arithmetic.
        expr = em.count_path(node)
    else:
        single = node[0] == "query"
        if single and tagg == "avg" and "as_rate" in node[5]:
            sel, _, _ = em.selector(node)
            expr = em.aggregate(node, f"rate({sel}[{window}])")
        else:
            # Classic path: arithmetic per point first, then time aggregation over the window.
            expr = f"{tagg}_over_time(({em.classic(node)})[{window}:])"
            if tagg == "sum":
                em.approx.append("sum() over a window of non-count data depends on the point interval; Prometheus "
                                 "sums subquery steps instead (default: the rule evaluation interval)")
    if len(set(em.by_sets)) > 1:
        raise Unsupported(MANUAL + "the queries are grouped by different tags, so the binary operator needs "
                          "on()/ignoring() vector matching. v1 does not generate on()/ignoring(); write the "
                          "matching by hand")
    by = list(em.by_sets[0]) if em.by_sets else []
    return expr, t.group("op"), t.group("val"), em.notes, em.approx, by, em.metrics

# ----------------------------------------------------------------------------- templates
def convert_text(text, by_labels, mapping, thresholds, notes):
    if not text:
        return ""
    text = re.sub(r"(?<![\w])@[\w.\-/@+]+", "", text)  # notification handles route in Alertmanager instead

    def repl(m):
        inner = m.group(1).strip()
        if re.match(r"^[#/^]", inner):
            return ""
        if inner == "value":
            return "{{ $value }}"
        if inner in ("threshold", "warn_threshold"):
            v = thresholds.get("critical" if inner == "threshold" else "warning")
            return str(v) if v is not None else ""
        mm = re.fullmatch(r"([\w.-]+)\.name", inner)
        if mm and prom_label(mm.group(1), mapping) in by_labels:
            return "{{ $labels." + prom_label(mm.group(1), mapping) + " }}"
        notes.add(f"template variable {{{{{inner}}}}} dropped from the message")
        return ""
    text = re.sub(r"\{\{\s*([^{}]*?)\s*\}\}", repl, text)
    text = text.replace("{{", "").replace("}}", "") if "{{ $" not in text else text
    return re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n", text)).strip()

def alert_name(name, mid, used):
    words = re.findall(r"[A-Za-z0-9]+", re.sub(r"\{\{.*?\}\}", " ", name or "")) or ["Monitor"]
    out = "".join(w[:1].upper() + w[1:] for w in words)[:80]
    if out[:1].isdigit():
        out = "M" + out
    if out in used:
        out = f"{out}_{mid}"
    used.add(out)
    return out

# ----------------------------------------------------------------------------- yaml
def q(s):
    return json.dumps(str(s), ensure_ascii=False)

def rules_yaml(group, rules):
    L = ["# Generated by monitors_to_prom.py. Review before loading; see the conversion report.",
         "groups:", f"  - name: {q(group)}", "    rules:"]
    if not rules:
        L[-1] = "    rules: []"
    for r in rules:
        L.append(f"      - alert: {q(r['alert'])}")
        L.append(f"        expr: {q(r['expr'])}")
        if r.get("for"):
            L.append(f"        for: {r['for']}")
        L.append("        labels:")
        for k, v in r["labels"].items():
            L.append(f"          {k}: {q(v)}")
        L.append("        annotations:")
        for k, v in r["annotations"].items():
            L.append(f"          {k}: {q(v)}")
    return "\n".join(L) + "\n"

# ----------------------------------------------------------------------------- main
def load_monitors(path):
    with open(path) as f:
        d = json.load(f)
    if isinstance(d, dict) and "monitors" in d:
        d = d["monitors"]
    return d if isinstance(d, list) else [d]

def convert(monitors, mapping, ids=None, rate_window="2m"):
    rules, results, used = [], [], set()
    for m in monitors:
        mid = m.get("id")
        if ids and mid not in ids:
            continue
        res = {"id": mid, "name": m.get("name"), "type": m.get("type"), "status": "", "notes": [], "not_translated": []}
        results.append(res)
        if m.get("type") not in SUPPORTED_TYPES:
            res["status"] = "skipped"
            res["not_translated"].append(f"monitor type '{m.get('type')}' is not a metric monitor")
            continue
        try:
            expr, op, val, notes, approx, by, metrics = convert_query(m.get("query"), mapping, rate_window)
        except Unsupported as e:
            res["status"] = "skipped"
            res["not_translated"].append(str(e))
            continue
        opts = m.get("options") or {}
        th = opts.get("thresholds") or {}
        if th.get("critical_recovery") is not None or th.get("warning_recovery") is not None:
            res["status"] = "skipped"
            res["not_translated"].append(RECOVERY_REASON)
            continue
        name = alert_name(m.get("name"), mid, used)
        notes = set(notes)
        desc = convert_text(m.get("message"), by, mapping, th, notes)
        summary = convert_text(m.get("name"), by, mapping, th, notes)
        base_labels = {"source_monitor_id": str(mid)}
        if m.get("priority"):
            base_labels["priority"] = f"P{m['priority']}"
        crit = th.get("critical", val)
        if th.get("critical") is not None and float(th["critical"]) != float(val):
            notes.add(f"options.thresholds.critical ({th['critical']}) differs from the query threshold ({val}); used the query")
            crit = val
        rules.append({"alert": name, "expr": f"{expr} {op} {crit}",
                      "labels": dict(base_labels, severity="critical"),
                      "annotations": {"summary": summary, "description": desc}})
        if th.get("warning") is not None:
            rules.append({"alert": name + "Warning", "expr": f"{expr} {op} {th['warning']}",
                          "labels": dict(base_labels, severity="warning"),
                          "annotations": {"summary": summary + " (warning)", "description": desc}})
        if opts.get("notify_no_data"):
            if by:
                res["not_translated"].append("no-data alert per group (absent_over_time() cannot keep group labels)")
            else:
                nd = f"{int(opts.get('no_data_timeframe') or 10)}m"
                for i, (mn, mt) in enumerate(dict.fromkeys((n, tuple(x)) for n, x in metrics)):
                    sel = mn + ("{" + ",".join(mt) + "}" if mt else "")
                    rules.append({"alert": f"{name}NoData" + (str(i) if i else ""), "expr": f"absent_over_time({sel}[{nd}])",
                                  "labels": dict(base_labels, severity="warning"),
                                  "annotations": {"summary": f"No data for {mn} ({summary})", "description": desc}})
        for k, label in UNTRANSLATED_OPTIONS.items():
            if opts.get(k):
                res["not_translated"].append(f"{label} (`{k}`={json.dumps(opts[k])})")
        if re.search(r"(?<![\w])@[\w.\-/@+]+", m.get("message") or ""):
            res["not_translated"].append("notification handles in the message (route them in Alertmanager)")
        res["notes"] = sorted(notes) + approx
        res["status"] = "converted with notes" if res["notes"] or res["not_translated"] else "converted"
        res["alerts"] = [r["alert"] for r in rules if r["labels"]["source_monitor_id"] == str(mid)]
    return rules, results

def report_md(results, rules_path, check_result):
    L = ["# Monitor conversion report", "",
         "Review every rule before loading it. Run the old monitor and the new rule side by side and compare "
         "firing history before you retire the monitor.", ""]
    if check_result is not None:
        L += [f"`promtool check rules` on `{os.path.basename(rules_path)}`: **{'passed' if check_result[0] == 0 else 'FAILED'}**", "",
              "```text", check_result[1].strip(), "```", ""]
    L += ["| Monitor | Name | Status | Alerts |", "|---|---|---|---|"]
    for r in results:
        L.append(f"| {r['id']} | {(r['name'] or '').replace('|', '/')} | {r['status']} | {', '.join(r.get('alerts', [])) or '-'} |")
    L.append("")
    manual = [(r, n) for r in results for n in r["not_translated"] if n.startswith(MANUAL)]
    if manual:
        L += ["## Manual conversion needed", "",
              "v1 refuses these on purpose rather than guess: on()/ignoring() vector matching and hysteresis "
              "(recovery thresholds, which do not map cleanly onto keep_firing_for). Convert them by hand.", "",
              "| Monitor | Name | Reason |", "|---|---|---|"]
        for r, n in manual:
            L.append(f"| {r['id']} | {(r['name'] or '').replace('|', '/')} | {n[len(MANUAL):].replace('|', '/')} |")
        L.append("")
    for r in results:
        if r["notes"] or r["not_translated"]:
            L.append(f"## {r['id']}: {r['name']}")
            L.append("")
            for n in r["notes"]:
                L.append(f"- Check: {n}")
            for n in r["not_translated"]:
                L.append(f"- Not translated: {n}")
            L.append("")
    return "\n".join(L)

def find_promtool(explicit):
    if explicit:
        return explicit
    return os.environ.get("PROMTOOL") or shutil.which("promtool")

def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--monitors", required=True, help="monitor export JSON")
    p.add_argument("--out", default=None,
                   help="rules YAML path (default: a new directory under ${TMPDIR:-/tmp}/obcost-conv-*)")
    p.add_argument("--report", default=None,
                   help="conversion report path (default: alongside --out)")
    p.add_argument("--map", help="JSON mapping: {\"metrics\": {dd_name: prom_name | {name, counter}}, \"labels\": {dd_tag: prom_label}}")
    p.add_argument("--ids", help="comma-separated monitor ids to convert (default: all)")
    p.add_argument("--group-name", default="converted-monitors")
    p.add_argument("--rate-window", default="2m", help="range for rate() inside subqueries (default 2m)")
    p.add_argument("--check", action="store_true", help="run promtool check rules on the output; exit 1 if it fails")
    p.add_argument("--promtool", help="path to promtool (default: $PROMTOOL or PATH)")
    a = p.parse_args(argv)
    workspace = None
    if a.out is None or a.report is None:
        workspace = tempfile.mkdtemp(prefix="obcost-conv-", dir=os.environ.get("TMPDIR") or None)
        if a.out is None:
            a.out = os.path.join(workspace, "converted.rules.yml")
        if a.report is None:
            a.report = os.path.join(workspace, "conversion-report.md")
        print(f"workspace: {workspace}", file=sys.stderr)
    if not re.fullmatch(r"\d+[smhdw]", a.rate_window):
        p.error("--rate-window must look like 2m")
    mapping = {}
    if a.map:
        with open(a.map) as f:
            mapping = json.load(f)
    ids = {int(x) for x in a.ids.split(",")} if a.ids else None
    rules, results = convert(load_monitors(a.monitors), mapping, ids, a.rate_window)
    with open(a.out, "w") as f:
        f.write(rules_yaml(a.group_name, rules))
    check = None
    if a.check:
        pt = find_promtool(a.promtool)
        if not pt:
            print("error: --check needs promtool on PATH, $PROMTOOL, or --promtool", file=sys.stderr)
            return 1
        r = subprocess.run([pt, "check", "rules", a.out], capture_output=True, text=True)
        check = (r.returncode, r.stdout + r.stderr)
    with open(a.report, "w") as f:
        f.write(report_md(results, a.out, check))
    conv = sum(1 for r in results if r["status"].startswith("converted"))
    print(f"wrote {a.out} ({len(rules)} rules from {conv}/{len(results)} monitors) and {a.report}", file=sys.stderr)
    if check is not None:
        print(check[1].strip(), file=sys.stderr)
        return 0 if check[0] == 0 else 1
    return 0

if __name__ == "__main__":
    sys.exit(main())

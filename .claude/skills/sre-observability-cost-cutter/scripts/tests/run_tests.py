#!/usr/bin/env python3
"""End-to-end tests for the cost audit (offline and mock-live) and the monitor converter.

Run from anywhere:  python3 scripts/tests/run_tests.py   (inside the skill folder)
promtool: found via $PROMTOOL, PATH or /home/box/bin. Without it the promtool tests are
skipped, unless REQUIRE_PROMTOOL=1 makes them fail. shellcheck is optional the same way.
Stdlib only; PyYAML is used when installed to parse the generated rules.
"""
import http.server
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.dirname(HERE)
FIX = os.path.join(HERE, "fixtures")
AUDIT = os.path.join(SCRIPTS, "dd_cost_audit.py")
CONV = os.path.join(SCRIPTS, "monitors_to_prom.py")
GATE = "**Gate: approval required.**"
API_SENTINEL, APP_SENTINEL = "sentinel-api-key-0f9e8d", "sentinel-app-key-7c6b5a"
COMMON = ["--month", "2026-09", "--as-of", "2026-10-18", "--example-label"]
SKILL = os.path.dirname(SCRIPTS)
DEMO = os.path.join(SKILL, "demo")
LABEL_RX = r"estimated from this org's Datadog estimated-cost data pulled (\d{4}-\d{2}-\d{2})"
NOT_GUARANTEED = "Savings are not guaranteed."
CONTRACT = "Actual savings depend on your contract, discounts and commitments."

def prose(md):
    """Report text without fenced code blocks (shell variables like $1 are not dollar figures)."""
    return re.sub(r"```.*?```", "", md, flags=re.S)

def check_dollar_labels(tc, md, date):
    text = prose(md)
    figures = re.findall(r"\$\d", text)
    labelled = re.findall(r"\$\d[\d,]*(?:/mo| per month)? \(" + LABEL_RX + r"\)", text)
    tc.assertGreater(len(figures), 0)
    tc.assertEqual(len(figures), len(labelled), "every dollar figure needs the source-and-date label")
    tc.assertEqual(set(labelled), {date}, "label must carry the pull date")

def check_disclaimers(tc, md):
    tc.assertIn(CONTRACT, md.split("## Estimated cost by product")[0], "contract statement near the top")
    lines = [l for l in prose(md).split("\n")]
    i = next(n for n, l in enumerate(lines) if l.startswith("### Upper-bound savings totals"))
    j = next(n for n in range(i, len(lines)) if lines[n].startswith("| **All priced items**"))
    after = next(l for l in lines[j + 1:] if l.strip())
    tc.assertIn(NOT_GUARANTEED, after, "not-guaranteed line right after the totals")
    tc.assertIn(CONTRACT, after)
    last_rule = max(n for n, l in enumerate(lines) if l.strip() == "---")
    footer = next(l for l in lines[last_rule + 1:] if l.strip())
    tc.assertIn(NOT_GUARANTEED, footer, "not-guaranteed line in the footer")
    tc.assertIn(CONTRACT, footer)

SYNTH = "SYNTHETIC EXAMPLE DATA, not from a real account"

def check_synthetic_everywhere(tc, md):
    """Label at the top, at the bottom, and as the first thing in every top-level section."""
    lines = md.split("\n")
    tc.assertTrue(any(SYNTH in l for l in lines[:5]), "label at the top")
    tc.assertIn(SYNTH, [l for l in lines if l.strip()][-1], "label at the bottom")
    fence, sections = False, 0
    for n, l in enumerate(lines):
        if l.startswith("```"):
            fence = not fence
        if not fence and l.startswith("## "):
            sections += 1
            first = next(x for x in lines[n + 1:] if x.strip())
            tc.assertIn(SYNTH, first, f"label at the start of section {l!r}")
    tc.assertGreaterEqual(sections, 4)

def ddw_helper(md):
    m = re.search(r"^ddw\(\) \{.*?^\}$", md, re.S | re.M)
    assert m, "ddw helper not found"
    return m.group(0)

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

audit = load(AUDIT, "dd_cost_audit")
conv = load(CONV, "monitors_to_prom")

def tool(name, env):
    p = os.environ.get(env) or shutil.which(name)
    if not p and os.path.exists(f"/home/box/bin/{name}"):
        p = f"/home/box/bin/{name}"
    return p

PROMTOOL = tool("promtool", "PROMTOOL")
SHELLCHECK = tool("shellcheck", "SHELLCHECK")
REQUIRE_PROMTOOL = os.environ.get("REQUIRE_PROMTOOL") == "1"

def run(args, env=None, cwd=None):
    e = dict(os.environ)
    for k in ("DD_API_KEY", "DD_APP_KEY", "DD_WRITE_API_KEY", "DD_WRITE_APP_KEY"):
        e.pop(k, None)
    e.update(env or {})
    return subprocess.run([sys.executable] + args, capture_output=True, text=True, env=e, cwd=cwd)

def read(path):
    with open(path) as f:
        return f.read()

def fenced_blocks(md):
    """Yield (line_above_fence, lang, body) for each fenced block."""
    lines = md.split("\n")
    i = 0
    while i < len(lines):
        if lines[i].startswith("```"):
            lang = lines[i][3:].strip()
            j = i - 1
            while j >= 0 and not lines[j].strip():
                j -= 1
            above = lines[j].strip() if j >= 0 else ""
            k = i + 1
            while not lines[k].startswith("```"):
                k += 1
            yield above, lang, "\n".join(lines[i + 1:k])
            i = k + 1
        else:
            i += 1

class OfflineAudit(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.report = os.path.join(cls.tmp, "report.md")
        cls.js = os.path.join(cls.tmp, "findings.json")
        r = run([AUDIT, "--input-dir", FIX, "--report", cls.report, "--json", cls.js, "--dollar-estimates"] + COMMON)
        assert r.returncode == 0, r.stderr
        cls.md = read(cls.report)
        cls.f = json.loads(read(cls.js))
        r2 = run([AUDIT, "--input-dir", FIX, "--report", os.path.join(cls.tmp, "nodollar.md")] + COMMON)
        assert r2.returncode == 0, r2.stderr
        cls.md_nodollar = read(os.path.join(cls.tmp, "nodollar.md"))

    def test_labels_and_disclaimer(self):
        self.assertIn("EXAMPLE REPORT built from fixture data", self.md)
        self.assertIn("All savings are estimates, not guarantees", self.md)
        self.assertIn("non-production", self.md)

    def test_ranking_and_findings(self):
        titles = [i["title"] for i in self.f["savings_items"]]
        self.assertEqual(len(titles), 11)
        self.assertEqual(titles[0], "Review: log index `main` has no active exclusion filter")
        self.assertTrue(all(t.startswith("Review: ") for t in titles), "thresholds raise review flags")
        usd = [i["upper_usd"] for i in self.f["savings_items"] if i["upper_usd"] is not None]
        self.assertEqual(usd, sorted(usd, reverse=True), "dollar upper bounds must be ranked biggest first")
        self.assertNotIn("Review: log index `security` has no active exclusion filter", self.md,
                         "indexes under --min-index-share get no exclusion flag")
        ret = [t for t in titles if "keeps logs" in t]
        self.assertEqual(sorted(ret), ["Review: log index `apps` keeps logs 30 days (check compliance first)",
                                       "Review: log index `audit` keeps logs 90 days (check compliance first)",
                                       "Review: log index `security` keeps logs 30 days (check compliance first)"])
        self.assertEqual(len(ret), 3, "every index over 15 days is flagged, whatever its share")
        self.assertTrue(all("(check compliance first)" in t for t in ret))
        self.assertNotIn("min-series", read(AUDIT), "no fixed series cutoff")

    def test_metrics_ranked_by_series_top_n(self):
        js = os.path.join(self.tmp, "top1.json")
        r = run([AUDIT, "--input-dir", FIX, "--report", os.devnull, "--json", js, "--top", "1"] + COMMON)
        self.assertEqual(r.returncode, 0, r.stderr)
        t = [i["title"] for i in json.loads(read(js))["savings_items"] if i["kind"] == "metric"]
        self.assertEqual(sorted(t), ["Review: high-cardinality custom metric `example.http.request.latency` (#1 by series)",
                                     "Review: unqueried custom metric `example.legacy.batch.duration` (#1 by series)",
                                     ])
        full = [i["title"] for i in self.f["savings_items"] if i["kind"] == "metric"]
        self.assertIn("Review: unqueried custom metric `example.tiny.unused` (#3 by series)", full,
                      "small metrics are ranked, not cut off")

    def test_exclusion_example_is_disabled_and_sampled(self):
        body = re.search(r"ddw PUT /api/v1/logs/config/indexes/main <<'JSON'\n(.*?)\nJSON", self.md, re.S).group(1)
        new = [f for f in json.loads(body)["exclusion_filters"] if f["name"].startswith("cost-cutter")][0]
        self.assertIs(new["is_enabled"], False)
        self.assertLessEqual(new["filter"]["sample_rate"], 0.9)
        self.assertIn("1.0 means none of the matching logs are kept", self.md)
        self.assertIn("use 0.9 or lower", self.md)

    def test_synthetic_label_everywhere(self):
        check_synthetic_everywhere(self, self.md)

    def test_committed_example_report_is_current_and_labelled(self):
        out = os.path.join(self.tmp, "example-report.md")
        r = run([AUDIT, "--input-dir", FIX, "--report", out, "--example-label", "--dollar-estimates"])
        self.assertEqual(r.returncode, 0, r.stderr)
        committed = read(os.path.join(SKILL, "references", "example-report.md"))
        self.assertEqual(read(out), committed, "references/example-report.md is stale; regenerate it")
        check_synthetic_everywhere(self, committed)
        self.assertTrue(all(i["upper_usd"] is None for i in self.f["savings_items"] if i["kind"] == "log_retention"))

    def test_monitor_hygiene(self):
        self.assertEqual(self.f["duplicate_monitor_groups"], [[1001, 1002]])
        self.assertEqual(self.f["not_triggered"], [1004, 1005, 1006])
        self.assertEqual(self.f["no_data"], [1006])
        self.assertEqual(self.f["rare_event_skipped"], [])
        self.assertIsNone(self.f["muted_long"], "fixtures have no matching_downtimes: check skipped")
        self.assertTrue(self.f["muted_check_skipped"])
        self.assertIn(audit.MUTED_SKIPPED, self.md)
        self.assertNotRegex(self.md, r"Muted for more than \d+ days: 0")

    def test_every_write_is_gated(self):
        writes = 0
        for above, lang, body in fenced_blocks(self.md):
            if re.search(r"^ddw (POST|PUT|PATCH|DELETE)\b", body, re.M):
                writes += 1
                self.assertEqual(above, GATE, f"write block without gate:\n{body[:200]}")
            elif lang == "bash":
                self.assertNotRegex(body, r"-X\s*(POST|PUT|PATCH|DELETE)\b|^ddw (POST|PUT|DELETE)", "ungated write")
        self.assertGreaterEqual(writes, 20)

    def test_heredoc_bodies_are_json(self):
        for _, _, body in fenced_blocks(self.md):
            for m in re.finditer(r"<<'JSON'\n(.*?)\nJSON", body, re.S):
                json.loads(m.group(1))

    def test_every_dollar_figure_is_labelled_with_pull_date(self):
        check_dollar_labels(self, self.md, "2026-10-18")

    def test_contract_and_not_guaranteed_statements(self):
        check_disclaimers(self, self.md)

    def test_totals_add_up(self):
        priced = [i["upper_usd"] for i in self.f["savings_items"] if i["upper_usd"] is not None]
        m = re.search(r"\| \*\*All priced items\*\* \| \*\*\$([\d,]+)/mo", self.md)
        self.assertEqual(int(m.group(1).replace(",", "")), round(sum(priced)))

    def test_pull_date_falls_back_to_file_date(self):
        d = tempfile.mkdtemp()
        for fn in os.listdir(FIX):
            if fn != "audit_meta.json":
                shutil.copy(os.path.join(FIX, fn), d)
        os.utime(os.path.join(d, "estimated_cost.json"), (1790000000, 1790000000))  # 2026-09-21 UTC
        out = os.path.join(d, "r.md")
        r = run([AUDIT, "--input-dir", d, "--report", out, "--dollar-estimates"] + COMMON)
        self.assertEqual(r.returncode, 0, r.stderr)
        md = read(out)
        check_dollar_labels(self, md, "2026-09-21")
        self.assertIn("file date of estimated_cost.json", md)

    def test_index_put_body_is_full_config(self):
        body = re.search(r"ddw PUT /api/v1/logs/config/indexes/apps <<'JSON'\n(.*?)\nJSON", self.md, re.S).group(1)
        d = json.loads(body)
        self.assertEqual(d["filter"], {"query": "service:example-*"})
        self.assertEqual(len(d["exclusion_filters"]), 2, "existing filter kept, new one appended")
        self.assertNotIn("name", d)
        self.assertNotIn("is_rate_limited", d)

    def test_no_dollar_figures_without_flag(self):
        plan = re.sub(r"```.*?```", "", self.md_nodollar.split("## Ranked savings plan")[1], flags=re.S)
        self.assertIsNone(re.search(r"\$\d", plan), "no dollar savings figure unless --dollar-estimates")
        self.assertIn("$ <fill in from contract>", plan)

    def test_missing_inputs_are_reported(self):
        d = tempfile.mkdtemp()
        for fn in ("log_indexes.json", "logs_by_index.json"):
            shutil.copy(os.path.join(FIX, fn), d)
        out = os.path.join(d, "r.md")
        r = run([AUDIT, "--input-dir", d, "--report", out] + COMMON)
        self.assertEqual(r.returncode, 0, r.stderr)
        md = read(out)
        self.assertIn("## Data not available", md)
        self.assertIn("usage_summary.json not in input dir", md)

    def test_shellcheck_report_blocks(self):
        if not SHELLCHECK:
            self.skipTest("shellcheck not installed")
        d = tempfile.mkdtemp()
        n = 0
        for _, lang, body in fenced_blocks(self.md):
            if lang == "bash":
                n += 1
                p = os.path.join(d, f"b{n}.sh")
                with open(p, "w") as f:
                    f.write("#!/usr/bin/env bash\n" + body + "\n")
                r = subprocess.run([SHELLCHECK, "-S", "warning", "-e", "SC2034", p], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, r.stdout + body)
        self.assertGreater(n, 10)

class Demo(unittest.TestCase):
    def test_demo_covers_every_offline_input(self):
        for fn in list(audit.INPUT_FILES.values()) + ["audit_meta.json", "README.md", "demo-report.md"]:
            self.assertTrue(os.path.exists(os.path.join(DEMO, fn)), fn)
        meta = json.loads(read(os.path.join(DEMO, "audit_meta.json")))
        self.assertIs(meta["synthetic"], True)
        self.assertIn("SYNTHETIC", read(os.path.join(DEMO, "README.md")))

    def test_demo_report_is_reproducible_and_labelled(self):
        out = os.path.join(tempfile.mkdtemp(), "demo-report.md")
        r = run([AUDIT, "--input-dir", DEMO, "--dollar-estimates", "--out", out])
        self.assertEqual(r.returncode, 0, r.stderr)
        fresh, committed = read(out), read(os.path.join(DEMO, "demo-report.md"))
        self.assertEqual(fresh, committed, "demo/demo-report.md is stale; maintainers: --out demo/demo-report.md")
        head = "\n".join(committed.split("\n")[:5])
        self.assertIn("SYNTHETIC EXAMPLE DATA, not from a real account", head)
        self.assertNotIn("## Data not available", committed)
        check_dollar_labels(self, committed, "2026-10-01")
        check_disclaimers(self, committed)
        check_synthetic_everywhere(self, committed)
        self.assertIn("Example Corp", head)

    def test_demo_names_are_fictional(self):
        blob = "\n".join(read(os.path.join(DEMO, f)) for f in os.listdir(DEMO))
        for host in set(re.findall(r"\b(?:[a-z0-9-]+\.)+(?:com|net|org|io|dev|co)\b", blob, re.I)):
            self.assertRegex(host.lower(), r"(^|\.)example\.com$", host)
        for word in ("slack", "pagerduty", "nginx", "envoy", "kubernetes", "k8s", "storefront", "checkout", "ledger"):
            self.assertNotIn(word, blob.lower(), word)

    def demo_findings(self, *extra):
        js = os.path.join(tempfile.mkdtemp(), "f.json")
        r = run([AUDIT, "--input-dir", DEMO, "--out", os.devnull, "--json", js] + list(extra))
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(read(js))

    def test_rare_event_monitors_are_skipped_and_overridable(self):
        f = self.demo_findings()
        self.assertEqual(f["rare_event_skipped"], [5022, 5023, 5024])
        self.assertFalse(set(f["rare_event_skipped"]) & set(f["not_triggered"]))
        md = read(os.path.join(DEMO, "demo-report.md"))
        self.assertIn("### Skipped: rare-event monitors", md)
        for k in audit.RARE_EVENT_KEYWORDS:
            self.assertIn(k, read(os.path.join(SKILL, "SKILL.md")), f"keyword {k} listed in SKILL.md")
        g = self.demo_findings("--rare-event-keywords", "")
        self.assertEqual(g["rare_event_skipped"], [])
        self.assertTrue({5022, 5023, 5024} <= set(g["not_triggered"]))
        h = self.demo_findings("--rare-event-keywords", "backup")
        self.assertEqual(h["rare_event_skipped"], [5023])

    def test_long_mutes_are_flagged(self):
        f = self.demo_findings()
        self.assertEqual(f["muted_long"], [5025], "5026 is muted for only 6 days")
        self.assertIn("### Muted for more than 30 days (review)", read(os.path.join(DEMO, "demo-report.md")))
        self.assertEqual(self.demo_findings("--muted-days", "5")["muted_long"], [5025, 5026])
        self.assertFalse(f["muted_check_skipped"])
        self.assertNotIn("Muted-monitor check skipped", read(os.path.join(DEMO, "demo-report.md")))

    def test_muted_check_skipped_only_when_field_missing_everywhere(self):
        mons = json.loads(read(os.path.join(DEMO, "monitors.json")))
        asof = int(audit.dt.datetime(2026, 10, 1, tzinfo=audit.dt.timezone.utc).timestamp())
        stripped = [{k: v for k, v in m.items() if k != "matching_downtimes"} for m in mons]
        _, _, _, _, muted = audit.monitor_findings(stripped, None, asof, 90)
        self.assertIsNone(muted, "field missing everywhere: skipped, not zero")
        empty = [dict(m, matching_downtimes=[]) for m in stripped]
        _, _, _, _, muted = audit.monitor_findings(empty, None, asof, 90)
        self.assertEqual(muted, [], "field present but empty: checked, nothing muted")
        _, _, _, _, muted = audit.monitor_findings(mons, None, asof, 90)
        self.assertEqual([m["id"] for m, _ in muted], [5025], "field present: normal flagging")
        d = tempfile.mkdtemp()
        for fn in os.listdir(DEMO):
            if fn.endswith(".json"):
                shutil.copy(os.path.join(DEMO, fn), d)
        with open(os.path.join(d, "monitors.json"), "w") as fh:
            json.dump(stripped, fh)
        out, js = os.path.join(d, "r.md"), os.path.join(d, "f.json")
        r = run([AUDIT, "--input-dir", d, "--out", out, "--json", js])
        self.assertEqual(r.returncode, 0, r.stderr)
        md = read(out)
        self.assertIn(audit.MUTED_SKIPPED, md)
        self.assertNotRegex(md, r"Muted for more than \d+ days")
        self.assertIsNone(json.loads(read(js))["muted_long"])

    def test_demo_has_a_spread_of_findings(self):
        js = os.path.join(tempfile.mkdtemp(), "f.json")
        r = run([AUDIT, "--input-dir", DEMO, "--dollar-estimates", "--out", os.devnull, "--json", js])
        self.assertEqual(r.returncode, 0, r.stderr)
        f = json.loads(read(js))
        kinds = {i["kind"] for i in f["savings_items"]}
        self.assertEqual(kinds, {"metric", "log_exclusion", "log_retention"})
        self.assertGreaterEqual(len(f["duplicate_monitor_groups"]), 2)
        self.assertGreaterEqual(len(f["not_triggered"]), 3)
        self.assertGreaterEqual(len(f["no_data"]), 2)
        self.assertGreaterEqual(len(f["rare_event_skipped"]), 2)
        self.assertGreaterEqual(len(f["muted_long"]), 1)


    def test_default_demo_run_leaves_skill_tree_and_git_clean(self):
        """Default outputs go under TMPDIR; a demo run must not dirty the skill or git status."""
        def fingerprint(root):
            rows = []
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames[:] = [d for d in dirnames if d != "__pycache__"]
                for fn in filenames:
                    if fn.endswith(".pyc"):
                        continue
                    path = os.path.join(dirpath, fn)
                    st = os.stat(path)
                    rows.append((os.path.relpath(path, root), st.st_size, int(st.st_mtime)))
            return rows
        repo = os.path.dirname(os.path.dirname(os.path.dirname(SKILL)))
        rel = os.path.relpath(SKILL, repo)
        before_git = ""
        if os.path.isdir(os.path.join(repo, ".git")):
            g0 = subprocess.run(["git", "status", "--porcelain", "--", rel],
                                cwd=repo, capture_output=True, text=True)
            self.assertEqual(g0.returncode, 0, g0.stderr)
            before_git = g0.stdout
        before = fingerprint(SKILL)
        tmp_parent = tempfile.mkdtemp(prefix="obcost-test-tmp-")
        env = {"TMPDIR": tmp_parent}
        r = run([AUDIT, "--input-dir", DEMO, "--dollar-estimates"], cwd=SKILL, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        m = re.search(r"^workspace: (.+)$", r.stderr, re.M)
        self.assertIsNotNone(m, r.stderr)
        ws = m.group(1).strip()
        self.assertTrue(ws.startswith(tmp_parent), ws)
        self.assertTrue(os.path.isfile(os.path.join(ws, "cost-audit-report.md")))
        self.assertTrue(os.path.isfile(os.path.join(ws, "findings.json")))
        self.assertEqual(fingerprint(SKILL), before, "skill tree changed after default demo run")
        r2 = run([CONV, "--monitors", os.path.join(DEMO, "monitors.json")], cwd=SKILL, env=env)
        self.assertEqual(r2.returncode, 0, r2.stderr)
        m2 = re.search(r"^workspace: (.+)$", r2.stderr, re.M)
        self.assertIsNotNone(m2, r2.stderr)
        self.assertTrue(m2.group(1).strip().startswith(tmp_parent))
        self.assertEqual(fingerprint(SKILL), before, "skill tree changed after default converter run")
        if os.path.isdir(os.path.join(repo, ".git")):
            g1 = subprocess.run(["git", "status", "--porcelain", "--", rel],
                                cwd=repo, capture_output=True, text=True)
            self.assertEqual(g1.returncode, 0, g1.stderr)
            self.assertEqual(g1.stdout, before_git, "demo/converter changed git status for the skill")

class MockDatadog(http.server.BaseHTTPRequestHandler):
    seen = []
    throttled = set()

    def log_message(self, *a):
        pass

    def _send(self, code, obj, headers=None):
        b = json.dumps(obj).encode()
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _fix(self, name):
        return json.loads(read(os.path.join(FIX, name)))

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(u.query)
        MockDatadog.seen.append(("GET", u.path, self.headers.get("DD-API-KEY"), self.headers.get("DD-APPLICATION-KEY")))
        p = u.path
        if p == "/api/v1/usage/summary" and p not in MockDatadog.throttled:
            MockDatadog.throttled.add(p)
            return self._send(429, {"errors": ["Rate limit exceeded"]}, {"X-RateLimit-Reset": "1"})
        routes = {"/api/v1/usage/summary": "usage_summary.json", "/api/v1/usage/top_avg_metrics": "top_avg_metrics.json",
                  "/api/v1/logs/config/indexes": "log_indexes.json", "/api/v1/usage/logs_by_index": "logs_by_index.json",
                  "/api/v1/query": "logs_ingest_by_index.json", "/api/v1/monitor/search": "monitor_search.json"}
        if p == "/api/v2/usage/estimated_cost":
            return self._send(403, {"errors": ["Forbidden"]})
        if p == "/api/v2/metrics":
            return self._send(200, self._fix("metrics_unqueried.json" if qs.get("filter[queried]") == ["false"]
                                             else "metrics_by_volume.json"))
        if p == "/api/v1/monitor":
            return self._send(200, self._fix("monitors.json") if qs.get("page") == ["0"] else [])
        if p in routes:
            return self._send(200, self._fix(routes[p]))
        return self._send(404, {"errors": ["not found"]})

    def do_POST(self):
        MockDatadog.seen.append(("POST", self.path, None, None))
        self._send(405, {"errors": ["no writes"]})

    do_PUT = do_PATCH = do_DELETE = do_POST

class LiveAgainstMock(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), MockDatadog)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.srv.server_address[1]}"
        cls.tmp = tempfile.mkdtemp()
        cls.save = os.path.join(cls.tmp, "raw")
        cls.report = os.path.join(cls.tmp, "live.md")
        cls.js = os.path.join(cls.tmp, "live.json")
        cls.r = run([AUDIT, "--base-url", cls.base, "--save-dir", cls.save, "--report", cls.report, "--json", cls.js,
                     "--month", "2026-09", "--as-of", "2026-10-18"],
                    env={"DD_API_KEY": API_SENTINEL, "DD_APP_KEY": APP_SENTINEL, "DD_SITE": "datadoghq.com"})

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def test_runs_and_only_reads(self):
        self.assertEqual(self.r.returncode, 0, self.r.stderr)
        methods = {m for m, _, _, _ in MockDatadog.seen}
        self.assertEqual(methods, {"GET"})
        paths = {p for _, p, _, _ in MockDatadog.seen}
        self.assertTrue(paths <= set(audit.READ_PATHS), paths - set(audit.READ_PATHS))
        self.assertTrue(all(a == API_SENTINEL and b == APP_SENTINEL for _, _, a, b in MockDatadog.seen))
        self.assertIn("rate limited on GET /api/v1/usage/summary", self.r.stderr)

    def test_keys_never_leak(self):
        blobs = [self.r.stdout, self.r.stderr, read(self.report), read(self.js)]
        for fn in os.listdir(self.save):
            blobs.append(read(os.path.join(self.save, fn)))
        for b in blobs:
            self.assertNotIn(API_SENTINEL, b)
            self.assertNotIn(APP_SENTINEL, b)

    def test_forbidden_source_reported_and_offline_rerun_matches(self):
        md = read(self.report)
        self.assertIn("HTTP 403 from GET /api/v2/usage/estimated_cost", md)
        self.assertFalse(os.path.exists(os.path.join(self.save, "estimated_cost.json")))
        out_js = os.path.join(self.tmp, "offline.json")
        r = run([AUDIT, "--input-dir", self.save, "--report", os.path.join(self.tmp, "o.md"), "--json", out_js,
                 "--month", "2026-09", "--as-of", "2026-10-18"])
        self.assertEqual(r.returncode, 0, r.stderr)
        a, b = json.loads(read(self.js)), json.loads(read(out_js))
        for k in ("savings_items", "duplicate_monitor_groups", "not_triggered", "no_data"):
            self.assertEqual(a[k], b[k], k)

class WriteHelper(unittest.TestCase):
    """Runs the report's ddw helper in bash against a fake curl that records what it was given."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        out = os.path.join(cls.tmp, "r.md")
        r = run([AUDIT, "--input-dir", FIX, "--report", out, "--dollar-estimates"] + COMMON)
        assert r.returncode == 0, r.stderr
        cls.md = read(out)
        cls.helper = ddw_helper(cls.md)
        bindir = os.path.join(cls.tmp, "bin")
        os.makedirs(bindir)
        cls.log = os.path.join(cls.tmp, "curl.log")
        with open(os.path.join(bindir, "curl"), "w") as f:
            f.write('#!/usr/bin/env bash\n{ printf "ARGS %s\\n" "$*"; prev=""\n'
                    '  for a in "$@"; do if [ "$prev" = "-H" ] && [ "${a#@}" != "$a" ]; then cat "${a#@}"; fi; prev="$a"; done\n'
                    '  printf "BODY "; cat; echo; } >> "$CURL_LOG"\n')
        os.chmod(os.path.join(bindir, "curl"), 0o755)
        cls.path = bindir + os.pathsep + os.environ.get("PATH", "")

    def ddw(self, body, env):
        if os.path.exists(self.log):
            os.remove(self.log)
        e = {"PATH": self.path, "CURL_LOG": self.log, "HOME": self.tmp}
        e.update(env)
        script = self.helper + "\nddw PUT /api/v1/logs/config/indexes/main <<'JSON'\n" + body + "\nJSON\n"
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=e)
        return r, (read(self.log) if os.path.exists(self.log) else "")

    READ = {"DD_API_KEY": "read-api-sentinel", "DD_APP_KEY": "read-app-sentinel", "DD_SITE": "datadoghq.com"}
    WRITE = {"DD_WRITE_API_KEY": "write-api-sentinel", "DD_WRITE_APP_KEY": "write-app-sentinel"}

    def test_ignores_read_keys_and_refuses_without_write_keys(self):
        r, log = self.ddw('{"num_retention_days": 15}', self.READ)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("DD_WRITE_API_KEY and DD_WRITE_APP_KEY", r.stderr)
        self.assertEqual(log, "", "curl must not run")
        self.assertNotRegex(self.helper, r"\$\{?DD_(API|APP)_KEY", "helper never expands the read keys")

    def test_uses_write_keys_only(self):
        r, log = self.ddw('{"num_retention_days": 15}', dict(self.READ, **self.WRITE))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("ARGS -sS -X PUT https://api.datadoghq.com/api/v1/logs/config/indexes/main", log)
        self.assertIn("DD-API-KEY: write-api-sentinel", log)
        self.assertIn("DD-APPLICATION-KEY: write-app-sentinel", log)
        self.assertNotIn("read-api-sentinel", log)
        self.assertNotIn("read-app-sentinel", log)
        self.assertIn('BODY {"num_retention_days": 15}', log)

    def test_refuses_placeholder_bodies(self):
        bodies = [m.group(1) for m in re.finditer(r"<<'JSON'\n(.*?)\nJSON", self.md, re.S)]
        with_ph = [b for b in bodies if re.search(audit.PLACEHOLDER_RX, b)]
        self.assertGreater(len(with_ph), 3)
        self.assertTrue(any("cost-cutter: <describe" in b for b in with_ph), "the exclusion example is among them")
        for b in with_ph:
            r, log = self.ddw(b, dict(self.READ, **self.WRITE))
            self.assertNotEqual(r.returncode, 0, b[:200])
            self.assertIn("placeholder", r.stderr)
            self.assertEqual(log, "", "curl must not run for a placeholder body")

class AuditGuards(unittest.TestCase):
    def test_audit_uses_read_keys_only(self):
        src = read(AUDIT)
        self.assertNotRegex(src, r'environ(\.get)?\(?\[?"DD_WRITE_', "audit never reads the write keys")
        r = run([AUDIT, "--report", "/dev/null"], env={"DD_WRITE_API_KEY": "x", "DD_WRITE_APP_KEY": "y"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("DD_API_KEY and DD_APP_KEY must be set", r.stderr)

    def test_log_index_403_falls_back_to_saved_export(self):
        os.environ["DD_API_KEY"], os.environ["DD_APP_KEY"] = "x", "y"
        try:
            src = audit.LiveSource("datadoghq.com")
        finally:
            del os.environ["DD_API_KEY"], os.environ["DD_APP_KEY"]

        def deny(path, params=None):
            raise audit.AuditError(f"HTTP 403 from GET {path}")
        src.http_get = deny
        self.assertIsNone(src.get("log_indexes", lambda: src.http_get("/api/v1/logs/config/indexes")))
        msg = src.unavailable["log_indexes"]
        self.assertIn("not supported with it", msg)
        self.assertIn("saved index export", msg)
        self.assertIn("--input-dir", msg)

    def test_allow_list_refuses_other_paths(self):
        os.environ["DD_API_KEY"], os.environ["DD_APP_KEY"] = "x", "y"
        try:
            src = audit.LiveSource("datadoghq.com")
            for path in ("/api/v1/monitor/123", "/api/v2/metrics/m/tags", "/api/v1/logs/config/indexes/main"):
                with self.assertRaises(audit.AuditError):
                    src.http_get(path)
        finally:
            del os.environ["DD_API_KEY"], os.environ["DD_APP_KEY"]

    def test_no_write_verbs_in_audit_source(self):
        src = read(AUDIT)
        self.assertNotRegex(src, r'method="(POST|PUT|PATCH|DELETE)"')
        self.assertEqual(len(re.findall(r'method="GET"', src)), 1)

    def test_base_url_is_test_only(self):
        r = run([AUDIT, "--base-url", "https://evil.example.com", "--report", "/dev/null"],
                env={"DD_API_KEY": "x", "DD_APP_KEY": "y"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("only accepts http://127.0.0.1", r.stderr)

    def test_missing_keys_and_bad_site(self):
        r = run([AUDIT, "--report", "/dev/null"])
        self.assertEqual(r.returncode, 2)
        self.assertIn("DD_API_KEY and DD_APP_KEY must be set", r.stderr)
        r = run([AUDIT, "--report", "/dev/null"], env={"DD_API_KEY": "x", "DD_APP_KEY": "y", "DD_SITE": "example.com"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown DD_SITE", r.stderr)

class Converter(unittest.TestCase):
    MAP = {"labels": {"host": "instance"}, "metrics": {"m.c": {"name": "c_total", "counter": True}}}
    CASES = [
        ("avg(last_5m):avg:system.load.1{env:prod} by {host} > 2",
         'avg_over_time((avg by (instance) (system_load_1{env="prod"}))[5m:])', ">", "2"),
        ("max(last_1h):max:disk.used{*} >= 0.9", "max_over_time((max(disk_used))[1h:])", ">=", "0.9"),
        ("sum(last_10m):sum:m.c{svc:a}.as_count() / sum:m.c{*}.as_count() > 0.1",
         'sum(increase(c_total{svc="a"}[10m])) / sum(increase(c_total[10m]))', ">", "0.1"),
        ("avg(last_5m):sum:m.c{*}.as_rate() < 1", "sum(rate(c_total[5m]))", "<", "1"),
        ("min(last_5m):avg:x.y{!env:dev,role:web-*} < 10",
         'min_over_time((avg(x_y{env!="dev",role=~"web\\\\-.*"}))[5m:])', "<", "10"),
        ("avg(last_5m):abs(avg:x.y{*} - week_before(avg:x.y{*})) > 5",
         "avg_over_time((abs(avg(x_y) - avg(x_y offset 1w)))[5m:])", ">", "5"),
        ("avg(last_5m):avg:x.y{env NOT IN (dev,test)} != 0",
         'avg_over_time((avg(x_y{env!~"dev|test"}))[5m:])', "!=", "0"),
        ("pct_change(avg(last_5m),5m_ago):avg:x.y{*} > 50",
         "avg_over_time((((avg(x_y)) - (avg(x_y offset 5m))) / (avg(x_y offset 5m)) * 100)[5m:])", ">", "50"),
    ]
    UNSUPPORTED = [
        ("avg(last_5m):anomalies(avg:x{*}, 'basic', 2) >= 1", "anomalies"),
        ("avg(last_5m):forecast(avg:x{*}, 'linear', 1) > 1", "forecast"),
        ("avg(last_5m):avg:x{env:a OR env:b} > 1", "boolean scope"),
        ("avg(last_5m):avg:e{*} by {host} / avg:r{*} by {service} > 1", "on()/ignoring()"),
        ("avg(last_5m):avg:x{prod} > 1", "has no key"),
        ("avg(last_5m):sum:x{*}.as_count() > 1", "only make sense with sum"),
        ("sum(last_5m):sum:a{*}.as_count() / sum:b{*} > 1", "mixes .as_count()"),
        ("avg(last_5m):avg:x{*} > threshold", "no numeric threshold"),
        ("percentile(last_5m):p95:x{*} > 1", "not supported"),
    ]

    def test_translation_table(self):
        for query, expr, op, val in self.CASES:
            got = conv.convert_query(query, self.MAP)
            self.assertEqual((got[0], got[1], got[2]), (expr, op, val), query)

    def test_unsupported_is_reported_not_guessed(self):
        for query, why in self.UNSUPPORTED:
            with self.assertRaises(conv.Unsupported, msg=query) as cm:
                conv.convert_query(query, self.MAP)
            self.assertIn(why, str(cm.exception), query)

    def test_templates(self):
        notes = set()
        out = conv.convert_text("{{#is_alert}}Host {{host.name}} at {{value}} > {{threshold}} {{foo.bar}}{{/is_alert}} @pagerduty-x",
                                ["instance"], self.MAP, {"critical": 3}, notes)
        self.assertEqual(out, "Host {{ $labels.instance }} at {{ $value }} > 3")
        self.assertTrue(any("foo.bar" in n for n in notes))

    def test_end_to_end_with_promtool(self):
        d = tempfile.mkdtemp()
        rules, rep = os.path.join(d, "converted.rules.yml"), os.path.join(d, "conversion.md")
        r = run([CONV, "--monitors", os.path.join(FIX, "monitors.json"), "--map", os.path.join(FIX, "mapping.json"),
                 "--out", rules, "--report", rep])
        self.assertEqual(r.returncode, 0, r.stderr)
        md = read(rep)
        status = dict(re.findall(r"^\| (\d+) \| [^|]* \| ([^|]+?) \|", md.split("## Manual")[0], re.M))
        self.assertEqual(status, {"1001": "converted with notes", "1002": "converted with notes", "1003": "converted",
                                  "1004": "converted with notes", "1005": "skipped", "1006": "converted with notes",
                                  "1007": "skipped", "1008": "converted", "1009": "converted",
                                  "1010": "skipped", "1011": "skipped"})
        self.assertIn("Not translated: anomalies()", md)
        self.assertIn("## Manual conversion needed", md)
        self.assertIn("Not translated: manual conversion needed (v1 refuses this): recovery thresholds", md)
        self.assertIn("do not map cleanly onto keep_firing_for", md)
        self.assertIn("hysteresis", md)
        self.assertIn("on()/ignoring()", md)
        self.assertRegex(md, r"\| 1011 \| [^|]+ \| the queries are grouped by different tags")
        self.assertIn("Not translated: evaluation delay", md)
        try:
            import yaml
            doc = yaml.safe_load(read(rules))
            self.assertEqual(len(doc["groups"][0]["rules"]), 10)
        except ImportError:
            pass
        if not PROMTOOL:
            if REQUIRE_PROMTOOL:
                self.fail("promtool not found and REQUIRE_PROMTOOL=1")
            self.skipTest("promtool not installed; rule syntax and unit tests not run")
        c = subprocess.run([PROMTOOL, "check", "rules", rules], capture_output=True, text=True)
        self.assertEqual(c.returncode, 0, c.stdout + c.stderr)
        self.assertIn("SUCCESS: 10 rules found", c.stdout + c.stderr)
        shutil.copy(os.path.join(FIX, "converted.test.yml"), d)
        t = subprocess.run([PROMTOOL, "test", "rules", "converted.test.yml"], capture_output=True, text=True, cwd=d)
        self.assertEqual(t.returncode, 0, t.stdout + t.stderr)
        # --check wires promtool into the converter itself
        r = run([CONV, "--monitors", os.path.join(FIX, "monitors.json"), "--map", os.path.join(FIX, "mapping.json"),
                 "--out", rules, "--report", rep, "--check", "--promtool", PROMTOOL])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("**passed**", read(rep))

    def test_check_fails_on_bad_rules(self):
        if not PROMTOOL:
            self.skipTest("promtool not installed")
        d = tempfile.mkdtemp()
        bad = os.path.join(d, "bad.rules.yml")
        with open(bad, "w") as f:
            f.write('groups:\n  - name: x\n    rules:\n      - alert: "Bad"\n        expr: "sum(rate(x[5m])"\n')
        c = subprocess.run([PROMTOOL, "check", "rules", bad], capture_output=True, text=True)
        self.assertNotEqual(c.returncode, 0)

if __name__ == "__main__":
    print(f"promtool: {PROMTOOL or 'not found'}; shellcheck: {SHELLCHECK or 'not found'}", file=sys.stderr)
    unittest.main(verbosity=2)

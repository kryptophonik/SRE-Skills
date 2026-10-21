#!/usr/bin/env python3
"""Read-only observability usage and cost audit (works with Datadog).

Collects usage, metric volume, log index and monitor data with GET requests only,
then writes a ranked savings plan in Markdown. Every proposed change in the report
is printed for a human to run after approval; this script never sends a write.

Live mode : DD_API_KEY, DD_APP_KEY (read-only service account) and DD_SITE from the environment.
            The report's write helper uses separate DD_WRITE_API_KEY / DD_WRITE_APP_KEY variables;
            this script never reads those. It does not check what a key is allowed to do.
Offline   : --input-dir DIR with the JSON files listed in INPUT_FILES (for example
            files saved earlier with --save-dir, or the test fixtures).

Keys are only placed in request headers. They are never printed, logged or saved.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

SITES = ("datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com", "datadoghq.eu",
         "ap1.datadoghq.com", "ap2.datadoghq.com", "uk1.datadoghq.com",
         "ddog-gov.com", "us2.ddog-gov.com")

# Every request the audit can make. GET only; anything else is refused in http_get().
READ_PATHS = (
    "/api/v1/usage/summary", "/api/v2/usage/estimated_cost", "/api/v1/usage/top_avg_metrics",
    "/api/v2/metrics", "/api/v1/logs/config/indexes", "/api/v1/usage/logs_by_index",
    "/api/v1/query", "/api/v1/monitor", "/api/v1/monitor/search",
)

INPUT_FILES = {
    "usage_summary": "usage_summary.json",
    "estimated_cost": "estimated_cost.json",
    "top_avg_metrics": "top_avg_metrics.json",
    "metrics_unqueried": "metrics_unqueried.json",
    "metrics_by_volume": "metrics_by_volume.json",
    "log_indexes": "log_indexes.json",
    "logs_by_index": "logs_by_index.json",
    "logs_ingest_by_index": "logs_ingest_by_index.json",
    "monitors": "monitors.json",
    "monitor_search": "monitor_search.json",
}

# Fields a log index PUT accepts (LogsIndexUpdateRequest). PUT replaces the whole config.
INDEX_PUT_FIELDS = ("filter", "exclusion_filters", "num_retention_days", "num_flex_logs_retention_days",
                    "daily_limit", "daily_limit_reset", "daily_limit_warning_threshold_percentage", "tags")

META_FILE = "audit_meta.json"  # pull date, month, and a synthetic-data label for demo sets
GATE = "**Gate: approval required.**"
NOT_GUARANTEED = "Savings are not guaranteed."
CONTRACT = "Actual savings depend on your contract, discounts and commitments."
COST_LABEL = "estimated from this org's Datadog estimated-cost data pulled"
SYNTH_LABEL = "> **SYNTHETIC EXAMPLE DATA, not from a real account.**"
RARE_EVENT_KEYWORDS = ("cert", "certificate", "ssl", "tls", "expiry", "expiration", "expire", "expires",
                       "disaster", "dr", "backup", "backups", "restore", "failover")
MUTED_SKIPPED = ("Muted-monitor check skipped: the monitor list had no downtime data (`matching_downtimes`), "
                 "so this report can't say whether any monitors are muted.")
PLACEHOLDER_RX = r"<[A-Za-z][^<>]*>"  # also used by the ddw helper's refusal check
DISCLAIMER = ("> **Before you change anything:** test every change in a non-production org or on a "
              "low-risk index or metric first. The operator reviews and approves each change; nothing "
              "in this report is applied automatically. All savings are estimates, not guarantees. "
              + CONTRACT + " The audit script "
              "only sent read (GET) requests in testing; review it before giving it any key.")

class AuditError(Exception):
    pass

def log(msg):
    print(msg, file=sys.stderr)

# --------------------------------------------------------------------------- data access
class LiveSource:
    def __init__(self, site, base_url=None, save_dir=None, max_retries=3):
        self.api_key = os.environ.get("DD_API_KEY", "")
        self.app_key = os.environ.get("DD_APP_KEY", "")
        if not self.api_key or not self.app_key:
            raise AuditError("DD_API_KEY and DD_APP_KEY must be set (use a read-only service account key)")
        if base_url:  # test hook: only a local mock server is accepted
            if not re.match(r"^http://(127\.0\.0\.1|localhost)(:\d+)?$", base_url):
                raise AuditError("--base-url only accepts http://127.0.0.1:<port> (test use)")
            self.base = base_url
        else:
            if site not in SITES:
                raise AuditError(f"unknown DD_SITE '{site}'; expected one of: {', '.join(SITES)}")
            self.base = f"https://api.{site}"
        self.save_dir = save_dir
        self.max_retries = max_retries
        self.unavailable = {}

    def http_get(self, path, params=None):
        if path not in READ_PATHS:
            raise AuditError(f"refusing request outside the read-only allow-list: GET {path}")
        url = self.base + path + ("?" + urllib.parse.urlencode(params, doseq=True) if params else "")
        req = urllib.request.Request(url, method="GET", headers={
            "DD-API-KEY": self.api_key, "DD-APPLICATION-KEY": self.app_key, "Accept": "application/json"})
        attempt = 0
        while True:
            attempt += 1
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return json.loads(r.read().decode() or "null")
            except urllib.error.HTTPError as e:
                if e.code == 429 and attempt <= self.max_retries:
                    reset = e.headers.get("X-RateLimit-Reset", "")
                    wait = min(int(reset) if reset.isdigit() else 2 ** attempt, 60)
                    log(f"rate limited on GET {path}; retrying in {wait}s ({attempt}/{self.max_retries})")
                    time.sleep(wait)
                    continue
                detail = ""
                try:
                    detail = "; ".join(str(x) for x in json.loads(e.read().decode()).get("errors", []))[:300]
                except Exception:
                    pass
                raise AuditError(f"HTTP {e.code} from GET {path}" + (f": {detail}" if detail else ""))
            except urllib.error.URLError as e:
                raise AuditError(f"network error on GET {path}: {e.reason}")

    def _save(self, name, data):
        if self.save_dir:
            os.makedirs(self.save_dir, exist_ok=True)
            with open(os.path.join(self.save_dir, INPUT_FILES[name]), "w") as f:
                json.dump(data, f, indent=1, sort_keys=True)

    def get(self, name, fn):
        try:
            data = fn()
        except AuditError as e:
            msg = str(e)
            if name == "log_indexes" and "HTTP 403" in msg:
                msg += (" (listing log indexes is not permitted with this key, so the log index section is not "
                        "supported with it. Fall back to the saved index export: someone allowed to read index "
                        "configs saves GET /api/v1/logs/config/indexes as log_indexes.json, then re-run offline "
                        "with --input-dir)")
            log(f"warning: {name} unavailable: {msg}")
            self.unavailable[name] = msg
            return None
        self._save(name, data)
        return data

    def collect(self, a):
        today = dt.datetime.now(dt.timezone.utc)
        out = {}
        out["usage_summary"] = self.get("usage_summary", lambda: self.http_get(
            "/api/v1/usage/summary", {"start_month": a.month, "end_month": a.month}))
        out["estimated_cost"] = self.get("estimated_cost", lambda: self.http_get(
            "/api/v2/usage/estimated_cost", {"start_month": a.month, "end_month": a.month}))
        out["top_avg_metrics"] = self.get("top_avg_metrics", lambda: self.http_get(
            "/api/v1/usage/top_avg_metrics", {"month": a.month, "limit": a.top}))
        base = {"include": "metric_volumes", "sort": "-metric_volumes.indexed_volume",
                "page[size]": a.metric_page_size, "filter[is_configurable]": "true",
                "filter[configured]": "false"}
        out["metrics_unqueried"] = self.get("metrics_unqueried", lambda: self.http_get(
            "/api/v2/metrics", dict(base, **{"filter[queried]": "false",
                                             "filter[queried][window][seconds]": a.unqueried_days * 86400})))
        out["metrics_by_volume"] = self.get("metrics_by_volume", lambda: self.http_get("/api/v2/metrics", base))
        out["log_indexes"] = self.get("log_indexes", lambda: self.http_get("/api/v1/logs/config/indexes"))
        start = (today - dt.timedelta(days=a.log_days)).strftime("%Y-%m-%dT%H")
        out["logs_by_index"] = self.get("logs_by_index", lambda: self.http_get(
            "/api/v1/usage/logs_by_index", {"start_hr": start, "end_hr": today.strftime("%Y-%m-%dT%H")}))
        now = int(today.timestamp())
        out["logs_ingest_by_index"] = self.get("logs_ingest_by_index", lambda: self.http_get("/api/v1/query", {
            "from": now - a.log_days * 86400, "to": now,
            "query": "sum:datadog.estimated_usage.logs.ingested_events{*} by "
                     "{datadog_index,datadog_is_excluded}.as_count().rollup(sum, 3600)"}))
        out["monitors"] = self.get("monitors", self._all_monitors)
        out["monitor_search"] = self.get("monitor_search", self._all_search)
        self.meta = {"pulled_at": today.strftime("%Y-%m-%dT%H:%M:%SZ"), "month": a.month, "site": a.site,
                     "synthetic": False}
        if self.save_dir:
            os.makedirs(self.save_dir, exist_ok=True)
            with open(os.path.join(self.save_dir, META_FILE), "w") as f:
                json.dump(self.meta, f, indent=1, sort_keys=True)
        return out

    def _all_monitors(self):
        allm, page = [], 0
        while True:
            batch = self.http_get("/api/v1/monitor", {"page": page, "page_size": 1000, "with_downtimes": "true"})
            if not batch:
                return allm
            allm.extend(batch)
            if len(batch) < 1000 or page > 200:
                return allm
            page += 1

    def _all_search(self):
        mons, page = [], 0
        while True:
            r = self.http_get("/api/v1/monitor/search", {"page": page, "per_page": 100})
            mons.extend(r.get("monitors", []))
            pc = (r.get("metadata") or {}).get("page_count", 1)
            page += 1
            if page >= pc or page > 500:
                return {"monitors": mons}

def load_meta(d):
    """Read audit_meta.json; fall back to the estimated-cost file date so every dollar figure has a pull date."""
    p = os.path.join(d, META_FILE)
    if os.path.exists(p):
        with open(p) as f:
            return json.load(f)
    ec = os.path.join(d, INPUT_FILES["estimated_cost"])
    if os.path.exists(ec):
        d8 = dt.datetime.fromtimestamp(os.path.getmtime(ec), dt.timezone.utc).strftime("%Y-%m-%d")
        return {"pulled_at": d8, "pulled_at_source": "file date of estimated_cost.json (no audit_meta.json)"}
    return {}

def load_offline(d):
    out, missing = {}, {}
    for k, fn in INPUT_FILES.items():
        p = os.path.join(d, fn)
        if os.path.exists(p):
            with open(p) as f:
                out[k] = json.load(f)
        else:
            out[k] = None
            missing[k] = f"{fn} not in input dir"
    return out, missing

# --------------------------------------------------------------------------- analysis
def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0

def fmt_int(x):
    return f"{int(round(x)):,}"

def volumes_by_metric(resp):
    vols = {}
    for inc in (resp or {}).get("included", []) or []:
        if inc.get("type") == "metric_volumes":
            a = inc.get("attributes") or {}
            vols[inc.get("id")] = (num(a.get("indexed_volume")), num(a.get("ingested_volume")))
    rows = []
    for m in (resp or {}).get("data", []) or []:
        mid = m.get("id")
        iv, gv = vols.get(mid, (0.0, 0.0))
        rows.append({"metric": mid, "indexed": iv, "ingested": gv,
                     "metric_type": (m.get("attributes") or {}).get("metric_type")})
    rows.sort(key=lambda r: -r["indexed"])
    return rows

def cost_by_product(est):
    """Sum estimated cost per product_name. Uses charge_type 'total' rows when the data has them,
    otherwise sums all rows (and says so) to avoid double counting committed + on-demand + total."""
    if not est:
        return {}, None, None
    charges = []
    month = None
    for row in est.get("data", []) or []:
        a = row.get("attributes") or {}
        month = month or a.get("date")
        charges.extend(a.get("charges", []) or [])
    has_total = any(c.get("charge_type") == "total" for c in charges)
    prod = {}
    for c in charges:
        if has_total and c.get("charge_type") != "total":
            continue
        prod[c.get("product_name", "?")] = prod.get(c.get("product_name", "?"), 0.0) + num(c.get("cost"))
    note = "charge_type=total rows" if has_total else "sum of all charge rows (no charge_type=total rows found)"
    return prod, note, month

def match_products(prod, product_map):
    """Return {category: [product names]} from --product-map, else by name heuristics (flagged)."""
    if product_map:
        return {k: [p for p in v if p in prod] for k, v in product_map.items()}, "from --product-map"
    cats = {"custom_metrics": [], "indexed_logs": []}
    for p in prod:
        lp = p.lower()
        if "custom" in lp and ("metric" in lp or "timeseries" in lp or "ts" in lp.split("_")):
            cats["custom_metrics"].append(p)
        elif "log" in lp and "ingest" not in lp and ("index" in lp or "retention" in lp or "event" in lp):
            cats["indexed_logs"].append(p)
    return cats, "matched by product name (confirm, or pass --product-map)"

def index_volumes(lbi):
    tot, ret = {}, {}
    for u in (lbi or {}).get("usage", []) or []:
        n = u.get("index_name") or u.get("index_id") or "?"
        tot[n] = tot.get(n, 0.0) + num(u.get("event_count"))
        if u.get("retention") is not None:
            ret[n] = u.get("retention")
    return tot, ret

def ingest_by_index(q):
    res = {}
    for s in (q or {}).get("series", []) or []:
        tags = s.get("tag_set") or []
        idx = next((t.split(":", 1)[1] for t in tags if t.startswith("datadog_index:")), None)
        exc = next((t.split(":", 1)[1] for t in tags if t.startswith("datadog_is_excluded:")), None)
        if idx is None:
            continue
        total = sum(num(p[1]) for p in s.get("pointlist", []) or [] if p and len(p) > 1 and p[1] is not None)
        d = res.setdefault(idx, {"excluded": 0.0, "kept": 0.0})
        d["excluded" if exc == "true" else "kept"] += total
    return res

def norm_query(q):
    q = re.sub(r"\s+", "", q or "")
    return re.sub(r"\{([^}]*)\}", lambda m: "{" + ",".join(sorted(m.group(1).split(","))) + "}", q)

def tokens(m):
    text = " ".join([m.get("name") or "", m.get("query") or ""] + [str(t) for t in m.get("tags") or []])
    return set(re.split(r"[^a-z0-9]+", text.lower()))

def long_mutes(m, now_ts, muted_days):
    """Active mutes that started more than muted_days ago: (start_ts or None, how)."""
    cutoff = now_ts - muted_days * 86400
    out = []
    for d in m.get("matching_downtimes") or []:
        st, en = d.get("start"), d.get("end")
        if st and st <= cutoff and (en is None or en > now_ts):
            out.append((st, f"downtime {d.get('id')}" + (" with no end" if en is None else "")))
    sil = ((m.get("options") or {}).get("silenced") or {})
    for scope, until in sil.items():
        mod = parse_ts(m.get("modified"))
        if (until is None or until > now_ts) and mod and mod <= cutoff:
            out.append((None, f"options.silenced `{scope}`" + (" with no end" if until is None else "")
                        + "; start not recorded, last modified " + dt.datetime.fromtimestamp(mod, dt.timezone.utc).strftime("%Y-%m-%d")))
    return out

def monitor_findings(monitors, search, now_ts, never_days, rare_keywords=RARE_EVENT_KEYWORDS, muted_days=30):
    monitors = monitors or []
    by_key = {}
    for m in monitors:
        th = ((m.get("options") or {}).get("thresholds") or {})
        key = (m.get("type"), norm_query(m.get("query")), th.get("critical"), th.get("warning"))
        by_key.setdefault(key, []).append(m)
    dups = [sorted(v, key=lambda m: m.get("id", 0)) for v in by_key.values() if len(v) > 1]
    last = {s.get("id"): s.get("last_triggered_ts") for s in (search or {}).get("monitors", []) or []}
    cutoff = now_ts - never_days * 86400
    never, rare = [], []
    for m in monitors:
        created = parse_ts(m.get("created"))
        lt = last.get(m.get("id"))
        if m.get("id") not in last:
            continue
        if (not lt or lt < cutoff) and created and created < cutoff:
            hit = sorted(tokens(m) & set(rare_keywords))
            if hit:
                rare.append((m, lt, hit))
            else:
                never.append((m, lt))
    nodata = [m for m in monitors if m.get("overall_state") == "No Data"]
    # No monitor carries the matching_downtimes key at all (not even an empty list): the export has no
    # downtime data, so the check is skipped (None) rather than reported as zero muted monitors.
    if any("matching_downtimes" in m for m in monitors):
        muted = [(m, mu) for m in monitors for mu in [long_mutes(m, now_ts, muted_days)] if mu]
    else:
        muted = None
    return dups, never, nodata, rare, muted

def parse_ts(s):
    if not s:
        return None
    try:
        return int(dt.datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None

# --------------------------------------------------------------------------- report helpers
WRITE_HELPER = """```bash
# Helper for approved changes only. It reads its own DD_WRITE_API_KEY / DD_WRITE_APP_KEY from your
# secret store and ignores the audit's read-only DD_API_KEY / DD_APP_KEY. It refuses a body that
# still contains <placeholder> text. Keys go to curl through a file descriptor, not argv.
ddw() {  # usage: ddw METHOD PATH  (JSON body, if any, on stdin)
  local body
  body=$(cat)
  if printf '%s' "$body" | grep -Eq '<[A-Za-z][^<>]*>'; then
    echo "ddw: refusing: the body still contains <placeholder> text; fill it in first" >&2
    return 1
  fi
  if [ -z "${DD_WRITE_API_KEY:-}" ] || [ -z "${DD_WRITE_APP_KEY:-}" ]; then
    echo "ddw: refusing: set DD_WRITE_API_KEY and DD_WRITE_APP_KEY (the read-only DD_API_KEY/DD_APP_KEY are never used for writes)" >&2
    return 1
  fi
  if [ -z "${DD_SITE:-}" ]; then
    echo "ddw: refusing: set DD_SITE" >&2
    return 1
  fi
  printf '%s' "$body" | curl -sS -X "$1" "https://api.${DD_SITE}$2" \\
    -H @<(printf 'DD-API-KEY: %s\\nDD-APPLICATION-KEY: %s\\n' "$DD_WRITE_API_KEY" "$DD_WRITE_APP_KEY") \\
    -H 'Content-Type: application/json' --data-binary @-
}
```"""

def gated(cmd_lines):
    return f"{GATE}\n\n```bash\n" + "\n".join(cmd_lines) + "\n```\n"

def body_cmd(method, path, body):
    return [f"ddw {method} {path} <<'JSON'", json.dumps(body, indent=2, sort_keys=True), "JSON"]

def put_body(index):
    return {k: index[k] for k in INDEX_PUT_FIELDS if k in index and index[k] is not None}

# --------------------------------------------------------------------------- report
def build(data, unavailable, a, mode):
    meta = a.meta or {}
    pulled = str(meta.get("pulled_at") or "unknown date")[:10]

    def usd(x, suffix=""):
        """Every dollar figure in the report goes through here so it always carries its source and date."""
        return f"${x:,.0f}{suffix} ({COST_LABEL} {pulled})"

    now = dt.datetime.now(dt.timezone.utc)
    now_ts = int(a.as_of.timestamp()) if a.as_of else int(now.timestamp())
    prod, cost_note, cost_month = cost_by_product(data.get("estimated_cost"))
    cats, cat_note = match_products(prod, a.product_map)
    us = data.get("usage_summary") or {}
    items = []  # savings items: dict(title, category, evidence, effect, upper_usd, share, risk, change, rollback)

    def cat_cost(cat):
        names = cats.get(cat) or []
        return sum(prod.get(n, 0.0) for n in names) if names else None

    # ---- custom metrics
    custom_total = num(us.get("custom_ts_sum"))
    unq = volumes_by_metric(data.get("metrics_unqueried"))
    unq_names = {r["metric"] for r in unq}
    mcost = cat_cost("custom_metrics")
    for rank, r in enumerate(unq[: a.top], 1):
        share = r["indexed"] / custom_total if custom_total else None
        items.append(dict(
            kind="metric", title=f"Review: unqueried custom metric `{r['metric']}` (#{rank} by series)",
            category="custom_metrics",
            evidence=(f"Ranked #{rank} by indexed series among unqueried metrics (top {a.top} listed). Not queried in the last {a.unqueried_days} days (dashboards, monitors, notebooks, API) "
                      f"and not yet configured with Metrics without Limits. Average indexed series: "
                      f"{fmt_int(r['indexed'])}" + (f" ({share:.1%} of the month's custom metric average "
                                                    f"{fmt_int(custom_total)})" if share else "") + "."),
            effect=(f"Upper bound: up to {fmt_int(r['indexed'])} indexed series fewer if you keep no tags or stop "
                    "sending it. Measure the real effect with the read-only estimate call before changing it."),
            share=share, upper_usd=(share * mcost if (share and mcost is not None) else None),
            basis=(f"{share:.1%} of custom metric average x {usd(mcost)} estimated custom-metric cost"
                   if (share and mcost is not None) else None),
            risk="Low to medium. Nobody queried it in the window, but a quarterly report or rare runbook may. "
                 "Configured metrics are also billed for ingested volume, so the net saving is smaller than "
                 "the indexed drop.",
            metric=r))
    for rank, r in enumerate(volumes_by_metric(data.get("metrics_by_volume"))[: a.top], 1):
        if r["metric"] in unq_names:
            continue
        share = r["indexed"] / custom_total if custom_total else None
        items.append(dict(
            kind="metric", title=f"Review: high-cardinality custom metric `{r['metric']}` (#{rank} by series)",
            category="custom_metrics",
            evidence=(f"Ranked #{rank} by indexed series (top {a.top} listed). In use, not configured with Metrics without Limits. Average indexed series: "
                      f"{fmt_int(r['indexed'])}" + (f" ({share:.1%} of custom metric average)" if share else "")
                      + ". Review which tag keys are actually queried."),
            effect="Depends on the tags you keep. Run the read-only estimate call with your allowlist to get the "
                   "new series count, then subtract.",
            share=share, upper_usd=(share * mcost if (share and mcost is not None) else None),
            basis=(f"{share:.1%} of custom metric average x {usd(mcost)} estimated custom-metric cost"
                   if (share and mcost is not None) else None),
            risk="Medium. Dropping a tag that a dashboard or monitor groups by breaks that view or alert. Check "
                 "the metric's related assets first.",
            metric=r))

    # ---- logs
    idx_list = (data.get("log_indexes") or {}).get("indexes", []) or []
    vol, ret_seen = index_volumes(data.get("logs_by_index"))
    ingest = ingest_by_index(data.get("logs_ingest_by_index"))
    total_indexed = sum(vol.values())
    lcost = cat_cost("indexed_logs")
    log_names = cats.get("indexed_logs") or []
    for ix in idx_list:
        name = ix.get("name")
        v = vol.get(name, 0.0)
        if v <= 0:
            continue
        share = v / total_indexed if total_indexed else None
        # Prefer the product for this index's retention tier (e.g. a name containing "15day");
        # otherwise fall back to this index's share of all indexed-log cost.
        r_days = ix.get("num_retention_days")
        tier = [n for n in log_names if r_days and re.search(rf"(^|\D){r_days}[-_ ]?days?(\D|$)", n.lower())]
        up, basis = None, None
        if tier:
            same = sum(vol.get(i.get("name"), 0.0) for i in idx_list if i.get("num_retention_days") == r_days)
            tier_cost = sum(prod.get(n, 0.0) for n in tier)
            if same:
                up = v / same * tier_cost
                basis = (f"{v / same:.1%} of the {r_days}-day tier's indexed events x {usd(tier_cost)} "
                         f"estimated cost of {', '.join('`' + n + '`' for n in tier)}")
        elif share and lcost is not None:
            up = share * lcost
            basis = f"{share:.1%} of all indexed events x {usd(lcost)} estimated indexed-log cost (no tier match)"
        enabled = [e for e in ix.get("exclusion_filters") or [] if e.get("is_enabled")]
        ing = ingest.get(name)
        ing_txt = (f" Ingested in the window: {fmt_int(ing['kept'] + ing['excluded'])}, of which "
                   f"{fmt_int(ing['excluded'])} were already excluded." if ing else "")
        if share and share >= a.min_index_share and not enabled:
            new = put_body(ix)
            new["exclusion_filters"] = list(new.get("exclusion_filters", [])) + [{
                "name": "cost-cutter: <describe the low-value logs>", "is_enabled": False,
                "filter": {"query": "<low-value query, e.g. status:debug service:<svc>>", "sample_rate": 0.9}}]
            items.append(dict(
                kind="log_exclusion", title=f"Review: log index `{name}` has no active exclusion filter", category="indexed_logs",
                evidence=(f"{fmt_int(v)} indexed events in the last {a.log_days} days ({share:.1%} of all indexed "
                          f"events), retention {ix.get('num_retention_days')} days, no enabled exclusion "
                          f"filter.{ing_txt}"),
                effect=("Saving = this index's indexed-log cost x the fraction your filter drops. Count the "
                        "matching events in Log Explorer first. sample_rate is the fraction of matching logs that "
                        "are excluded: for the trial window use 0.9 or lower, so at least 10% of matching logs are "
                        "still indexed. 1.0 means none of the matching logs are kept in this index. The example "
                        "filter ships disabled (is_enabled false) with placeholders the helper refuses to send; "
                        "fill them in, apply, then enable it in a second approved change."),
                share=share, upper_usd=up, basis=basis,
                risk="Medium. Excluded logs are not searchable in this index and cannot be re-indexed later, "
                     "though they still feed live tail, archives and log-based metrics. Exclusion is the first "
                     "matching filter only.",
                index=ix, new_body=new))
        r = ix.get("num_retention_days")
        if r and a.retention_over and r > a.retention_over:
            new = put_body(ix)
            new["num_retention_days"] = a.target_retention if a.target_retention else "<target days from your contract>"
            items.append(dict(
                kind="log_retention", title=f"Review: log index `{name}` keeps logs {r} days (check compliance first)", category="indexed_logs",
                evidence=(f"Retention {r} days, over the {a.retention_over}-day review threshold, on an index holding "
                          f"{share:.1%} of indexed events ({fmt_int(v)} in {a.log_days} days). Check compliance "
                          "first: audit, security, legal hold and contract terms may require this retention."),
                effect="Depends on your contracted price per retention tier. Fill in: events x (current tier rate - "
                       "new tier rate). No dollar upper bound is shown because the index's whole cost is not saved.",
                share=share, upper_usd=None,
                risk="High for the data, check compliance first: logs older than the new retention become unsearchable and raising "
                     "retention again does not bring them back. Check audit, security and legal hold needs.",
                index=ix, new_body=new))

    # ---- ranking: dollar upper bound first (only with --dollar-estimates), then share of product usage
    def key(i):
        usd = i["upper_usd"] if a.dollar_estimates and i["upper_usd"] is not None else -1
        return (-usd, -(i["share"] or 0))
    items.sort(key=key)

    dups, never, nodata, rare, muted = monitor_findings(data.get("monitors"), data.get("monitor_search"), now_ts,
                                                        a.never_triggered_days, a.rare_event_keywords, a.muted_days)

    # ---- write
    L = []
    title = "Observability cost audit and savings plan"
    L.append(f"# {title}\n")
    synthetic = bool(meta.get("synthetic")) or (mode == "offline" and a.example_label)
    if synthetic:
        L.append(SYNTH_LABEL + " " + str(meta.get("label") or "Built from test fixtures.").strip() + "\n")
    if mode == "offline" and a.example_label:
        L.append("> **EXAMPLE REPORT built from fixture data.** Every number below is made up for testing. "
                 "It is not a measurement of any real organization and not a savings claim.\n")
    L.append(DISCLAIMER + "\n")
    if mode == "live":
        L.append(f"- Generated: {now.strftime('%Y-%m-%d %H:%M')} UTC (data pulled now)")
    else:
        L.append(f"- Generated: offline from data pulled {meta.get('pulled_at', 'on an unknown date')}"
                 + (f" ({meta['pulled_at_source']})" if meta.get("pulled_at_source") else ""))
    L.append(f"- Mode: {mode}" + (f" (site `{a.site}`)" if mode == "live" else f" (input dir `{os.path.basename(os.path.normpath(a.input_dir))}`)"))
    L.append(f"- Usage month: {a.month}; unqueried window: {a.unqueried_days} days; log window: {a.log_days} days")
    L.append("- Dollar figures: " + ("upper-bound estimates from your own estimated-cost API data"
                                     if a.dollar_estimates else "off (placeholders). Re-run with --dollar-estimates "
                                     "to derive upper bounds from your estimated-cost data") + "\n")
    if unavailable:
        L.append("## Data not available\n")
        L.append("| Source | Reason |\n|---|---|")
        for k, v in sorted(unavailable.items()):
            L.append(f"| `{k}` | {v.replace('|', '/')} |")
        L.append("")

    L.append("## Estimated cost by product\n")
    if prod:
        L.append(f"Source: estimated-cost API for {cost_month or a.month} ({cost_note}). This is the vendor's "
                 "running estimate, delayed by up to 72 hours. It is not an invoice.\n")
        L.append("| Product | Estimated cost |\n|---|---|")
        for p, c in sorted(prod.items(), key=lambda x: -x[1]):
            L.append(f"| `{p}` | {usd(c)} |")
        L.append(f"\nCategory matching for upper bounds ({cat_note}): "
                 + "; ".join(f"{k}: {', '.join('`'+n+'`' for n in v) or 'none'}" for k, v in cats.items()) + "\n")
    else:
        L.append("No estimated-cost data (needs a parent-level org and `usage_read` + `billing_read`). Fill in "
                 "prices from your contract.\n")

    L.append("## Usage inventory\n")
    inv = [("Infrastructure hosts (top 99th percentile)", "infra_host_top99p_sum"),
           ("APM hosts (top 99th percentile)", "apm_host_top99p_sum"),
           ("Containers (average)", "container_avg_sum"),
           ("Custom metrics (average per hour)", "custom_ts_sum"),
           ("Ingested log bytes", "ingested_events_bytes_agg_sum"),
           ("Indexed spans", "trace_search_indexed_events_count_agg_sum")]
    if us:
        L.append("| Usage | Value |\n|---|---|")
        for label, f in inv:
            if f in us:
                L.append(f"| {label} (`{f}`) | {fmt_int(num(us[f]))} |")
        for r in us.get("logs_by_retention", {}).get("usage", []) or []:
            L.append(f"| Indexed logs, {r.get('retention')}{'-day' if str(r.get('retention')).isdigit() else ''} retention | {fmt_int(num(r.get('logs_indexed_logs_usage_agg_sum')))} |")
        L.append("")
    else:
        L.append("No usage summary (needs a parent-level org and `usage_read`).\n")
    if idx_list:
        L.append("| Log index | Retention (days) | Indexed events in window | Enabled exclusion filters | Daily limit |")
        L.append("|---|---|---|---|---|")
        for ix in sorted(idx_list, key=lambda i: -vol.get(i.get("name"), 0)):
            en = len([e for e in ix.get("exclusion_filters") or [] if e.get("is_enabled")])
            L.append(f"| `{ix.get('name')}` | {ix.get('num_retention_days')} | {fmt_int(vol.get(ix.get('name'), 0))} | "
                     f"{en} | {ix.get('daily_limit') or 'none'} |")
        L.append("")
    tam = (data.get("top_avg_metrics") or {}).get("usage", []) or []
    if tam:
        L.append(f"Top custom metrics by hourly average ({a.month}):\n")
        L.append("| Metric | Avg per hour | Max per hour |\n|---|---|---|")
        for u in sorted(tam, key=lambda u: -num(u.get("avg_metric_hour")))[: a.top]:
            L.append(f"| `{u.get('metric_name')}` | {fmt_int(num(u.get('avg_metric_hour')))} | {fmt_int(num(u.get('max_metric_hour')))} |")
        L.append("")

    L.append("## Ranked savings plan\n")
    L.append("Every item here is a review flag, not a recommendation to cut: a threshold or a ranking put it on "
             "the list, and the owner decides whether to change anything.\n")
    L.append("Ranked by " + ("estimated upper-bound dollars, then " if a.dollar_estimates else "")
             + "share of the product's usage. Shares compare items within one product, not across products, "
             "until you fill in your contract rates.\n")
    if not items:
        L.append("No review flags.\n")
    else:
        L.append("| # | Item | Share of product usage | Estimated effect | Risk |\n|---|---|---|---|---|")
        for n, i in enumerate(items, 1):
            fig = (f"upper bound {usd(i['upper_usd'], '/mo')}" if a.dollar_estimates and i["upper_usd"] is not None
                   else "$ <fill in from contract>")
            L.append(f"| {n} | {i['title']} | {('%.1f%%' % (100 * i['share'])) if i['share'] else 'n/a'} | {fig} | "
                     f"{re.split(r'[.:]', i['risk'])[0]} |")
        priced = [i for i in items if i["upper_usd"] is not None]
        if a.dollar_estimates and priced:
            L.append("\n### Upper-bound savings totals\n")
            L.append("Sum of the items' upper bounds. Each metric and index carries at most one dollar figure, so "
                     "nothing is counted twice. The achievable saving is lower.\n")
            L.append("| Category | Total upper bound |\n|---|---|")
            for cat in sorted({i["category"] for i in priced}):
                L.append(f"| {cat} | {usd(sum(i['upper_usd'] for i in priced if i['category'] == cat), '/mo')} |")
            L.append(f"| **All priced items** | **{usd(sum(i['upper_usd'] for i in priced), '/mo')}** |")
            L.append(f"\n**{NOT_GUARANTEED}** {CONTRACT}")
        L.append("\nApproved changes use this helper:\n")
        L.append(WRITE_HELPER + "\n")
        for n, i in enumerate(items, 1):
            L.append(f"### {n}. {i['title']}\n")
            L.append(f"- **Evidence:** {i['evidence']}")
            L.append(f"- **Estimated effect:** {i['effect']}")
            if a.dollar_estimates and i["upper_usd"] is not None:
                L.append(f"- **Upper-bound dollars (estimate, not guaranteed):** {usd(i['upper_usd'], ' per month')} = "
                         f"{i['basis']}. The real saving is lower: see Estimated effect.")
            L.append(f"- **Risk:** {i['risk']}\n")
            if i["kind"] == "metric":
                m = i["metric"]["metric"]
                mt = i["metric"].get("metric_type") or "<gauge|count|rate|distribution>"
                q = urllib.parse.quote(m, safe="")
                L.append("Measure first (read-only). The metric type comes from the metadata call:\n")
                L.append("```bash\n"
                         f"curl -sS -G \"https://api.${{DD_SITE}}/api/v1/metrics/{q}\" \\\n"
                         "  -H @<(printf 'DD-API-KEY: %s\\nDD-APPLICATION-KEY: %s\\n' \"$DD_API_KEY\" \"$DD_APP_KEY\") | jq .type\n"
                         f"curl -sS -G \"https://api.${{DD_SITE}}/api/v2/metrics/{q}/estimate\" \\\n"
                         "  -H @<(printf 'DD-API-KEY: %s\\nDD-APPLICATION-KEY: %s\\n' \"$DD_API_KEY\" \"$DD_APP_KEY\") \\\n"
                         "  --data-urlencode 'filter[groups]=<tag keys to keep, comma separated>' "
                         "| jq .data.attributes.estimated_output_series\n```\n")
                L.append("Change: keep only the listed tag keys queryable (Metrics without Limits allowlist).\n")
                L.append(gated(body_cmd("POST", f"/api/v2/metrics/{q}/tags", {"data": {
                    "type": "manage_tags", "id": m,
                    "attributes": {"metric_type": mt, "tags": ["<tag key to keep>", "<another tag key>"]}}})))
                L.append("Rollback: remove the tag configuration so all submitted tags are queryable again "
                         "(data written while it was configured stays at the reduced tag set).\n")
                L.append(gated([f"ddw DELETE /api/v2/metrics/{q}/tags </dev/null"]))
            else:
                ix = i["index"]
                L.append("Change: the index update **replaces the whole index config**, so this body is the current "
                         "config with only the proposed field changed. Re-export the index right before applying "
                         "and stop if it differs from the evidence here.\n")
                L.append(gated(body_cmd("PUT", f"/api/v1/logs/config/indexes/{urllib.parse.quote(ix['name'], safe='')}",
                                        i["new_body"])))
                L.append("Rollback: put back the config as exported." +
                         (" This does not restore logs already aged out." if i["kind"] == "log_retention" else "") + "\n")
                L.append(gated(body_cmd("PUT", f"/api/v1/logs/config/indexes/{urllib.parse.quote(ix['name'], safe='')}",
                                        put_body(ix))))

    L.append("## Monitor hygiene (no dollar claim)\n")
    L.append("Monitors are rarely billed one by one; these are review flags for alert noise and review load.\n")
    if not data.get("monitors"):
        L.append("No monitor export available.\n")
    else:
        L.append(f"- Duplicate groups (same type, query and thresholds): {len(dups)}")
        L.append(f"- Not triggered in {a.never_triggered_days} days and older than that: {len(never)} "
                 f"(plus {len(rare)} rare-event monitors skipped)")
        L.append(f"- Muted for more than {a.muted_days} days: {len(muted)}" if muted is not None
                 else f"- {MUTED_SKIPPED}")
        L.append(f"- In No Data state: {len(nodata)}\n")
        for g in dups:
            keep, rest = g[0], g[1:]
            L.append(f"### Duplicate: keep monitor {keep['id']} \"{keep.get('name')}\"\n")
            L.append(f"Query: `{keep.get('query')}`. Duplicates: " + ", ".join(f"{m['id']} \"{m.get('name')}\"" for m in rest)
                     + ". Check that the notification targets of the duplicates are covered by the one you keep.\n")
            for m in rest:
                L.append(f"Trial first: mute monitor {m['id']} with a downtime for two weeks.\n")
                L.append(gated(body_cmd("POST", "/api/v2/downtime", {"data": {"type": "downtime", "attributes": {
                    "scope": "*", "monitor_identifier": {"monitor_id": m["id"]},
                    "message": "cost-cutter trial mute of a duplicate monitor",
                    "schedule": {"end": "<ISO-8601 end time, e.g. two weeks from now>"}}}})))
                L.append("Rollback of the mute: cancel the downtime using the id returned above.\n")
                L.append(gated(["ddw DELETE \"/api/v2/downtime/${DOWNTIME_ID:?id from the downtime response}\" </dev/null"]))
                L.append(f"Then delete monitor {m['id']} (irreversible; links, SLOs and composites that use this id break).\n")
                L.append(gated([f"ddw DELETE /api/v1/monitor/{m['id']} </dev/null"]))
                recreate = {k: m[k] for k in ("name", "type", "query", "message", "tags", "options", "priority") if m.get(k) is not None}
                L.append("Rollback of the delete: re-create it from the exported definition (it gets a new id).\n")
                L.append(gated(body_cmd("POST", "/api/v1/monitor", recreate)))
        if never:
            L.append("### Not triggered recently (review, do not delete blindly)\n")
            L.append("A monitor that never fires may be well tuned, or broken (wrong scope, dead metric, impossible "
                     "threshold). Ask the owner before muting or deleting; use the same gated downtime and delete "
                     "steps as above.\n")
            L.append("| Monitor | Name | Type | Last triggered |\n|---|---|---|---|")
            for m, lt in never:
                when = dt.datetime.fromtimestamp(lt, dt.timezone.utc).strftime("%Y-%m-%d") if lt else "never (in search data)"
                L.append(f"| {m['id']} | {m.get('name')} | {m.get('type')} | {when} |")
            L.append("")
        if rare:
            L.append("### Skipped: rare-event monitors\n")
            L.append("These have not triggered in the window, but their name, tags or query match a rare-event "
                     "keyword (certificate expiry, disaster recovery, backups and similar), so staying quiet is "
                     "expected. They are not flagged. Keywords: " + ", ".join(f"`{k}`" for k in a.rare_event_keywords)
                     + " (change with --rare-event-keywords).\n")
            L.append("| Monitor | Name | Matched keywords |\n|---|---|---|")
            for m, lt, hit in rare:
                L.append(f"| {m['id']} | {m.get('name')} | {', '.join(hit)} |")
            L.append("")
        if muted:
            L.append(f"### Muted for more than {a.muted_days} days (review)\n")
            L.append("A long mute usually means the monitor is noisy, obsolete, or covering a known gap. Ask the owner "
                     "whether to fix it, unmute it or retire it; any change uses the gated steps above.\n")
            L.append("| Monitor | Name | Muted since | How |\n|---|---|---|---|")
            for m, mu in muted:
                for st, how in mu:
                    when = dt.datetime.fromtimestamp(st, dt.timezone.utc).strftime("%Y-%m-%d") if st else "unknown"
                    L.append(f"| {m['id']} | {m.get('name')} | {when} | {how} |")
            L.append("")
        if nodata:
            L.append("### In No Data state\n")
            L.append("| Monitor | Name | Query |\n|---|---|---|")
            for m in nodata:
                L.append(f"| {m['id']} | {m.get('name')} | `{m.get('query')}` |")
            L.append("")

    L.append("## Not covered and assumptions\n")
    L.append("- Upper bounds assume cost scales linearly with the share of usage. Commitments, tiers and minimums "
             "mean the real saving can be lower, or zero until the next renewal.")
    L.append("- Per-index ingest uses the estimated usage metric tagged by index; it is an estimate.")
    L.append("- APM, RUM, Synthetics and security products are listed in the inventory only.")
    L.append("- Monitor hygiene uses the monitor list and search APIs; it does not read monitor history. Mute "
             "ages come from the monitor list's matching_downtimes (requested with with_downtimes=true).")
    L.append("- The script does not check what the key is allowed to do. The operator confirms the service "
             "account's role in the Datadog UI before the run.")
    L.append("\n---\n")
    L.append(f"{NOT_GUARANTEED} {CONTRACT} Dollar figures in this report are {COST_LABEL} {pulled}; "
             "they are not an invoice or a quote. Test changes in non-production first; the operator approves "
             "every change.")
    if synthetic:
        L = label_sections(L)
        L.append("\n" + SYNTH_LABEL)
    return "\n".join(L) + "\n", items, dups, never, nodata, rare, muted

def label_sections(L):
    """Put the synthetic-data label at the start of every top-level section, outside code blocks."""
    out, fence = [], False
    for chunk in L:
        lines = chunk.split("\n")
        for n, line in enumerate(lines):
            if line.startswith("```"):
                fence = not fence
            if not fence and line.startswith("## "):
                lines[n] = line + "\n\n" + SYNTH_LABEL + "\n" if n + 1 == len(lines) or lines[n + 1] != "" else line + "\n\n" + SYNTH_LABEL
        out.append("\n".join(lines))
    return out

def prev_month():
    first = dt.datetime.now(dt.timezone.utc).replace(day=1)
    return (first - dt.timedelta(days=1)).strftime("%Y-%m")

def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--input-dir", help="offline mode: read exported JSON from this directory")
    p.add_argument("--save-dir", help="live mode: also save each raw response here for evidence and offline re-runs")
    p.add_argument("--report", "--out", dest="report", default=None,
                   help="Markdown report path (default: a new directory under ${TMPDIR:-/tmp}/obcost-*)")
    p.add_argument("--json", dest="json_out", help="also write findings as JSON")
    p.add_argument("--month", help="usage month YYYY-MM (default: audit_meta.json month offline, else previous month, UTC)")
    p.add_argument("--unqueried-days", type=int, default=30)
    p.add_argument("--log-days", type=int, default=7)
    p.add_argument("--never-triggered-days", type=int, default=90)
    p.add_argument("--top", type=int, default=10,
                   help="metrics to flag per list, ranked by indexed series count (also the top-metrics table)")
    p.add_argument("--metric-page-size", type=int, default=1000)
    p.add_argument("--min-index-share", type=float, default=0.05, help="ignore indexes below this share of indexed events")
    p.add_argument("--retention-over", type=int, default=15,
                   help="flag indexes with retention above N days for review (check compliance first)")
    p.add_argument("--muted-days", type=int, default=30, help="flag monitors muted for more than N days")
    p.add_argument("--rare-event-keywords", default=",".join(RARE_EVENT_KEYWORDS),
                   help="comma-separated keywords; not-triggered monitors whose name, tags or query contain one "
                        "are skipped (empty string: skip none)")
    p.add_argument("--target-retention", type=int, help="retention to propose; default is a placeholder")
    p.add_argument("--product-map", dest="product_map_path", help="JSON file {category: [product_name, ...]} for cost matching")
    p.add_argument("--dollar-estimates", action="store_true",
                   help="show upper-bound dollar estimates derived from your estimated-cost data")
    p.add_argument("--example-label", action="store_true", help="mark the report as an example built from fixtures")
    p.add_argument("--as-of", help="evaluate 'not triggered' against this UTC date YYYY-MM-DD (default: now)")
    p.add_argument("--base-url", help=argparse.SUPPRESS)
    a = p.parse_args(argv)
    a.meta = load_meta(a.input_dir) if a.input_dir else {}
    a.month = a.month or a.meta.get("month") or prev_month()
    a.rare_event_keywords = tuple(k.strip().lower() for k in a.rare_event_keywords.split(",") if k.strip())
    a.as_of = a.as_of or a.meta.get("as_of")
    if not re.fullmatch(r"\d{4}-\d{2}", a.month):
        p.error("--month must be YYYY-MM")
    if not 1 <= a.unqueried_days <= 180:
        p.error("--unqueried-days must be 1..180 (API maximum is 180 days)")
    if not 1 <= a.log_days <= 31:
        p.error("--log-days must be 1..31")
    if not 1 <= a.metric_page_size <= 10000:
        p.error("--metric-page-size must be 1..10000")
    a.site = os.environ.get("DD_SITE", "datadoghq.com")
    if a.as_of:
        try:
            a.as_of = dt.datetime.strptime(a.as_of, "%Y-%m-%d").replace(tzinfo=dt.timezone.utc)
        except ValueError:
            p.error("--as-of must be YYYY-MM-DD")

    # Default outputs go under ${TMPDIR:-/tmp}, never the cwd or the skill tree.
    workspace = None
    if a.report is None:
        workspace = tempfile.mkdtemp(prefix="obcost-", dir=os.environ.get("TMPDIR") or None)
        a.report = os.path.join(workspace, "cost-audit-report.md")
        if a.json_out is None:
            a.json_out = os.path.join(workspace, "findings.json")
        if a.save_dir is None and not a.input_dir:
            a.save_dir = os.path.join(workspace, "raw")
        print(f"workspace: {workspace}", file=sys.stderr)

    a.product_map = None
    if a.product_map_path:
        with open(a.product_map_path) as f:
            a.product_map = json.load(f)
    try:
        if a.input_dir:
            data, unavailable = load_offline(a.input_dir)
            mode = "offline"
        else:
            src = LiveSource(a.site, a.base_url, a.save_dir)
            data = src.collect(a)
            a.meta = src.meta
            unavailable = src.unavailable
            mode = "live"
    except AuditError as e:
        log(f"error: {e}")
        return 2
    report, items, dups, never, nodata, rare, muted = build(data, unavailable, a, mode)
    with open(a.report, "w") as f:
        f.write(report)
    if a.json_out:
        with open(a.json_out, "w") as f:
            json.dump({"savings_items": [{k: v for k, v in i.items() if k in ("kind", "title", "category", "share", "upper_usd")}
                                         for i in items],
                       "duplicate_monitor_groups": [[m["id"] for m in g] for g in dups],
                       "not_triggered": [m["id"] for m, _ in never], "no_data": [m["id"] for m in nodata],
                       "rare_event_skipped": [m["id"] for m, _, _ in rare], "muted_long": None if muted is None else [m["id"] for m, _ in muted],
                       "muted_check_skipped": muted is None,
                       "unavailable": unavailable}, f, indent=1)
    log(f"wrote {a.report}: {len(items)} savings items, {len(dups)} duplicate monitor groups, "
        f"{len(never)} not-triggered monitors ({len(rare)} rare-event skipped), {'muted check skipped' if muted is None else str(len(muted)) + ' long-muted'}, "
        f"{len(unavailable)} sources unavailable")
    return 0

if __name__ == "__main__":
    sys.exit(main())

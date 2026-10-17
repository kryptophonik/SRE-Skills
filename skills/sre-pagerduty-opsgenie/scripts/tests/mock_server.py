#!/usr/bin/env python3
"""Tiny offline mock of the PagerDuty REST v2 and Opsgenie v2 endpoints used by the scripts.
Fake data only. Records each request method and auth scheme (never the key) in /tmp mock log.
Usage: mock_server.py PORT LOGFILE"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

PORT, LOG = int(sys.argv[1]), sys.argv[2]
BASE = f"http://127.0.0.1:{PORT}"
INC = [{"id": f"PI{i}", "incident_number": i, "status": "triggered", "urgency": "high",
        "service": {"summary": "svc-a"}, "created_at": "2026-10-16T00:00:00Z",
        "title": f"fake incident {i}", "html_url": f"https://example.invalid/i/{i}"} for i in range(1, 251)]

def pd_page(items, key, q):
    off, lim = int(q.get("offset", ["0"])[0]), int(q.get("limit", ["25"])[0])
    return {key: items[off:off+lim], "limit": lim, "offset": off, "more": off+lim < len(items), "total": None}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def _log(self):
        auth = self.headers.get("Authorization", "")
        with open(LOG, "a") as f:
            f.write(json.dumps({"method": self.command, "path": urlparse(self.path).path,
                                "auth_scheme": auth.split(" ")[0] if auth else None,
                                "accept": self.headers.get("Accept")}) + "\n")
    def do_POST(self): self._log(); self._send(405, {"error": "mock: writes not expected"})
    do_PUT = do_DELETE = do_PATCH = do_POST
    def do_GET(self):
        self._log(); u = urlparse(self.path); p, q = u.path, parse_qs(u.query)
        auth = self.headers.get("Authorization", "")
        if p.startswith("/v2/") and not auth.startswith("GenieKey "): return self._send(401, {"message": "no key"})
        if not p.startswith("/v2/") and not auth.startswith("Token token="): return self._send(401, {"error": "no key"})
        # ---- PagerDuty
        if p == "/incidents": return self._send(200, pd_page(INC, "incidents", q))
        if p == "/oncalls":
            oc = [{"escalation_policy": {"summary": "EP-A"}, "escalation_level": 1, "user": {"summary": "Test User"},
                   "schedule": {"summary": "Sched-A"}, "start": "2026-10-16T00:00:00Z", "end": "2026-10-17T00:00:00Z"}]
            return self._send(200, pd_page(oc, "oncalls", q))
        if p == "/schedules": return self._send(200, pd_page([{"id": "PS1"}, {"id": "PS2"}], "schedules", q))
        if p == "/schedules/PS1":
            return self._send(200, {"schedule": {"id": "PS1", "name": "Sched-Gappy",
                "schedule_layers": [{"name": "L1", "users": [{"user": {"summary": "Solo Person"}}]}],
                "final_schedule": {"rendered_schedule_entries": [
                    {"start": "2026-10-16T00:00:00Z", "end": "2026-10-16T08:00:00Z"},
                    {"start": "2026-10-16T10:00:00Z", "end": "2026-10-17T00:00:00Z"}]}}})
        if p == "/schedules/PS2":
            return self._send(200, {"schedule": {"id": "PS2", "name": "Sched-OK",
                "schedule_layers": [{"name": "L1", "users": [{"user": {"summary": "A"}}, {"user": {"summary": "B"}}]}],
                "final_schedule": {"rendered_schedule_entries": [{"start": "2026-10-16T00:00:00Z", "end": "2026-10-17T00:00:00Z"}]}}})
        if p == "/escalation_policies":
            return self._send(200, pd_page([
                {"id": "PE1", "name": "EP-Orphan", "services": [], "escalation_rules": [{"targets": [{"id": "x"}]}, {"targets": []}]},
                {"id": "PE2", "name": "EP-OK", "services": [{"id": "S"}], "escalation_rules": [{"targets": [{"id": "y"}]}]}],
                "escalation_policies", q))
        if p == "/users":
            return self._send(200, pd_page([
                {"id": "PU1", "name": "Unreachable", "contact_methods": [], "notification_rules": []},
                {"id": "PU2", "name": "Reachable", "contact_methods": [{"id": "c"}], "notification_rules": [{"id": "r"}]}],
                "users", q))
        # ---- Opsgenie
        if p == "/v2/alerts":
            off = int(q.get("offset", ["0"])[0]); lim = int(q.get("limit", ["20"])[0]); total = 130
            data = [{"tinyId": str(i), "status": "open", "acknowledged": False, "priority": "P3",
                     "createdAt": "2026-10-16T00:00:00Z", "message": f"fake alert {i}"} for i in range(off, min(off+lim, total))]
            body = {"data": data, "paging": {}}
            if off+lim < total: body["paging"]["next"] = f"{BASE}/v2/alerts?limit={lim}&offset={off+lim}&query=status%3Aopen"
            return self._send(200, body)
        if p == "/v2/schedules": return self._send(200, {"data": [{"id": "OS1", "name": "Ops Primary"}, {"id": "OS2", "name": "Empty Sched"}]})
        if p == "/v2/schedules/Ops%20Primary/on-calls" or p == "/v2/schedules/Ops Primary/on-calls":
            return self._send(200, {"data": {"_parent": {"name": "Ops Primary"}, "onCallRecipients": ["test@example.invalid"]}})
        if p.startswith("/v2/schedules/Empty") and p.endswith("/on-calls"):
            return self._send(200, {"data": {"_parent": {"name": "Empty Sched"}, "onCallRecipients": []}})
        if p.startswith("/v2/schedules/") and p.endswith("/overrides"): return self._send(200, {"data": []})
        if p.startswith("/v2/schedules/"): return self._send(200, {"data": {"id": p.split("/")[3]}})
        if p in ("/v2/teams", "/v2/escalations", "/v2/integrations"): return self._send(200, {"data": [{"id": p[4:] + "-1"}]})
        if p == "/v2/heartbeats": return self._send(200, {"data": {"heartbeats": []}})
        if p == "/v2/users": return self._send(200, {"data": [{"id": "OU1"}], "paging": {}})
        if p.startswith("/v2/users/") or p.startswith("/v2/integrations/"): return self._send(200, {"data": []})
        return self._send(404, {"error": "mock: unknown path " + p})

HTTPServer(("127.0.0.1", PORT), H).serve_forever()

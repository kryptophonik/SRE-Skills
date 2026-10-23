#!/usr/bin/env python3
"""Lab fixture for example 12: a tiny local HTTP server that sends an X-Powered-By
header, the way a PHP app server would. Three paths, three PHP versions:
  /checkout  -- PHP/8.3.6   (below the 8.3.36 fix: vulnerable)
  /admin     -- PHP/8.1.31  (EOL branch, backport-only: needs a manual check)
  /docs      -- PHP/8.4.27  (at the fixed build: patched)
Usage: python3 mock-server.py <port>
"""
import http.server, sys

VERSIONS = {"/checkout": "PHP/8.3.6", "/admin": "PHP/8.1.31", "/docs": "PHP/8.4.27"}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_HEAD(self):
        self.send_response(200)
        v = VERSIONS.get(self.path)
        if v:
            self.send_header("X-Powered-By", v)
        self.end_headers()

    do_GET = do_HEAD

if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()

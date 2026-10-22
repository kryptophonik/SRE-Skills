# Lab fake service: ~100 req/s, 5% HTTP 500 (50x the 0.1% budget)
import time, http.server
t0=time.time()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        n=int((time.time()-t0)*100); err=n*5//100
        body=("# TYPE http_requests_total counter\n"
              f'http_requests_total{{code="200"}} {n-err}\n'
              f'http_requests_total{{code="500"}} {err}\n').encode()
        self.send_response(200); self.send_header("Content-Type","text/plain; version=0.0.4"); self.end_headers(); self.wfile.write(body)
    def log_message(self,*a): pass
http.server.HTTPServer(("127.0.0.1",59100),H).serve_forever()

"""Local browser regression fixture; never serves workspace files."""
import http.server
import sys
import time
from pathlib import Path

PAYLOAD = b"PC1 download test\n" * 1024
PAGE = b"""<!doctype html><meta charset=utf-8><title>Download fixture</title>
<style>body {font:28px sans-serif;margin:32px} button {font:inherit;padding:24px} main {height:600px;background:#dae9f0}</style>
<button onclick="history.pushState({}, '', '/route-' + Date.now());document.querySelector('main').textContent = 'New route content '.repeat(300);document.title='Route changed'">Change route</button>
<a href="/file" download>Download test file</a><main>Original content</main>"""
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/file') or self.path.startswith('/slow'):
            slow = self.path.startswith('/slow')
            payload = PAYLOAD * (100 if slow else 1)
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="fixture.bin"')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            try:
                for start in range(0, len(payload), 4096):
                    self.wfile.write(payload[start:start+4096])
                    self.wfile.flush()
                    if slow: time.sleep(0.03)
            except (BrokenPipeError, ConnectionResetError): pass
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(PAGE)))
            self.end_headers()
            self.wfile.write(PAGE)
    def log_message(self, *args): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()

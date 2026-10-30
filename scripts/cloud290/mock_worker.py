#!/usr/bin/env python3
"""Minimal mock of the avdb-covers Worker contract (GET/HEAD/PUT /v1/cover/{prefix}/{name}.{ext}, X-AVDB-Key, 404, 401,
413, 415, 507 for the `full` prefix).
Usage: mock_worker.py <port> [key] [--delay S] [--log FILE] [--preload OBJECTKEY=FILE ...]"""
import re, sys, time, json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
args = sys.argv[1:]
PORT = int(args.pop(0)); KEY = args.pop(0) if args and not args[0].startswith('--') else 'test-key'
DELAY = 0.0; LOG = None; store = {}
while args:
    a = args.pop(0)
    if a == '--delay': DELAY = float(args.pop(0))
    elif a == '--log': LOG = args.pop(0)
    elif a == '--preload':
        k, f = args.pop(0).split('=', 1); store[k] = ('image/jpeg', open(f, 'rb').read())
PATH = re.compile(r'^/v1/cover/((?:[A-Za-z0-9._-]{1,80}/)?[A-Za-z0-9._-]{1,80})\.(jpg|jpeg|webp|heic)$')
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body=b'', ctype='application/json', head=False):
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(body))); self.end_headers()
        if not head: self.wfile.write(body)
    def route(self):
        if LOG:
            with open(LOG, 'a') as f: f.write(json.dumps({'t': time.time(), 'method': self.command, 'path': self.path,
                                                          'bytes': int(self.headers.get('Content-Length') or 0),
                                                          'type': self.headers.get('Content-Type')}) + '\n')
        if DELAY: time.sleep(DELAY)
        if self.headers.get('X-AVDB-Key') != KEY: self.reply(401, b'{"error":"unauthorized"}'); return None
        m = PATH.match(self.path)
        if not m: self.reply(400, b'{"error":"bad key"}'); return None
        return m.group(1) + '.' + m.group(2)
    def do_GET(self, head=False):
        k = self.route()
        if k is None: return
        if k not in store: self.reply(404, b'{"error":"not found"}', head=head); return
        ct, body = store[k]; self.reply(200, body, ct, head=head)
    def do_HEAD(self): self.do_GET(head=True)
    def do_PUT(self):
        n = int(self.headers.get('Content-Length') or 0); body = self.rfile.read(n)
        k = self.route()
        if k is None: return
        ct = (self.headers.get('Content-Type') or '').split(';')[0].strip().lower()
        if ct not in ('image/jpeg', 'image/webp', 'image/heic'): self.reply(415); return
        if n == 0: self.reply(400); return
        if n > 3 * 1024 * 1024: self.reply(413); return
        if k.startswith('full/'): self.reply(507, b'{"error":"quota"}'); return
        store[k] = (ct, body); self.reply(201, b'{"ok":true}')
ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()

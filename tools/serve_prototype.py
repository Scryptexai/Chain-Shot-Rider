#!/usr/bin/env python3
"""
serve_prototype.py — Server statis untuk prototipe CHAIN RIDER.

Prototipe membaca Config/arena_config.json (di root repo), jadi server harus
melayani dari root repo. Handler ini hanya menambahkan satu hal: "/" diarahkan
ke /prototype/ supaya preview langsung membuka game, bukan daftar direktori.

    python3 tools/serve_prototype.py [port]
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.send_response(302)
            self.send_header("Location", "/prototype/")
            self.end_headers()
            return
        super().do_GET()

    def end_headers(self):
        # Prototipe di-iterasi cepat; jangan biarkan browser men-cache.
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    handler = partial(Handler, directory=str(ROOT))
    print(f"CHAIN RIDER prototype  ->  http://0.0.0.0:{port}/  (root: {ROOT})")
    ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()

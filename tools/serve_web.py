#!/usr/bin/env python3
"""Static server for the Godot 4.3 WebAssembly export.

Two reasons this exists instead of `python3 -m http.server`:

  1. `.wasm` must be served as `application/wasm`, otherwise
     `WebAssembly.instantiateStreaming()` refuses the stream and the engine
     falls back to a slower path (or fails outright on some browsers).
  2. The export is built with thread support OFF on purpose, so it needs no
     COOP/COEP isolation headers. Those headers are therefore NOT sent: in an
     embedded preview iframe the parent document is not cross-origin isolated,
     and demanding isolation there is what makes a Godot web build show a
     blank canvas.

Usage: python3 tools/serve_web.py [port] [directory]
"""
import functools, http.server, mimetypes, socketserver, sys

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".js")

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # No-cache keeps a rebuilt .wasm/.pck from being shadowed by a stale copy.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    root = sys.argv[2] if len(sys.argv) > 2 else "godot-web"
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", port),
            functools.partial(Handler, directory=root)) as httpd:
        print(f"Godot web export: http://0.0.0.0:{port}/ (root={root})", flush=True)
        httpd.serve_forever()

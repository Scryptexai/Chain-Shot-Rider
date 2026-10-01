#!/usr/bin/env python3
"""
serve_web_build.py - Static server for the exported Godot web build.

    godot --headless --path godot/ --export-release "Web" ../build/web/index.html
    python3 tools/serve_web_build.py [port]        # default 8081

This is NOT the plain `python3 -m http.server` used for the web build at the
repo root. That one serves the JavaScript
prototype from the repo root; this one serves the real engine build from
build/web and is the only way to see the actual MVP in a browser.

Why a dedicated server instead of `python3 -m http.server`:

  1. The Web preset is exported with variant/thread_support=true, so the
     build needs SharedArrayBuffer, which browsers only hand out to a
     cross-origin isolated page. That requires two response headers on
     every request:
         Cross-Origin-Opener-Policy: same-origin
         Cross-Origin-Embedder-Policy: require-corp
     Without them the canvas stays black and the console says
     "SharedArrayBuffer is not defined" - nothing about the missing headers.
     (The alternative is setting thread_support=false in the preset, which
     drops the requirement at the cost of threaded performance.)

  2. Python's default mimetypes table has no entry for .wasm on many
     systems, and a wasm file served as text/plain is rejected by
     WebAssembly.instantiateStreaming.
"""

import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "build" / "web"

EXTRA_TYPES = {
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".data": "application/octet-stream",
    ".js": "text/javascript",
}


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        # Cross-origin isolation: required for SharedArrayBuffer.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()

    def guess_type(self, path):
        suffix = Path(str(path)).suffix.lower()
        if suffix in EXTRA_TYPES:
            return EXTRA_TYPES[suffix]
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    if not (WEB_DIR / "index.html").exists():
        print(f"No web build at {WEB_DIR}/index.html", file=sys.stderr)
        print("", file=sys.stderr)
        print("Export it first (needs the 4.3 export templates installed):", file=sys.stderr)
        print(
            '  godot --headless --path godot/ --export-release "Web" ../build/web/index.html',
            file=sys.stderr,
        )
        return 2

    handler = partial(Handler, directory=str(WEB_DIR))
    print(f"CHAIN RIDER web build  ->  http://0.0.0.0:{port}/  (root: {WEB_DIR})")
    print("cross-origin isolated: COOP=same-origin, COEP=require-corp")
    ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

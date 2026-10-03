#!/usr/bin/env python3
"""
serve_web_build.py - Static server for the exported Godot web build.

    godot --headless --path godot/ --export-release "Web" ../build/web/index.html
    python3 tools/serve_web_build.py [port] [--isolated]     # default 8081

This is NOT the plain `python3 -m http.server` used for the JavaScript
prototype at the repo root; this one serves the real engine build from
build/web and is the only way to see the actual Godot MVP in a browser.

Sejak v1.0 preset Web diekspor dengan variant/thread_support=false memakai
template web_nothreads_*. Artinya build TIDAK butuh SharedArrayBuffer, dan
karena itu tidak butuh header cross-origin isolation:

    Cross-Origin-Opener-Policy: same-origin
    Cross-Origin-Embedder-Policy: require-corp

Itu pilihan sadar, bukan kompromi malas. GitHub Pages, itch.io, dan sebagian
besar host statis gratis tidak bisa mengirim kedua header itu, dan Safari iOS
mematikan SharedArrayBuffer di banyak konfigurasi. Build berulir akan tampil
sebagai kanvas hitam di sana, tanpa pesan error yang menyebut header.

Jadi server ini sengaja menyajikan build persis seperti GitHub Pages
menyajikannya: tanpa header isolasi. Kalau build berulir diuji lagi,
jalankan dengan --isolated supaya headernya ikut terkirim.

Yang tetap dilakukan server ini, karena tanpanya build pasti gagal:
Python's default mimetypes table has no entry for .wasm on many systems, dan
file wasm yang disajikan sebagai text/plain ditolak oleh
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


ISOLATED = False


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        # Hanya untuk build berulir. Build nothreads sengaja disajikan polos,
        # supaya yang diuji di sini sama persis dengan yang dilihat pemain di
        # GitHub Pages.
        if ISOLATED:
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
    global ISOLATED
    args = [a for a in sys.argv[1:] if a != "--isolated"]
    ISOLATED = "--isolated" in sys.argv
    port = int(args[0]) if args else 8081
    if not (WEB_DIR / "index.html").exists():
        print(f"No web build at {WEB_DIR}/index.html", file=sys.stderr)
        print("", file=sys.stderr)
        print("Export it first (needs the 4.6.2 export templates installed):", file=sys.stderr)
        print(
            '  godot --headless --path godot/ --export-release "Web" ../build/web/index.html',
            file=sys.stderr,
        )
        return 2

    handler = partial(Handler, directory=str(WEB_DIR))
    print(f"CHAIN RIDER web build  ->  http://0.0.0.0:{port}/  (root: {WEB_DIR})")
    if ISOLATED:
        print("cross-origin isolated: COOP=same-origin, COEP=require-corp")
    else:
        print("tanpa header isolasi — sama seperti GitHub Pages (build nothreads)")
    ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

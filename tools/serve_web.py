#!/usr/bin/env python3
"""Server statis kecil untuk build web Godot di `build/web/`.

`python3 -m http.server` saja tidak cukup untuk dua alasan:

  * `.wasm` tidak ada di tabel MIME bawaan sebagian sistem, jadi terkirim
    sebagai `application/octet-stream`. `WebAssembly.instantiateStreaming`
    menolak itu dan game-nya gagal start dengan pesan yang membingungkan.
  * Build Godot butuh `.pck` (8–9 MB) dan `.wasm` (35 MB) terkirim utuh;
    caching browser di preview sandbox bikin perubahan build tidak kelihatan,
    jadi cache dimatikan.

Header COOP/COEP sengaja TIDAK dipasang: template yang dipakai adalah varian
`nothreads`, yang justru tidak memerlukannya.

    python3 tools/serve_web.py [port]      # default 8090
"""
import functools
import http.server
import os
import socketserver
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
        ".json": "application/json",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):  # ringkas: satu baris per permintaan
        sys.stderr.write("%s %s\n" % (self.command, self.path))


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
    root = os.path.normpath(ROOT)
    if not os.path.isfile(os.path.join(root, "index.html")):
        print("build/web/index.html belum ada — jalankan: bash tools/export_web.sh")
        return 1
    handler = functools.partial(Handler, directory=root)
    socketserver.TCPServer.allow_reuse_address = True
    # 0.0.0.0, bukan localhost: preview dijangkau dari luar sandbox.
    with socketserver.ThreadingTCPServer(("0.0.0.0", port), handler) as httpd:
        print("menyajikan %s di 0.0.0.0:%d" % (root, port), flush=True)
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

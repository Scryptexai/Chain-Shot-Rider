#!/usr/bin/env python3
"""
run_web_preview.py — Satu perintah untuk melihat game Godot asli di browser.

    python3 tools/run_web_preview.py            # ekspor + sajikan di :8081
    python3 tools/run_web_preview.py --port 9000
    python3 tools/run_web_preview.py --skip-export      # sajikan build yang ada
    python3 tools/run_web_preview.py --install-templates

Yang tergambar adalah engine sungguhan: runtime Godot yang dikompilasi ke
WebAssembly, menggambar lewat WebGL2. Ini BUKAN index.html di root, yang
merupakan prototipe JavaScript tulisan tangan tanpa Godot sama sekali.

Skrip ini sengaja tipis. Dulu ia menyimpan salinan sendiri dari logika ekspor
(versi engine, lokasi template, perintah ekspor) dan salinan itu membusuk:
project sudah pindah ke 4.6 dengan template nothreads sementara skrip ini
masih mencari template berulir 4.3, lalu gagal dengan pesan yang menuduh
engine. Sekarang ekspor hidup di satu tempat — tools/export_web.py — dan
berkas ini hanya merangkai ekspor + server.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "build" / "web"
TEMPLATE_HINT = """
Export template dipasang dari zip yang sudah ada di root repo (sandbox ini
tidak bisa mengunduh dari godotengine.org):

  mkdir -p ~/.local/share/godot/export_templates/4.6.2.stable
  cp web_nothreads_debug.zip web_nothreads_release.zip \\
     ~/.local/share/godot/export_templates/4.6.2.stable/
  echo "4.6.2.stable" > ~/.local/share/godot/export_templates/4.6.2.stable/version.txt

Di mesin sendiri: Editor -> Manage Export Templates -> Download and Install.
Preset "Web" memakai variant/thread_support=false, jadi yang dibutuhkan
adalah berkas web_nothreads_*.zip, bukan web_*.zip.
""".strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--skip-export", action="store_true")
    parser.add_argument("--debug", action="store_true", help="ekspor preset debug")
    parser.add_argument("--install-templates", action="store_true")
    args = parser.parse_args()

    if args.install_templates:
        print(TEMPLATE_HINT)
        return 0

    if not args.skip_export:
        export = [sys.executable, str(ROOT / "tools" / "export_web.py")]
        if args.debug:
            export.append("--debug")
        code = subprocess.run(export).returncode
        if code != 0:
            print("\n" + TEMPLATE_HINT, file=sys.stderr)
            return code
    elif not (WEB_DIR / "index.html").exists():
        print(f"Tidak ada build di {WEB_DIR}. Jalankan tanpa --skip-export.", file=sys.stderr)
        return 1

    serve = [sys.executable, str(ROOT / "tools" / "serve_web_build.py"), str(args.port)]
    return subprocess.run(serve).returncode


if __name__ == "__main__":
    raise SystemExit(main())

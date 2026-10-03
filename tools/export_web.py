#!/usr/bin/env python3
"""
export_web.py — Mengekspor build web Godot yang sesungguhnya, lalu memeriksanya.

    python3 tools/export_web.py [--debug] [--serve]

Mengekspor lewat engine yang sama dengan yang dipakai tools/run_game.py, ke
build/web/ (di luar git, lihat .gitignore). Sebelum mengekspor, tiga hal
diperiksa — ketiganya pernah menghabiskan waktu berjam-jam karena pesan
errornya menyesatkan:

  1. Versi engine cocok dengan project. Engine 4.3 mengekspor project 4.6
     tanpa menolak, lalu build-nya mati di browser karena fitur yang tidak
     ada.
  2. Export template untuk versi itu terpasang, DAN varian yang terpasang
     cocok dengan preset. Preset nothreads menuntut web_nothreads_*.zip;
     kalau yang ada cuma web_*.zip, Godot menjawab "Template file not found"
     tanpa menyebut varian.
  3. Hasil ekspor punya keempat berkas wajib. Ekspor bisa "berhasil" dengan
     .pck hilang, dan halamannya baru mati setelah engine boot.

Setelah ekspor, ukuran tiap berkas dilaporkan beserta perkiraan ukuran
terkirim (gzip) — yang dirasakan pemain di jaringan ponsel adalah angka
kedua, bukan ukuran di disk.
"""

from __future__ import annotations

import argparse
import gzip
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "godot"
OUT_DIR = ROOT / "build" / "web"
PRESET = "Web"
PRESETS_FILE = PROJECT / "export_presets.cfg"

REQUIRED = ["index.html", "index.js", "index.wasm", "index.pck"]


def engine() -> str:
    """Binary Godot yang sama dengan yang dipakai run_game.py."""
    import os

    override = os.environ.get("GODOT")
    if override:
        return override
    found = shutil.which("godot")
    if not found:
        sys.exit("Godot tidak ada di PATH. Jalankan: bash tools/install_godot.sh 4.6.2-stable")
    return found


def engine_version(binary: str) -> str:
    out = subprocess.run([binary, "--version"], capture_output=True, text=True)
    return (out.stdout or out.stderr).strip().splitlines()[-1]


def project_feature_version() -> str:
    text = (PROJECT / "project.godot").read_text(encoding="utf-8")
    found = re.search(r'config/features=PackedStringArray\("([\d.]+)"', text)
    return found.group(1) if found else ""


def thread_support() -> bool:
    """Preset Web memakai template berulir atau tidak."""
    text = PRESETS_FILE.read_text(encoding="utf-8")
    block = text.split('name="Web"', 1)[-1]
    return "variant/thread_support=true" in block


def template_dir(version: str) -> Path:
    import os

    base = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
    return Path(base) / "godot" / "export_templates" / f"{version}.stable"


def check_templates(version: str, threaded: bool) -> Path:
    folder = template_dir(version)
    wanted = ["web_debug.zip", "web_release.zip"] if threaded else [
        "web_nothreads_debug.zip",
        "web_nothreads_release.zip",
    ]
    missing = [w for w in wanted if not (folder / w).exists()]
    if missing:
        print(f"Template web hilang di {folder}:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        print("", file=sys.stderr)
        print("Salin berkas template ke folder itu, mis.:", file=sys.stderr)
        print(f"  mkdir -p {folder}", file=sys.stderr)
        print(f"  cp web_nothreads_*.zip {folder}/", file=sys.stderr)
        print(f"  echo {version}.stable > {folder}/version.txt", file=sys.stderr)
        sys.exit(2)
    return folder


def human(n: int) -> str:
    return f"{n / 1_048_576:.2f} MB" if n >= 1_048_576 else f"{n / 1024:.0f} KB"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debug", action="store_true", help="build debug, bukan release")
    parser.add_argument("--serve", action="store_true", help="jalankan server setelah ekspor")
    args = parser.parse_args()

    binary = engine()
    version_line = engine_version(binary)
    engine_short = ".".join(version_line.split(".")[:2])
    want = project_feature_version()

    print("\nCHAIN RIDER — ekspor web")
    print("=" * 72)
    print(f"engine  : {version_line}")
    print(f"project : fitur {want}")
    if want and not version_line.startswith(want):
        print(
            f"\nEngine {engine_short} tidak cocok dengan project {want}.\n"
            "Pasang engine yang benar atau perbarui config/features di project.godot.",
            file=sys.stderr,
        )
        return 2

    threaded = thread_support()
    full_version = ".".join(version_line.split(".")[:3])
    folder = check_templates(full_version, threaded)
    print(f"template: {'berulir' if threaded else 'nothreads'} @ {folder}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mode = "--export-debug" if args.debug else "--export-release"
    print(f"\nmengekspor preset '{PRESET}' ({mode[9:]})...")
    run = subprocess.run(
        [binary, "--headless", "--path", str(PROJECT), mode, PRESET,
         str(OUT_DIR / "index.html")],
        capture_output=True,
        text=True,
    )
    if run.returncode != 0:
        sys.stderr.write(run.stdout[-4000:])
        sys.stderr.write(run.stderr[-4000:])
        return run.returncode

    missing = [f for f in REQUIRED if not (OUT_DIR / f).exists()]
    if missing:
        print(f"\nEkspor selesai tapi berkas wajib hilang: {', '.join(missing)}", file=sys.stderr)
        return 3

    print("\nhasil:")
    total = 0
    sent = 0
    for path in sorted(OUT_DIR.iterdir()):
        if not path.is_file():
            continue
        size = path.stat().st_size
        total += size
        # Perkiraan ukuran terkirim: host statis mana pun mengirim .wasm dan
        # .js dalam gzip. Itu angka yang dirasakan pemain, bukan ukuran disk.
        if path.suffix in (".wasm", ".js", ".html", ".json"):
            packed = len(gzip.compress(path.read_bytes(), 6))
        else:
            packed = size
        sent += packed
        note = f"  (gzip {human(packed)})" if packed != size else ""
        print(f"  {path.name:<34} {human(size):>10}{note}")
    print(f"  {'TOTAL':<34} {human(total):>10}  (gzip {human(sent)})")

    budget = 100 * 1_048_576
    if total > budget:
        print(f"\nMELEWATI anggaran docs/08 ({human(budget)}).", file=sys.stderr)
        return 4
    print(f"\nDi bawah anggaran docs/08 ({human(budget)}).")
    print("\nUji di browser sungguhan:")
    print("  python3 tools/serve_web_build.py 8081 &")
    print("  node tools/web_build_test.js")

    if args.serve:
        subprocess.run([sys.executable, str(ROOT / "tools" / "serve_web_build.py")])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

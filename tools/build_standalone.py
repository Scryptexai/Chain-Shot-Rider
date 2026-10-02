#!/usr/bin/env python3
"""
build_standalone.py — Menggabung seluruh game menjadi SATU berkas HTML.

Semua cara menjalankan sebelumnya masih menuntut server lokal, karena browser
memblokir fetch() dan pemuatan GLB lewat protokol file:// (aturan CORS). Skrip
ini menghapus syarat itu dengan menanam semuanya ke dalam satu berkas:

  - Config/arena_config.json      -> objek JS literal
  - js/vendor/three.min.js        -> inline
  - js/vendor/GLTFLoader.js       -> inline
  - js/render3d.js                -> inline
  - assets/models/*.glb           -> data URI base64

Hasilnya chain-rider.html yang bisa dibuka dengan klik dua kali, tanpa server,
tanpa internet, tanpa Godot, tanpa Python. Berkas itu juga bisa dikirim lewat
chat atau disalin ke HP dan tetap jalan.

Pemakaian:
    python3 tools/build_standalone.py
"""

from __future__ import annotations

import base64
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "chain-rider.html"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def main() -> None:
    html = read("index.html")

    # --- 1. Model GLB -> data URI -----------------------------------------
    models = {}
    for glb in sorted((ROOT / "assets" / "models").glob("*.glb")):
        b64 = base64.b64encode(glb.read_bytes()).decode("ascii")
        models[f"assets/models/{glb.name}"] = f"data:model/gltf-binary;base64,{b64}"
    print(f"  {len(models)} model GLB ditanam")

    # --- 2. Three.js, GLTFLoader, renderer --------------------------------
    three = read("js/vendor/three.min.js")
    loader = read("js/vendor/GLTFLoader.js")
    render3d = read("js/render3d.js")

    # Peta path -> data URI dipakai render3d saat memanggil GLTFLoader.
    render3d = render3d.replace(
        "  var loaded = {};      // name -> Object3D prototype",
        "  // Build satu berkas: path diganti data URI yang ditanam di halaman.\n"
        "  if (typeof INLINE_MODELS !== 'undefined') {\n"
        "    Object.keys(MODELS).forEach(function (k) {\n"
        "      if (INLINE_MODELS[MODELS[k]]) MODELS[k] = INLINE_MODELS[MODELS[k]];\n"
        "    });\n"
        "  }\n"
        "  var loaded = {};      // name -> Object3D prototype",
        1,
    )

    inline_scripts = (
        "<script>window.INLINE_MODELS = "
        + json.dumps(models)
        + ";</script>\n"
        + f"<script>{three}</script>\n"
        + f"<script>{loader}</script>\n"
        + f"<script>{render3d}</script>"
    )

    # Ganti ketiga tag <script src> dengan versi inline.
    html, n = re.subn(
        r'<script src="js/vendor/three\.min\.js"></script>\s*'
        r'<script src="js/vendor/GLTFLoader\.js"></script>\s*'
        r'<script src="js/render3d\.js"></script>',
        lambda _m: inline_scripts,
        html,
        count=1,
    )
    assert n == 1, "tag script vendor tidak ditemukan"

    # --- 3. Config -> literal, menggantikan fetch() -----------------------
    cfg = json.loads(read("Config/arena_config.json"))
    old_boot = re.search(r"fetch\('Config/arena_config\.json'\)", html)
    assert old_boot, "pemanggilan fetch config tidak ditemukan"

    # fetch() diganti Promise yang langsung memberi config, sehingga sisa alur
    # boot tidak perlu diubah sama sekali.
    html = html.replace(
        "fetch('Config/arena_config.json')\n  .then(r=>r.json())",
        "Promise.resolve(window.INLINE_CONFIG)",
        1,
    )
    html = html.replace(
        "<script>window.INLINE_MODELS = ",
        "<script>window.INLINE_CONFIG = " + json.dumps(cfg) + ";\nwindow.INLINE_MODELS = ",
        1,
    )

    html = html.replace("<title>CHAIN RIDER</title>",
                        "<title>CHAIN RIDER — satu berkas, tanpa server</title>", 1)

    OUT.write_text(html, encoding="utf-8")
    size = OUT.stat().st_size
    print(f"\n  {OUT.name}  {size / 1024 / 1024:.2f} MB")
    print("  Buka dengan klik dua kali. Tanpa server, tanpa internet, tanpa Godot.\n")


if __name__ == "__main__":
    main()

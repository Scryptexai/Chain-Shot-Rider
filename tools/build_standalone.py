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

    # --- 1. Aset -> data URI ----------------------------------------------
    models: dict[str, str] = {}

    # Props arena: GLB mandiri, cukup di-base64.
    for glb in sorted((ROOT / "assets/models").glob("*.glb")):
        b64 = base64.b64encode(glb.read_bytes()).decode("ascii")
        models[f"assets/models/{glb.name}"] = f"data:model/gltf-binary;base64,{b64}"

    # Karakter dan animasi KayKit: juga GLB mandiri (tekstur sudah di dalam).
    for rel in ("assets/models/kaykit/Characters/gltf",
                "assets/models/kaykit/Animations/gltf/Rig_Medium"):
        for glb in sorted((ROOT / rel).glob("*.glb")):
            b64 = base64.b64encode(glb.read_bytes()).decode("ascii")
            models[f"{rel}/{glb.name}"] = f"data:model/gltf-binary;base64,{b64}"

    # Senjata: .gltf + .bin + .png terpisah, jadi dua berkas pendampingnya
    # ikut ditanam KE DALAM JSON-nya sebagai data URI, lalu JSON-nya sendiri
    # jadi data URI. Berkas aslinya tidak diubah; yang dibentuk hanya salinan
    # di dalam HTML. GLTFLoader memeriksa magic "glTF" lebih dulu dan jatuh ke
    # jalur JSON kalau tidak cocok, jadi data URI JSON ini dimuat apa adanya.
    weapons = ROOT / "assets/models/kaykit/Assets/gltf"
    used = set()
    # Nama senjata KayKit ber-camelCase ("bow_withString"), jadi kelas
    # karakternya harus menyertakan huruf besar. Versi pertama regex ini hanya
    # huruf kecil: busur Ranger diam-diam tidak ikut ditanam dan baru ketahuan
    # dari error CORS saat berkas tunggal dibuka dari file://.
    for name in re.findall(r"(?:right|left): '([A-Za-z0-9_]+)'", read("js/render3d.js")):
        used.add(name)
    embedded = set()
    for gltf_path in sorted(weapons.glob("*.gltf")):
        if gltf_path.stem not in used:
            continue              # pack berisi 30 senjata; hanya yang dipakai
        embedded.add(gltf_path.stem)
        doc = json.loads(gltf_path.read_text(encoding="utf-8"))
        for buf in doc.get("buffers", []):
            uri = buf.get("uri")
            if uri and not uri.startswith("data:"):
                raw = (weapons / uri).read_bytes()
                buf["uri"] = ("data:application/octet-stream;base64,"
                              + base64.b64encode(raw).decode("ascii"))
        for img in doc.get("images", []):
            uri = img.get("uri")
            if uri and not uri.startswith("data:"):
                raw = (weapons / uri).read_bytes()
                img["uri"] = ("data:image/png;base64,"
                              + base64.b64encode(raw).decode("ascii"))
        packed = base64.b64encode(
            json.dumps(doc, separators=(",", ":")).encode("utf-8")).decode("ascii")
        key = f"assets/models/kaykit/Assets/gltf/{gltf_path.name}"
        models[key] = f"data:application/json;base64,{packed}"

    # Senjata yang disebut resep tapi tidak ketemu berkasnya = berkas tunggal
    # yang pincang. Lebih baik build berhenti di sini daripada pemain membuka
    # HTML-nya dan melihat tangan kosong.
    missing = {n for n in used if (weapons / f"{n}.gltf").exists()} - embedded
    unknown = {n for n in used if not (weapons / f"{n}.gltf").exists()
               and n not in ("handslotr", "handslotl")}
    if missing:
        raise SystemExit(f"senjata dipakai tapi tidak ditanam: {sorted(missing)}")
    if unknown:
        raise SystemExit(f"resep menyebut senjata yang tidak ada di pack: {sorted(unknown)}")

    print(f"  {len(models)} aset ditanam ({len(embedded)} senjata)")

    # --- 2. Three.js, GLTFLoader, renderer --------------------------------
    three = read("js/vendor/three.min.js")
    loader = read("js/vendor/GLTFLoader.js")
    render3d = read("js/render3d.js")

    # Peta path -> data URI dipakai render3d saat memanggil GLTFLoader.
    # Sisipan diletakkan SESUDAH kedua tabel path dideklarasikan. Pernah
    # diletakkan di tengah (setelah MODELS, sebelum RIGGED) dan hasilnya
    # halaman mati dengan "Cannot convert undefined or null to object" —
    # error yang tidak pernah muncul di versi multi-berkas.
    # Tidak ada lagi tabel path yang perlu ditambal: semua pemuatan aset di
    # render3d.js lewat assetURL(), yang otomatis membaca window.INLINE_MODELS
    # kalau ada. Dulu bagian ini menulis ulang dua tabel dengan string replace
    # dan selalu rapuh terhadap perubahan nama variabel.
    assert "function assetURL(" in render3d, "render3d.js tidak punya assetURL()"

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

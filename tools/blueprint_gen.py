#!/usr/bin/env python3
"""
blueprint_gen.py — Generator blueprint arena CHAIN RIDER.

Membaca Config/arena_config.json dan menghasilkan docs/01-arena-blueprint.md:
  - ASCII top-down grid per varian arena (skala akurat terhadap data)
  - Tabel koordinat obstacle
  - Tabel zona, dinding, spawn

Blueprint TIDAK digambar manual supaya dokumen selalu sinkron dengan data.
Jalankan ulang setiap kali arena_config.json berubah:

    python3 tools/blueprint_gen.py

Sistem koordinat dunia:
    X : -10 .. +10   (lebar 20 unit, kiri ke kanan)
    Z :   0 .. 40    (panjang 40 unit, bawah ke atas)
    Y : up (tinggi), lantai pada Y = 0

Resolusi ASCII: 1 karakter = 0.5 unit pada sumbu X, 1 baris = 1.0 unit pada sumbu Z.
Rasio ini menjaga proporsi visual karena karakter terminal kira-kira 2x lebih tinggi
daripada lebarnya.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "Config" / "arena_config.json"
OUTPUT_PATH = ROOT / "docs" / "01-arena-blueprint.md"

CELL_X = 0.5   # unit dunia per karakter (sumbu X)
CELL_Z = 1.0   # unit dunia per baris     (sumbu Z)

GLYPH = {
    "empty": " ",
    "floor": ".",
    "wall": "|",
    "gate": "=",
    "floorline": "_",
    "defense": "-",
    "player": "A",
    "muzzle": "^",
    "pillar": "O",
    "bumper": "o",
    "barrel": "B",
    "gravityWell": "@",
    "gravityField": ":",
    "shieldWall": "#",
    "movingPlatform": "=",
    "platformTravel": "~",
}


def world_to_col(x: float, cols: int, x_min: float) -> int:
    return int(round((x - x_min) / CELL_X))


def world_to_row(z: float, rows: int, z_max: float) -> int:
    """Baris 0 = paling atas (z tertinggi)."""
    return int(round((z_max - z) / CELL_Z))


class Canvas:
    def __init__(self, cols: int, rows: int, fill: str = " "):
        self.cols = cols
        self.rows = rows
        self.buf = [[fill for _ in range(cols)] for _ in range(rows)]

    def put(self, col: int, row: int, ch: str, overwrite: bool = True) -> None:
        if 0 <= row < self.rows and 0 <= col < self.cols:
            if overwrite or self.buf[row][col] in (" ", GLYPH["floor"]):
                self.buf[row][col] = ch

    def render(self) -> list[str]:
        return ["".join(r) for r in self.buf]


def draw_base(cv: Canvas, arena: dict) -> None:
    x_min, x_max = arena["xMin"], arena["xMax"]
    z_max = arena["zMax"]
    rows, cols = cv.rows, cv.cols

    # Lantai grid tipis: titik tiap 2 unit supaya terbaca.
    for r in range(rows):
        z = z_max - r * CELL_Z
        for c in range(cols):
            x = x_min + c * CELL_X
            if int(round(z)) % 2 == 0 and int(round(x * 2)) % 4 == 0:
                cv.put(c, r, GLYPH["floor"])

    # Dinding kiri & kanan = bumper ricochet.
    for r in range(rows):
        cv.put(0, r, GLYPH["wall"])
        cv.put(cols - 1, r, GLYPH["wall"])

    # Dinding atas = spawn gate, dinding bawah = lantai pertahanan.
    for c in range(cols):
        cv.put(c, 0, GLYPH["gate"])
        cv.put(c, rows - 1, GLYPH["floorline"])

    # Garis pertahanan.
    dz = arena["defenseLineZ"]
    r = world_to_row(dz, rows, z_max)
    for c in range(1, cols - 1):
        cv.put(c, r, GLYPH["defense"])

    # Player.
    p = arena["playerSpawn"]
    pc = world_to_col(p["x"], cols, x_min)
    pr = world_to_row(p["z"], rows, z_max)
    cv.put(pc, pr, GLYPH["player"])
    cv.put(pc, pr - 1, GLYPH["muzzle"])


def draw_circle(cv: Canvas, arena: dict, x: float, z: float, radius: float,
                edge: str, fill: str | None = None) -> None:
    x_min, z_max = arena["xMin"], arena["zMax"]
    steps = max(24, int(radius * 40))
    if fill:
        rr = int(math.ceil(radius / CELL_Z))
        for dr in range(-rr, rr + 1):
            zz = z + dr * CELL_Z
            half = radius * radius - (zz - z) ** 2
            if half <= 0:
                continue
            half = math.sqrt(half)
            c0 = world_to_col(x - half, cv.cols, x_min)
            c1 = world_to_col(x + half, cv.cols, x_min)
            r = world_to_row(zz, cv.rows, z_max)
            for c in range(c0, c1 + 1):
                cv.put(c, r, fill, overwrite=False)
    for i in range(steps):
        a = (i / steps) * math.tau
        cx = x + math.cos(a) * radius
        cz = z + math.sin(a) * radius
        cv.put(world_to_col(cx, cv.cols, x_min),
               world_to_row(cz, cv.rows, z_max), edge)


def draw_obstacles(cv: Canvas, arena: dict, obstacles: list[dict], defaults: dict) -> None:
    x_min, z_max = arena["xMin"], arena["zMax"]
    for ob in obstacles:
        t = ob["type"]
        d = defaults.get(t, {})
        x, z = ob["x"], ob["z"]
        if t in ("pillar", "bumper"):
            radius = ob.get("radius", d.get("radius", 1.0))
            draw_circle(cv, arena, x, z, radius, GLYPH[t], GLYPH[t] if radius < 1.2 else " ")
        elif t == "barrel":
            radius = ob.get("radius", d.get("radius", 0.6))
            c, r = world_to_col(x, cv.cols, x_min), world_to_row(z, cv.rows, z_max)
            cv.put(c, r, GLYPH["barrel"])
            cv.put(c + 1, r, GLYPH["barrel"])
        elif t == "gravityWell":
            radius = ob.get("radius", d.get("radius", 4.0))
            draw_circle(cv, arena, x, z, radius, GLYPH["gravityField"], None)
            cv.put(world_to_col(x, cv.cols, x_min),
                   world_to_row(z, cv.rows, z_max), GLYPH["gravityWell"])
        elif t == "shieldWall":
            w = ob.get("width", d.get("width", 3.0))
            r = world_to_row(z, cv.rows, z_max)
            for c in range(world_to_col(x - w / 2, cv.cols, x_min),
                           world_to_col(x + w / 2, cv.cols, x_min) + 1):
                cv.put(c, r, GLYPH["shieldWall"])
        elif t == "movingPlatform":
            w = ob.get("width", d.get("width", 4.0))
            travel = ob.get("travel", 6.0)
            r = world_to_row(z, cv.rows, z_max)
            for c in range(world_to_col(x - travel / 2 - w / 2, cv.cols, x_min),
                           world_to_col(x + travel / 2 + w / 2, cv.cols, x_min) + 1):
                cv.put(c, r, GLYPH["platformTravel"], overwrite=False)
            for c in range(world_to_col(x - w / 2, cv.cols, x_min),
                           world_to_col(x + w / 2, cv.cols, x_min) + 1):
                cv.put(c, r, GLYPH["movingPlatform"])


def with_rulers(lines: list[str], arena: dict) -> list[str]:
    """Tambah penggaris Z di kiri dan label X di atas/bawah."""
    z_max = arena["zMax"]
    out = []
    header = "      " + "".join(
        "|" if i % 4 == 0 else " " for i in range(len(lines[0]))
    )
    labels = "      "
    for i in range(0, len(lines[0]), 4):
        labels += f"{arena['xMin'] + i * CELL_X:<4.0f}"
    out.append("  X:  " + labels.strip().ljust(len(lines[0])))
    out.append(header)
    for r, line in enumerate(lines):
        z = z_max - r * CELL_Z
        tag = f"{z:>4.0f} " if int(z) % 5 == 0 else "     "
        out.append(f"{tag}{line}")
    return out


def zone_annotations(arena: dict) -> list[tuple[float, float, str]]:
    return [
        (arena["spawnZone"]["zMin"], arena["spawnZone"]["zMax"], "SPAWN ZONE (10u) — gate musuh"),
        (arena["combatZone"]["zMin"], arena["combatZone"]["zMax"], "COMBAT ZONE (25u) — ricochet + crowd"),
        (arena["playerZone"]["zMin"], arena["playerZone"]["zMax"], "PLAYER ZONE (5u) — garis pertahanan"),
    ]


def build_variant_block(cfg: dict, variant: dict) -> str:
    arena = cfg["arena"]
    cols = int(round((arena["xMax"] - arena["xMin"]) / CELL_X)) + 1
    rows = int(round((arena["zMax"] - arena["zMin"]) / CELL_Z)) + 1

    cv = Canvas(cols, rows)
    draw_base(cv, arena)
    draw_obstacles(cv, arena, variant["obstacles"], cfg["obstacleDefaults"])
    lines = with_rulers(cv.render(), arena)

    theme = variant["theme"]
    md = []
    md.append(f"### {variant['index']}. {variant['name']}  `id: {variant['id']}`\n")
    md.append(f"> {variant['description']}\n")
    md.append(
        f"| Tema | Musik | Musuh spesial | Boss |\n|---|---|---|---|\n"
        f"| `{theme['primary']}` / `{theme['enemy']}` / `{theme['bumper']}` "
        f"| `{variant['musicLayer']}` | `{variant['specialEnemy']}` | `{variant['boss']}` |\n"
    )
    md.append("```text")
    md.extend(lines)
    md.append("```\n")

    md.append("**Koordinat obstacle**\n")
    md.append("| # | Type | X | Z | Param |")
    md.append("|---|------|---|---|-------|")
    for i, ob in enumerate(variant["obstacles"], 1):
        extra = {k: v for k, v in ob.items() if k not in ("type", "x", "z")}
        defaults = cfg["obstacleDefaults"].get(ob["type"], {})
        merged = {**defaults, **extra}
        param = ", ".join(f"{k}={v}" for k, v in merged.items()) or "—"
        md.append(f"| {i} | `{ob['type']}` | {ob['x']:+.1f} | {ob['z']:.1f} | {param} |")
    md.append("")
    return "\n".join(md)


def build_document(cfg: dict) -> str:
    arena = cfg["arena"]
    md: list[str] = []
    md.append("# 1. Blueprint Arena — CHAIN RIDER\n")
    md.append(
        "> **File ini di-generate otomatis** oleh `tools/blueprint_gen.py` dari "
        "`Config/arena_config.json`.\n> Jangan edit manual — ubah JSON-nya lalu jalankan "
        "`python3 tools/blueprint_gen.py`.\n"
    )

    md.append("## 1.1 Sistem Koordinat\n")
    md.append(
        "Arena memakai koordinat dunia 3D dengan **origin di tengah dinding bawah**, "
        "supaya matematika ricochet dan spawn gampang dibaca:\n"
    )
    md.append("```text")
    md.append("            Z = 40  (spawn gate / dinding atas)")
    md.append("               ^")
    md.append("               |")
    md.append("  X = -10 <----+----> X = +10      Y = up (tinggi), lantai di Y = 0")
    md.append("               |")
    md.append("            Z = 0   (lantai / belakang player)")
    md.append("```\n")
    md.append(
        f"- Lebar dunia **{arena['width']:.0f} unit**, panjang **{arena['height']:.0f} unit** "
        f"(rasio 1:2, pas untuk viewport portrait 9:16 dengan kamera miring "
        f"{cfg['camera']['pitchDegrees']:.0f}°).\n"
        f"- 1 unit dunia ≈ tinggi 1 musuh grunt. Spacing crowd {cfg['spawn']['spacing']} unit "
        "→ 12 kolom muat pas di lebar arena tanpa menyentuh dinding.\n"
    )

    md.append("## 1.2 Zona\n")
    md.append("| Zona | Rentang Z | Ukuran | Fungsi |")
    md.append("|------|-----------|--------|--------|")
    for z0, z1, label in zone_annotations(arena):
        name, rest = label.split(" — ")
        md.append(f"| **{name.split(' (')[0]}** | `{z0:.0f} .. {z1:.0f}` | {z1 - z0:.0f}u | {rest} |")
    md.append("")
    md.append(
        f"- **Garis pertahanan** pada `Z = {arena['defenseLineZ']:.0f}`. Musuh yang melewatinya "
        f"→ `-{cfg['player']['damagePerLeakedEnemy']} HP` (total {cfg['player']['lives']} nyawa).\n"
        f"- **Near-miss band**: musuh dalam `{arena['nearMissBandZ']}` unit di atas garis "
        "memicu SFX heartbeat.\n"
        f"- **Player** statis di `({arena['playerSpawn']['x']:.1f}, {arena['playerSpawn']['z']:.1f})`, "
        "menghadap +Z. Tidak ada kontrol gerak — semua mobilitas dari peluru.\n"
    )

    md.append("## 1.3 Dinding\n")
    md.append("| Dinding | Posisi | Tipe | Restitution | Catatan |")
    md.append("|---------|--------|------|-------------|---------|")
    w = arena["walls"]
    md.append(f"| Kiri | `X = {w['left']['x']:.0f}` | `{w['left']['type']}` | {w['left']['restitution']} | Memantulkan peluru, **tidak** memantulkan musuh |")
    md.append(f"| Kanan | `X = {w['right']['x']:.0f}` | `{w['right']['type']}` | {w['right']['restitution']} | Idem |")
    md.append(f"| Atas | `Z = {w['top']['z']:.0f}` | `{w['top']['type']}` | {w['top']['restitution']} | Peluru yang keluar di sini mati (bukan pantul) |")
    md.append(f"| Bawah | `Z = {w['bottom']['z']:.0f}` | `{w['bottom']['type']}` | {w['bottom']['restitution']} | Peluru mati, musuh = damage |")
    md.append("")

    md.append("## 1.4 Legenda ASCII\n")
    md.append("```text")
    md.append("|  dinding bumper (kiri/kanan)      O  pillar (r = 1.5–2.4)")
    md.append("=  spawn gate (atas)                o  bumper kecil (r = 0.9)")
    md.append("_  lantai belakang (bawah)          B  barrel explosive")
    md.append("-  GARIS PERTAHANAN (Z = 5)         @  gravity well (inti)")
    md.append("A  player (statis)                  :  radius gravity well")
    md.append("^  arah tembak (+Z)                 #  shield wall (rusak dari belakang)")
    md.append(".  grid lantai neon (tiap 2u)       ~  jalur travel moving platform")
    md.append("")
    md.append("Skala: 1 karakter = 0.5 unit X, 1 baris = 1.0 unit Z.")
    md.append("```\n")

    md.append("## 1.5 Blueprint 5 Varian Arena\n")
    for variant in cfg["variants"]:
        md.append(build_variant_block(cfg, variant))

    md.append("## 1.6 Aturan Penempatan (design rules)\n")
    md.append(
        "1. **Simetri kiri-kanan wajib** untuk semua bumper — pemain satu jempol harus bisa "
        "memprediksi pantulan dari dua sisi dengan model mental yang sama.\n"
        "2. **Koridor minimum 2.0 unit** antara obstacle dan dinding, supaya peluru ber-radius "
        f"{cfg['bullet']['radius']} unit tidak pernah stuck.\n"
        "3. **Tidak ada obstacle di `Z < 7`** — player zone harus bersih agar pemain bisa membaca "
        "ancaman yang menembus garis.\n"
        "4. **Tidak ada obstacle solid di `Z > 32`** — spawn gate harus bebas agar formasi tidak "
        "rusak sebelum masuk combat zone.\n"
        "5. **Obstacle didesain sebagai sumber sudut**: tiap bumper menghasilkan minimal satu "
        "lintasan 3-bounce yang menyapu crowd penuh jika pemain steer benar.\n"
        "6. **Gravity well tidak boleh tumpang-tindih** — akumulasi force membuat lintasan "
        "tak terbaca dan merusak determinisme perseptual.\n"
    )
    return "\n".join(md) + "\n"


def main() -> None:
    cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(build_document(cfg), encoding="utf-8")
    print(f"OK  -> {OUTPUT_PATH.relative_to(ROOT)}  ({OUTPUT_PATH.stat().st_size} bytes)")


if __name__ == "__main__":
    main()

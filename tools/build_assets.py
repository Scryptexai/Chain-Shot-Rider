#!/usr/bin/env python3
"""
build_assets.py — Produksi PROPS arena CHAIN RIDER menjadi berkas GLB.

Model dibangun secara prosedural dengan Python + trimesh, diekspor ke GLB, lalu
dimuat di web oleh Three.js GLTFLoader. Tidak perlu Godot, tidak perlu Blender,
dan GLB yang sama bisa dipakai build Godot maupun build web, jadi keduanya
tidak menyimpang.

KARAKTER TIDAK LAGI DIBUAT DI SINI. Sejak pack KayKit Adventurers (CC0) masuk,
prajurit, tujuh tipe musuh, dan boss — baik versi ber-tulang di
assets/models/rigged/ maupun versi statis LOD jauh di assets/models/ — semuanya
dihasilkan tools/build_kaykit.py. Menjalankan skrip ini tidak boleh menimpa
mereka; yang tersisa di sini hanya perabot arena.

Warna dipanggang sebagai vertex color memakai palet resmi project. Material di
Three.js mengalikan warna itu, jadi tema tiap arena masih bisa menimpanya saat
runtime.

Sumbu: Y adalah atas (konvensi glTF), origin di telapak kaki, menghadap -Z
(arah musuh datang). Ukuran mengikuti radius di Config/arena_config.json supaya
mesh tidak perlu diskalakan sembarangan saat dirender.

Pemakaian:
    python3 -m venv ~/.cache/venv && ~/.cache/venv/bin/pip install trimesh numpy
    ~/.cache/venv/bin/python tools/build_assets.py
"""

from __future__ import annotations

import pathlib

import numpy as np
import trimesh

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "models"

# Palet props fantasi (docs/02-visual-style-guide.md). Kayu, batu, besi, dan
# satu warna sihir — tidak ada neon, karena karakter KayKit yang harus jadi
# benda paling terang di layar, bukan perabotnya.
WOOD = (122, 84, 48)
WOOD_DARK = (74, 50, 30)
IRON = (96, 102, 110)
STONE = (120, 118, 106)
STONE_DARK = (74, 74, 68)
MOSS = (86, 110, 64)
RUNE = (180, 107, 255)
EMBER = (255, 157, 60)
BONE = (214, 226, 240)


def tint(mesh: trimesh.Trimesh, rgb) -> trimesh.Trimesh:
    """Memanggang satu warna solid ke seluruh vertex."""
    rgba = np.array([[rgb[0], rgb[1], rgb[2], 255]] * len(mesh.vertices), dtype=np.uint8)
    mesh.visual.vertex_colors = rgba
    return mesh


def box(size, pos=(0, 0, 0), color=STONE) -> trimesh.Trimesh:
    m = trimesh.creation.box(extents=size)
    m.apply_translation(pos)
    return tint(m, color)


def cyl(radius, height, pos=(0, 0, 0), color=STONE, sections=12) -> trimesh.Trimesh:
    m = trimesh.creation.cylinder(radius=radius, height=height, sections=sections)
    m.apply_translation(pos)
    return tint(m, color)


def ball(radius, pos=(0, 0, 0), color=STONE, subdiv=2) -> trimesh.Trimesh:
    m = trimesh.creation.icosphere(subdivisions=subdiv, radius=radius)
    m.apply_translation(pos)
    return tint(m, color)


def cone(radius, height, pos=(0, 0, 0), color=STONE, sections=12) -> trimesh.Trimesh:
    m = trimesh.creation.cone(radius=radius, height=height, sections=sections)
    m.apply_translation(pos)
    return tint(m, color)


def save(parts, name: str) -> None:
    mesh = trimesh.util.concatenate(parts)
    # Vertex dipisah per face supaya shading-nya flat: bentuk kotak harus terlihat
    # bersudut, bukan membulat seperti hasil normal yang dirata-rata.
    mesh.unmerge_vertices()
    # Tanpa atribut NORMAL, material Lambert di Three.js tidak punya bahan untuk
    # menghitung cahaya dan modelnya tampil hitam pekat.
    mesh.rezero() if False else None
    _ = mesh.vertex_normals
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.glb"
    data = mesh.export(file_type="glb", include_normals=True)
    path.write_bytes(data)
    print(f"  {name + '.glb':<22} {len(mesh.vertices):>5} vert  {len(data):>7,} bytes")


# ---------------------------------------------------------------------------
# RINTANGAN
# ---------------------------------------------------------------------------
def build_barrel():
    """Tong mesiu kayu: duga kayu, dua simpai besi, sumbu membara di tutupnya."""
    p = [
        cyl(0.34, 0.80, (0, 0.40, 0), WOOD),
        cyl(0.37, 0.09, (0, 0.18, 0), IRON),
        cyl(0.37, 0.09, (0, 0.62, 0), IRON),
        cyl(0.30, 0.05, (0, 0.82, 0), WOOD_DARK),
        cyl(0.05, 0.14, (0, 0.90, 0), EMBER),
    ]
    save(p, "barrel")


def build_bumper():
    """Batu rune: tumpukan batu berlumut dengan cincin rune yang berpendar.

    Bentuk kubahnya dipertahankan dari versi lama — pemain membaca pantulan
    dari siluet, bukan dari bahannya — tapi bahannya kini batu dan sihir, bukan
    logam neon.
    """
    p = [
        cyl(0.90, 0.26, (0, 0.13, 0), STONE_DARK, sections=20),
        cyl(0.94, 0.07, (0, 0.28, 0), RUNE, sections=20),
        ball(0.62, (0, 0.20, 0), STONE),
        cyl(0.30, 0.10, (0, 0.74, 0), MOSS, sections=12),
    ]
    save(p, "bumper")


def build_shield_wall():
    """Palisade kayu berpalang besi; sisi lemahnya tetap punggung, seperti dulu."""
    p = [
        box((4.0, 1.15, 0.26), (0, 0.58, 0), WOOD_DARK),
        box((4.1, 0.10, 0.32), (0, 1.12, 0), IRON),
        box((0.12, 1.0, 0.34), (-1.2, 0.58, 0), WOOD),
        box((0.12, 1.0, 0.34), (0, 0.58, 0), WOOD),
        box((0.12, 1.0, 0.34), (1.2, 0.58, 0), WOOD),
        box((3.6, 0.08, 0.30), (0, 0.30, 0), IRON),
    ]
    save(p, "shield_wall")


def main():
    print("\nCHAIN RIDER — produksi props arena (trimesh -> GLB)")
    print("=" * 62)
    build_barrel()
    build_bumper()
    build_shield_wall()
    total = sum(f.stat().st_size for f in OUT.glob("*.glb"))
    print("=" * 62)
    print(f"{len(list(OUT.glob('*.glb')))} model, total {total / 1024:.0f} KB -> {OUT}\n")


if __name__ == "__main__":
    main()

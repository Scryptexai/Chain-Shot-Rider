#!/usr/bin/env python3
"""
build_assets.py — Produksi model 3D CHAIN RIDER menjadi berkas GLB.

Pola ini diambil dari Last Harbor: model dibangun secara prosedural dengan
Python + trimesh, diekspor ke GLB, lalu dimuat di web oleh Three.js GLTFLoader.
Tidak perlu Godot, tidak perlu Blender, tidak perlu artist — dan GLB yang sama
bisa dipakai build Godot maupun build web, jadi keduanya tidak menyimpang.

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

# Palet resmi project (docs/02-visual-style-guide.md).
INK = (232, 243, 255)
CYAN = (0, 229, 255)
DEEP = (0, 119, 182)
ENEMY = (255, 77, 61)
ORANGE = (255, 138, 43)
YELLOW = (255, 201, 60)
MAGENTA = (177, 77, 255)
STEEL = (120, 142, 170)
DARK = (28, 38, 66)
BONE = (214, 226, 240)


def tint(mesh: trimesh.Trimesh, rgb) -> trimesh.Trimesh:
    """Memanggang satu warna solid ke seluruh vertex."""
    rgba = np.array([[rgb[0], rgb[1], rgb[2], 255]] * len(mesh.vertices), dtype=np.uint8)
    mesh.visual.vertex_colors = rgba
    return mesh


def box(size, pos=(0, 0, 0), color=INK) -> trimesh.Trimesh:
    m = trimesh.creation.box(extents=size)
    m.apply_translation(pos)
    return tint(m, color)


def cyl(radius, height, pos=(0, 0, 0), color=INK, sections=12) -> trimesh.Trimesh:
    m = trimesh.creation.cylinder(radius=radius, height=height, sections=sections)
    m.apply_translation(pos)
    return tint(m, color)


def ball(radius, pos=(0, 0, 0), color=INK, subdiv=2) -> trimesh.Trimesh:
    m = trimesh.creation.icosphere(subdivisions=subdiv, radius=radius)
    m.apply_translation(pos)
    return tint(m, color)


def cone(radius, height, pos=(0, 0, 0), color=INK, sections=12) -> trimesh.Trimesh:
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
# SQUAD
# ---------------------------------------------------------------------------
def build_soldier():
    """Prajurit squad. Dibuat ramping dan tegak supaya barisan mudah dibaca."""
    p = []
    p.append(box((0.13, 0.30, 0.13), (-0.09, 0.15, 0), DARK))     # leg L
    p.append(box((0.13, 0.30, 0.13), (0.09, 0.15, 0), DARK))      # leg R
    p.append(box((0.34, 0.38, 0.22), (0, 0.49, 0), INK))          # torso
    p.append(box((0.42, 0.10, 0.24), (0, 0.63, 0), DEEP))         # shoulders
    p.append(ball(0.13, (0, 0.80, 0), BONE))                      # head
    p.append(box((0.07, 0.07, 0.42), (0.17, 0.52, -0.18), STEEL))  # rifle
    p.append(box((0.10, 0.04, 0.10), (0.17, 0.52, -0.40), CYAN))   # muzzle glow
    save(p, "soldier")


# ---------------------------------------------------------------------------
# MUSUH — tiap tipe harus punya siluet berbeda, bukan sekadar warna berbeda
# ---------------------------------------------------------------------------
def build_grunt():
    p = [
        box((0.14, 0.22, 0.14), (-0.11, 0.11, 0), DARK),
        box((0.14, 0.22, 0.14), (0.11, 0.11, 0), DARK),
        box((0.40, 0.34, 0.26), (0, 0.39, 0), ENEMY),
        ball(0.15, (0, 0.66, 0), ENEMY),
        box((0.10, 0.06, 0.08), (0, 0.68, -0.13), YELLOW),   # mata
    ]
    save(p, "enemy_grunt")


def build_runner():
    """Condong ke depan: terbaca cepat meski kecil."""
    p = [
        box((0.10, 0.34, 0.12), (-0.09, 0.17, 0.04), DARK),
        box((0.10, 0.34, 0.12), (0.09, 0.17, -0.04), DARK),
        box((0.26, 0.30, 0.20), (0, 0.50, -0.05), ORANGE),
        ball(0.12, (0, 0.72, -0.12), ORANGE),
        box((0.30, 0.05, 0.05), (0, 0.60, -0.16), YELLOW),
    ]
    save(p, "enemy_runner")


def build_brute():
    p = [
        box((0.22, 0.26, 0.22), (-0.18, 0.13, 0), DARK),
        box((0.22, 0.26, 0.22), (0.18, 0.13, 0), DARK),
        box((0.68, 0.46, 0.40), (0, 0.49, 0), (190, 60, 50)),
        box((0.80, 0.14, 0.44), (0, 0.70, 0), STEEL),        # bahu lapis baja
        ball(0.17, (0, 0.86, 0), (190, 60, 50)),
        box((0.16, 0.16, 0.16), (-0.42, 0.74, 0), STEEL),
        box((0.16, 0.16, 0.16), (0.42, 0.74, 0), STEEL),
    ]
    save(p, "enemy_brute")


def build_shielder():
    p = [
        box((0.14, 0.24, 0.14), (-0.12, 0.12, 0), DARK),
        box((0.14, 0.24, 0.14), (0.12, 0.12, 0), DARK),
        box((0.38, 0.38, 0.24), (0, 0.43, 0.06), ENEMY),
        ball(0.14, (0, 0.69, 0.06), ENEMY),
        box((0.66, 0.70, 0.09), (0, 0.46, -0.18), STEEL),    # perisai depan
        box((0.10, 0.52, 0.04), (0, 0.46, -0.24), CYAN),     # garis energi
    ]
    save(p, "enemy_shielder")


def build_splitter():
    """Dua paruh yang jelas: menyiratkan ia akan pecah saat mati."""
    p = [
        ball(0.26, (-0.15, 0.30, 0), MAGENTA),
        ball(0.26, (0.15, 0.30, 0), MAGENTA),
        box((0.06, 0.46, 0.34), (0, 0.30, 0), (60, 20, 90)),
        ball(0.07, (-0.15, 0.44, -0.18), YELLOW),
        ball(0.07, (0.15, 0.44, -0.18), YELLOW),
    ]
    save(p, "enemy_splitter")


def build_bomber():
    p = [
        ball(0.30, (0, 0.32, 0), (255, 110, 60)),
        cyl(0.05, 0.22, (0, 0.68, 0), DARK),                 # sumbu
        ball(0.07, (0, 0.80, 0), YELLOW),                    # percikan
        box((0.44, 0.07, 0.44), (0, 0.18, 0), DARK),         # cincin
    ]
    save(p, "enemy_bomber")


# ---------------------------------------------------------------------------
# BOSS
# ---------------------------------------------------------------------------
def build_boss():
    p = [
        box((2.3, 0.5, 1.5), (0, 0.3, 0), (70, 86, 120)),        # dasar
        box((1.9, 1.1, 1.2), (0, 1.05, 0), (150, 60, 55)),       # badan
        box((2.6, 0.30, 1.35), (0, 1.55, 0), STEEL),             # bahu
        ball(0.52, (0, 2.00, 0), (190, 70, 60)),                 # kepala
        box((0.70, 0.18, 0.18), (0, 2.02, -0.48), ENEMY),        # visor
        cyl(0.26, 1.3, (-1.25, 1.2, -0.2), STEEL),               # meriam kiri
        cyl(0.26, 1.3, (1.25, 1.2, -0.2), STEEL),                # meriam kanan
        ball(0.20, (-1.25, 1.2, -0.75), YELLOW),
        ball(0.20, (1.25, 1.2, -0.75), YELLOW),
    ]
    save(p, "boss")


# ---------------------------------------------------------------------------
# RINTANGAN
# ---------------------------------------------------------------------------
def build_barrel():
    p = [
        cyl(0.34, 0.80, (0, 0.40, 0), ORANGE),
        cyl(0.37, 0.07, (0, 0.18, 0), DARK),
        cyl(0.37, 0.07, (0, 0.62, 0), DARK),
        cyl(0.22, 0.05, (0, 0.82, 0), YELLOW),
    ]
    save(p, "barrel")


def build_bumper():
    """Pemantul: kubah rendah dengan cincin menyala, mudah dikenali dari atas."""
    p = [
        cyl(0.90, 0.26, (0, 0.13, 0), DEEP, sections=20),
        cyl(0.94, 0.07, (0, 0.28, 0), CYAN, sections=20),
        ball(0.62, (0, 0.20, 0), (20, 60, 110)),
    ]
    save(p, "bumper")


def build_shield_wall():
    p = [
        box((4.0, 1.15, 0.26), (0, 0.58, 0), (60, 30, 95)),
        box((4.1, 0.10, 0.32), (0, 1.12, 0), MAGENTA),
        box((0.12, 1.0, 0.34), (-1.2, 0.58, 0), MAGENTA),
        box((0.12, 1.0, 0.34), (0, 0.58, 0), MAGENTA),
        box((0.12, 1.0, 0.34), (1.2, 0.58, 0), MAGENTA),
    ]
    save(p, "shield_wall")


def main():
    print("\nCHAIN RIDER — produksi aset 3D (trimesh -> GLB)")
    print("=" * 62)
    build_soldier()
    build_grunt()
    build_runner()
    build_brute()
    build_shielder()
    build_splitter()
    build_bomber()
    build_boss()
    build_barrel()
    build_bumper()
    build_shield_wall()
    total = sum(f.stat().st_size for f in OUT.glob("*.glb"))
    print("=" * 62)
    print(f"{len(list(OUT.glob('*.glb')))} model, total {total / 1024:.0f} KB -> {OUT}\n")


if __name__ == "__main__":
    main()

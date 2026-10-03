#!/usr/bin/env python3
"""
build_rigged.py — Karakter ber-tulang CHAIN RIDER (v1.0).

v0.x menggambar pasukan dan musuh sebagai kotak statis: mereka meluncur di
lantai seperti bidak catur. v1.0 menuntut karakter sungguhan — kaki melangkah,
badan menahan recoil, mayat roboh — jadi setiap unit sekarang punya skeleton,
senjata yang menempel di tangan, dan lima klip animasi.

Dibangun prosedural, sama seperti `tools/build_assets.py`, karena alasan yang
sama: satu sumber kebenaran yang bisa dibaca dan diubah di repo, tanpa artist,
tanpa Blender, tanpa unduhan berlisensi. Bedanya di sini kita tidak bisa pakai
trimesh — ia tidak punya konsep skin maupun animasi — jadi GLB-nya ditulis oleh
`tools/rigkit.py`.

Satu skeleton untuk semua tipe (nama tulang dan nama klip identik, hanya
proporsi yang berbeda), sehingga kode renderer tidak perlu tahu sedang
memainkan siapa: `run`, `shoot`, `hit`, `die`, `idle` selalu ada.

    python3 tools/build_rigged.py

Hasil: assets/models/rigged/*.glb
"""

from __future__ import annotations

import pathlib

from rigkit import Bone, Clip, Rig, export

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "models" / "rigged"

# Palet resmi project (docs/02-visual-style-guide.md). Alpha ikut ditulis
# karena COLOR_0 glTF bertipe VEC4.
INK = (0.91, 0.95, 1.0, 1)
BONE_W = (0.93, 0.89, 0.80, 1)
CYAN = (0.0, 0.90, 1.0, 1)
DEEP = (0.0, 0.47, 0.71, 1)
DARK = (0.09, 0.13, 0.20, 1)
STEEL = (0.47, 0.56, 0.67, 1)
ENEMY = (1.0, 0.30, 0.24, 1)
ORANGE = (1.0, 0.54, 0.17, 1)
BRUTE = (0.76, 0.20, 0.12, 1)
YELLOW = (1.0, 0.79, 0.24, 1)
PINK = (1.0, 0.37, 0.64, 1)
GOLD = (1.0, 0.84, 0.31, 1)
MAGENTA = (0.69, 0.30, 1.0, 1)


# ---------------------------------------------------------------------------
# SKELETON
# ---------------------------------------------------------------------------
def humanoid(scale: float = 1.0) -> list[Bone]:
    """Skeleton 15 tulang, Y atas, menghadap -Z (arah musuh datang).

    Lima belas, bukan lima puluh: yang perlu dibaca di layar 390 px hanyalah
    langkah kaki, ayunan lengan, dan tubuh yang roboh. Jari, klavikula, dan
    tulang punggung bersegmen tidak akan pernah terlihat, tapi akan selalu
    dibayar di setiap frame skinning untuk 90 unit sekaligus.
    """

    def s(x, y, z):
        return (x * scale, y * scale, z * scale)

    return [
        Bone("hips", None, s(0, 0.46, 0)),
        Bone("spine", "hips", s(0, 0.10, 0)),
        Bone("chest", "spine", s(0, 0.12, 0)),
        Bone("head", "chest", s(0, 0.16, 0)),
        Bone("shoulder_l", "chest", s(-0.17, 0.07, 0)),
        Bone("arm_l", "shoulder_l", s(0, -0.16, 0)),
        Bone("hand_l", "arm_l", s(0, -0.16, 0)),
        Bone("shoulder_r", "chest", s(0.17, 0.07, 0)),
        Bone("arm_r", "shoulder_r", s(0, -0.16, 0)),
        Bone("hand_r", "arm_r", s(0, -0.16, 0)),
        Bone("thigh_l", "hips", s(-0.09, -0.04, 0)),
        Bone("shin_l", "thigh_l", s(0, -0.21, 0)),
        Bone("foot_l", "shin_l", s(0, -0.17, 0)),
        Bone("thigh_r", "hips", s(0.09, -0.04, 0)),
        Bone("shin_r", "thigh_r", s(0, -0.21, 0)),
        Bone("foot_r", "shin_r", s(0, -0.17, 0)),
    ]


def body(rig: Rig, k: float, skin, cloth, trim, head_color=None) -> Rig:
    """Badan dasar: torso, kepala, dua lengan, dua kaki.

    Semua kotak ditulis di ruang bind, dan masing-masing menempel kaku pada
    satu tulang — itu yang memberi siluet bersendi tegas yang masih terbaca
    saat karakter cuma setinggi 40 piksel.
    """
    head_color = head_color or skin

    def v(x, y, z=0.0):
        return (x * k, y * k, z * k)

    def sz(x, y, z):
        return (x * k, y * k, z * k)

    rig.add("hips", sz(0.26, 0.15, 0.18), v(0, 0.47), cloth)
    rig.add("spine", sz(0.30, 0.13, 0.19), v(0, 0.60), cloth)
    rig.add("chest", sz(0.33, 0.20, 0.21), v(0, 0.70), skin)
    rig.add("head", sz(0.21, 0.20, 0.20), v(0, 0.86), head_color)
    for side, x in (("l", -1), ("r", 1)):
        rig.add("shoulder_%s" % side, sz(0.12, 0.12, 0.17), v(0.19 * x, 0.73), trim)
        rig.add("arm_%s" % side, sz(0.09, 0.17, 0.09), v(0.17 * x, 0.58), skin)
        rig.add("hand_%s" % side, sz(0.09, 0.09, 0.10), v(0.17 * x, 0.45), trim)
        rig.add("thigh_%s" % side, sz(0.12, 0.20, 0.13), v(0.09 * x, 0.32), cloth)
        rig.add("shin_%s" % side, sz(0.10, 0.17, 0.12), v(0.09 * x, 0.13), cloth)
        rig.add("foot_%s" % side, sz(0.12, 0.06, 0.19), v(0.09 * x, 0.03, -0.04), trim)
    return rig


# ---------------------------------------------------------------------------
# KLIP
# ---------------------------------------------------------------------------
def clip_idle(period: float = 1.8) -> Clip:
    """Diam yang tidak benar-benar diam: tanpa ini unit terlihat seperti patung."""
    h = period * 0.5
    return Clip(
        "idle",
        period,
        tracks={
            "chest": [(0, (0, 0, 0)), (h, (2.5, 0, 0)), (period, (0, 0, 0))],
            "head": [(0, (0, 0, 0)), (h, (-2, 3, 0)), (period, (0, 0, 0))],
            "arm_l": [(0, (0, 0, 0)), (h, (-4, 0, 0)), (period, (0, 0, 0))],
            "arm_r": [(0, (0, 0, 0)), (h, (-3, 0, 0)), (period, (0, 0, 0))],
        },
        root_motion=[(0, (0, 0, 0)), (h, (0, 0.012, 0)), (period, (0, 0, 0))],
    )


def clip_run(period: float = 0.62, stride: float = 34.0, lean: float = 6.0) -> Clip:
    """Langkah berjalan/berlari.

    Empat pose kunci per siklus, bukan dua: dengan dua pose kaki melewati
    posisi netral secara linear dan hasilnya terbaca seperti geser, bukan
    langkah. Lutut yang menekuk di fase ayun itulah yang membuat mata percaya.
    """
    q = period * 0.25
    half = period * 0.5
    return Clip(
        "run",
        period,
        tracks={
            "thigh_l": [
                (0, (stride, 0, 0)),
                (q, (0, 0, 0)),
                (half, (-stride * 0.8, 0, 0)),
                (q * 3, (0, 0, 0)),
                (period, (stride, 0, 0)),
            ],
            "shin_l": [
                (0, (-10, 0, 0)),
                (q, (-stride * 1.1, 0, 0)),
                (half, (-6, 0, 0)),
                (q * 3, (-14, 0, 0)),
                (period, (-10, 0, 0)),
            ],
            "thigh_r": [
                (0, (-stride * 0.8, 0, 0)),
                (q, (0, 0, 0)),
                (half, (stride, 0, 0)),
                (q * 3, (0, 0, 0)),
                (period, (-stride * 0.8, 0, 0)),
            ],
            "shin_r": [
                (0, (-6, 0, 0)),
                (q, (-14, 0, 0)),
                (half, (-10, 0, 0)),
                (q * 3, (-stride * 1.1, 0, 0)),
                (period, (-6, 0, 0)),
            ],
            "shoulder_l": [
                (0, (-stride * 0.5, 0, 0)),
                (half, (stride * 0.5, 0, 0)),
                (period, (-stride * 0.5, 0, 0)),
            ],
            "shoulder_r": [
                (0, (stride * 0.5, 0, 0)),
                (half, (-stride * 0.5, 0, 0)),
                (period, (stride * 0.5, 0, 0)),
            ],
            "spine": [(0, (lean, 0, 0)), (period, (lean, 0, 0))],
            "head": [(0, (-lean * 0.6, 0, 0)), (period, (-lean * 0.6, 0, 0))],
        },
        # Dua kali naik-turun per siklus: satu per injakan kaki.
        root_motion=[
            (0, (0, 0, 0)),
            (q, (0, 0.028, 0)),
            (half, (0, 0, 0)),
            (q * 3, (0, 0.028, 0)),
            (period, (0, 0, 0)),
        ],
    )


def clip_shoot(period: float = 0.26) -> Clip:
    """Recoil. Pendek dan keras — tembakan yang lembut terasa seperti bug."""
    return Clip(
        "shoot",
        period,
        loop=False,
        tracks={
            "shoulder_r": [(0, (0, 0, 0)), (0.05, (14, 0, 0)), (period, (0, 0, 0))],
            "arm_r": [(0, (0, 0, 0)), (0.05, (10, 0, 0)), (period, (0, 0, 0))],
            "chest": [(0, (0, 0, 0)), (0.05, (-5, 0, 0)), (period, (0, 0, 0))],
            "head": [(0, (0, 0, 0)), (0.05, (-4, 0, 0)), (period, (0, 0, 0))],
        },
    )


def clip_hit(period: float = 0.34) -> Clip:
    return Clip(
        "hit",
        period,
        loop=False,
        tracks={
            "spine": [(0, (0, 0, 0)), (0.08, (-16, 0, 0)), (period, (0, 0, 0))],
            "head": [(0, (0, 0, 0)), (0.08, (-22, 0, 0)), (period, (0, 0, 0))],
            "shoulder_l": [(0, (0, 0, 0)), (0.08, (-26, 0, 0)), (period, (0, 0, 0))],
            "shoulder_r": [(0, (0, 0, 0)), (0.08, (-26, 0, 0)), (period, (0, 0, 0))],
        },
    )


def clip_die(period: float = 0.85, drop: float = 0.40) -> Clip:
    """Roboh ke belakang.

    Kematian adalah satu-satunya umpan balik yang membuktikan tembakan kena,
    jadi ia harus punya bentuk — bukan unit yang tiba-tiba hilang. Pinggul
    jatuh dan berputar, lutut melipat, badan menyusul telat (0.12 s) supaya
    ada kesan berat.
    """
    return Clip(
        "die",
        period,
        loop=False,
        tracks={
            "hips": [(0, (0, 0, 0)), (0.18, (22, 0, 8)), (period, (88, 0, 12))],
            "spine": [(0, (0, 0, 0)), (0.30, (-14, 0, 0)), (period, (-26, 0, 0))],
            "head": [(0, (0, 0, 0)), (0.30, (-10, 0, 0)), (period, (-30, 0, 6))],
            "thigh_l": [(0, (0, 0, 0)), (period, (-46, 0, 0))],
            "thigh_r": [(0, (0, 0, 0)), (period, (-28, 0, 0))],
            "shin_l": [(0, (0, 0, 0)), (period, (-60, 0, 0))],
            "shin_r": [(0, (0, 0, 0)), (period, (-40, 0, 0))],
            "shoulder_l": [(0, (0, 0, 0)), (period, (-70, 0, 0))],
            "shoulder_r": [(0, (0, 0, 0)), (period, (-64, 0, 0))],
        },
        root_motion=[(0, (0, 0, 0)), (0.22, (0, -drop * 0.35, 0)), (period, (0, -drop, 0.06))],
    )


def standard_clips(rig: Rig, k: float, run_period: float, stride: float = 34.0) -> Rig:
    rig.clip(clip_idle())
    rig.clip(clip_run(run_period, stride))
    rig.clip(clip_shoot())
    rig.clip(clip_hit())
    rig.clip(clip_die(drop=0.40 * k))
    return rig


# ---------------------------------------------------------------------------
# UNIT
# ---------------------------------------------------------------------------
def build_trooper() -> Rig:
    """Prajurit squad: senapan di tangan kanan, moncong jadi soket efek."""
    k = 1.0
    rig = Rig("trooper", humanoid(k))
    body(rig, k, INK, DEEP, DARK, BONE_W)
    # Visor: satu garis cyan di kepala. Dari belakang kamera inilah satu-satunya
    # cara membedakan pasukan sendiri dari musuh pada barisan padat.
    rig.add("head", (0.22, 0.05, 0.03), (0, 0.88, -0.10), CYAN)
    rig.add("chest", (0.12, 0.10, 0.04), (0, 0.72, -0.11), CYAN)
    # Senapan menempel di tulang tangan kanan, bukan di badan: saat lengan
    # mengayun atau menahan recoil, senjatanya ikut — itu bedanya dengan
    # menempelkan prop di root karakter.
    rig.add("hand_r", (0.07, 0.08, 0.40), (0.17, 0.47, -0.16), STEEL)
    rig.add("hand_r", (0.05, 0.11, 0.07), (0.17, 0.40, -0.06), DARK)
    rig.add("hand_r", (0.09, 0.09, 0.07), (0.17, 0.47, -0.38), CYAN)
    rig.socket("muzzle", (0.17, 0.47, -0.44))
    return standard_clips(rig, k, 0.58)


def build_grunt() -> Rig:
    k = 1.0
    rig = Rig("grunt", humanoid(k))
    body(rig, k, ENEMY, DARK, ENEMY, ENEMY)
    rig.add("head", (0.12, 0.06, 0.03), (0, 0.88, -0.10), YELLOW)   # mata
    rig.add("hand_r", (0.10, 0.10, 0.16), (0.17, 0.45, -0.10), DARK)  # kepalan
    rig.add("hand_l", (0.10, 0.10, 0.16), (-0.17, 0.45, -0.10), DARK)
    rig.socket("muzzle", (0.17, 0.45, -0.20))
    return standard_clips(rig, k, 0.70, stride=30.0)


def build_runner() -> Rig:
    """Lebih ramping, langkah lebih cepat, condong — terbaca cepat meski kecil."""
    k = 0.92
    rig = Rig("runner", humanoid(k))
    body(rig, k, ORANGE, DARK, ORANGE, ORANGE)
    rig.add("head", (0.26, 0.05, 0.05), (0, 0.80, -0.10), YELLOW)
    rig.add("chest", (0.10, 0.10, 0.26), (0, 0.70, 0.14), ORANGE)  # sirip belakang
    rig.socket("muzzle", (0.16, 0.42, -0.18))
    return standard_clips(rig, k, 0.42, stride=42.0)


def build_brute() -> Rig:
    """Tank: lebih tinggi, bahu lebar, langkah berat."""
    k = 1.45
    rig = Rig("brute", humanoid(k))
    body(rig, k, BRUTE, DARK, BRUTE, BRUTE)
    rig.add("chest", (0.62, 0.18, 0.30), (0, 1.02, 0), DARK)      # pelat bahu
    rig.add("head", (0.26, 0.07, 0.05), (0, 1.26, -0.15), YELLOW)
    rig.add("hand_r", (0.22, 0.22, 0.24), (0.25, 0.62, -0.08), DARK)
    rig.add("hand_l", (0.22, 0.22, 0.24), (-0.25, 0.62, -0.08), DARK)
    rig.socket("muzzle", (0.25, 0.62, -0.24))
    return standard_clips(rig, k, 0.92, stride=26.0)


def build_shielder() -> Rig:
    """Perisai besar di lengan kiri — siluetnya harus mengumumkan 'tembak dari samping'."""
    k = 1.05
    rig = Rig("shielder", humanoid(k))
    body(rig, k, YELLOW, DARK, YELLOW, YELLOW)
    rig.add("hand_l", (0.52, 0.62, 0.07), (-0.20, 0.60, -0.26), STEEL)
    rig.add("hand_l", (0.46, 0.08, 0.04), (-0.20, 0.60, -0.31), YELLOW)
    rig.add("head", (0.22, 0.06, 0.04), (0, 0.92, -0.11), DARK)
    rig.socket("muzzle", (0.18, 0.48, -0.20))
    return standard_clips(rig, k, 0.86, stride=24.0)


def build_splitter() -> Rig:
    """Bulat dan bengkak: harus terbaca 'ini akan pecah'."""
    k = 1.0
    rig = Rig("splitter", humanoid(k))
    body(rig, k, PINK, DARK, PINK, PINK)
    rig.add("chest", (0.44, 0.34, 0.40), (0, 0.72, 0), PINK)
    rig.add("spine", (0.36, 0.22, 0.34), (0, 0.58, 0), MAGENTA)
    rig.add("head", (0.14, 0.06, 0.04), (0, 0.88, -0.12), YELLOW)
    rig.socket("muzzle", (0, 0.72, -0.24))
    return standard_clips(rig, k, 0.76, stride=28.0)


def build_bomber() -> Rig:
    """Membawa bom di depan dada: bahaya terlihat sebelum ia meledak."""
    k = 0.98
    rig = Rig("bomber", humanoid(k))
    body(rig, k, YELLOW, DARK, YELLOW, YELLOW)
    rig.add("chest", (0.26, 0.26, 0.26), (0, 0.60, -0.20), DARK)
    rig.add("chest", (0.10, 0.10, 0.10), (0, 0.74, -0.20), ENEMY)   # sumbu
    rig.add("head", (0.18, 0.06, 0.04), (0, 0.86, -0.11), ENEMY)
    rig.socket("muzzle", (0, 0.60, -0.34))
    return standard_clips(rig, k, 0.64, stride=32.0)


def build_boss() -> Rig:
    """Boss: dua kali ukuran prajurit, meriam di kedua lengan."""
    k = 2.1
    rig = Rig("boss", humanoid(k))
    body(rig, k, ENEMY, DARK, BRUTE, DARK)
    rig.add("chest", (0.90, 0.26, 0.42), (0, 1.52, 0), BRUTE)
    rig.add("head", (0.40, 0.10, 0.06), (0, 1.84, -0.22), GOLD)
    rig.add("spine", (0.30, 0.30, 0.16), (0, 1.30, -0.24), GOLD)   # inti dada
    for side, x in (("l", -1), ("r", 1)):
        rig.add("hand_%s" % side, (0.22, 0.22, 0.62), (0.36 * x, 0.95, -0.26), STEEL)
        rig.add("hand_%s" % side, (0.26, 0.26, 0.10), (0.36 * x, 0.95, -0.58), ENEMY)
    rig.socket("muzzle", (0.36, 0.95, -0.66))
    rig.socket("muzzle_l", (-0.36, 0.95, -0.66))
    rig.socket("core", (0, 1.30, -0.30))
    return standard_clips(rig, k, 1.10, stride=22.0)


UNITS = {
    "trooper": build_trooper,
    "grunt": build_grunt,
    "runner": build_runner,
    "brute": build_brute,
    "shielder": build_shielder,
    "splitter": build_splitter,
    "bomber": build_bomber,
    "boss": build_boss,
}


def main() -> None:
    print("\nCHAIN RIDER — karakter ber-tulang (v1.0)\n")
    total = 0
    for name, builder in UNITS.items():
        rig = builder()
        size = export(rig, OUT / f"{name}.glb")
        total += size
        print(
            "  %-22s %2d tulang  %3d kotak  %d klip  %6s bytes"
            % (name + ".glb", len(rig.bones), len(rig.parts), len(rig.clips), f"{size:,}")
        )
    print("\n  total %s bytes di %s\n" % (f"{total:,}", OUT.relative_to(OUT.parent.parent.parent)))


if __name__ == "__main__":
    main()

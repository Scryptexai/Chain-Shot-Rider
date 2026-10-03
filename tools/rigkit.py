#!/usr/bin/env python3
"""
rigkit.py — Penulis glTF 2.0 ber-tulang (skinned + animated) tanpa dependensi.

`tools/build_assets.py` memakai trimesh dan hanya bisa menghasilkan mesh statis:
trimesh tidak punya konsep skeleton, skin, maupun klip animasi. Untuk v1.0
karakter harus bergerak dari tulangnya — kaki melangkah, lengan menahan recoil,
mayat roboh — jadi dibutuhkan penulis GLB sendiri.

Yang ditulis modul ini:

  · hierarki node tulang (rest pose murni translasi),
  · satu skinned mesh dengan atribut JOINTS_0 / WEIGHTS_0 / COLOR_0,
  · `inverseBindMatrices`, dan
  · beberapa klip animasi berisi kurva rotasi (plus translasi pinggul).

Tiga keputusan yang membentuk sisanya:

1. **Skinning kaku, satu tulang per bagian tubuh.** Bobot campuran membutuhkan
   mesh rapat supaya tidak melipat jelek; karakter di sini kotak-kotak
   low-poly, dan satu bagian = satu tulang justru memberi siluet bersendi
   tegas yang terbaca di layar ponsel 390 px. Ini juga membuat normal tetap
   benar tanpa skinning normal yang mahal.

2. **Rest pose tanpa rotasi.** Semua tulang hanya punya translasi lokal, jadi
   matriks bind global = translasi global, dan inverse-nya cukup translasi
   negatif. Tidak ada inversi matriks umum yang perlu di-debug.

3. **Geometri ditulis di ruang bind (world).** Bagian tubuh didefinisikan di
   tempatnya berdiri; skin memindahkannya ke ruang tulang lewat IBM. Artinya
   definisi karakter terbaca seperti daftar kotak, sama seperti build_assets.py.

Dipakai oleh `tools/build_rigged.py`.
"""

from __future__ import annotations

import json
import math
import pathlib
import struct
from dataclasses import dataclass, field

# --- tipe komponen glTF ----------------------------------------------------
FLOAT = 5126
UNSIGNED_BYTE = 5121
UNSIGNED_SHORT = 5123

ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


# ---------------------------------------------------------------------------
# Matematika kecil (stdlib saja)
# ---------------------------------------------------------------------------
def euler_to_quat(x_deg: float, y_deg: float, z_deg: float) -> tuple:
    """Euler XYZ (derajat) → kuaternion (x, y, z, w), urutan rotasi X→Y→Z."""
    hx, hy, hz = (math.radians(a) * 0.5 for a in (x_deg, y_deg, z_deg))
    cx, sx = math.cos(hx), math.sin(hx)
    cy, sy = math.cos(hy), math.sin(hy)
    cz, sz = math.cos(hz), math.sin(hz)
    return (
        sx * cy * cz - cx * sy * sz,
        cx * sy * cz + sx * cy * sz,
        cx * cy * sz - sx * sy * cz,
        cx * cy * cz + sx * sy * sz,
    )


# ---------------------------------------------------------------------------
# Definisi rig
# ---------------------------------------------------------------------------
@dataclass
class Bone:
    name: str
    parent: str | None
    offset: tuple  # translasi lokal terhadap induk


@dataclass
class Part:
    """Sekotak geometri yang menempel kaku pada satu tulang."""

    size: tuple
    center: tuple
    color: tuple
    bone: str
    # Rotasi statis opsional (derajat, XYZ) di sekitar pusat kotak — untuk
    # bagian miring seperti laras senapan atau perisai yang dipegang serong.
    tilt: tuple = (0.0, 0.0, 0.0)


@dataclass
class Clip:
    """Satu klip animasi.

    `tracks` memetakan nama tulang → daftar (waktu, (rx, ry, rz)) dalam derajat.
    `root_motion` adalah kurva translasi opsional untuk tulang pertama (pinggul):
    daftar (waktu, (x, y, z)) sebagai offset terhadap posisi rest-nya.
    """

    name: str
    duration: float
    tracks: dict = field(default_factory=dict)
    root_motion: list = field(default_factory=list)
    loop: bool = True


class Rig:
    """Kumpulan tulang + bagian tubuh + klip, siap diekspor jadi GLB."""

    def __init__(self, name: str, bones: list[Bone]):
        self.name = name
        self.bones = bones
        self.index = {b.name: i for i, b in enumerate(bones)}
        self.parts: list[Part] = []
        self.clips: list[Clip] = []
        self.sockets: dict[str, tuple] = {}  # nama → posisi world (bind)
        self._global: dict[str, tuple] = {}
        for bone in bones:
            if bone.parent is None:
                self._global[bone.name] = bone.offset
            else:
                px, py, pz = self._global[bone.parent]
                ox, oy, oz = bone.offset
                self._global[bone.name] = (px + ox, py + oy, pz + oz)

    def bone_position(self, name: str) -> tuple:
        """Posisi tulang di ruang bind — dipakai saat menempatkan geometri."""
        return self._global[name]

    def add(self, bone: str, size: tuple, center: tuple, color: tuple, tilt=(0.0, 0.0, 0.0)):
        self.parts.append(Part(size, center, color, bone, tilt))
        return self

    def socket(self, name: str, position: tuple):
        """Titik tempel (mis. moncong senjata).

        Diekspor sebagai node kosong anak tulang, jadi renderer bisa membaca
        posisi dunianya tiap frame — itulah yang membuat kilatan moncong dan
        tracer tetap menempel di ujung laras saat lengan beranimasi, alih-alih
        ditebak dari posisi karakter.
        """
        self.sockets[name] = position
        return self

    def clip(self, clip: Clip):
        self.clips.append(clip)
        return self


# ---------------------------------------------------------------------------
# Geometri
# ---------------------------------------------------------------------------
def _rotate_point(p: tuple, tilt: tuple) -> tuple:
    """Rotasi XYZ dalam derajat, dipakai hanya untuk tilt statis part."""
    x, y, z = p
    rx, ry, rz = (math.radians(a) for a in tilt)
    # X
    y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
    # Y
    x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
    # Z
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    return (x, y, z)


_FACES = [
    # (normal, empat sudut dalam satuan setengah-ukuran)
    ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
    ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)]),
    ((1, 0, 0), [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)]),
    ((-1, 0, 0), [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)]),
    ((0, 1, 0), [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)]),
    ((0, -1, 0), [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
]


def _box_geometry(part: Part, joint: int, base: int):
    """Satu kotak → 24 vertex (normal datar) + 36 indeks."""
    hx, hy, hz = (s * 0.5 for s in part.size)
    cx, cy, cz = part.center
    positions, normals, colors, joints, weights, indices = [], [], [], [], [], []
    for normal, corners in _FACES:
        n = _rotate_point(normal, part.tilt) if any(part.tilt) else normal
        for sx, sy, sz in corners:
            local = (sx * hx, sy * hy, sz * hz)
            if any(part.tilt):
                local = _rotate_point(local, part.tilt)
            positions.append((cx + local[0], cy + local[1], cz + local[2]))
            normals.append(n)
            colors.append(part.color)
            joints.append((joint, 0, 0, 0))
            weights.append((1.0, 0.0, 0.0, 0.0))
        v = base + len(positions) - 4
        indices += [v, v + 1, v + 2, v, v + 2, v + 3]
    return positions, normals, colors, joints, weights, indices


# ---------------------------------------------------------------------------
# Penulis GLB
# ---------------------------------------------------------------------------
class _Buffer:
    def __init__(self):
        self.blob = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def _view(self, data: bytes, target: int | None = None) -> int:
        while len(self.blob) % 4:
            self.blob.append(0)
        offset = len(self.blob)
        self.blob += data
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        return len(self.views) - 1

    def accessor(self, values, kind: str, component: int, target=None, minmax=False) -> int:
        count = len(values)
        if component == FLOAT:
            flat = [c for v in values for c in (v if isinstance(v, (tuple, list)) else (v,))]
            data = struct.pack("<%df" % len(flat), *flat)
        elif component == UNSIGNED_BYTE:
            flat = [c for v in values for c in v]
            data = struct.pack("<%dB" % len(flat), *flat)
        elif component == UNSIGNED_SHORT:
            data = struct.pack("<%dH" % count, *values)
        else:
            raise ValueError(component)
        accessor = {
            "bufferView": self._view(data, target),
            "componentType": component,
            "count": count,
            "type": kind,
        }
        if component == UNSIGNED_BYTE and kind in ("VEC4",):
            accessor["normalized"] = False
        if minmax:
            if isinstance(values[0], (tuple, list)):
                dims = len(values[0])
                accessor["min"] = [min(v[i] for v in values) for i in range(dims)]
                accessor["max"] = [max(v[i] for v in values) for i in range(dims)]
            else:
                accessor["min"] = [min(values)]
                accessor["max"] = [max(values)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1


def export(rig: Rig, path: pathlib.Path) -> int:
    """Menulis rig jadi satu berkas .glb. Mengembalikan ukuran byte."""
    buf = _Buffer()

    # --- geometri ----------------------------------------------------------
    positions, normals, colors, joints, weights, indices = [], [], [], [], [], []
    for part in rig.parts:
        joint = rig.index[part.bone]
        p, n, c, j, w, idx = _box_geometry(part, joint, len(positions))
        positions += p
        normals += n
        colors += c
        joints += j
        weights += w
        indices += idx

    acc_pos = buf.accessor(positions, "VEC3", FLOAT, ARRAY_BUFFER, minmax=True)
    acc_nrm = buf.accessor(normals, "VEC3", FLOAT, ARRAY_BUFFER)
    acc_col = buf.accessor(colors, "VEC4", FLOAT, ARRAY_BUFFER)
    acc_jnt = buf.accessor(joints, "VEC4", UNSIGNED_BYTE, ARRAY_BUFFER)
    acc_wgt = buf.accessor(weights, "VEC4", FLOAT, ARRAY_BUFFER)
    acc_idx = buf.accessor(indices, "SCALAR", UNSIGNED_SHORT, ELEMENT_ARRAY_BUFFER)

    # --- inverse bind matrices --------------------------------------------
    # Rest pose hanya translasi, jadi inverse-nya cukup translasi negatif.
    # Kolom-major seperti yang diminta spesifikasi glTF.
    ibm = []
    for bone in rig.bones:
        gx, gy, gz = rig.bone_position(bone.name)
        ibm.append(
            (1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -gx, -gy, -gz, 1)
        )
    acc_ibm = buf.accessor(ibm, "MAT4", FLOAT)

    # --- node tulang -------------------------------------------------------
    nodes: list[dict] = []
    for bone in rig.bones:
        nodes.append({"name": bone.name, "translation": list(bone.offset)})
    for bone in rig.bones:
        if bone.parent is None:
            continue
        parent = nodes[rig.index[bone.parent]]
        parent.setdefault("children", []).append(rig.index[bone.name])

    # Soket: node kosong anak tulang terdekat, dipakai renderer untuk
    # menempelkan efek (moncong, tangan, dada).
    for name, (sx, sy, sz) in rig.sockets.items():
        bone_name = _nearest_bone(rig, (sx, sy, sz))
        bx, by, bz = rig.bone_position(bone_name)
        nodes.append({"name": name, "translation": [sx - bx, sy - by, sz - bz]})
        nodes[rig.index[bone_name]].setdefault("children", []).append(len(nodes) - 1)

    mesh_node = len(nodes)
    nodes.append({"name": rig.name, "mesh": 0, "skin": 0})

    # --- animasi -----------------------------------------------------------
    animations = []
    for clip in rig.clips:
        samplers, channels = [], []
        for bone_name, keys in clip.tracks.items():
            times = [t for t, _ in keys]
            quats = [euler_to_quat(*rot) for _, rot in keys]
            samplers.append(
                {
                    "input": buf.accessor(times, "SCALAR", FLOAT, minmax=True),
                    "output": buf.accessor(quats, "VEC4", FLOAT),
                    "interpolation": "LINEAR",
                }
            )
            channels.append(
                {
                    "sampler": len(samplers) - 1,
                    "target": {"node": rig.index[bone_name], "path": "rotation"},
                }
            )
        if clip.root_motion:
            root = rig.bones[0]
            times = [t for t, _ in clip.root_motion]
            moves = [
                (root.offset[0] + d[0], root.offset[1] + d[1], root.offset[2] + d[2])
                for _, d in clip.root_motion
            ]
            samplers.append(
                {
                    "input": buf.accessor(times, "SCALAR", FLOAT, minmax=True),
                    "output": buf.accessor(moves, "VEC3", FLOAT),
                    "interpolation": "LINEAR",
                }
            )
            channels.append(
                {
                    "sampler": len(samplers) - 1,
                    "target": {"node": 0, "path": "translation"},
                }
            )
        animations.append({"name": clip.name, "samplers": samplers, "channels": channels})

    gltf = {
        "asset": {"version": "2.0", "generator": "chain-rider rigkit"},
        "scene": 0,
        "scenes": [{"nodes": [0, mesh_node]}],
        "nodes": nodes,
        "meshes": [
            {
                "name": rig.name,
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": acc_pos,
                            "NORMAL": acc_nrm,
                            "COLOR_0": acc_col,
                            "JOINTS_0": acc_jnt,
                            "WEIGHTS_0": acc_wgt,
                        },
                        "indices": acc_idx,
                        "material": 0,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": "character",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [1, 1, 1, 1],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.85,
                },
            }
        ],
        "skins": [
            {
                "inverseBindMatrices": acc_ibm,
                "joints": list(range(len(rig.bones))),
                "skeleton": 0,
            }
        ],
        "bufferViews": buf.views,
        "accessors": buf.accessors,
        "buffers": [{"byteLength": len(buf.blob)}],
    }
    if animations:
        gltf["animations"] = animations

    blob = bytes(buf.blob)
    json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * (-len(json_chunk) % 4)
    bin_chunk = blob + b"\x00" * (-len(blob) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk
    out += struct.pack("<II", len(bin_chunk), 0x004E4942) + bin_chunk
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)
    return len(out)


def _nearest_bone(rig: Rig, point: tuple) -> str:
    best, best_d = rig.bones[0].name, 1e9
    for bone in rig.bones:
        bx, by, bz = rig.bone_position(bone.name)
        d = (bx - point[0]) ** 2 + (by - point[1]) ** 2 + (bz - point[2]) ** 2
        if d < best_d:
            best, best_d = bone.name, d
    return best

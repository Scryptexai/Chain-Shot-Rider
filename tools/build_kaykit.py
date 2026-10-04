#!/usr/bin/env python3
"""Membangun karakter game dari pack KayKit Adventurers 2.0 FREE (CC0).

    python3 tools/build_kaykit.py            # bangun semua peran
    python3 tools/build_kaykit.py grunt boss # bangun sebagian

Masukan  : KayKit_Adventurers_2.0_FREE.zip di akar repo (diekstrak otomatis
           ke assets/models/kaykit/ saat pertama kali dijalankan).
Keluaran : assets/models/rigged/<peran>.glb — menimpa model prosedural lama,
           dengan kontrak yang sama persis supaya loader web dan Godot tidak
           perlu diubah sama sekali:

           · satu primitif, satu material (draw call per aktor tetap satu),
           · tulang bernama `muzzle` di ujung senjata tangan kanan,
           · klip `idle`, `run`, `shoot`, `hit`, `die`,
           · tinggi model sama dengan model lama (CHAR_SCALE 2.0 tetap benar).

Empat hal yang dikerjakan skrip ini, dan kenapa:

1. GABUNG PRIMITIF. Karakter KayKit dipecah per bagian tubuh (7–9 mesh node).
   Dipakai apa adanya, 26 aktor ber-skeleton = ±208 draw call, jauh di atas
   anggaran 45 di docs/08. Semua bagian memakai satu material, jadi aman
   digabung jadi satu primitif: 26 aktor = 26 draw call.

2. TEKSTUR ASLI IKUT, TIDAK DIGANTI APA PUN. UV dan atlas PNG milik KayKit
   disalin apa adanya ke dalam GLB keluaran, jadi wajah, mata, emblem, dan
   gradien bayangan buatan pembuat aslinya tetap utuh piksel demi piksel.

   Percobaan sebelumnya memanggang atlas jadi vertex color demi menghemat
   pengikatan tekstur. Itu memang menghemat, tapi detail halus (garis mata,
   tepi emblem, gradien pada satu permukaan) hilang karena satu verteks hanya
   bisa menyimpan satu warna. Atlasnya cuma 12–15 KB dan lima karakter berbagi
   lima atlas; harga teksturnya jauh lebih murah daripada harga detail yang
   hilang.

3. TEMPEL SENJATA SEBAGAI VERTEX TER-SKIN. Rig KayKit punya tulang khusus
   `handslot.l`/`handslot.r` tempat senjata duduk pada transform identitas.
   Verteks senjata dipindah ke ruang mesh lewat matriks bind tulang itu lalu
   diberi bobot penuh ke tulangnya, sehingga pedang ikut terayun tanpa
   menambah node, mesh, atau draw call.

4. SALIN ANIMASI LINTAS FILE. Klip tinggal di dua GLB terpisah yang memakai
   rig sama tapi urutan node berbeda, jadi kanal dipetakan ulang lewat NAMA
   tulang. Kanal yang nilainya tetap (kebanyakan trek skala dan translasi)
   dibuang: hemat ±60% ukuran animasi tanpa mengubah gerak.
"""

import json
import math
import os
import shutil
import struct
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gltfkit import (  # noqa: E402
    Doc, Writer, mat_invert, mat_mul, mat_from_trs, normalized,
    xform_dir, xform_point,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZIP = os.path.join(ROOT, "KayKit_Adventurers_2.0_FREE.zip")
PACK = os.path.join(ROOT, "assets", "models", "kaykit")
OUT = os.path.join(ROOT, "assets", "models", "rigged")

FLOAT, UBYTE, USHORT, UINT = 5126, 5121, 5123, 5125
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963

# Berkas yang disalin keluar dari zip. Sisanya (fbx, obj, sampel render)
# tidak dipakai pipeline, jadi tidak ikut diekstrak.
WANTED = [
    "Characters/gltf/Barbarian.glb",
    "Characters/gltf/Knight.glb",
    "Characters/gltf/Mage.glb",
    "Characters/gltf/Ranger.glb",
    "Characters/gltf/Rogue.glb",
    "Characters/gltf/Rogue_Hooded.glb",
    "Animations/gltf/Rig_Medium/Rig_Medium_General.glb",
    "Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb",
    "License.txt",
]
WANTED_DIRS = ["Assets/gltf"]

# Peran game -> resep. `height` mengikuti tinggi model prosedural yang
# digantikan, supaya kamera, kotak tabrakan, dan CHAR_SCALE tidak bergeser.
# `tint` mengalikan warna hasil panggangan: pasukan pemain condong ke biru
# terang, musuh ke merah/ungu, supaya kawan dan lawan tetap terbaca sekejap
# mata meski keduanya memakai gaya visual yang sama.
RECIPES = {
    "trooper": {
        "char": "Knight", "height": 0.96,
        "right": "sword_1handed", "left": "shield_round_color",
        "shoot": "Throw",
    },
    "grunt": {
        "char": "Rogue", "height": 0.96,
        "right": "dagger", "left": None,
        "shoot": "Throw",
    },
    "runner": {
        "char": "Ranger", "height": 0.883,
        "right": "bow_withString", "left": None,
        "right_rot": (0.70710678, 0.0, 0.0, 0.70710678),
        "shoot": "Throw",
    },
    "brute": {
        "char": "Barbarian", "height": 1.392,
        "right": "axe_2handed", "left": None,
        "shoot": "Throw",
    },
    "splitter": {
        "char": "Mage", "height": 0.96,
        "right": "staff", "left": "spellbook_closed",
        "shoot": "Use_Item",
    },
    "bomber": {
        "char": "Rogue_Hooded", "height": 0.941,
        "right": "smokebomb", "left": None,
        "shoot": "Throw",
    },
    "shielder": {
        "char": "Knight", "height": 1.008,
        "right": "sword_1handed", "left": "shield_square_color",
        "shoot": "Throw",
    },
    "boss": {
        "char": "Knight", "height": 2.016,
        "right": "sword_2handed_color", "left": None,
        "shoot": "Throw",
    },
}

# Peran -> berkas model statis LOD jauh. Jalur MultiMesh menggambar puluhan
# musuh yang jauh dengan satu panggilan; model itu harus bergaya sama dengan
# aktor ber-tulang di dekat kamera, kalau tidak gaya visualnya patah persis di
# garis pergantian LOD.
STATIC = {
    "trooper": "soldier.glb",
    "grunt": "enemy_grunt.glb",
    "runner": "enemy_runner.glb",
    "brute": "enemy_brute.glb",
    "splitter": "enemy_splitter.glb",
    "bomber": "enemy_bomber.glb",
    "shielder": "enemy_shielder.glb",
    "boss": "boss.glb",
}

# Ukuran sel pengelompokan verteks untuk model statis, sebagai pecahan tinggi
# karakter. Semakin besar semakin sedikit segitiga dan semakin kasar bentuknya;
# 1/26 menahan siluet (kepala, perisai, senjata masih terbaca) di ±3.000 segitiga — cukup ringan untuk kerumunan jauh tanpa mencincang bentuknya.
CLUSTER = 1.0 / 26.0

# Nama klip di pack -> nama klip yang dipakai kode game. `shoot` berbeda per
# peran (tier gratis tidak punya animasi serang, `Throw` dan `Use_Item` adalah
# padanan terdekat untuk ayunan dan rapalan).
CLIPS = [("idle", "Idle_A"), ("run", "Running_A"), ("shoot", None),
         ("hit", "Hit_A"), ("die", "Death_A")]

HAND_R, HAND_L = "handslot_r", "handslot_l"


# --------------------------------------------------------------- ekstraksi ---

def ensure_pack():
    """Menyalin subset yang dipakai keluar dari zip sumber (sekali saja)."""
    if os.path.isdir(PACK) and os.path.exists(os.path.join(PACK, "License.txt")):
        return
    if not os.path.exists(ZIP):
        sys.exit("zip pack tidak ditemukan: %s" % ZIP)
    os.makedirs(PACK, exist_ok=True)
    with zipfile.ZipFile(ZIP) as zf:
        names = zf.namelist()
        prefix = ""
        for n in names:
            if n.endswith("License.txt"):
                prefix = n[:-len("License.txt")]
                break
        picked = [prefix + w for w in WANTED]
        picked += [n for n in names
                   if any(d in n for d in WANTED_DIRS) and not n.endswith("/")]
        for name in picked:
            if name not in names:
                continue
            rel = name[len(prefix):]
            dest = os.path.join(PACK, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with zf.open(name) as src, open(dest, "wb") as dst:
                shutil.copyfileobj(src, dst)
    print("pack diekstrak ke %s" % os.path.relpath(PACK, ROOT))


# ------------------------------------------------------------------ geometri ---

class Mesh:
    """Kantong atribut yang terus ditumpuk sampai jadi satu primitif."""

    def __init__(self):
        self.pos, self.nrm, self.uv = [], [], []
        self.jnt, self.wgt, self.idx = [], [], []

    def add(self, pos, nrm, uv, jnt, wgt, tris):
        base = len(self.pos)
        self.pos.extend(pos)
        self.nrm.extend(nrm)
        self.uv.extend(uv)
        self.jnt.extend(jnt)
        self.wgt.extend(wgt)
        self.idx.extend(i + base for i in tris)

    def bounds(self):
        lo = [min(p[i] for p in self.pos) for i in range(3)]
        hi = [max(p[i] for p in self.pos) for i in range(3)]
        return lo, hi


def take_character(doc, mesh, joint_remap):
    """Menumpuk semua bagian tubuh ke satu mesh, lengkap dengan bobot kulit."""
    g = doc.gltf
    for node in g["nodes"]:
        if "mesh" not in node:
            continue
        for prim in g["meshes"][node["mesh"]]["primitives"]:
            attrs = prim["attributes"]
            pos = doc.accessor(attrs["POSITION"])
            nrm = doc.accessor(attrs["NORMAL"])
            uvs = doc.accessor(attrs["TEXCOORD_0"])
            jnt = doc.accessor(attrs["JOINTS_0"])
            wgt = doc.accessor(attrs["WEIGHTS_0"])
            tris = doc.accessor(prim["indices"])
            jnt = [tuple(joint_remap[j] for j in quad) for quad in jnt]
            mesh.add(pos, nrm, uvs, jnt, [tuple(w) for w in wgt], tris)


def take_weapon(path, mesh, bind, joint, atlas_png, extra=None):
    """Menempel satu aset senjata ke tulang `joint` (bobot penuh, satu tulang).

    `bind` adalah matriks bind global tulang itu: verteks senjata dipindahkan
    ke ruang mesh dengan matriks tersebut, jadi saat skinning dihitung ulang
    oleh shader, senjata persis mendarat di telapak tangan.
    """
    doc = Doc.load(path)
    g = doc.gltf
    # Satu aktor = satu material = satu draw call. Itu hanya benar kalau
    # senjatanya memakai atlas yang sama dengan karakternya, jadi resep yang
    # memasangkan knight dengan kapak barbarian harus gagal di sini, bukan
    # diam-diam menambah material kedua.
    if doc.image_bytes(0) != atlas_png:
        raise SystemExit("atlas senjata != atlas karakter: %s" % path)
    # Beberapa aset tidak berdiri di sumbu yang sama dengan pegangan tangan
    # (busur membentang di sumbu Z, bukan Y), jadi resep boleh memutarnya.
    adjust = mat_from_trs((0.0, 0.0, 0.0), extra or (0.0, 0.0, 0.0, 1.0),
                          (1.0, 1.0, 1.0))
    top = 0.0
    for i, node in enumerate(g["nodes"]):
        if "mesh" not in node:
            continue
        local = mat_mul(adjust, doc.global_matrix(i))
        world = mat_mul(bind, local)
        for prim in g["meshes"][node["mesh"]]["primitives"]:
            attrs = prim["attributes"]
            raw_pos = doc.accessor(attrs["POSITION"])
            raw_nrm = doc.accessor(attrs["NORMAL"])
            uvs = doc.accessor(attrs["TEXCOORD_0"])
            tris = doc.accessor(prim["indices"])
            pos = [xform_point(world, p) for p in raw_pos]
            nrm = [normalized(xform_dir(world, n)) for n in raw_nrm]
            jnt = [(joint, 0, 0, 0)] * len(pos)
            wgt = [(1.0, 0.0, 0.0, 0.0)] * len(pos)
            mesh.add(pos, nrm, uvs, jnt, wgt, tris)
            top = max(top, max(xform_point(local, p)[1] for p in raw_pos))
    return top


# --------------------------------------------------------- pose & desimasi ---

def sample_pose(src, clip_name, t, rest, scale):
    """TRS tiap tulang pada detik `t` dari satu klip, hasil interpolasi linier."""
    anim = None
    for candidate in src.gltf.get("animations", []):
        if candidate.get("name") == clip_name:
            anim = candidate
            break
    pose = {n: {"translation": list(v["translation"]),
                "rotation": list(v["rotation"]),
                "scale": list(v["scale"])} for n, v in rest.items()}
    if anim is None:
        return pose
    for ch in anim["channels"]:
        target = ch["target"]
        name = src.gltf["nodes"][target["node"]].get("name", "").replace(".", "_")
        if name not in pose:
            continue
        sampler = anim["samplers"][ch["sampler"]]
        times = src.accessor(sampler["input"])
        values = src.accessor(sampler["output"])
        i = 0
        while i + 1 < len(times) and times[i + 1] < t:
            i += 1
        j = min(i + 1, len(times) - 1)
        span = times[j] - times[i]
        f = 0.0 if span <= 0 else max(min((t - times[i]) / span, 1.0), 0.0)
        a, b = values[i], values[j]
        mix = [a[k] + (b[k] - a[k]) * f for k in range(len(a))]
        if target["path"] == "rotation":
            n = math.sqrt(sum(v * v for v in mix)) or 1.0
            pose[name]["rotation"] = [v / n for v in mix]
        elif target["path"] == "translation":
            # Klip memakai satuan pack; tulang keluaran sudah dikecilkan, jadi
            # translasinya ikut dikecilkan di sini.
            pose[name]["translation"] = [v * scale for v in mix]
        else:
            pose[name]["scale"] = mix
    return pose


def skin_to_static(nodes, parent_of, ibms, pose, mesh, positions):
    """Membekukan satu pose: skinning dihitung sekali di sini, bukan tiap frame."""
    name_index = {n["name"]: i for i, n in enumerate(nodes) if "name" in n}
    local = []
    for i, node in enumerate(nodes):
        p = pose.get(node.get("name"))
        if p is None:
            local.append(mat_from_trs(node.get("translation", [0, 0, 0]),
                                      node.get("rotation", [0, 0, 0, 1]),
                                      node.get("scale", [1, 1, 1])))
        else:
            local.append(mat_from_trs(p["translation"], p["rotation"], p["scale"]))
    globals_ = [None] * len(nodes)

    def resolve(i):
        if globals_[i] is None:
            parent = parent_of.get(i)
            globals_[i] = local[i] if parent is None else mat_mul(resolve(parent), local[i])
        return globals_[i]

    skin = [mat_mul(resolve(i), ibms[i]) for i in range(len(ibms))]
    out_pos, out_nrm = [], []
    for v in range(len(positions)):
        px, py, pz = positions[v]
        nx, ny, nz = mesh.nrm[v]
        ax = ay = az = 0.0
        bx = by = bz = 0.0
        for k in range(4):
            w = mesh.wgt[v][k]
            if w <= 0.0:
                continue
            m = skin[mesh.jnt[v][k]]
            qx, qy, qz = xform_point(m, (px, py, pz))
            rx, ry, rz = xform_dir(m, (nx, ny, nz))
            ax += qx * w
            ay += qy * w
            az += qz * w
            bx += rx * w
            by += ry * w
            bz += rz * w
        out_pos.append((ax, ay, az))
        out_nrm.append(normalized((bx, by, bz)))
    return out_pos, out_nrm


def decimate(pos, nrm, uv, tris, cell, uv_steps=24):
    """Pengelompokan verteks berbasis kisi: cepat, tanpa pustaka, dan cukup.

    Verteks yang jatuh di sel kubus yang sama dilebur jadi satu titik rata-rata;
    segitiga yang kehilangan dua sudutnya dibuang.

    Satu tambahan penting: petak UV ikut masuk ke kunci sel. Tanpa itu dua
    bagian yang bersebelahan tapi mengambil warna dari petak atlas berbeda
    (kulit dan tudung, baja dan kulit sarung) dilebur jadi satu verteks, dan
    UV rata-ratanya mendarat di petak ketiga yang warnanya tidak ada
    hubungannya. Dengan UV sebagai pemisah, batas antar bahan tetap jadi tepi
    geometri dan warnanya tidak pernah meleset.
    """
    bucket, remap = {}, []
    for i, p in enumerate(pos):
        patch = (int(uv[i][0] * uv_steps), int(uv[i][1] * uv_steps))
        key = (round(p[0] / cell), round(p[1] / cell), round(p[2] / cell), patch)
        if key not in bucket:
            bucket[key] = [len(bucket), [0.0, 0.0, 0.0], [0.0, 0.0, 0.0],
                           [0.0, 0.0], 0]
        slot = bucket[key]
        for k in range(3):
            slot[1][k] += p[k]
            slot[2][k] += nrm[i][k]
        slot[3][0] += uv[i][0]
        slot[3][1] += uv[i][1]
        slot[4] += 1
        remap.append(slot[0])
    merged = sorted(bucket.values(), key=lambda s: s[0])
    out_pos = [tuple(v / s[4] for v in s[1]) for s in merged]
    out_nrm = [normalized(tuple(v / s[4] for v in s[2])) for s in merged]
    out_uv = [(s[3][0] / s[4], s[3][1] / s[4]) for s in merged]
    out_tris = []
    for t in range(0, len(tris), 3):
        a, b, c = (remap[tris[t]], remap[tris[t + 1]], remap[tris[t + 2]])
        if a != b and b != c and a != c:
            out_tris.extend((a, b, c))
    return out_pos, out_nrm, out_uv, out_tris


def texture_block(writer, png, name):
    """Menanam PNG atlas ke dalam GLB dan merakit material yang memakainya."""
    view = writer.raw_view(png)
    return {
        "images": [{"name": name, "mimeType": "image/png", "bufferView": view}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987,
                      "wrapS": 33071, "wrapT": 33071}],
        "textures": [{"sampler": 0, "source": 0}],
        "materials": [{"name": name, "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0},
            "baseColorFactor": [1, 1, 1, 1],
            "metallicFactor": 0.0, "roughnessFactor": 0.85}}],
    }


def write_static(path, name, pos, nrm, uv, tris, png):
    writer = Writer()
    acc_pos = writer.add(pos, "VEC3", FLOAT, ARRAY_BUFFER, minmax=True)
    acc_nrm = writer.add(nrm, "VEC3", FLOAT, ARRAY_BUFFER)
    acc_uv = writer.add(uv, "VEC2", FLOAT, ARRAY_BUFFER)
    comp = USHORT if len(pos) <= 65535 else UINT
    acc_idx = writer.add(tris, "SCALAR", comp, ELEMENT_ARRAY_BUFFER)
    gltf = {
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": acc_pos, "NORMAL": acc_nrm,
                           "TEXCOORD_0": acc_uv},
            "indices": acc_idx, "material": 0,
        }]}],
    }
    gltf.update(texture_block(writer, png, name))
    with open(path, "wb") as f:
        f.write(writer.build(gltf))


# ------------------------------------------------------------------- animasi ---

def constant(values, rest, eps=1e-4):
    """True kalau semua keyframe sama dan sama dengan nilai rest tulang."""
    first = values[0]
    for v in values:
        if any(abs(a - b) > eps for a, b in zip(v, first)):
            return False
    return all(abs(a - b) <= eps for a, b in zip(first, rest))


def copy_clip(src, name, out_name, name_to_node, rest, scale, writer):
    """Menyalin satu klip, memetakan kanal lewat nama tulang."""
    anim = None
    for candidate in src.gltf.get("animations", []):
        if candidate.get("name") == name:
            anim = candidate
            break
    if anim is None:
        return None
    samplers, channels = [], []
    for ch in anim["channels"]:
        target = ch["target"]
        node_name = src.gltf["nodes"][target["node"]].get("name")
        if node_name not in name_to_node:
            continue
        path = target["path"]
        sampler = anim["samplers"][ch["sampler"]]
        times = src.accessor(sampler["input"])
        values = src.accessor(sampler["output"])
        node = rest[node_name.replace(".", "_")]
        if path == "translation":
            values = [(v[0] * scale, v[1] * scale, v[2] * scale) for v in values]
            default = node["translation"]
        elif path == "rotation":
            default = node["rotation"]
        else:
            default = node["scale"]
        if constant(values, default):
            continue
        kind = "VEC4" if path == "rotation" else "VEC3"
        samplers.append({
            "input": writer.add(list(times), "SCALAR", FLOAT, minmax=True),
            "output": writer.add(values, kind, FLOAT),
            "interpolation": sampler.get("interpolation", "LINEAR"),
        })
        channels.append({
            "sampler": len(samplers) - 1,
            "target": {"node": name_to_node[node_name], "path": path},
        })
    if not channels:
        return None
    return {"name": out_name, "samplers": samplers, "channels": channels}


# -------------------------------------------------------------------- bangun ---

def build(role, spec):
    char_path = os.path.join(PACK, "Characters", "gltf", spec["char"] + ".glb")
    doc = Doc.load(char_path)
    g = doc.gltf
    skin = g["skins"][0]
    joints = skin["joints"]
    # Titik di nama tulang ("hand.r") dibuang: three.js menyanitasi nama node
    # saat memuat glTF, jadi nama ber-titik berubah diam-diam di sisi web dan
    # pencarian tulang antar build jadi tidak sama. Underscore aman di mana pun.
    names = [g["nodes"][j].get("name").replace(".", "_") for j in joints]
    joint_remap = {node: i for i, node in enumerate(joints)}
    by_name = {n: i for i, n in enumerate(names)}

    # Matriks bind dipakai untuk menempel senjata; diambil dari hierarki
    # langsung, bukan dari inverseBindMatrices, supaya tidak bergantung pada
    # eksportir yang menulis keduanya konsisten.
    bind = {n: doc.global_matrix(joints[i]) for n, i in by_name.items()}

    atlas_png = doc.image_bytes(0)
    mesh = Mesh()
    take_character(doc, mesh, joint_remap)
    lo, hi = mesh.bounds()
    body_height = hi[1] - lo[1]
    scale = spec["height"] / body_height

    tip = 0.0
    for slot, bone in (("right", HAND_R), ("left", HAND_L)):
        asset = spec.get(slot)
        if not asset:
            continue
        path = os.path.join(PACK, "Assets", "gltf", asset + ".gltf")
        reach = take_weapon(path, mesh, bind[bone], by_name[bone], atlas_png,
                            spec.get(slot + "_rot"))
        if slot == "right":
            tip = reach

    # Semua ukuran dikecilkan di sini, bukan lewat node pembungkus berskala:
    # Godot mengimpor skala node ke dalam Skeleton3D dengan cara yang mudah
    # hilang saat aktor dipakai ulang dari pool.
    pos = [(p[0] * scale, p[1] * scale, p[2] * scale) for p in mesh.pos]
    floor = min(p[1] for p in pos)
    pos = [(p[0], p[1] - floor, p[2]) for p in pos]

    # --- node tulang -------------------------------------------------------
    rest, nodes = {}, []
    for i, node_index in enumerate(joints):
        src = g["nodes"][node_index]
        t = [v * scale for v in src.get("translation", [0.0, 0.0, 0.0])]
        t[1] -= floor if i == 0 else 0.0
        r = list(src.get("rotation", [0.0, 0.0, 0.0, 1.0]))
        s = list(src.get("scale", [1.0, 1.0, 1.0]))
        entry = {"name": names[i], "translation": t, "rotation": r, "scale": s}
        children = [joint_remap[c] for c in src.get("children", []) if c in joint_remap]
        if children:
            entry["children"] = children
        nodes.append(entry)
        rest[names[i]] = {"translation": t, "rotation": r, "scale": s}

    # Tulang moncong: ujung senjata tangan kanan, tempat kilatan tembakan
    # dipasang oleh kedua build.
    muzzle_index = len(nodes)
    nodes.append({
        "name": "muzzle",
        "translation": [0.0, max(tip * scale * 0.92, 0.1), 0.0],
        "rotation": [0.0, 0.0, 0.0, 1.0], "scale": [1.0, 1.0, 1.0],
    })
    nodes[by_name[HAND_R]].setdefault("children", []).append(muzzle_index)

    # --- inverse bind ------------------------------------------------------
    def global_of(index):
        m = mat_from_trs(nodes[index]["translation"], nodes[index]["rotation"],
                         nodes[index]["scale"])
        parent = parent_of.get(index)
        while parent is not None:
            p = nodes[parent]
            m = mat_mul(mat_from_trs(p["translation"], p["rotation"], p["scale"]), m)
            parent = parent_of.get(parent)
        return m

    parent_of = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            parent_of[child] = i
    ibms = [mat_invert(global_of(i)) for i in range(len(nodes))]

    # --- model statis LOD jauh ---------------------------------------------
    # Dipanggang pada pose siaga, bukan bind pose: kerumunan jauh yang berdiri
    # dengan tangan terentang seperti orang-orangan sawah langsung terlihat.
    pose = sample_pose(ANIM["general"], "Idle_A", 0.0, rest, scale)
    static_pos, static_nrm = skin_to_static(nodes, parent_of, ibms, pose, mesh, pos)
    ground = min(p[1] for p in static_pos)
    static_pos = [(p[0], p[1] - ground, p[2]) for p in static_pos]
    far_pos, far_nrm, far_uv, far_tris = decimate(
        static_pos, static_nrm, mesh.uv, mesh.idx, spec["height"] * CLUSTER)
    write_static(os.path.join(ROOT, "assets", "models", STATIC[role]), role,
                 far_pos, far_nrm, far_uv, far_tris, atlas_png)

    # --- tulis -------------------------------------------------------------
    writer = Writer()
    acc_pos = writer.add(pos, "VEC3", FLOAT, ARRAY_BUFFER, minmax=True)
    acc_nrm = writer.add(mesh.nrm, "VEC3", FLOAT, ARRAY_BUFFER)
    acc_uv = writer.add(mesh.uv, "VEC2", FLOAT, ARRAY_BUFFER)
    acc_jnt = writer.add(mesh.jnt, "VEC4", UBYTE, ARRAY_BUFFER)
    acc_wgt = writer.add(mesh.wgt, "VEC4", FLOAT, ARRAY_BUFFER)
    comp = USHORT if len(pos) <= 65535 else UINT
    acc_idx = writer.add(mesh.idx, "SCALAR", comp, ELEMENT_ARRAY_BUFFER)
    acc_ibm = writer.add(ibms, "MAT4", FLOAT)

    # Peta dari nama di file sumber (ber-titik) ke indeks node keluaran.
    name_to_node = {n.replace("_", "."): i for i, n in enumerate(names)}
    name_to_node.update({n: i for i, n in enumerate(names)})
    animations = []
    for out_name, src_name in CLIPS:
        src_name = src_name or spec["shoot"]
        for src_doc in (ANIM["general"], ANIM["movement"]):
            clip = copy_clip(src_doc, src_name, out_name, name_to_node, rest,
                             scale, writer)
            if clip:
                animations.append(clip)
                break
        else:
            print("  ! klip %s (%s) tidak ditemukan" % (out_name, src_name))

    mesh_node = len(nodes)
    nodes.append({"name": role, "mesh": 0, "skin": 0})

    gltf = {
        "scene": 0,
        "scenes": [{"nodes": [0, mesh_node]}],
        "nodes": nodes,
        "meshes": [{
            "name": role,
            "primitives": [{
                "attributes": {
                    "POSITION": acc_pos, "NORMAL": acc_nrm, "TEXCOORD_0": acc_uv,
                    "JOINTS_0": acc_jnt, "WEIGHTS_0": acc_wgt,
                },
                "indices": acc_idx,
                "material": 0,
            }],
        }],
        "skins": [{
            "inverseBindMatrices": acc_ibm,
            "joints": list(range(len(nodes) - 1)),
            "skeleton": 0,
        }],
        "animations": animations,
    }
    gltf.update(texture_block(writer, atlas_png, spec["char"].lower()))
    blob = writer.build(gltf)
    out_path = os.path.join(OUT, role + ".glb")
    with open(out_path, "wb") as f:
        f.write(blob)
    print("  %-9s %-13s tris %5d  klip %d  %6.1f KB  tinggi %.3f   LOD jauh "
          "%4d tris (%s)"
          % (role, spec["char"], len(mesh.idx) // 3, len(animations),
             len(blob) / 1024.0, max(p[1] for p in pos), len(far_tris) // 3,
             STATIC[role]))


ANIM = {}


def main(argv):
    ensure_pack()
    anim_dir = os.path.join(PACK, "Animations", "gltf", "Rig_Medium")
    ANIM["general"] = Doc.load(os.path.join(anim_dir, "Rig_Medium_General.glb"))
    ANIM["movement"] = Doc.load(os.path.join(anim_dir, "Rig_Medium_MovementBasic.glb"))
    roles = argv or list(RECIPES)
    os.makedirs(OUT, exist_ok=True)
    for role in roles:
        if role not in RECIPES:
            sys.exit("peran tidak dikenal: %s" % role)
        build(role, RECIPES[role])


if __name__ == "__main__":
    main(sys.argv[1:])

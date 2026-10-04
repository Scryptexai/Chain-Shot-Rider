"""Pembaca/penulis glTF seadanya, tanpa dependensi di luar pustaka standar.

Dipakai `tools/build_kaykit.py` untuk mengubah pack KayKit Adventurers (CC0)
menjadi karakter siap pakai: banyak primitif digabung jadi satu, senjata
ditempel ke tulang tangan, klip animasi disalin dari rig terpisah, dan warna
atlas dipanggang jadi vertex color supaya kedua build tidak perlu mengikat
tekstur sama sekali.

Alasan menulis sendiri alih-alih memakai pygltflib: paket pip tidak ikut
tersimpan di workspace, jadi pipeline yang bergantung padanya akan mati sunyi
di mesin lain. Lihat juga `tools/rigkit.py` yang memakai pendekatan sama untuk
model prosedural.
"""

import base64
import json
import math
import os
import struct
import zlib

# ---------------------------------------------------------------- matriks ---
# Semua matriks 4x4 disimpan sebagai list 16 float column-major, persis seperti
# urutan di file glTF, supaya tidak ada transpose tersembunyi di jalur data.

IDENTITY = [1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0]


def mat_mul(a, b):
    """a * b dengan konvensi column-major (b dipakai lebih dulu ke vektor)."""
    out = [0.0] * 16
    for col in range(4):
        for row in range(4):
            out[col * 4 + row] = (
                a[row] * b[col * 4]
                + a[4 + row] * b[col * 4 + 1]
                + a[8 + row] * b[col * 4 + 2]
                + a[12 + row] * b[col * 4 + 3]
            )
    return out


def mat_from_trs(t, r, s):
    x, y, z, w = r
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    sx, sy, sz = s
    return [
        (1 - 2 * (yy + zz)) * sx, (2 * (xy + wz)) * sx, (2 * (xz - wy)) * sx, 0.0,
        (2 * (xy - wz)) * sy, (1 - 2 * (xx + zz)) * sy, (2 * (yz + wx)) * sy, 0.0,
        (2 * (xz + wy)) * sz, (2 * (yz - wx)) * sz, (1 - 2 * (xx + yy)) * sz, 0.0,
        t[0], t[1], t[2], 1.0,
    ]


def mat_invert(m):
    """Invers umum 4x4 lewat eliminasi Gauss-Jordan.

    Cukup cepat untuk puluhan tulang dan tidak mengasumsikan skala seragam,
    yang penting karena beberapa tulang KayKit punya skala 0.9999998.
    """
    a = [[m[c * 4 + r] for c in range(4)] + [1.0 if i == r else 0.0 for i in range(4)]
         for r in range(4)]
    for col in range(4):
        pivot = max(range(col, 4), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) < 1e-12:
            raise ValueError("matriks singular")
        a[col], a[pivot] = a[pivot], a[col]
        div = a[col][col]
        a[col] = [v / div for v in a[col]]
        for row in range(4):
            if row == col:
                continue
            factor = a[row][col]
            if factor == 0.0:
                continue
            a[row] = [v - factor * w for v, w in zip(a[row], a[col])]
    return [a[r][4 + c] for c in range(4) for r in range(4)]


def xform_point(m, p):
    x, y, z = p
    return (
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    )


def xform_dir(m, v):
    x, y, z = v
    return (
        m[0] * x + m[4] * y + m[8] * z,
        m[1] * x + m[5] * y + m[9] * z,
        m[2] * x + m[6] * y + m[10] * z,
    )


def normalized(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if n < 1e-9:
        return (0.0, 1.0, 0.0)
    return (v[0] / n, v[1] / n, v[2] / n)


# ------------------------------------------------------------------ baca ----

_COMP = {
    5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
    5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4),
}
_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Doc:
    """Satu file glTF/GLB beserta buffer binernya."""

    def __init__(self, gltf, buffers, base_dir):
        self.gltf = gltf
        self.buffers = buffers
        self.base_dir = base_dir
        self._parent = None

    # -- muat ---------------------------------------------------------------
    @staticmethod
    def load(path):
        base_dir = os.path.dirname(os.path.abspath(path))
        raw = open(path, "rb").read()
        if raw[:4] == b"glTF":
            gltf, blob = _split_glb(raw)
            buffers = [blob]
        else:
            gltf = json.loads(raw.decode("utf-8"))
            buffers = []
        for i, buf in enumerate(gltf.get("buffers", [])):
            if i < len(buffers) and buffers[i] is not None:
                continue
            uri = buf.get("uri", "")
            if uri.startswith("data:"):
                data = base64.b64decode(uri.split(",", 1)[1])
            else:
                data = open(os.path.join(base_dir, uri), "rb").read()
            while len(buffers) <= i:
                buffers.append(None)
            buffers[i] = data
        return Doc(gltf, buffers, base_dir)

    # -- akses --------------------------------------------------------------
    def accessor(self, index):
        """Mengembalikan list tuple (atau list skalar untuk SCALAR)."""
        acc = self.gltf["accessors"][index]
        fmt, size = _COMP[acc["componentType"]]
        n = _COUNT[acc["type"]]
        count = acc["count"]
        if "bufferView" not in acc:
            return [tuple([0] * n) if n > 1 else 0 for _ in range(count)]
        view = self.gltf["bufferViews"][acc["bufferView"]]
        data = self.buffers[view.get("buffer", 0)]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride") or size * n
        out = []
        for i in range(count):
            off = start + i * stride
            vals = struct.unpack_from("<" + fmt * n, data, off)
            out.append(vals[0] if n == 1 else vals)
        return out

    def parent_of(self, index):
        if self._parent is None:
            self._parent = {}
            for i, node in enumerate(self.gltf.get("nodes", [])):
                for child in node.get("children", []):
                    self._parent[child] = i
        return self._parent.get(index)

    def local_matrix(self, index):
        node = self.gltf["nodes"][index]
        if "matrix" in node:
            return list(node["matrix"])
        return mat_from_trs(
            node.get("translation", [0.0, 0.0, 0.0]),
            node.get("rotation", [0.0, 0.0, 0.0, 1.0]),
            node.get("scale", [1.0, 1.0, 1.0]),
        )

    def global_matrix(self, index):
        m = self.local_matrix(index)
        parent = self.parent_of(index)
        while parent is not None:
            m = mat_mul(self.local_matrix(parent), m)
            parent = self.parent_of(parent)
        return m

    def node_by_name(self, name):
        for i, node in enumerate(self.gltf.get("nodes", [])):
            if node.get("name") == name:
                return i
        return None

    def image_bytes(self, index):
        img = self.gltf["images"][index]
        if "bufferView" in img:
            view = self.gltf["bufferViews"][img["bufferView"]]
            data = self.buffers[view.get("buffer", 0)]
            start = view.get("byteOffset", 0)
            return data[start:start + view["byteLength"]]
        uri = img["uri"]
        if uri.startswith("data:"):
            return base64.b64decode(uri.split(",", 1)[1])
        return open(os.path.join(self.base_dir, uri), "rb").read()


def _split_glb(raw):
    total = struct.unpack_from("<I", raw, 8)[0]
    off = 12
    gltf, blob = None, None
    while off < total:
        length, kind = struct.unpack_from("<II", raw, off)
        chunk = raw[off + 8:off + 8 + length]
        if kind == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            blob = chunk
        off += 8 + length + ((4 - length % 4) % 4 if length % 4 else 0)
    return gltf, blob


# -------------------------------------------------------------------- PNG ---

def decode_png(data):
    """Mengembalikan (lebar, tinggi, bytearray RGB). Cukup untuk atlas KayKit.

    Hanya menangani 8 bit per kanal, color type 0/2/3/6, tanpa interlace —
    semua tekstur pack ini memenuhi itu.
    """
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("bukan PNG")
    off, idat, palette, width, height, depth, color = 8, [], None, 0, 0, 8, 2
    while off < len(data):
        length, kind = struct.unpack_from(">I4s", data, off)
        body = data[off + 8:off + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace != 0:
                raise ValueError("PNG tidak didukung: depth=%d interlace=%d" % (depth, interlace))
        elif kind == b"PLTE":
            palette = body
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        off += 12 + length
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    out = bytearray(stride * height)
    prev = bytearray(stride)
    pos = 0
    for row in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if filt == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filt == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filt == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        out[row * stride:(row + 1) * stride] = line
        prev = line
    rgb = bytearray(width * height * 3)
    for i in range(width * height):
        if color == 3:
            idx = out[i] * 3
            rgb[i * 3:i * 3 + 3] = palette[idx:idx + 3]
        elif color in (0, 4):
            v = out[i * channels]
            rgb[i * 3] = rgb[i * 3 + 1] = rgb[i * 3 + 2] = v
        else:
            rgb[i * 3:i * 3 + 3] = out[i * channels:i * channels + 3]
    return width, height, rgb


class Atlas:
    """Atlas warna datar; dibaca sebagai sampler nearest dengan clamp."""

    def __init__(self, png_bytes):
        self.w, self.h, self.px = decode_png(png_bytes)

    def sample(self, u, v):
        x = min(max(int(u * self.w), 0), self.w - 1)
        y = min(max(int((1.0 - v) * self.h), 0), self.h - 1)
        i = (y * self.w + x) * 3
        return (self.px[i] / 255.0, self.px[i + 1] / 255.0, self.px[i + 2] / 255.0)


# ------------------------------------------------------------------ tulis ---

class Writer:
    """Perakit GLB: menumpuk bufferView lalu menyusun chunk JSON + BIN."""

    def __init__(self):
        self.blob = bytearray()
        self.views = []
        self.accessors = []

    def _view(self, data, target=None):
        while len(self.blob) % 4:
            self.blob.append(0)
        offset = len(self.blob)
        self.blob.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        return len(self.views) - 1

    def raw_view(self, data):
        return self._view(data)

    def add(self, values, kind, comp, target=None, minmax=False):
        """Menambah accessor dari list tuple/skalar."""
        fmt, _ = _COMP[comp]
        n = _COUNT[kind]
        buf = bytearray()
        if n == 1:
            for v in values:
                buf.extend(struct.pack("<" + fmt, v))
        else:
            for v in values:
                buf.extend(struct.pack("<" + fmt * n, *v))
        view = self._view(buf, target)
        acc = {"bufferView": view, "componentType": comp,
               "count": len(values), "type": kind}
        if minmax and values:
            if n == 1:
                acc["min"] = [min(values)]
                acc["max"] = [max(values)]
            else:
                acc["min"] = [min(v[i] for v in values) for i in range(n)]
                acc["max"] = [max(v[i] for v in values) for i in range(n)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def build(self, gltf):
        gltf["asset"] = {"version": "2.0", "generator": "chain-shot-rider/gltfkit"}
        gltf["bufferViews"] = self.views
        gltf["accessors"] = self.accessors
        gltf["buffers"] = [{"byteLength": len(self.blob)}]
        js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        js += b" " * ((4 - len(js) % 4) % 4)
        bin_blob = bytes(self.blob) + b"\x00" * ((4 - len(self.blob) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(bin_blob)
        out = bytearray()
        out.extend(struct.pack("<4sII", b"glTF", 2, total))
        out.extend(struct.pack("<II", len(js), 0x4E4F534A))
        out.extend(js)
        out.extend(struct.pack("<II", len(bin_blob), 0x004E4942))
        out.extend(bin_blob)
        return bytes(out)

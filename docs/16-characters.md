# 16 — Karakter ber-tulang (v1.0)

Sampai v0.5 setiap unit di CHAIN RIDER adalah bentuk: kapsul di Godot, kubus
dan bola bercahaya di web. Bentuk itu cukup untuk menguji aturan main, tapi
tidak pernah cukup untuk sebuah game — pasukan yang tidak melangkah, musuh yang
tidak roboh, dan senapan yang tidak pernah ada membuat semuanya terasa seperti
simulasi papan tulis.

v1.0 mengganti lapisan itu: **delapan karakter ber-rig dengan lima klip
animasi, senjata di tangan, soket efek di ujung laras, dan mayat yang
tergeletak sebentar setelah mati** — di web dan di Godot, dari sumber aset yang
sama.

---

## 1. Dari mana asetnya

Tidak diunduh. Delapan GLB ber-tulang ditulis oleh kode di repo ini:

| Berkas | Isi |
| --- | --- |
| `tools/rigkit.py` | Penulis GLB ber-skeleton **tanpa dependensi** (stdlib saja). Menyusun buffer, accessor, skin, `inverseBindMatrices`, dan sampler animasi sendiri. |
| `tools/build_rigged.py` | Definisi delapan unit: proporsi, warna, senjata, klip. Memakai rigkit, menulis ke `assets/models/rigged/`. |

```bash
cd tools && python3 build_rigged.py        # regenerasi 8 GLB (~375 KB total)
```

Kenapa ditulis sendiri dan bukan memakai pustaka: sandbox ini tidak punya
Blender, dan `trimesh` (yang dipakai `tools/build_assets.py` untuk model statis
lama) tidak bisa menulis skin maupun animasi. Yang dibutuhkan hanyalah subset
kecil glTF 2.0, dan subset itu muat dalam satu berkas yang bisa dibaca.

Model statis lama di `assets/models/*.glb` **tetap dipakai** — itulah LOD jauh.

---

## 2. Skeleton kanonik

Enam belas tulang, **identik untuk kedelapan unit**, Y ke atas, menghadap −Z,
titik nol di telapak kaki:

```
hips (0, 0.46·k, 0)
├── spine (+0.10·k) ── chest (+0.12·k) ── head (+0.16·k)
│                       ├── shoulder_l (−0.17·k, +0.07·k) ── arm_l (−0.16·k) ── hand_l (−0.16·k)
│                       └── shoulder_r (+0.17·k, +0.07·k) ── arm_r (−0.16·k) ── hand_r (−0.16·k)
├── thigh_l (−0.09·k, −0.04·k) ── shin_l (−0.21·k) ── foot_l (−0.17·k)
└── thigh_r (+0.09·k, −0.04·k) ── shin_r (−0.21·k) ── foot_r (−0.17·k)
```

`k` adalah skala unit (trooper 1.0, brute 1.45, boss 2.1, dst).

Kenapa satu skeleton untuk semua: renderer tidak perlu tahu sedang memainkan
siapa. Kode yang sama memasang grunt, brute, atau bos; satu-satunya yang
berbeda adalah berkasnya.

**Soket efek** diekspor sebagai tulang, bukan node biasa, supaya ikut terbawa
baik oleh three.js maupun importer Godot:

| Soket | Ada di | Dipakai untuk |
| --- | --- | --- |
| `muzzle` | semua unit | kilatan tembakan di ujung laras |
| `muzzle_l`, `core` | boss | meriam kedua dan inti dada yang berdenyut |

---

## 3. Lima klip, nama sama di semua unit

| Klip | Durasi | Ulang | Isi |
| --- | --- | --- | --- |
| `idle` | 1.8 s | ya | napas, bahu turun-naik |
| `run` | 0.42–1.10 s per unit | ya | langkah, ayunan lengan, bobot badan |
| `shoot` | 0.26 s | tidak | recoil bahu + sentakan laras |
| `hit` | 0.34 s | tidak | badan terdorong ke belakang |
| `die` | 0.85 s | tidak | roboh, dengan root motion jatuh |

Periode `run` berbeda per unit: runner melangkah 0.42 s, brute 0.92 s, boss
1.10 s. Itulah yang membuat kerumunan terbaca sebagai beberapa jenis makhluk
dan bukan satu makhluk yang digandakan.

---

## 4. Anggaran LOD — kenapa tidak semua unit ber-tulang

Satu unit ber-skin berarti satu skeleton yang pose-nya dihitung ulang tiap
frame. Pada gelombang 200 musuh itu 200 skeleton untuk siluet selebar dua
piksel: seluruh anggaran frame ponsel habis untuk tulang yang tidak terlihat.

Jadi hanya unit **terdekat** yang mendapat tubuh ber-tulang, sisanya tetap mesh
statis (MultiMesh di Godot, kolam mesh di web). Angkanya sama di kedua target:

| Anggaran | Jumlah | Di mana |
| --- | --- | --- |
| Prajurit ber-tulang | 10 (barisan depan) | `SKIN.troops` / `CharacterPool.BUDGET.troops` |
| Musuh ber-tulang | 16 terdekat (urut `z` menaik) | `SKIN.enemies` / `BUDGET.enemies` |
| Mayat | 8 sekaligus, maks 3 per jenis | `SKIN.corpses` / `BUDGET.corpses` |
| Bos | selalu ber-tulang | — |

Batas atas: 10 + 16 + bos ≈ 27 skeleton. Sisanya digambar seperti v0.5.

**`CHAR_SCALE = 2.0`.** Tinggi manusia 0,96 unit di lorong selebar 20 unit itu
benar secara skala, tapi di layar ponsel 9:16 jadi ~24 piksel — animasi tulang
tidak akan pernah terbaca. Semua unit dibesarkan dengan faktor yang sama,
termasuk jalur statis, supaya tidak ada lompatan ukuran saat sebuah unit
melewati batas LOD. Simulasi tidak ikut diubah: radius tabrakan tetap apa
adanya.

---

## 5. Web — `js/render3d.js`

Yang ditambahkan di v1.0:

- `loadRigs()` memuat kedelapan GLB lewat GLTFLoader yang sama dengan model
  statis.
- `cloneSkinned()` — salinan SkinnedMesh yang benar. `Object3D.clone()` biasa
  **tidak cukup**: salinannya tetap berbagi skeleton asli, jadi seluruh pasukan
  bergerak serempak seperti satu tubuh. Vendor three.js di repo ini (r128)
  tidak membawa `SkeletonUtils`, jadi rebind-nya ditulis tangan.
- Material **wajib** `skinning: true` di r128. Tanpa flag itu karakter membeku
  di bind pose **tanpa satu pun error** — kegagalan paling mahal di fase ini.
- `frustumCulled = false` untuk mesh ber-rig: bounding box yang dipanggang
  masih bind pose, jadi unit yang roboh berkedip hilang di tepi layar.
- Fase animasi acak per aktor (`Math.random`, bukan RNG simulasi) supaya
  barisan tidak baris-berbaris. Determinisme permainan tidak terpengaruh.
- Efek baru yang membaca `S.fx` (sebelumnya diabaikan renderer 3D): cincin
  hantaman, kilatan moncong di posisi soket `muzzle`, bola cahaya, dan jejak
  12 titik untuk peluru chain.
- Deteksi kematian lewat `id` musuh yang hilang antar frame → `spawnCorpse`.
  `index.html` memberi setiap musuh `id` dari penghitung deterministik
  (`S.enemySeq`), bukan dari RNG.

Deteksi tembakan **tidak** memakai panjang `S.autoBullets`: peluru bisa lahir
dan mati di frame yang sama, jadi tembakan justru terlewat saat layar paling
ramai. Yang dipakai adalah keberadaan peluru di dekat moncong.

---

## 6. Godot — `godot/scripts/view/character_pool.gd`

Satu-satunya tempat di proyek Godot yang tahu tentang Skeleton3D,
AnimationPlayer, dan BoneAttachment3D. `ArenaView` hanya meminta "beri aku
seorang grunt di sini, sedang berlari".

Dua hal yang khas Godot dan tidak ada di web:

1. **glTF tidak menyimpan "klip ini berulang"**, jadi importer menandai semua
   klip sekali-jalan. Tanpa `_prepare_clips()` musuh melangkah satu langkah
   lalu membeku di udara.
2. Soket `muzzle` masuk sebagai **tulang**, jadi diambil lewat
   `BoneAttachment3D`, bukan `find_child()`.

Aset dijangkau lewat symlink `godot/assets -> ../assets` supaya web dan Godot
memakai berkas yang sama persis; tanpa itu dua salinan GLB akan hidup di repo
dan akhirnya berbeda. Konsekuensinya: sekali per mesin perlu

```bash
godot --headless --path godot/ --import
```

agar cache impor terbentuk. Berkas `*.glb.import` ikut di-commit.

---

## 7. Apa yang membuktikan semuanya hidup

| Perintah | Yang dibuktikan |
| --- | --- |
| `node tools/rig_test.js` | Kedelapan GLB: SkinnedMesh, 16 tulang, 5 klip, soket, dan **tulang yang seharusnya bergerak memang bergerak** (kaki saat `run`, kepala saat `die`, tangan kanan saat `shoot`) |
| `node tools/char_test.js` | Karakter hidup **di dalam game**: aktor muncul saat bertempur, anggaran LOD dihormati, klip berbeda sesuai keadaan, tiap aktor punya fase sendiri, senjata dan kilatan ada, mayat roboh lalu dibersihkan, tanpa error konsol |
| `python3 tools/run_game.py --check` | Hal yang sama di Godot, lima varian, 1800 frame per varian |

Keduanya butuh server lokal (`python3 tools/run_web_preview.py`) dan Chromium
(`bash tools/setup_chromium.sh`).

Yang **tidak** dibuktikan oleh tes mana pun: apakah karakternya enak dilihat.
Itu hanya bisa dinilai mata, di `screenshots/qa-gameplay.png` atau di ponsel.

---

## 8. Batas yang diketahui

- Bos memakai klip `idle`/`hit` saja; pola serangannya belum punya animasi
  khusus per fase.
- Mayat tidak menumpuk di medan perang (maks 8, hilang setelah 1,5 detik). Itu
  pilihan anggaran, bukan keterbatasan pipeline.
- Model statis LOD jauh masih model v0.5; siluetnya mirip tapi tidak identik
  dengan versi ber-rig.
- Unit ber-tulang tidak punya ragdoll: `die` adalah klip, bukan fisika.

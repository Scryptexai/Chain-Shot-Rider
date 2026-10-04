# 16 — Karakter ber-tulang (v2.0 — KayKit Adventurers)

Sampai v0.5 setiap unit di CHAIN RIDER adalah bentuk: kapsul di Godot, kubus
dan bola bercahaya di web. v1.0 menggantinya dengan delapan karakter ber-rig
yang ditulis sendiri oleh `tools/rigkit.py` — cukup untuk membuktikan seluruh
jalur animasi hidup, tapi tetap terlihat seperti mainan kayu.

v2.0 mengganti **tubuhnya**, bukan jalurnya: delapan peran sekarang memakai
**KayKit Adventurers 2.0 FREE** (Kay Lousberg, lisensi **CC0** — bebas dipakai
komersial, kredit opsional). Kontrak berkasnya sengaja dibuat sama persis
dengan v1.0, jadi `js/render3d.js` dan `godot/scripts/view/character_pool.gd`
**tidak diubah satu baris pun**: satu primitif, satu material, tulang `muzzle`
di ujung senjata, dan lima klip `idle` / `run` / `shoot` / `hit` / `die`.

---

## 1. Dari mana asetnya

| Berkas | Isi |
| --- | --- |
| `KayKit_Adventurers_2.0_FREE.zip` | Pack asli dari pembuatnya, 13 MB, disimpan utuh di akar repo sebagai sumber yang bisa dilacak |
| `assets/models/kaykit/` | Subset yang benar-benar dipakai pipeline (6 karakter, 2 GLB animasi, 30 aset senjata, `License.txt`). Diekstrak otomatis saat build pertama; ada `.gdignore` supaya Godot tidak ikut mengimpor 40-an berkas sumber |
| `tools/gltfkit.py` | Pembaca/penulis glTF **tanpa dependensi** (stdlib saja): accessor, skin, animasi, dekoder PNG, dan penulis GLB |
| `tools/build_kaykit.py` | Resep per peran: karakter mana, senjata apa, klip mana, tinggi berapa. Warna **tidak** disentuh — atlas bawaan ikut apa adanya |

```bash
python3 tools/build_kaykit.py            # semua peran (~26 detik)
python3 tools/build_kaykit.py grunt boss # sebagian
```

Tidak memakai pygltflib atau trimesh untuk jalur ini dengan sengaja: paket pip
tidak ikut tersimpan bersama repo, dan pipeline yang mati di mesin orang lain
sama saja dengan tidak punya pipeline. `tools/build_assets.py` (yang memang
butuh trimesh) kini hanya membangun **props** arena — tong, batu rune, palisade.

### Peta peran → karakter

| Peran | Karakter KayKit | Tangan kanan | Tangan kiri | Klip `shoot` | Tinggi | Tris dekat | Tris LOD jauh |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `trooper` (squad) | Knight | `sword_1handed` | `shield_round_color` | `Throw` | 0,960 | 6.384 | 3.736 |
| `grunt` | Rogue | `dagger` | — | `Throw` | 0,960 | 7.734 | 4.031 |
| `runner` | Ranger | `bow_withString` | — | `Throw` | 0,883 | 9.584 | 4.007 |
| `brute` | Barbarian | `axe_2handed` | — | `Throw` | 1,392 | 7.631 | 3.754 |
| `splitter` | Mage | `staff` | `spellbook_closed` | `Use_Item` | 0,960 | 7.400 | 3.901 |
| `bomber` | Rogue_Hooded | `smokebomb` | — | `Throw` | 0,941 | 7.495 | 4.150 |
| `shielder` | Knight | `sword_1handed` | `shield_square_color` | `Throw` | 1,008 | 6.362 | 3.723 |
| `boss` | Knight (skala 2×) | `sword_2handed_color` | — | `Throw` | 2,016 | 6.212 | 3.600 |

Tinggi setiap peran **sama persis dengan model v1.0 yang digantikannya**, jadi
`CHAR_SCALE = 2.0`, kotak tabrakan, framing kamera, dan jarak formasi tidak
perlu disetel ulang sama sekali.

Senjata dipilih dari keluarga tekstur karakternya (pedang knight memakai atlas
knight, kapak memakai atlas barbarian, dan seterusnya). Itu bukan selera: satu
atlas per aktor berarti satu material, dan satu material berarti satu draw
call. Aturan itu ditegakkan builder — kalau sebuah resep meminta senjata dari
atlas lain, build berhenti dengan error, bukan diam-diam menambah material.

**Warna bawaan tidak digeser sama sekali.** Versi pertama pipeline ini memakai
pengali warna per peran supaya kawan terlihat dingin dan lawan kemerahan;
pendekatan itu dibuang. Menggeser palet KayKit sama saja dengan mengedit
karakternya, dan karakter yang diedit berhenti terlihat seperti karakter
aslinya. Peran dibedakan lewat tiga hal yang tidak merusak aset: **pilihan
karakternya** (Knight, Rogue, Ranger, Barbarian, Mage, Rogue_Hooded),
**senjatanya**, dan **skalanya** (boss 2×).

---

## 2. Empat keputusan di dalam pipeline

**a. Gabung primitif.** Karakter KayKit dipecah per bagian tubuh (7–9 mesh
node). 26 aktor × 8 bagian ≈ **208 draw call**, sementara anggaran docs/08
adalah 45. Karena semuanya satu material, semua bagian digabung jadi satu
primitif → **26 draw call**.

**b. Bawa UV dan atlas aslinya.** Karakter memakai `TEXCOORD_0` asli KayKit,
dan atlas PNG-nya (12–15 KB, lima berkas untuk delapan peran) ditanam ke dalam
GLB sebagai `baseColorTexture`. Satu tekstur per aktor, jadi penggabungan
primitif di keputusan (a) tetap sah.

> **Percobaan yang dibuang: memanggang atlas jadi `COLOR_0`.** Versi pertama
> mengambil warna per verteks dari UV-nya dan membuang tekstur sama sekali —
> nol pengikatan tekstur, GLB lebih kecil. Tapi satu verteks hanya bisa
> menyimpan satu warna, sementara satu permukaan KayKit sering melewati
> beberapa petak gradien sekaligus. Yang hilang justru detail yang membuat
> pack ini hidup: garis mata, tepi emblem di perisai, dan peralihan halus di
> dalam satu potong zirah. Hasilnya karakter yang "mirip", dan mirip bukan
> yang diminta. Jangan dihidupkan lagi.

> Jebakan yang memakan satu putaran penuh: di glTF **v = 0 adalah baris ATAS**
> gambar, dan three.js memuat tekstur glTF dengan `flipY = false` untuk
> mematuhi itu. Membalik sumbu V tidak membuat warna salah sedikit — ia
> menukar ujung terang gradien dengan ujung gelap, dan seluruh pasukan tampil
> pucat seperti patung gips.

> Jebakan kedua, di sisi render: GLTFLoader menandai `baseColorTexture` sebagai
> sRGB sementara `renderer.outputEncoding` di proyek ini Linear. Kombinasi itu
> membuat shader mengonversi dua kali dan zirah peraknya jadi abu lumpur.
> Atlas KayKit sudah berupa warna jadi, jadi `map.encoding` di-set
> `LinearEncoding` dan dibaca apa adanya. Tiga tempat memakai aturan yang sama:
> `js/render3d.js`, `tools/cast_sheet.js`, dan jalur statis `MODELS`.

**c. Senjata sebagai verteks ter-skin.** Rig KayKit punya tulang khusus
`handslot.l` / `handslot.r` tempat senjata duduk pada transform identitas.
Verteks senjata dipindah ke ruang mesh lewat matriks bind tulang itu lalu
diberi bobot penuh ke tulangnya. Pedang ikut terayun persis seperti tangan,
tanpa node tambahan, tanpa mesh kedua, tanpa draw call kedua. Busur perlu satu
putaran tambahan (`right_rot` di resep) karena ia membentang di sumbu Z.

**d. Salin animasi lintas berkas.** Klip tinggal di dua GLB terpisah
(`Rig_Medium_General`, `Rig_Medium_MovementBasic`) yang memakai rig sama tapi
**urutan node berbeda**. Kanal dipetakan ulang lewat nama tulang, lalu kanal
yang nilainya tetap (kebanyakan trek skala dan translasi) dibuang — ±60% data
animasi hilang tanpa satu pun gerakan berubah.

Titik pada nama tulang (`hand.r`) diganti underscore (`hand_r`) saat ditulis:
three.js menyanitasi nama node saat memuat glTF, jadi nama ber-titik berubah
diam-diam di sisi web dan pencarian tulang antar build berhenti cocok.

---

## 2b. Model LOD jauh ikut dari sumber yang sama

Model statis di `assets/models/*.glb` (jalur MultiMesh/kolam mesh untuk musuh
jauh) **tidak lagi sisa v0.5**. Skrip yang sama memanggang pose siaga karakter
(skinning dihitung sekali di Python), meratakan verteks dengan pengelompokan
kisi, lalu menulis mesh statis bertekstur 3,6k–4,2k tris.

Dua setelan yang penting di sini:

* **Kunci selnya menyertakan petak UV**, bukan hanya posisi. Tanpa itu sel
  sebesar ini melumatkan kepala ke bahu dan menggabungkan verteks dari dua
  petak atlas yang berbeda — hasilnya permukaan yang warnanya meleleh dari
  kulit ke logam. Dengan petak UV (24×24) sebagai pemisah, batas material
  tetap jadi tepi geometri.
* **Selnya 1/26 tinggi badan**, bukan 1/15 seperti versi vertex color. Sel
  yang lebih besar memang menghasilkan mesh lebih ringan, tapi pada model
  bertekstur ia menarik verteks melewati batas petak UV dan wajahnya rusak.
  Selisih biayanya ditanggung di tempat yang benar: LOD jauh dipakai justru
  saat musuh kecil di layar.

---

## 3. Skeleton kanonik — "Rig_Medium" (23 tulang + `muzzle`)

Dua puluh tiga tulang, **identik untuk keenam karakter**, Y ke atas, menghadap
−Z, titik nol di telapak kaki:

```
root ── hips ── spine ── chest ── head
                 │        ├── upperarm_l ── lowerarm_l ── wrist_l ── hand_l ── handslot_l
                 │        └── upperarm_r ── lowerarm_r ── wrist_r ── hand_r ── handslot_r ── muzzle
                 ├── upperleg_l ── lowerleg_l ── foot_l ── toes_l
                 └── upperleg_r ── lowerleg_r ── foot_r ── toes_r
```

Kenapa satu skeleton untuk semua: renderer tidak perlu tahu sedang memainkan
siapa. Kode yang sama memasang grunt, brute, atau bos; satu-satunya yang
berbeda adalah berkasnya.

**Soket efek** `muzzle` ditambahkan pipeline sebagai **tulang** (anak dari
`handslot_r`, di 92% panjang senjata), bukan node biasa, supaya ikut terbawa
baik oleh three.js maupun importer Godot — di Godot ia diambil lewat
`BoneAttachment3D`, di web lewat `getObjectByName('muzzle')`.

## 4. Lima klip, nama sama di semua unit

Pack tier gratis tidak punya animasi serang, jadi `shoot` dipinjam dari gerak
terdekat: `Throw` untuk ayunan senjata, `Use_Item` untuk rapalan penyihir.

| Klip | Sumber di pack | Durasi | Ulang |
| --- | --- | --- | --- |
| `idle` | `Idle_A` | 1,07 s | ya |
| `run` | `Running_A` | 0,80 s | ya |
| `shoot` | `Throw` / `Use_Item` | 1,37 s / 1,60 s | tidak |
| `hit` | `Hit_A` | 0,67 s | tidak |
| `die` | `Death_A` | 0,80 s | tidak |

Variasi antar unit tidak lagi datang dari periode klip yang berbeda, melainkan
dari `rate` acak per aktor (0,92–1,08×) plus fase awal acak — keduanya sudah
ada sejak v1.0 di kedua build. Itu yang membuat kerumunan terbaca sebagai
banyak makhluk, bukan satu makhluk yang digandakan.

## 5. Anggaran LOD — kenapa tidak semua unit ber-tulang

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

## 6. Web — `js/render3d.js`

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

## 7. Godot — `godot/scripts/view/character_pool.gd`

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

## 8. Apa yang membuktikan semuanya hidup

| Perintah | Yang dibuktikan |
| --- | --- |
| `node tools/rig_test.js` | Kedelapan GLB: SkinnedMesh, 24 tulang, 5 klip, soket, dan **tulang yang seharusnya bergerak memang bergerak** (kaki saat `run`, kepala saat `die`, tangan kanan saat `shoot`) |
| `node tools/char_test.js` | Karakter hidup **di dalam game**: aktor muncul saat bertempur, anggaran LOD dihormati, klip berbeda sesuai keadaan, tiap aktor punya fase sendiri, senjata dan kilatan ada, mayat roboh lalu dibersihkan, tanpa error konsol |
| `python3 tools/run_game.py --check` | Hal yang sama di Godot, lima varian, 1800 frame per varian |
| `node tools/cast_sheet.js <url> screenshots/kaykit-cast.png` | Lembar kontak kedelapan karakter untuk diperiksa mata: senjata di tangan yang benar, warna tidak pucat, pose tidak kusut |

Keduanya butuh server lokal (`python3 tools/run_web_preview.py`) dan Chromium
(`bash tools/setup_chromium.sh`).

Yang **tidak** dibuktikan oleh tes mana pun: apakah karakternya enak dilihat.
Itu hanya bisa dinilai mata, di `screenshots/qa-gameplay.png` atau di ponsel.

---

## 9. Batas yang diketahui

- Bos memakai klip `idle`/`hit` saja; pola serangannya belum punya animasi
  khusus per fase.
- Mayat tidak menumpuk di medan perang (maks 8, hilang setelah 1,5 detik). Itu
  pilihan anggaran, bukan keterbatasan pipeline.
- Model statis LOD jauh kini dipanggang dari karakter yang sama, tapi hasil
  desimasinya berlubang kalau dilihat dari dekat — ia memang hanya untuk jarak
  ≥ 26 unit.
- Beban segitiga puncak naik dari ±6k ke ±190k (lihat docs/08). Aman menurut
  draw call, belum diuji di Snapdragon 660 sungguhan.
- Jalur MultiMesh Godot masih memakai kapsul berwarna, bukan model statis
  seperti di web: menambah satu MultiMesh per tipe musuh berarti tujuh draw
  call tambahan, dan itu belum terbukti sepadan.
- Unit ber-tulang tidak punya ragdoll: `die` adalah klip, bukan fisika.

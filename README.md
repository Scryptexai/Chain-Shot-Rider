# CHAIN RIDER — Arena 2.5D Portrait

> **Bullet-steering crowd shooter.** Tembak satu peluru, masuk ke dalamnya, belokkan untuk membantai ratusan musuh.
> Mobile portrait 9:16, satu jempol, sesi 1–3 menit.

![Arena 2.5D](docs/images/arena-2_5d-reference.png)

Repo ini berisi **paket desain + implementasi arena** lengkap: blueprint, style guide, struktur scene, skeleton kode Unity, spesifikasi prefab, wireframe UI, cue sheet audio, checklist optimasi & testing, dan **prototipe web yang bisa langsung dimainkan**.

---

## Mulai dari mana

| Kalau kamu… | Buka ini |
|---|---|
| Ingin **main sekarang tanpa memasang apa pun** | `python3 -m http.server 8000` → buka `http://localhost:8000` |
| Level designer | [`docs/01-arena-blueprint.md`](docs/01-arena-blueprint.md) → [`docs/10-level-variations.md`](docs/10-level-variations.md) |
| Technical artist | [`docs/02-visual-style-guide.md`](docs/02-visual-style-guide.md) → [`docs/05-prefab-spec.md`](docs/05-prefab-spec.md) |
| Programmer | [`docs/04-script-skeleton.md`](docs/04-script-skeleton.md) → `unity/Assets/ChainRider/Scripts/` |
| UI/UX | [`docs/06-ui-wireframe.md`](docs/06-ui-wireframe.md) |
| Audio | [`docs/07-audio-cue-sheet.md`](docs/07-audio-cue-sheet.md) |
| QA / produser | [`docs/08-optimization-checklist.md`](docs/08-optimization-checklist.md) → [`docs/09-testing-checklist.md`](docs/09-testing-checklist.md) |
| Game designer / balance | [`docs/11-balance-and-deviations.md`](docs/11-balance-and-deviations.md) → [`docs/12-aim-mode-comparison.md`](docs/12-aim-mode-comparison.md) |
| Mau menjalankan gamenya | [`docs/15-godot-setup.md`](docs/15-godot-setup.md) |
| Mau paham desain MVP | [`docs/14-lastwar-atm.md`](docs/14-lastwar-atm.md) |

---

## Deliverables

| # | Dokumen | Isi |
|---|---|---|
| 1 | [Blueprint Arena](docs/01-arena-blueprint.md) | Grid ASCII 5 varian, koordinat presisi, zona, dinding, aturan penempatan. **Di-generate otomatis** dari data. |
| 2 | [Visual Style Guide](docs/02-visual-style-guide.md) | Palet, lighting rig, post-processing, material, bahasa VFX, referensi |
| 3 | [Scene Hierarchy](docs/03-scene-hierarchy.md) | Struktur folder, hierarchy Unity lengkap, 44 script, urutan eksekusi, padanan Godot 4 |
| 4 | [Script Skeleton](docs/04-script-skeleton.md) | Peta kode + 6 keputusan teknis yang menentukan arsitektur |
| 5 | [Prefab Spec](docs/05-prefab-spec.md) | 25+ prefab dengan budget tris, material, pool size, shadow |
| 6 | [UI Wireframe](docs/06-ui-wireframe.md) | Wireframe portrait, anatomi HUD, safe area, tipografi |
| 7 | [Audio Cue Sheet](docs/07-audio-cue-sheet.md) | 16 cue SFX, pitch ladder, musik dinamis, mixing, timing diagram |
| 8 | [Optimization Checklist](docs/08-optimization-checklist.md) | Anggaran frame 16.6 ms, pooling, batching, LOD, tier device |
| 9 | [Testing Checklist](docs/09-testing-checklist.md) | Performa, determinisme, gameplay — dengan kriteria lolos |
| 10 | [Level Variations](docs/10-level-variations.md) | 5 arena: maksud desain, tema, musuh spesial, boss |
| 11 | [Balance & Deviasi Spec](docs/11-balance-and-deviations.md) | **Baca ini sebelum mengubah angka.** Deviasi desain dari spec awal beserta buktinya, hasil balance pass 30 run, dan daftar lever yang terbukti tidak berpengaruh |
| 12 | [Perbandingan Mode Bidikan](docs/12-aim-mode-comparison.md) | Keputusan kontrol MVP: bidik manual vs sapuan otomatis, 30 run per konfigurasi |
| 13 | [Setup Unity MVP v1](docs/13-unity-mvp-setup.md) | Jalur Unity (tidak lagi jadi target utama) |
| 14 | [ATM Last War / Top War](docs/14-lastwar-atm.md) | **Desain MVP saat ini.** Apa yang ditiru, apa yang dimodifikasi, dan hasil ukur ekonomi gate |
| 15 | [Setup Godot](docs/15-godot-setup.md) | Menjalankan project Godot, installer sandbox, validator statis |

---

## Menjalankan MVP (Godot 4.6)

MVP ada di `godot/` dan butuh **Godot 4.6.2 stable** edisi standar (bukan .NET).
Versi ini mengikat: `project.godot` memakai `config/features=("4.6", ...)`.

```bash
godot --path godot/ --editor     # sekali, biar aset ter-import
godot --path godot/              # jalankan (F5 dari editor juga bisa)
```

Jendela terbuka 1080x1920 portrait; mouse berfungsi sebagai jempol
(`emulate_touch_from_mouse`). Dari sini terlihat MVP sebenarnya: menu, **peta 15
stage**, arena, HUD, layar hasil, dan draft kartu.

Preview di browser — ekspor dan server dalam satu perintah:

```bash
python3 tools/export_web.py             # ekspor + periksa hasilnya
python3 tools/serve_web_build.py 8081   # http://localhost:8081/
```

Yang dirender di browser itu **engine Godot sungguhan** (dikompilasi ke
WebAssembly, menggambar lewat WebGL2), bukan prototipe JavaScript. Build ~41 MB
di disk, ~14 MB terkirim setelah gzip.

Preset Web diekspor **tanpa thread** supaya bisa dihosting di GitHub Pages:
build berulir menuntut header COOP/COEP yang tidak bisa dikirim hosting statis,
dan tanpa header itu kanvasnya hitam. Tetap pakai `tools/serve_web_build.py`,
**bukan** `python3 -m http.server`, karena MIME `.wasm` harus
`application/wasm`. Build web diuji otomatis sampai benar-benar dimainkan
(`node tools/web_build_test.js`). APK Android dan detail lengkapnya ada di
[`docs/15-godot-setup.md`](docs/15-godot-setup.md).

Verifikasi tanpa GPU:

```bash
godot --headless --path godot/ --script res://tests/sim_headless.gd   # balance + determinisme
godot --headless --path godot/ res://tests/smoke.tscn                 # renderer, UI, audio
```

---

## Cara tercepat: satu berkas, tanpa server

Unduh **`chain-rider.html`** (1,5 MB) lalu klik dua kali. Selesai.

Tanpa server, tanpa internet, tanpa Godot, tanpa Python, tanpa npm. Seluruh
game ada di dalam satu berkas itu: config, Three.js, GLTFLoader, renderer, dan
11 model GLB ditanam sebagai data URI. Bisa dikirim lewat chat atau disalin ke
HP dan tetap jalan.

Dibangun ulang dengan `python3 tools/build_standalone.py` setiap kali sumbernya
berubah. Diverifikasi dibuka lewat `file://` di Chromium sungguhan: WebGL
aktif, 11 model termuat, simulasi berjalan, konsol bersih.

## Build Web — versi folder (untuk pengembangan)

Butuh satu perintah, tanpa Godot, tanpa unduhan, tanpa akun:

```bash
python3 -m http.server 8000
# buka http://localhost:8000
```

Tanpa build step, tanpa dependency, tanpa Godot, tanpa npm. `index.html` ada di
root repo, jadi perintah standar itu sudah cukup — tidak ada skrip server buatan
sendiri dan tidak ada pengalihan URL.

### GitHub Pages tidak diperlukan

Pages **tidak dipakai dan tidak perlu diaktifkan**. Untuk memainkan game cukup
klik dua kali `chain-rider.html`; untuk mengembangkannya cukup `http.server` di
atas. Pages hanya relevan pada satu kasus: Anda ingin membuka game dari
perangkat lain (HP) lewat URL internet, tanpa menyalin berkasnya. Kalau itu yang
dibutuhkan: `Settings → Pages → Source: Deploy from a branch → Branch:
arena/01a0ee17-chain-shot-rider, folder: / (root)`. Selain kasus itu, abaikan.

### Kenapa versi folder butuh server, sedangkan satu-berkas tidak

Browser memberlakukan CORS pada berkas yang dibuka lewat `file://`: asalnya
dianggap `null`, sehingga `fetch()` dan `<script type="module">` diblokir.
Versi folder mengambil `Config/arena_config.json` dan 11 `.glb` lewat `fetch()`,
jadi ia **wajib** disajikan dari sebuah origin HTTP. `chain-rider.html` tidak
kena aturan itu karena config, three.js, loader, dan seluruh model sudah
ditanam sebagai base64 di dalam satu berkas — tidak ada satu pun permintaan
jaringan saat boot.

Yang terbuka adalah **MVP yang bisa dimainkan**, bukan demo teknis. Alurnya penuh:

**peta 15 stage → main → menang → draft 3 kartu → kartu tersimpan → stage berikutnya**

Isinya sama dengan build Godot karena keduanya membaca **satu sumber kebenaran
yang sama**, `Config/arena_config.json`: 8 kartu di `meta.cards`, `stageCount`,
`cardsOffered`, `variantCycle`, dan `difficultyPerStage`. Tidak ada definisi
kartu yang ditulis ulang di JavaScript, jadi kedua build tidak bisa menyimpang
diam-diam.

Loop tempur Last War sudah lengkap di sini: squad yang digeser kiri-kanan, gate
matematika (dilewati squad **dan** peluru), auto-fire yang skalanya mengikuti
jumlah pasukan, tekanan 5 wave, elite, dan boss di ujung stage — ditambah
ricochet analitik tanpa physics engine, bullet riding, dan slow-mo. Simulasinya
fixed-step 60 Hz dan deterministik: stage yang sama selalu bermain sama persis.

**Kontrol:** `tap`/`klik` = tembak (atau rem saat riding) · `drag` = belokkan peluru · `←` `→` = geser squad · `R` = restart · tombol `1`–`5` di panel = intip arena

**Progres** disimpan di `localStorage` browser; tombol `RESET PROGRESS` di peta
mengosongkannya.

### Pipeline aset 3D

**Karakter (v2.1): KayKit Adventurers 2.0 FREE, dipakai apa adanya** — Kay
Lousberg, lisensi **CC0** (bebas komersial, kredit opsional; salinan lisensi
ikut di `assets/models/kaykit/License.txt`). Pack aslinya disimpan utuh di
`KayKit_Adventurers_2.0_FREE.zip`, dan berkas yang dipakai diekstrak
berdampingan di `assets/models/kaykit/`.

**Tidak ada langkah build untuk karakter.** Yang tampil di layar adalah berkas
pack itu sendiri, dirakit saat runtime dari tiga sumber:

| Berkas pack | Perannya |
| --- | --- |
| `Characters/gltf/<nama>.glb` | tubuh + rig 23 tulang |
| `Animations/gltf/Rig_Medium/*.glb` | lima klip, dipakai bersama seluruh cast |
| `Assets/gltf/<senjata>.gltf` | digantung di tulang `handslot.r` / `handslot.l` |

Satu-satunya perlakuan terhadap geometrinya adalah **penyatuan di memori**:
KayKit memecah tiap tubuh jadi 7–9 mesh bermaterial sama, dan renderer
menyambungnya jadi satu mesh saat dimuat (694 → 184 draw call terukur, jumlah
segitiga tidak berubah sedikit pun). Versi sebelumnya melakukan hal yang sama
dengan **menulis ulang GLB-nya** plus memanggang tekstur jadi vertex color dan
mendesimasi LOD jauh; itu dibuang, berikut skrip-skripnya, karena yang ikut
berubah adalah karakternya.

Detail lengkap — peta peran, rig, anggaran LOD, dan hal-hal khas three.js r128
maupun importer Godot — ada di
[`docs/16-characters.md`](docs/16-characters.md); angka draw call terukurnya di
[`docs/08`](docs/08-optimization-checklist.md) §8.0.

**Props arena: tetap dihasilkan kode.** Tong mesiu, batu rune, dan palisade
dibangun prosedural:

```bash
python3 -m venv ~/.cache/venv
~/.cache/venv/bin/pip install trimesh numpy
~/.cache/venv/bin/python tools/build_assets.py
```

GLB yang sama bisa dipakai build Godot maupun build web, jadi keduanya tidak
akan menyimpang secara visual.

### Bagaimana game ini dirender di web

Pakai pendekatan yang sama dengan Last Harbor: **Three.js yang di-vendor**, bukan
engine yang diekspor.

| | Cara kerja |
|---|---|
| Library | `js/vendor/three.min.js` (r128, UMD, 603 KB) **ikut di repo** — tanpa CDN, tanpa npm saat runtime |
| Pemuatan | `<script src="...">` biasa, bukan ES module, jadi host statis apa pun melayaninya |
| Kanvas | `<canvas id="webgl-canvas">` dengan `THREE.WebGLRenderer` |
| Kamera | `PerspectiveCamera` FOV 41, tinggi 51, miring 33,7 derajat ke arena 20x40 |
| Cahaya | `HemisphereLight` + matahari `DirectionalLight` + fill — tanpa shadow map demi HP kentang |
| Model | **GLB sungguhan**: 3 props di `assets/models/` + pack KayKit di `assets/models/kaykit/`, dimuat `THREE.GLTFLoader` |
| Karakter | 10 prajurit + 24 musuh terdekat + bos digambar sebagai SkinnedMesh ber-animasi; musuh lain memakai karakter yang sama dengan pose beku (lihat docs 16) |
| Pembuat model | hanya props: `tools/build_assets.py` (`trimesh`). Karakter tidak dibuat, melainkan dimuat dari pack — **tanpa Blender dan tanpa Godot** |
| Fallback | kalau GLB belum selesai dimuat, primitif Three.js dipakai lebih dulu supaya tidak ada layar kosong |
| Build step | tidak ada |

`js/render3d.js` hanya **menggambar**. Ia membaca `S` sekali per frame dan
memindahkan mesh; ia tidak pernah menyentuh state simulasi dan tidak pernah
memakai RNG simulasi. Itu yang menjaga build web dan build Godot tetap sejalan.

Kalau WebGL tidak tersedia, `draw()` otomatis jatuh ke renderer Canvas 2D lama,
jadi halamannya tidak pernah blank.

Perbedaan dengan build Godot: Godot merender lewat WebGL2 dari engine yang
dikompilasi ke WebAssembly. Keduanya 3D, dan aturan main, angka, serta
progresinya sama karena membaca config yang sama.

---

## Kontrol (MVP v2 — Godot)

| Keadaan | Gestur | Aksi |
|---|---|---|
| Idle | geser | menggerakkan squad kiri-kanan menembus gate |
| Idle | tap | menembakkan chain shot |
| Bullet-riding | geser | membelokkan peluru |
| Bullet-riding | tap | mengerem |

Satu sumbu, dua kedalaman: **posisi squad adalah bidikannya.** Chain shot selalu
melesat lurus, jadi menggeser squad untuk memilih gate sekaligus menyiapkan
geometri pantulan. Loop dasarnya di-ATM dari Last War / Top War; chain shot yang
bisa ditunggangi adalah modifikasi yang memberi langit-langit kemahiran yang
tidak dimiliki game referensinya. Lihat [doc 14](docs/14-lastwar-atm.md).

Temuan doc 12 tetap jadi dasarnya: **sudut tembak harus milik pemain.** Sekarang
pemain memilikinya lewat posisi, bukan lewat sudut drag.

---

## Status Balance (loop Last War ATM, terukur)

6 seed × 5 varian per baris, harness `tools/sim_test.js`:

| | Bot mahir | Bot acak |
|---|---|---|
| Durasi median | 143 s | 90 s |
| Dalam jendela 60–180 s | 25/30 | 24/30 |
| Run buntu | 0/30 | 0/30 |
| Pasukan akhir | 70,6 | 3,0 |
| Menang | 22/30 | 1/30 |
| Pelanggaran invariant | 0 | 0 |

Determinisme lulus (5 varian × 7200 tick), `draw()` bersih 600 eksekusi.
Pemisahan 70,6 vs 3,0 pasukan adalah buktinya: kemahiran terbayar.

---

## Harness Simulasi & Status Balance

Balance game ini **diukur, bukan ditebak**. `tools/sim_test.js` memuat logika
gameplay langsung dari `index.html` (tidak ada duplikasi aturan),
menstub DOM/Canvas/WebAudio, lalu menjalankan run penuh dengan bot.

```bash
node tools/sim_test.js                 # semua varian, bot standar
node tools/sim_test.js --bot=skilled   # bot mahir
node tools/sim_test.js --determinism   # uji replay 120 detik x 5 varian
```

`sim_test.js` menstub DOM habis-habisan, jadi layar meta sengaja dilewati di
sana. Lapisan meta diuji terpisah di DOM sungguhan dengan jsdom — klik asli,
`localStorage` asli:

```bash
npm install --no-save jsdom && node tools/meta_test.js
```

Lapisan rasa — milestone pantulan, ambang kill, near miss, perfect clear, dan
peluru terakhir — punya harness sendiri. Yang diuji bukan angka balance,
melainkan reaksi, dan tiap reaksi diperiksa dalam dua keadaan berlawanan
(pantulan ke-4 diam, ke-5 berbunyi; zoom sinematik menyala lalu benar-benar
padam):

```bash
node tools/juice_test.js
```

Renderer WebGL diuji tanpa GPU oleh `tools/render3d_test.js`. Three.js menghitung
matriks proyeksi di CPU, jadi framing kamera bisa **dibuktikan secara matematis**:
tes memproyeksikan sudut-sudut arena lewat kamera yang sama persis yang dipakai
game, lalu memastikan tidak ada yang terpotong. Tes itu juga membangun scene
graph sungguhan (hanya `WebGLRenderer` yang distub) untuk memastikan pemetaan
`(x, y, -z)` benar, mesh dipakai ulang alih-alih dialokasikan tiap frame, dan
renderer tidak mengubah state simulasi.

```bash
node tools/render3d_test.js
```

Yang **tidak** bisa dibuktikan tanpa GPU: warna, cahaya, dan rasa. Itu hanya
bisa dinilai mata di browser sungguhan.

Karakter ber-tulang punya dua tes sendiri, dan keduanya berjalan di **Chromium
sungguhan** (lewat `bash tools/setup_chromium.sh`), karena animasi skinning
adalah hal yang gagal diam-diam: material tanpa flag `skinning` membekukan
karakter di bind pose tanpa satu pun error, dan SkinnedMesh yang di-clone
keliru membuat seluruh pasukan bergerak serempak seperti satu tubuh.

```bash
node tools/rig_test.js      # 8 GLB: tulang, klip, soket, vertex yang bergerak
node tools/char_test.js     # karakter hidup di dalam game yang sedang dimainkan
```

`char_test.js` memainkan stage sungguhan lalu memeriksa aktor ber-skeleton
muncul, anggaran LOD dihormati, klip berbeda sesuai keadaan, tiap aktor punya
fase animasi sendiri, kilatan moncong tergambar, dan mayat roboh lalu
dibersihkan. Lihat [`docs/16-characters.md`](docs/16-characters.md).

Uji itu menelusuri peta 15 stage → main → menang → draft kartu → kartu tersimpan
→ stage berikutnya terbuka, lalu membuktikan kartunya **benar-benar mengubah
parameter simulasi** (bukan hiasan), determinisme tetap utuh, dan progres
terbaca kembali setelah halaman dimuat ulang. Status terakhir: **34 pemeriksaan,
0 gagal**.

Kondisi saat ini (6 seed × 5 varian = 30 run, bot skilled):

| Metrik | Hasil | Target |
|---|---|---|
| Durasi sesi rata-rata | 105 detik | 60–180 detik ✓ |
| Run dalam jendela target | 29/30 | — |
| Mencapai boss (wave 5) | 30/30 | — |
| Bot menang | 3/30 (10%) | 5–20% ✓ |
| Pelanggaran invariant | 0 | 0 ✓ |
| Determinisme | identik | identik ✓ |

Harness ini menemukan dua cacat yang tidak terlihat dari membaca kode: peluru
yang tidak pernah memantul (0.10 bounce/peluru) dan bug determinisme pada
Splitter yang lolos karena uji lama terlalu pendek. Keduanya dijelaskan di
[doc 11](docs/11-balance-and-deviations.md).

---

## Struktur Repo

```text
Config/arena_config.json     ← SUMBER KEBENARAN TUNGGAL (arena, bullet, spawn, 5 varian)
tools/blueprint_gen.py       ← generator docs/01 dari JSON di atas
index.html                   ← GAME: build web playable (2.5D canvas, tanpa dependency)
docs/                        ← 10 dokumen deliverable + referensi visual
unity/Assets/ChainRider/
  Scripts/
    Core/      SimClock, DeterministicRng, GameEvents, ArenaBounds, ArenaManager
    Bullet/    BulletController, BulletSystem, RicochetSolver, BulletData, BulletView
    Crowd/     CrowdManager, FormationBuilder, EnemyData
    Camera/    CameraRig
    Time/      SlowMoSystem
    Obstacles/ ObstacleField
    Input/     InputRouter
    Pooling/   ObjectPool, PoolRegistry
    UI/        HudController, FloatingTextSpawner, ComboPopup
    Audio/     AudioDirector
    Config/    ConfigSO (semua ScriptableObject)
    Debug/     ReplayRecorder, PerfHud
```

Ubah `Config/arena_config.json` → jalankan `python3 tools/blueprint_gen.py` → blueprint & prototipe ikut ter-update.

---

## Enam Keputusan Arsitektur

1. **Fixed-step 60 Hz.** Slow-mo mengubah *berapa banyak* tick yang jalan, bukan ukurannya → replay tetap akurat walau pemain memicu bullet time.
2. **Ricochet analitik, bukan physics engine.** Swept-circle test (akar persamaan kuadrat) → deterministik lintas platform, anti-tunneling di 150% kecepatan.
3. **Musuh biasa ditembus, musuh berarmor memantulkan.** Kalau semua musuh memantulkan, 15 bounce habis dalam 0.2 detik di crowd rapat dan pemain kehilangan kendali. Brute & Shielder jadi "bumper hidup".
4. **Crowd = array struct + GPU instancing.** 200 MonoBehaviour = 8–12 ms/frame, seluruh budget habis. Spatial grid dibangun sekali per tick dengan counting sort, dipakai dua konsumen (peluru + separation).
5. **Satu pemilik waktu.** Hanya `SlowMoSystem` yang menulis `Time.timeScale`; sistem lain mengirim intent lewat event bus. Permintaan paling lambat menang.
6. **Gravity well memutar arah, bukan menambah velocity.** Menjaga cap kecepatan 150% sambil tetap menghasilkan lintasan melengkung.

Detail lengkap + alasannya ada di [`docs/04-script-skeleton.md`](docs/04-script-skeleton.md).

---

## Target Teknis

| Metrik | Target |
|---|---|
| Frame rate | 60 FPS @ Snapdragon 660, 200 musuh aktif |
| Frame budget | 16.6 ms (rincian per blok di dokumen 8) |
| RAM | < 200 MB |
| Build | < 100 MB (Android AAB) |
| GC | **0 B/frame** selama gameplay |
| Draw call | ≤ 45 — **tidak tercapai sejak karakter KayKit masuk**; terukur 184, lihat docs/08 §8.0 |
| Determinisme | seed + input stream → run identik lintas device & frame rate |

---

## Constraint yang Dipatuhi

- [x] Portrait only, satu jempol
- [x] Sesi 1–3 menit (5 wave)
- [x] Tidak ada kontrol gerak player — player statis di `(0, 2)`
- [x] Semua mobilitas datang dari peluru
- [x] Tidak ada reload manual (auto-reload 0.35 s/peluru)
- [x] Tidak ada tombol lompat/dash
- [x] Semua efek dalam frame budget 16 ms (partikel di-cap 200, prioritas berjenjang)
- [x] Tidak memakai physics engine untuk ricochet (`RicochetSolver`, analitik)
- [x] Deterministik dan bisa direplay (`SimClock` + `DeterministicRng` + `ReplayRecorder`)

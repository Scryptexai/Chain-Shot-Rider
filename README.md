# CHAIN RIDER — Arena 2.5D Portrait

> **Bullet-steering crowd shooter.** Tembak satu peluru, masuk ke dalamnya, belokkan untuk membantai ratusan musuh.
> Mobile portrait 9:16, satu jempol, sesi 1–3 menit.

![Arena 2.5D](docs/images/arena-2_5d-reference.png)

Repo ini berisi **paket desain + implementasi arena** lengkap: blueprint, style guide, struktur scene, skeleton kode Unity, spesifikasi prefab, wireframe UI, cue sheet audio, checklist optimasi & testing, dan **prototipe web yang bisa langsung dimainkan**.

---

## Mulai dari mana

| Kalau kamu… | Buka ini |
|---|---|
| Ingin **merasakan** mekaniknya dulu | `prototype/index.html` → jalankan server lokal (lihat di bawah) |
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

## Menjalankan MVP (Godot 4.3)

MVP ada di `godot/` dan butuh **Godot 4.3 stable** edisi standar (bukan .NET).
Versi ini mengikat: `project.godot` memakai `config_version=5`.

```bash
godot --path godot/ --editor     # sekali, biar aset ter-import
godot --path godot/              # jalankan (F5 dari editor juga bisa)
```

Jendela terbuka 1080x1920 portrait; mouse berfungsi sebagai jempol
(`emulate_touch_from_mouse`). Dari sini terlihat MVP sebenarnya: menu, **peta 15
stage**, arena, HUD, layar hasil, dan draft kartu.

Preview di browser lewat server Python — satu perintah, mengurus ekspor dan
header sekaligus:

```bash
python3 tools/run_web_preview.py --install-templates   # sekali, ~700 MB
python3 tools/run_web_preview.py                       # http://localhost:8081/
```

Yang dirender di browser itu **engine Godot sungguhan** (dikompilasi ke
WebAssembly, menggambar lewat WebGL2), bukan prototipe JavaScript.

Pakai `tools/serve_web_build.py`, **bukan** `python3 -m http.server`: build Web
diekspor dengan thread support, jadi perlu header COOP/COEP atau kanvasnya
hitam. APK Android dan detail lengkapnya ada di
[`docs/15-godot-setup.md`](docs/15-godot-setup.md).

Verifikasi tanpa GPU:

```bash
godot --headless --path godot/ --script res://tests/sim_headless.gd   # balance + determinisme
godot --headless --path godot/ res://tests/smoke.tscn                 # renderer, UI, audio
```

---

## Prototipe Interaktif (bukan MVP)

Prototipe web menjalankan **aturan yang sama** dengan spec Unity: fixed-step 60 Hz, ricochet analitik tanpa physics engine, bullet riding + slow-mo, 5 varian arena yang dibaca langsung dari `Config/arena_config.json`.

```bash
python3 tools/serve_prototype.py 8080
# buka http://localhost:8080/  (diarahkan ke /prototype/)
```

**Kontrol:** `tap`/`klik` = tembak (atau rem saat riding) · `drag` = belokkan peluru · `←` `→` = steer keyboard · `1`–`5` = ganti arena · `R` = restart

Prototipe ini **lebih lama dari MVP** dan belum memakai desain Last War: tidak ada peta stage, kartu upgrade, gate, maupun squad yang bisa digeser. Gunakan untuk iterasi layout arena — memindahkan bumper di JSON lalu me-refresh browser jauh lebih cepat daripada menjalankan ulang engine.

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
gameplay langsung dari `prototype/index.html` (tidak ada duplikasi aturan),
menstub DOM/Canvas/WebAudio, lalu menjalankan run penuh dengan bot.

```bash
node tools/sim_test.js                 # semua varian, bot standar
node tools/sim_test.js --bot=skilled   # bot mahir
node tools/sim_test.js --determinism   # uji replay 120 detik x 5 varian
```

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
prototype/index.html         ← prototipe 2.5D playable (canvas, tanpa dependency)
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
| Draw call | ≤ 45 |
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

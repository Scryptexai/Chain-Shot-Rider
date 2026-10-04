# 8. Optimization Checklist — CHAIN RIDER

**Target keras:** 60 FPS (16.6 ms/frame) di Snapdragon 660, 200 musuh aktif, < 200 MB RAM, < 100 MB build.

---

## 8.1 Anggaran Frame (16.6 ms)

| Blok | Budget | Isi |
|---|---|---|
| Simulasi crowd | **3.0 ms** | gerak 200 musuh + separation + rebuild spatial grid |
| Simulasi peluru | **0.8 ms** | sweep 1–3 peluru × 4 substep |
| Obstacle + wave logic | **0.4 ms** | platform, chain explosion, timer |
| Render — bangun matriks instancing | **1.5 ms** | 200 `Matrix4x4.TRS` |
| Render — draw call GPU | **5.0 ms** | ≤ 45 draw call *(lihat §8.0 — angka ini tidak lagi tercapai)* |
| Post-processing | **2.5 ms** | bloom + vignette (+ CA hanya saat slow-mo) |
| UI | **1.0 ms** | canvas rebuild terpisah |
| Audio | **0.6 ms** | 8 voice |
| Partikel | **1.0 ms** | ≤ 200 partikel aktif |
| **Headroom** | **0.8 ms** | cadangan untuk hitch OS |

> Kalau satu blok melewati budget, blok lain **tidak** boleh "meminjam". Yang dipotong adalah fitur, bukan frame rate.

## 8.0 Angka terukur, bukan angka harapan

Seluruh anggaran di bawah ditulis sebelum karakter sungguhan masuk. Sejak
karakter KayKit dipakai **apa adanya** (docs/16), angka draw call-nya diukur,
bukan ditaksir — `node tools/perf_probe.js` memainkan stage 1 di Chromium dan
membaca `renderer.info` tiap detik.

Puncak yang terukur pada 4 Oktober 2026, 480×854, gelombang terpadat
(74 musuh + 5 prajurit + 21 aktor ber-skeleton):

| Besaran | Sebelum penyatuan mesh | Sesudah | Anggaran lama |
| --- | --- | --- | --- |
| Draw call | **694** | **184** (ulangan: 178–184) | ≤ 45 |
| Pengikatan tekstur | 203 | **36** | — |
| Segitiga | 651.790 | **651.790** | — |
| Program shader | 9 | 9 | ≤ 20 SetPass |

Dua hal yang harus dibaca bersamaan:

1. **Penyatuan mesh tubuh memangkas 73% draw call tanpa mengubah satu pun
   piksel.** Jumlah segitiganya identik sampai angka terakhir — itu buktinya
   tidak ada yang dibuang. Yang hilang hanya delapan panggilan GPU per aktor
   (KayKit memecah tubuh jadi 7–9 mesh bermaterial sama). Sisi Godot melakukan
   hal yang sama di `CharacterPool._merge_body`, dan `tests/smoke.tscn`
   memverifikasi 1 mesh per aktor dengan jumlah segitiga yang cocok dengan
   berkas pack.
2. **184 masih empat kali anggaran lama, dan anggaran lama itu memang sudah
   mati.** Ia ditulis untuk kapsul dan kubus. Satu aktor sekarang = 1 draw call
   tubuh + 1–2 senjata (senjata punya atlas sendiri, jadi tidak bisa ikut
   digabung tanpa mengedit tekstur pack — dan itu dilarang).

Batas kerja yang menggantikannya, sampai ada pengukuran di perangkat asli:

| Besaran | Batas baru | Alasan |
| --- | --- | --- |
| Draw call | **≤ 200** | terukur 184 pada gelombang terpadat |
| Segitiga | **≤ 700k** | terukur 652k; ini angka yang paling berisiko |
| Pengikatan tekstur | **≤ 40** | satu atlas per karakter, satu per senjata |

Tuas yang belum ditarik, berurutan dari yang paling murah:

1. Musuh di luar anggaran skinning digambar sebagai `InstancedMesh` ber-pose
   beku (satu draw call per peran, bukan per musuh) → taksiran ±60 draw call.
2. Pita terjauh (> 26 unit) kembali ke kapsul seperti jalur MultiMesh Godot →
   memangkas draw call **dan** segitiga, dengan harga siluet.
3. Turunkan `SKIN.enemies` / `BUDGET.enemies` dari 24.

Belum satu pun diambil karena keduanya menukar tampilan dengan angka, dan
angkanya belum pernah diuji di Snapdragon 660 sungguhan.

---

### Anggaran karakter ber-tulang (v1.0)

Skinning adalah biaya baru yang tidak ada di v0.5, dan biayanya per-unit, bukan
per-draw-call: setiap unit ber-skeleton berarti satu set pose yang dihitung
ulang tiap frame. Batas keras, sama di web dan Godot (lihat [docs 16](16-characters.md)):

| Hal | Batas | Alasan |
|---|---|---|
| Prajurit ber-tulang | 10 barisan depan | sisanya tertutup punggung teman sendiri |
| Musuh ber-tulang | 24 terdekat (urut `z`) | musuh di ujung lorong tingginya dua piksel |
| Mayat | 8 sekaligus, umur 1,5 s | efek, bukan kuburan |
| Bos | 1 (selalu) | satu-satunya yang ditatap lama |
| **Total skeleton aktif** | **≈ 35** (terukur 34) | sisanya MultiMesh (Godot) / salinan beku (web) |

- [ ] Aktor yang tidak dipinjam frame ini **disembunyikan DAN mixer-nya
      dihentikan** — skeleton tak terlihat tidak boleh ikut dibayar.
- [ ] Mesh ber-rig memakai `frustumCulled = false` (bounding box-nya masih bind
      pose), jadi culling-nya diurus oleh anggaran LOD di atas, bukan oleh GPU.

---

## 8.2 Pooling

- [ ] **Nol `Instantiate` / `Destroy` setelah loading.** Verifikasi: Profiler → `GC.Alloc` harus 0 B/frame selama gameplay.
- [ ] Musuh: pool **500** slot (`EnemyData[]`), bukan GameObject. Pool habis → spawn **ditolak**, bukan alokasi baru.
- [ ] Peluru: pool 16 `BulletController` + 16 `BulletView`.
- [ ] Partikel: pool per tipe FX (lihat `docs/05-prefab-spec.md` §5.5).
- [ ] Floating text: pool 32; saat penuh → **agregasi** jadi satu popup, bukan pool membesar.
- [ ] Audio: 8 voice tetap, dengan pencurian berbasis prioritas.
- [ ] `TrailRenderer.Clear()` wajib saat peluru di-reuse (bug garis panjang).
- [ ] `PoolRegistry.HighWaterMark` dipantau di `PerfHud`. Kalau HWM = kapasitas, pool kekecilan.

## 8.3 Rendering & Batching

- [ ] **GPU Instancing ON** pada semua material musuh. 1 material per tipe → maksimum 6 batch untuk 200 musuh.
- [ ] `Graphics.DrawMeshInstanced`, bukan `Transform` per musuh. Batas 1023 per panggilan — sudah ditangani `FlushBatch`.
- [ ] `MaterialPropertyBlock` untuk semua perubahan warna. **Dilarang** `renderer.material` (membuat instance + GC).
- [ ] SRP Batcher ON; shader memakai `CBUFFER` yang kompatibel.
- [ ] Static batching untuk lantai, dinding, pilar (`Static` flag ON).
- [ ] Target draw call: **≤ 45**. SetPass call: **≤ 20**.
- [x] **Potongan tubuh KayKit disatukan di memori, bukan di berkas.** Pack
      memecah tiap karakter jadi 7–9 mesh (lengan, kepala, helm, jubah…) yang
      memakai satu material dan satu skin. Renderer menyambung atributnya jadi
      satu mesh saat berkas dimuat — `mergeBody()` di `js/render3d.js`,
      `_merge_body()` di `character_pool.gd`. Lossless (jumlah segitiga dan
      verteks sama persis, diperiksa `rig_test.js` dan `smoke.tscn`), dan
      terukur 694 → 184 draw call. Versi lama menggabungkannya dengan menulis
      ulang GLB-nya; itu ditolak karena yang ikut berubah adalah karakternya.
- [ ] **Senjata masih draw call sendiri.** Tiap senjata membawa atlas-nya
      sendiri, jadi 1–2 panggilan tambahan per aktor. Menggabungnya menuntut
      penggabungan atlas — mengedit tekstur pack, dilarang.
- [x] **Satu tekstur per karakter, lima atlas untuk delapan peran.** Atlas
      1024² KayKit ditanam ke GLB apa adanya (PNG 12–15 KB masing-masing,
      karena isinya petak gradien yang kompres nyaris sempurna). Knight dipakai
      ulang oleh `trooper`/`shielder`/`boss`, jadi lima atlas menutupi delapan
      peran dan GPU hanya perlu lima pengikatan tekstur untuk seluruh cast.
      Versi sebelumnya memanggang atlas jadi `COLOR_0` (nol tekstur), tapi itu
      membuang detail yang tidak bisa diwakili satu warna per verteks — lihat
      docs/16 §2b. Tekstur sekarang wajib ikut; biayanya murah, kerusakan
      visualnya tidak.
- [ ] Atlas tekstur tunggal 2048² untuk semua UI.
- [ ] Shader musuh: **unlit/simple-lit**, tanpa normal map, tanpa tangent.
- [ ] Animasi jalan musuh lewat **vertex shader** (sin wave), bukan Animator. 200 Animator = mustahil.

## 8.4 LOD & Culling

- [ ] LOD musuh: `< 26 u` = mesh penuh, `≥ 26 u` = billboard 2 tris.
- [x] **Dua tingkat karakter, satu sumber, tanpa desimasi.** Dekat: karakter
      pack ber-tulang 5,8k–8,9k tris dengan mixer penuh. Jauh (web): karakter
      yang **sama persis**, pose siaga dihitung sekali lalu skeleton-nya tidak
      pernah maju lagi — nol biaya animasi, geometri dan tekstur utuh. Jauh
      (Godot): masih kapsul MultiMesh. Model LOD hasil desimasi sudah tidak
      ada lagi di repo: ia merusak wajah dan menyeberangi batas petak atlas.
- [ ] **Risiko terbuka nomor satu: segitiga, bukan draw call.** Terukur
      **652k segitiga** pada gelombang terpadat (74 musuh digambar sebagai
      karakter penuh di web). Shader-nya tetap Lambert satu tekstur tanpa
      normal map, tapi 652k × 60 fps = 39 juta segitiga per detik, dan itu
      belum pernah diuji di Snapdragon 660. Kalau meleset, tuas pertama:
      kembalikan pita terjauh ke kapsul (jalur yang sudah dipakai Godot),
      lalu turunkan `SKIN.enemies` dari 24.
- [ ] Occlusion culling ON untuk obstacle besar (pilar), OFF untuk crowd (semuanya terlihat).
- [ ] Frustum culling manual di `RenderCrowd` — musuh di luar frustum tidak masuk batch.
- [ ] `Camera.farClipPlane = 60` (arena hanya 40 unit).
- [ ] Shadow distance = 25, **hanya player + boss** yang cast shadow, resolusi 512, cascade **1**.
- [ ] Crowd memakai **blob shadow** (quad di-batch), bukan shadow map.
- [ ] Reflection: planar RT ¼ resolusi, **hanya tier device ≥ mid**; tier low memakai fake gradient.

## 8.5 CPU & Memori

- [ ] Spatial grid dibangun dengan **counting sort dua lintasan** — array biasa, nol alokasi. Tidak ada `List`/`Dictionary` di hot path.
- [ ] Grid dibangun **sekali per tick**, dipakai dua konsumen (peluru + separation).
- [ ] Separation memeriksa **9 cell**, bukan seluruh crowd. O(n·k), k ≈ 6.
- [ ] Semua struct data blittable (siap `NativeArray` + Burst tanpa rewrite).
- [ ] Event payload = `readonly struct`. Tidak ada boxing, tidak ada closure yang menangkap variabel.
- [ ] Tidak ada `foreach` pada `Dictionary` di hot path (alokasi enumerator + urutan tak dijamin).
- [ ] String: `StringBuilder` + `TMP_Text.SetText(sb)`. **Dilarang** `"Score: " + score` di `Update`.
- [ ] UI diperbarui **saat event**, bukan tiap frame.
- [ ] Canvas dipecah: `Canvas_Static` (skor/HP) vs `Canvas_Dynamic` (floating text).
- [ ] `Application.targetFrameRate = 60`, `vSyncCount = 0`.
- [ ] Script Execution Order eksplisit; sistem simulasi di-drive manual oleh `ArenaManager`.

## 8.6 Partikel & VFX

- [ ] **Hard cap 200 partikel aktif.** `VfxBudget` menolak spawn saat penuh.
- [ ] Prioritas saat penuh: `Bounce > Kill > Explosion > Milestone > Ambient`.
- [ ] Semua ParticleSystem: `Stop Action = Disable`, `Culling Mode = Pause and Catch-up`.
- [ ] **Dimatikan:** module Collision, Trails, Lights, Sub Emitters (kecuali chain explosion).
- [ ] Satu material additive untuk semua partikel (1 atlas) → 1 draw call.
- [ ] Kill pop memakai **kombinasi** partikel + flash quad, bukan 20 partikel.

## 8.7 Post-Processing

- [ ] Hanya **2 Volume Profile** (`VP_Normal`, `VP_BulletTime`), di-blend lewat `weight` — bukan mengubah parameter per frame (memicu rebuild stack + alokasi).
- [ ] Bloom: `High Quality Filtering OFF`, downscale ½.
- [ ] Chromatic aberration **hanya** saat bullet time.
- [ ] Motion Blur, Depth of Field, SSAO, Screen Space Reflections: **OFF** permanen.
- [ ] Render scale: 1.0 (tier high), 0.85 (mid), 0.7 (low) — diatur oleh deteksi tier device.
- [ ] MSAA: 2× (tier high/mid), OFF (low). Bukan 4×.

## 8.8 Aset & Build Size

- [ ] Mesh: `Read/Write OFF`, `Mesh Compression = Medium`, tangent `None`.
- [ ] Tekstur: ASTC 6×6, crunch compression, mipmap OFF untuk UI.
- [ ] Audio SFX: mono 22 kHz ADPCM; musik Vorbis q70 streaming. Total audio < 12 MB.
- [ ] Font: **satu** SDF atlas.
- [ ] Managed stripping: `Medium`, IL2CPP, `.NET Standard 2.1`.
- [ ] Hapus paket tak terpakai dari `manifest.json` (Timeline, Cinemachine kalau tidak dipakai, TextMeshPro examples).
- [ ] Satu scene gameplay untuk **5 varian** — varian dibangun runtime dari `VariantSO`.
- [ ] Target build: **< 100 MB** (Android AAB), **< 120 MB** (iOS IPA).
- [x] Build web Godot 4.6.2 (nothreads): **41,5 MB di disk / 14,3 MB gzip** —
      `index.wasm` 35,9 MB (9,0 MB gzip) mendominasi, `index.pck` 5,2 MB. Angka
      ini dilaporkan tiap kali `python3 tools/export_web.py` dijalankan, jadi
      pertumbuhannya ketahuan sebelum pemain yang menanggungnya.

## 8.9 Tier Device

| Tier | Contoh | Render scale | MSAA | Shadow | Reflection | Partikel cap |
|---|---|---|---|---|---|---|
| High | SD 8xx, A14+ | 1.00 | 2× | ON | planar ¼ | 200 |
| Mid | SD 660–7xx, A11 | 0.85 | 2× | ON (512) | fake gradient | 150 |
| Low | SD 4xx, RAM ≤ 3 GB | 0.70 | OFF | OFF | fake gradient | 80 |

Deteksi tier di boot: `SystemInfo.graphicsDeviceName` + `systemMemorySize` + benchmark 60 frame pertama. Tier boleh **turun** saat runtime kalau rata-rata frame > 20 ms selama 3 detik, tetapi **tidak pernah naik** (mencegah osilasi).

---

## 8.10 Tiga Jebakan Terbesar di Game Ini

1. **Crowd sebagai GameObject.** 200 `Update()` + 200 `Transform` write = 8–12 ms. Ini sendirian menghabiskan seluruh budget. → array struct + instancing.
2. **Mengubah parameter post-processing per frame.** Setiap penulisan ke `VolumeComponent` memicu rebuild + alokasi. → blend `weight` dua profile.
3. **Audio tanpa cooldown.** 200 kill = 200 `PlayOneShot` = voice starvation + spike audio thread. → cooldown 0.04 s + voice pool 8 + prioritas.

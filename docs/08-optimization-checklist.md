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
| Render — draw call GPU | **5.0 ms** | ≤ 45 draw call |
| Post-processing | **2.5 ms** | bloom + vignette (+ CA hanya saat slow-mo) |
| UI | **1.0 ms** | canvas rebuild terpisah |
| Audio | **0.6 ms** | 8 voice |
| Partikel | **1.0 ms** | ≤ 200 partikel aktif |
| **Headroom** | **0.8 ms** | cadangan untuk hitch OS |

> Kalau satu blok melewati budget, blok lain **tidak** boleh "meminjam". Yang dipotong adalah fitur, bukan frame rate.

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
- [ ] Atlas tekstur tunggal 2048² untuk semua UI.
- [ ] Shader musuh: **unlit/simple-lit**, tanpa normal map, tanpa tangent.
- [ ] Animasi jalan musuh lewat **vertex shader** (sin wave), bukan Animator. 200 Animator = mustahil.

## 8.4 LOD & Culling

- [ ] LOD musuh: `< 26 u` = mesh penuh, `≥ 26 u` = billboard 2 tris.
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

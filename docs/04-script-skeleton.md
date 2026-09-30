# 4. Script Skeleton — Peta Kode & Keputusan Teknis

Seluruh kode ada di `unity/Assets/ChainRider/Scripts/`. Dokumen ini menjelaskan **kenapa** kode ditulis seperti itu; detail implementasinya ada di komentar tiap file.

---

## 4.1 Lima Script Inti (yang diminta)

| File | Lokasi | Peran |
|---|---|---|
| `BulletController.cs` | `Scripts/Bullet/` | Ricochet, steer, bullet-riding, pemicu slow-mo |
| `CrowdManager.cs` | `Scripts/Crowd/` | Spawn, formasi, movement, separation, damage, spatial grid |
| `ArenaManager.cs` | `Scripts/Core/` | Wave, win/lose, skor/combo, driver tick simulasi |
| `CameraRig.cs` | `Scripts/Camera/` | Follow, zoom FOV, shake, framing clamp |
| `SlowMoSystem.cs` | `Scripts/Time/` | timeScale, blend post-FX, audio ducking, prioritas request |

### Pendukung yang wajib ada agar lima file di atas berfungsi

| File | Alasan keberadaannya |
|---|---|
| `Core/SimClock.cs` | Fixed-step 60 Hz. Tanpa ini determinisme mustahil. |
| `Core/DeterministicRng.cs` | xorshift128 yang state-nya bisa di-serialize. `UnityEngine.Random` dilarang di jalur simulasi. |
| `Core/GameEvents.cs` | Event bus struct-only. Memutus coupling UI/Audio/VFX dari gameplay tanpa alokasi. |
| `Core/ArenaBounds.cs` | Dinding sebagai bidang analitik, bukan Collider. |
| `Bullet/RicochetSolver.cs` | Semua matematika pantulan. Static, tanpa state, bisa di-unit-test tanpa Unity. |
| `Bullet/BulletData.cs` | Struct blittable + 3 interface kontrak dunia (`IArenaQuery`, `IObstacleQuery`, `ICrowdQuery`). |
| `Bullet/BulletSystem.cs` | Pool peluru, amunisi, sinkronisasi view. |
| `Crowd/FormationBuilder.cs` | 5 formasi (rect/V/diamond/line/circle), fungsi murni. |
| `Obstacles/ObstacleField.cs` | Obstacle sebagai array data + sweep analitik + chain explosion. |
| `Input/InputRouter.cs` | Tap + swipe → `InputFrame` per tick (rekaman replay). |
| `Pooling/ObjectPool.cs` | Nol `Instantiate` setelah load. |
| `Debug/ReplayRecorder.cs` | Bukti determinisme: seed + input stream → run identik. |
| `Input/AimController.cs` | Turret penyapu + garis bidik. **Wajib**: tanpa sudut awal, peluru tidak pernah kena dinding samping (0.10 bounce/peluru). Lihat [doc 11](11-balance-and-deviations.md). |
| `Boss/BossController.cs` | Boss wave 5, satu pola per varian. Tanpa physics; boss adalah bumper raksasa yang perisainya menentukan apakah damage masuk. |

---

## 4.2 Enam Keputusan Teknis yang Menentukan Segalanya

### 1. Simulasi fixed-step 60 Hz, render bebas

```
Update()  →  scaled = unscaledDeltaTime × slowMo.TimeScale
          →  steps  = SimClock.Advance(scaled)        // 0..4 tick
          →  for each step: SimulateTick(1/60)
          →  render dengan interpolasi alpha
```

Slow-mo **tidak mengubah ukuran langkah**, hanya berapa banyak langkah yang dijalankan per detik nyata. Konsekuensinya: `timeScale 0.3` menghasilkan urutan tick yang persis sama, hanya dijalankan lebih jarang → **replay tetap akurat walaupun pemain memicu slow-mo**.

### 2. Peluru memakai sweep (continuous), bukan overlap

Pada kecepatan 37.5 u/s (150%) dan Δt = 1/60, peluru bergerak 0.625 unit per tick — lebih besar dari radiusnya (0.18). Deteksi berbasis overlap akan **menembus musuh dan dinding**. Karena itu setiap langkah memakai *swept circle test* (akar persamaan kuadrat), dan sisa jarak setelah pantulan dilanjutkan pada arah baru di tick yang sama.

```csharp
float remaining = Speed * dt;
while (remaining > 0 && resolves < 4) {
    sweep → hit? → pindah ke titik kontak, pantulkan, sisa jarak lanjut
}
```

### 3. Musuh biasa ditembus, musuh berarmor memantulkan

Spec menyebut peluru memantul dari musuh. Kalau diterapkan ke **semua** musuh, di crowd dengan spacing 0.8 unit peluru akan memantul setiap 0.02 detik dan 15 bounce habis seketika — pemain kehilangan kendali. Keputusan final:

| Tipe | Perilaku |
|---|---|
| Grunt, Runner, Splitter, Bomber | **Ditembus** — kena damage penuh, bounce tidak berkurang |
| Brute | **Memantulkan** — konsumsi 1 bounce, +combo, armor menyerap 50% damage |
| Shielder | **Memantulkan hanya dari depan**; dari samping/belakang ditembus |

Efeknya: menembus crowd terasa seperti membelah kerumunan, dan musuh berarmor menjadi **bumper hidup** yang aktif dicari pemain untuk menyambung combo.

### 4. Crowd = array struct + GPU instancing, bukan GameObject

200 musuh sebagai MonoBehaviour berarti 200 `Update()`, 200 penulisan `Transform`, dan cache miss di mana-mana. Di sini musuh adalah entri `EnemyData[]`; broadphase memakai **uniform spatial grid** (cell 1.0 unit) yang dibangun dengan *counting sort* dua lintasan — nol alokasi. Grid yang sama dipakai dua konsumen: tabrakan peluru **dan** separation boids. Render lewat `Graphics.DrawMeshInstanced` (1 draw call per 1023 musuh per tipe).

Separation menjadi **O(n·k)** dengan k ≈ 6, bukan O(n²). Inilah yang membuat 200 musuh muat di Snapdragon 660.

### 5. Satu pemilik waktu

Hanya `SlowMoSystem` yang boleh menulis `Time.timeScale`. Sistem lain mengirim *intent* lewat `GameEvents.RaiseSlowMo`. `SlowMoSystem` menyelesaikan konflik dengan aturan: **permintaan paling lambat menang**, dan permintaan "kembali normal" hanya diterima dari sumber yang sedang memegang state. Tanpa aturan ini, ledakan barrel akan mematikan bullet time yang sedang berjalan.

Semua transisi kamera/FOV/post-FX memakai **unscaled time** — kalau tidak, transisi masuk slow-mo ikut melambat 0.3× dan terasa seperti hang, bukan sinematik.

### 6. Gravity well memutar arah, bukan menambah velocity

Menambahkan gaya ke velocity akan melanggar cap kecepatan 150% dan membuat lintasan tak terkendali. Implementasinya memutar vektor arah menuju pusat well dengan batas `maxCurveDegPerSec = 120` dan falloff linear. Hasilnya lintasan melengkung yang indah **tanpa** merusak budget kecepatan.

---

## 4.3 Kontrak Antar Sistem

```text
                     ┌──────────────────┐
                     │   ArenaManager   │  driver tunggal
                     └────────┬─────────┘
             ┌────────────────┼────────────────┬──────────────┐
             ▼                ▼                ▼              ▼
      InputRouter      ObstacleField     CrowdManager    BulletSystem
             │                │                │              │
             │      IObstacleQuery      ICrowdQuery           │
             │                └────────┬───────┘              │
             │                         ▼                      │
             └────────────────► BulletController ◄────────────┘
                                       │
                                  GameEvents (struct)
                                       │
          ┌──────────────┬─────────────┼─────────────┬────────────────┐
          ▼              ▼             ▼             ▼                ▼
    HudController   AudioDirector   CameraRig   SlowMoSystem      VfxBudget
```

`BulletController` **tidak tahu** apa itu MonoBehaviour, Collider, atau Scene. Ia hanya bertanya ke tiga interface. Karena itu ia bisa diuji headless:

```csharp
[Test]
public void Bullet_ReflectsSymmetrically_OnSideWall() {
    var bullet = new BulletController(cfg, slowCfg, new FakeArena(), new NullObstacles(), new NullCrowd());
    bullet.Fire(1, new Vector3(0, 0, 10), new Vector3(1, 0, 1).normalized);
    for (int i = 0; i < 120; i++) bullet.Tick(1f / 60f);
    Assert.AreEqual(1, bullet.Data.BounceCount);
    Assert.That(bullet.Data.Direction.x, Is.LessThan(0));   // sudah membalik arah
}
```

---

## 4.4 Urutan Satu Tick (wajib dipertahankan)

```csharp
private void SimulateTick(float dt) {
    _input.ConsumeTick(_clock.Tick);      // 1. input tick ini (live atau replay)
    _aim.Tick(dt);                        // 2. sapuan turret (deterministik)
    _obstacleField.Tick(dt, _clock.Time); // 3. platform bergerak, chain explosion
    _crowd.Tick(dt, _clock.Time);         // 4. gerak musuh + REBUILD spatial grid
    _boss?.Tick(dt, ref _rng);            // 5. boss bergerak SEBELUM sweep peluru
    _bullets.Tick(dt);                    // 6. sweep peluru (baca grid yang fresh)
    TickWaveLogic(dt);                    // 7. timer wave, menang/kalah
    _clock.CommitTick();                  // 8. tick++
}
```

Crowd **harus** sebelum bullet: peluru membaca spatial grid, dan grid yang basi menyebabkan peluru menembus musuh yang sudah bergeser. Alasan yang sama berlaku untuk boss — kalau boss bergerak setelah sweep, peluru menabrak posisi boss yang basi.

`AimController.Tick` harus di dalam `SimulateTick`, **bukan** di `Update()`. Sudut turret ikut menentukan arah tembak, jadi ia bagian dari state simulasi; memajukannya dari render akan merusak replay.

---

## 4.5 Larangan Keras (code review akan menolak)

| Larangan | Alasan |
|---|---|
| `UnityEngine.Random` di jalur simulasi | Merusak determinisme. Pakai `DeterministicRng`. |
| `Time.deltaTime` di jalur simulasi | Pakai `SimClock.FixedDelta`. |
| `Time.time` untuk logika | Pakai `SimClock.Time`. |
| `renderer.material` | Membuat instance material + GC. Pakai `MaterialPropertyBlock`. |
| `Instantiate` / `Destroy` setelah load | Pakai `ObjectPool`. |
| `GetComponent` di dalam loop per-frame | Cache di `Awake`. |
| `Physics.*` untuk ricochet | Non-deterministik lintas platform. Pakai `RicochetSolver`. |
| `foreach` pada `Dictionary` di hot path | Urutan iterasi tidak dijamin → non-determinisme. |
| `string` concat di `Update` | Alokasi → GC spike. Pakai `StringBuilder` + `SetText`. |
| Static event tanpa `ClearAll()` saat keluar scene | Memory leak + NullReference. |

---

## 4.6 Jalur Migrasi ke DOTS/ECS

Semua struct sudah blittable, jadi migrasi bersifat mekanis:

| Sekarang | Setelah migrasi |
|---|---|
| `EnemyData[]` | `NativeArray<EnemyData>` |
| `MoveEnemies()` loop | `IJobParallelFor` + `[BurstCompile]` |
| `BuildSpatialGrid()` counting sort | `NativeMultiHashMap` atau job counting sort |
| `Graphics.DrawMeshInstanced` | `BatchRendererGroup` / Entities Graphics |
| `BulletController` (POCO) | `ISystem` + `BulletData` sebagai `IComponentData` |

Titik migrasi sudah ditandai `// DOTS:` di `CrowdManager.cs`. Ambang keputusan: **jalankan profiler di device target dulu**. Kalau 200 musuh sudah 60 FPS tanpa DOTS (dan skeleton ini dirancang untuk itu), migrasi ditunda sampai target naik ke 500+ musuh.

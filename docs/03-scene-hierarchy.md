# 3. Scene Hierarchy & Struktur Proyek — CHAIN RIDER

Target utama: **Unity 2022 LTS + URP + (opsional) DOTS/ECS untuk crowd**.
Bagian 3.6 memuat padanan struktur untuk **Godot 4**.

---

## 3.1 Struktur Folder Proyek

```text
Assets/ChainRider/
├── Art/
│   ├── Materials/          M_Enemy_Grunt, M_Wall_Bumper, M_Floor, M_Bullet ...
│   ├── Meshes/             LowPoly: enemy_grunt (180 tris) ... pillar, barrel
│   ├── Shaders/            SG_NeonGrid, SG_RimEnemy, SG_FakeReflection
│   ├── VFX/                PS_Bounce, PS_Kill, PS_Explosion, PS_Confetti
│   └── UI/                 Atlas_HUD (2048²), Font_Display (SDF)
├── Audio/
│   ├── SFX/                shot, bounce_01..08, kill, combo, explosion, heartbeat
│   ├── Music/              mus_base_120bpm.ogg + 5 layer varian
│   └── Mixer/              AM_Main (Master > Music > SFX > UI)
├── Config/
│   ├── ArenaConfig.asset           (ScriptableObject)
│   ├── BulletConfig.asset
│   ├── SpawnConfig.asset
│   ├── SlowMoConfig.asset
│   ├── Variants/           SO_Variant_ClassicPit ... SO_Variant_MovingMaze
│   └── arena_config.json           (source of truth, di-import ke SO)
├── Prefabs/
│   ├── Core/               Player, Bullet, ArenaRoot
│   ├── Enemies/            Enemy_Grunt, Runner, Brute, Shielder, Splitter, Bomber
│   ├── Bosses/             Boss_Colossus ... Boss_Shifter
│   ├── Obstacles/          Bumper, Pillar, Barrel, GravityWell, MovingPlatform, ShieldWall
│   ├── FX/                 FX_Bounce, FX_Kill, FX_Explosion, FX_MuzzleFlash
│   └── UI/                 FloatingText, ComboPopup, HUD_Canvas
├── Scenes/
│   ├── 00_Boot.unity       Bootstrap, load config, init pool, → Menu
│   ├── 01_Menu.unity       Main menu, pilih varian arena
│   ├── 02_Arena.unity      Scene gameplay (SATU scene untuk semua varian)
│   └── 99_Sandbox.unity    Scene test: determinisme, stress 200 musuh
└── Scripts/
    ├── Core/       ArenaManager, GameEvents, DeterministicRng, SimClock, ArenaBounds
    ├── Bullet/     BulletController, BulletSystem, RicochetSolver, BulletData
    ├── Crowd/      CrowdManager, FormationBuilder, EnemyView, EnemyData, BoidSeparation
    ├── Camera/     CameraRig, ShakeImpulse
    ├── Time/       SlowMoSystem
    ├── Obstacles/  ObstacleBase, Barrel, GravityWell, MovingPlatform, ShieldWall, Bumper
    ├── Pooling/    ObjectPool, PoolRegistry, IPoolable
    ├── UI/         HudController, FloatingTextSpawner, ComboPopup
    ├── Audio/      AudioDirector, SfxCue
    └── Config/     ArenaConfigSO, BulletConfigSO, SpawnConfigSO, VariantSO, ConfigImporter
```

---

## 3.2 Hierarchy Scene `02_Arena.unity`

```text
02_Arena
│
├── ── SYSTEMS ──────────────────────────────  (GameObject kosong, tidak bergerak)
│   ├── GameRoot                     [ArenaManager] [SimClock] [DeterministicRng]
│   │                                 └ menyimpan seed, frame counter, state machine
│   ├── TimeSystem                   [SlowMoSystem]
│   ├── BulletSystem                 [BulletSystem] [RicochetSolver(static, no MB)]
│   │   └── BulletPoolRoot           (parent instance peluru, 16 pre-warm)
│   ├── CrowdSystem                  [CrowdManager] [FormationBuilder] [BoidSeparation]
│   │   └── EnemyPoolRoot            (500 instance pre-warm, inactive)
│   ├── AudioDirector                [AudioDirector] + 8 AudioSource (pooled voices)
│   ├── VfxBudget                    [VfxBudget] + PoolRegistry untuk FX
│   └── InputRouter                  [InputRouter]  tap = fire/brake, swipe = steer
│
├── ── ARENA ────────────────────────────────  (di-build runtime dari VariantSO)
│   ├── ArenaRoot                    [ArenaBounds]  width 20, height 40
│   │   ├── Floor                    Mesh plane 20×40, M_Floor (neon grid)
│   │   │   └── ReflectionPlane      (tier ≥ mid only, RT 1/4 res)
│   │   ├── Wall_Left                BoxCollider trigger, layer=Wall, x=-10
│   │   ├── Wall_Right               BoxCollider trigger, layer=Wall, x=+10
│   │   ├── Wall_Top_SpawnGate       z=40, layer=Killzone
│   │   ├── Wall_Bottom              z=0,  layer=Killzone
│   │   ├── DefenseLine              z=5, LineRenderer cyan + [DefenseLineTrigger]
│   │   └── Obstacles                ← di-spawn oleh ArenaManager.BuildVariant()
│   │       ├── Bumper_L_01 .. R_02  [Bumper]
│   │       ├── Pillar_01 ..         [Pillar]
│   │       ├── Barrel_01 ..         [Barrel]
│   │       ├── GravityWell_01 ..    [GravityWell]
│   │       ├── MovingPlatform_01 .. [MovingPlatform]
│   │       └── ShieldWall_01 ..     [ShieldWall]
│   └── AmbientFX
│       ├── PS_DustAmbient           max 40 partikel, looping
│       └── PS_GridPulse             pulse sinkron BPM 120
│
├── ── ACTORS ───────────────────────────────
│   ├── Player                       pos (0, 0, 2)  [PlayerRig] [PlayerHealth]
│   │   ├── Mesh_Body                M_Player, cast shadow ON
│   │   ├── Muzzle                   pos (0, 0.6, 0.8) — origin spawn peluru
│   │   ├── Light_PlayerGlow         Point, cyan, range 6
│   │   └── AimIndicator             LineRenderer prediksi 2 bounce pertama
│   └── BossSlot                     kosong; boss di-spawn saat wave 5
│
├── ── CAMERA ───────────────────────────────
│   ├── Main Camera                  [Camera] [CameraRig] [UniversalAdditionalCameraData]
│   │   └── Volume_PostFX            [Volume] blend VP_Normal ↔ VP_BulletTime
│   └── CM_Target                    dummy transform yang di-lerp CameraRig
│       (Cinemachine opsional: CM_vcam_Gameplay + CM_vcam_BulletTime + Impulse Source)
│
├── ── LIGHTING ─────────────────────────────
│   ├── Light_Key                    Directional, shadow ON (hanya player+boss layer)
│   ├── Light_EnemyRim               Directional, culling mask = Enemy, shadow OFF
│   └── ReflectionProbe_Static       baked, 1 buah, cukup untuk arena kotak
│
└── ── UI ───────────────────────────────────
    └── HUD_Canvas                   Screen Space - Overlay, CanvasScaler 1080×1920
        ├── SafeArea                 [SafeAreaFitter]
        │   ├── TopBar               Score, ComboMultiplier, WaveCounter
        │   ├── CenterOverlay        ComboPopup, WarningBanner
        │   └── BottomBar            SteerMeter, AmmoIcons, HeartsHP, BrakeButton
        ├── FloatingTextRoot         pool 32 item, world→screen
        └── ScreenFX                 flash image, damage vignette (Image, alpha driven)
```

### Catatan penting hierarchy

- **Semua sistem berada di root, tidak bersarang.** Menghindari `GetComponentInParent` di hot path.
- **Musuh TIDAK memiliki Collider maupun Rigidbody.** Deteksi tabrakan peluru↔musuh dilakukan manual di `BulletSystem` melalui **uniform spatial grid** milik `CrowdManager`. Collider hanya dipakai untuk dinding & obstacle statis (dan itu pun opsional; `RicochetSolver` memakai bidang analitik).
- **`ArenaRoot/Obstacles` dibangun saat runtime** dari `VariantSO` agar satu scene melayani 5 varian → build size & waktu load lebih kecil.
- **Layer**: `Player(8)`, `Bullet(9)`, `Enemy(10)`, `Wall(11)`, `Bumper(12)`, `Obstacle(13)`, `Killzone(14)`, `FX(15)`. Collision matrix: Bullet × {Wall, Bumper, Obstacle, Killzone} saja.

---

## 3.3 Daftar Script (44 file inti)

| Folder | Script | Tanggung jawab |
|---|---|---|
| Core | `ArenaManager.cs` | State machine run, wave, win/lose, build varian, event bus |
| Core | `GameEvents.cs` | Static event bus tanpa alokasi (`Action<T>` pre-bound) |
| Core | `DeterministicRng.cs` | xorshift128, seed per-run, serializable state |
| Core | `SimClock.cs` | Fixed-step accumulator, frame index, replay tick |
| Core | `ArenaBounds.cs` | Bidang dinding analitik, query zona, clamp |
| Core | `RunResult.cs` | Skor akhir, koin, statistik run |
| Bullet | `BulletController.cs` | **Inti**: ricochet, steer, bullet-riding, slow-mo trigger |
| Bullet | `BulletSystem.cs` | Update semua peluru aktif, pooling, broadphase |
| Bullet | `RicochetSolver.cs` | Matematika murni: reflect, sweep vs circle/plane, TOI |
| Bullet | `BulletData.cs` | `struct` data peluru (blittable, siap di-ECS-kan) |
| Bullet | `BulletTrail.cs` | Manajemen TrailRenderer, max 20 titik, reset saat pooled |
| Crowd | `CrowdManager.cs` | **Inti**: spawn, formasi, gerak, separation, damage, spatial grid |
| Crowd | `FormationBuilder.cs` | rect / vshape / diamond / line / circle → posisi offset |
| Crowd | `EnemyData.cs` | `struct` musuh (pos, hp, type, flags) dalam `NativeArray`/array |
| Crowd | `EnemyView.cs` | Jembatan data→Transform/instancing, LOD switch |
| Crowd | `BoidSeparation.cs` | Separation + alignment + cohesion ringan, grid-accelerated |
| Crowd | `EnemyTypeTable.cs` | Statistik 6 tipe musuh dari config |
| Crowd | `BossController.cs` | Pola gerak boss per varian |
| Camera | `CameraRig.cs` | **Inti**: follow, zoom FOV, shake, framing clamp |
| Camera | `ShakeImpulse.cs` | Perlin shake berbasis amplitude/frequency/duration |
| Time | `SlowMoSystem.cs` | **Inti**: timeScale, fixedDeltaTime, blend post-FX, audio duck |
| Obstacles | `ObstacleBase.cs` | Interface `IBulletReflector`, `IBulletDamageable` |
| Obstacles | `Bumper.cs` / `Pillar.cs` | Restitution, bonus damage, flash MPB |
| Obstacles | `Barrel.cs` | HP 1, overlap sphere + falloff, chain delay 0.08s |
| Obstacles | `GravityWell.cs` | Attraction force per substep terhadap velocity peluru |
| Obstacles | `MovingPlatform.cs` | Ping-pong deterministik berbasis `SimClock.Time` |
| Obstacles | `ShieldWall.cs` | Dot product arah datang → tembus atau pantul |
| Pooling | `ObjectPool.cs` | Pool generik tanpa alokasi, pre-warm, `IPoolable` |
| Pooling | `PoolRegistry.cs` | Registry semua pool, statistik high-water mark |
| UI | `HudController.cs` | Bind event bus → UI, string caching (no `ToString()` per frame) |
| UI | `FloatingTextSpawner.cs` | Pool 32 teks, world→screen, curve naik + fade |
| UI | `ComboPopup.cs` | Animasi milestone combo |
| UI | `SafeAreaFitter.cs` | Notch handling |
| Audio | `AudioDirector.cs` | Cue table, voice limiting, pitch ladder bounce, ducking |
| Audio | `SfxCue.cs` | SO: clip, volume, pitch range, priority, cooldown |
| Config | `*ConfigSO.cs` | ScriptableObject mirror dari JSON |
| Config | `ConfigImporter.cs` | Editor tool: `arena_config.json` → semua `.asset` |
| Input | `InputRouter.cs` | Tap → fire/brake, swipe horizontal → steer, dead zone |
| Debug | `ReplayRecorder.cs` | Rekam seed + input stream, replay verifikasi determinisme |
| Debug | `PerfHud.cs` | FPS, ms/frame, GC alloc, jumlah musuh/peluru aktif |

---

## 3.4 Urutan Eksekusi (Script Execution Order)

Determinisme mensyaratkan urutan update yang **tetap**:

```text
-200  SimClock          → advance fixed-step accumulator, tentukan jumlah substep
-150  InputRouter       → sample input, buffer ke SimClock tick saat ini
-100  SlowMoSystem      → set timeScale & fixedDeltaTime SEBELUM simulasi
 -50  CrowdManager      → gerak musuh + rebuild spatial grid
   0  BulletSystem      → sweep peluru (baca grid yang sudah fresh)
  50  Obstacles         → moving platform, gravity well (pakai SimClock.Time)
 100  CameraRig         → LateUpdate-like, follow target yang sudah final
 150  HudController     → baca state, render UI
 200  AudioDirector     → flush cue queue frame ini
```

Semua simulasi gameplay berjalan di **`SimClock.Tick()` (fixed 1/60 s)**, bukan di `Update()`. `Update()` hanya untuk interpolasi visual & UI.

---

## 3.5 Prefab Variant & Data Flow

```text
arena_config.json
      │  (ConfigImporter, editor-time)
      ▼
ArenaConfigSO ── BulletConfigSO ── SpawnConfigSO ── SlowMoConfigSO
      │                │                │                │
      └────────────────┴────────┬───────┴────────────────┘
                                ▼
                         ArenaManager.Boot(seed, variantId)
                                │
          ┌─────────────────────┼─────────────────────┐
          ▼                     ▼                     ▼
   BuildVariant()        CrowdManager.Init()   BulletSystem.Init()
   (spawn obstacle,      (pre-warm 500,        (pre-warm 16 peluru)
    set tema warna,       set tabel musuh)
    swap music layer)
```

---

## 3.6 Padanan Godot 4

```text
Arena.tscn (Node3D)
├── Systems (Node)
│   ├── ArenaManager      (Node, arena_manager.gd)
│   ├── SimClock          (Node, _physics_process fixed 60 Hz)
│   ├── SlowMoSystem      (Node, Engine.time_scale)
│   ├── BulletSystem      (Node3D)  → MultiMeshInstance3D untuk trail pooling
│   ├── CrowdSystem       (Node3D)  → MultiMeshInstance3D (1 per tipe musuh)
│   └── AudioDirector     (Node, 8 × AudioStreamPlayer)
├── Arena (Node3D)
│   ├── Floor             (MeshInstance3D + ShaderMaterial grid)
│   ├── Walls             (4 × Area3D, monitoring off — hanya data bidang)
│   ├── DefenseLine       (MeshInstance3D + Area3D)
│   └── Obstacles         (di-instance runtime dari Resource varian)
├── Player                (Node3D + OmniLight3D)
├── CameraRig             (Node3D → Camera3D, script camera_rig.gd)
├── WorldEnvironment      (glow on, ssao off, fog off)
└── HUD                   (CanvasLayer → Control, anchors portrait)
```

| Unity | Godot 4 |
|---|---|
| ScriptableObject | `Resource` (`.tres`) |
| `Time.timeScale` | `Engine.time_scale` |
| GPU Instancing | `MultiMeshInstance3D` |
| DOTS/ECS | `GDExtension` C++ atau `Server`-level API (`RenderingServer.multimesh_set_buffer`) |
| Cinemachine | script `camera_rig.gd` manual (sudah disediakan pola yang sama) |
| URP Volume | `WorldEnvironment` + `CameraAttributes`, blend manual |
| Object pooling | Node pooling manual (`remove_child` + reuse), hindari `queue_free` per kill |

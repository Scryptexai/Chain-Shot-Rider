# 5. Prefab Spec — CHAIN RIDER

Konvensi nama: `P_` prefab gameplay, `FX_` efek, `UI_` antarmuka, `M_` material, `SM_` static mesh.
Budget tris adalah **anggaran keras** — aset yang melebihi ditolak di review.

---

## 5.1 Ringkasan Budget

| Kategori | Prefab | Tris | Material | Collider | Pool | Shadow |
|---|---|---|---|---|---|---|
| Actor | `P_Player` | 850 | 1 | — | 1 | **Cast + Receive** |
| Actor | `P_Bullet` | 60 | 1 (additive) | — | 16 | Off |
| Enemy | `P_Enemy_Grunt` | 180 | 1 (instanced) | — | 500 (shared) | Off |
| Enemy | `P_Enemy_Runner` | 190 | 1 | — | shared | Off |
| Enemy | `P_Enemy_Brute` | 290 | 1 | — | shared | Off |
| Enemy | `P_Enemy_Shielder` | 260 | 1 | — | shared | Off |
| Enemy | `P_Enemy_Splitter` | 240 | 1 | — | shared | Off |
| Enemy | `P_Enemy_Bomber` | 220 | 1 | — | shared | Off |
| Boss | `P_Boss_*` (5) | 2400 | 2 | — | 1 | **Cast** |
| Obstacle | `P_Bumper` | 120 | 1 | — | 8 | Off |
| Obstacle | `P_Pillar` | 220 | 1 | — | 4 | Receive |
| Obstacle | `P_Barrel` | 160 | 1 | — | 12 | Off |
| Obstacle | `P_GravityWell` | 40 + VFX | 1 (transparan) | — | 4 | Off |
| Obstacle | `P_MovingPlatform` | 100 | 1 | — | 4 | Receive |
| Obstacle | `P_ShieldWall` | 90 | 1 | — | 4 | Off |
| FX | `FX_*` | — | 1 (atlas) | — | lihat §5.5 | Off |
| UI | `UI_*` | — | atlas | — | lihat §5.6 | — |

> **Tidak ada satu pun Collider atau Rigidbody di seluruh daftar.** Tabrakan dihitung analitik di `RicochetSolver` + spatial grid `CrowdManager`.

---

## 5.2 Actor

### `P_Player`
```text
P_Player                    [PlayerRig] [PlayerHealth]
├── Mesh_Body               SM_PlayerTurret (850 tris), M_Player, cast+receive shadow
├── Mesh_Barrel             child, rotasi mengikuti arah bidik (visual saja)
├── Muzzle                  Transform kosong, local (0, 0.6, 0.8) ← origin peluru
├── Light_Glow              Point, #00E5FF, range 6, intensity 2, shadow OFF
├── FX_MuzzleFlash          ParticleSystem, stop action = Disable, 8 partikel
└── AimIndicator            LineRenderer, 8 titik, width 0.08, M_AimDots
                            diisi RicochetSolver.PredictWallPath (2 bounce)
```
| Properti | Nilai |
|---|---|
| Posisi dunia | `(0, 0, 2)` |
| Rotasi | menghadap `+Z`, tidak pernah berubah |
| Layer | `Player (8)` |
| Animasi | idle bob 0.05u @ 0.5 Hz + recoil punch saat menembak |

### `P_Bullet`
```text
P_Bullet                    [BulletView]
├── Mesh_Capsule            SM_BulletCapsule (60 tris), M_Bullet (unlit additive, ZWrite off)
├── TrailRenderer           time 0.35s, MAX 20 titik, width 0.22→0.02,
│                           gradient #FFFFFF → #00E5FF → transparan, M_Trail
├── Light_Bullet            Point, #00E5FF, range 4, intensity 3, shadow OFF
└── FX_Death                ParticleSystem, 6 partikel, autoplay off
```
> **Bug pooling paling umum:** `TrailRenderer` tidak di-`Clear()` saat reuse → muncul garis panjang dari posisi peluru sebelumnya. `BulletView.ResetTrail()` menanganinya. Wajib ada di test checklist.

---

## 5.3 Enemy (6 tipe)

Semua musuh **tidak di-instantiate sebagai GameObject saat gameplay**. Prefab di bawah hanya sumber **Mesh + Material** untuk `Graphics.DrawMeshInstanced`, dan referensi visual untuk artist.

| Tipe | HP | Speed | Tris | Warna | Perilaku peluru | Kematian | Skor |
|---|---|---|---|---|---|---|---|
| `Grunt` | 10 | 0.6 | 180 | `#FF4D3D` | ditembus | pop biasa | 10 |
| `Runner` | 6 | 1.1 | 190 | `#FF8A2B` | ditembus | pop cepat | 15 |
| `Brute` | 60 | 0.5 | 290 | `#C2341F` | **memantulkan**, armor −50% dmg | pop besar + shake | 50 |
| `Shielder` | 25 | 0.5 | 260 | `#FFC93C` | **memantulkan dari depan**, tembus dari samping/belakang | shield pecah dulu | 40 |
| `Splitter` | 20 | 0.5 | 240 | `#FF5FA2` | ditembus | pecah jadi 3 Grunt | 35 |
| `Bomber` | 12 | 0.7 | 220 | `#FFE04D` | ditembus | **meledak r=2.5, dmg 30** | 45 |

> **Kecepatan ini hasil balance pass terukur, bukan tebakan.** Nilai awal
> (1.2 / 2.2 / 0.6 / 0.9 / 1.0 / 1.4) membuat run berakhir rata-rata 55 detik —
> di bawah target sesi 1–3 menit — dan Runner 2.2 melanggar rentang spec
> 0.5–1.5 u/s. Setelah penyesuaian: durasi rata-rata **105 detik**, **29/30 run**
> masuk jendela 60–180 detik, wave 5 tercapai **30/30**. Detail di
> [`11-balance-and-deviations.md`](11-balance-and-deviations.md).

**Spesifikasi mesh musuh:**
- Satu sumbu simetri, siluet lebar-bahu agar terbaca di 20 px.
- Rig: **tanpa tulang**. Animasi "jalan" dilakukan lewat vertex shader (sin wave berbasis `_Time` + offset instance) — nol biaya CPU untuk 200 unit.
- LOD: `< 26 unit` = mesh penuh, `≥ 26 unit` = `SM_EnemyBillboard` (2 tris quad). Switch ditangani `CrowdManager.RenderCrowd`.
- Blob shadow: quad transparan di-batch, bukan shadow map.

### `P_Boss_*` (5 boss)
| Boss | Varian | HP | Pola | Titik lemah |
|---|---|---|---|---|
| `Colossus` | Classic Pit | 1200 | turun lambat, slam tiap 4 s | depan setelah slam |
| `Twin Warden` | Twin Towers | 900 ×2 | pasangan cermin, sidestep | keduanya harus mati dalam 3 detik |
| `Singularity` | Gravity Chamber | 1000 | orbit + pulse tarikan | inti terbuka saat pulse |
| `Pyro Baron` | Explosive Yard | 1100 | menjatuhkan barrel, charge | ledakan barrel sendiri |
| `Shifter` | Moving Maze | 1400 | teleport antar lajur | punggung (back_weak) |

---

## 5.4 Obstacle

### `P_Bumper` — pantulan presisi
```text
P_Bumper                    radius 0.9, restitution 0.95
├── Mesh_Puck               SM_BumperPuck (120 tris), M_Wall_Bumper
├── Ring_Emissive           quad additive, pulse saat bounce (MaterialPropertyBlock)
└── FX_BounceRing           ParticleSystem, 12 partikel, dipicu event
```

### `P_Pillar` — radius besar
`radius 1.5–2.4`, `restitution 0.98`. Menerima shadow (satu-satunya obstacle yang boleh), karena ia menjadi landmark spasial arena.

### `P_Barrel` — chain explosion
| Properti | Nilai |
|---|---|
| HP | 1 (mati dari satu sentuhan peluru) |
| Explosion radius | 3.0 |
| Explosion damage | 50 (falloff linear ke tepi) |
| Chain delay | 0.08 s per tingkat — agar terbaca sebagai **rantai**, bukan satu ledakan |
| Chain depth max | 8 |

### `P_GravityWell`
Radius 4, force 5, `maxCurveDegPerSec = 120`. Visual: torus transparan + partikel spiral ke dalam (max 20 partikel, looping) + distorsi grid lantai lewat shader (bukan post-process).

### `P_MovingPlatform`
Width 5, travel ±3, speed 1.8–2.5. **Menghalangi musuh, tidak memantulkan peluru** — kalau ia memantulkan peluru juga, pemain kehilangan satu-satunya cara menembus barisan tengah. Gerak ping-pong dihitung dari `SimClock.Time` (deterministik), bukan `Time.time`.

### `P_ShieldWall`
Width 3, HP 3, hanya rusak dari **belakang**. Dari depan ia memantulkan peluru tanpa menerima damage — memaksa pemain merancang lintasan memutar.

---

## 5.5 FX Prefab

| Prefab | Partikel | Durasi | Pool | Dipicu oleh |
|---|---|---|---|---|
| `FX_MuzzleFlash` | 8 | 0.12 s | 4 | `OnBulletFired` |
| `FX_BounceRing` | 12 | 0.20 s | 16 | `OnBounce` |
| `FX_KillPop` | 6 | 0.30 s | 48 | `OnEnemyKilled` |
| `FX_Explosion` | 30 | 0.45 s | 12 | `OnExplosion` |
| `FX_ChainSpark` | 10 | 0.25 s | 8 | chain depth > 0 |
| `FX_ComboBurst` | 24 | 0.50 s | 2 | combo milestone |
| `FX_Confetti` | 40 | 1.20 s | 1 | kill milestone |
| `FX_SlowMoRipple` | 10 | 0.20 s | 2 | masuk bullet time |
| `FX_PerfectSweep` | 16 | 0.80 s | 1 | perfect clear |
| `PS_DustAmbient` | 40 (loop) | ∞ | 1 | selalu |

**Aturan keras:** total partikel aktif ≤ **200**. `VfxBudget` menolak spawn baru saat cap tercapai, dengan prioritas `Bounce > Kill > Explosion > Milestone > Ambient`. Semua ParticleSystem: `Stop Action = Disable`, `Culling Mode = Pause and Catch-up`, **tanpa** Collision, **tanpa** Trails module, **tanpa** Lights module.

---

## 5.6 UI Prefab

| Prefab | Pool | Catatan |
|---|---|---|
| `UI_HUD_Canvas` | 1 | Screen Space Overlay, CanvasScaler `1080×1920`, match width |
| `UI_FloatingText` | 32 | TMP, `SetText("+{0}", n)` — nol alokasi string |
| `UI_ComboPopup` | 1 | Animasi kurva, bukan Animator |
| `UI_HeartIcon` | 3 | Sprite atlas |
| `UI_AmmoIcon` | 5 | Sprite atlas |
| `UI_SteerMeter` | 1 | `Image` filled horizontal |
| `UI_WarningBanner` | 1 | muncul saat musuh near-miss |

> Canvas dipecah dua: **`Canvas_Static`** (skor, HP, amunisi — jarang berubah) dan **`Canvas_Dynamic`** (floating text, combo popup). Satu elemen yang berubah akan me-rebuild **seluruh** canvas-nya; memisahkan keduanya menghemat rebuild besar setiap kill.

---

## 5.7 Checklist Import Aset

- [ ] Mesh: `Read/Write` **OFF**, `Optimize Mesh` ON, `Normals = Calculate`, `Tangents = None` (unlit tidak butuh)
- [ ] Mesh: `Mesh Compression = Medium`
- [ ] Texture: atlas 2048², `Crunch Compression`, ASTC 6×6 (Android) / ASTC 6×6 (iOS)
- [ ] Texture: `Mip Maps` OFF untuk UI, ON untuk mesh
- [ ] Audio: SFX `Decompress on Load` + `PCM`/`ADPCM` (pendek), Musik `Streaming` + `Vorbis q=70`
- [ ] Audio: semua SFX **mono** (arena kecil, panning tidak membantu; mono = separuh memori)
- [ ] Prefab: `Static` flag ON untuk floor & dinding (batching + occlusion)
- [ ] Material: `Enable GPU Instancing` ON untuk semua material musuh

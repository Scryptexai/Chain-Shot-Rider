# 2. Visual Style Guide — CHAIN RIDER  ⚠️ DEPRECATED

> **Dokumen ini sudah tidak berlaku sejak rombakan NEON (2026-10-05).**
>
> Arah visual fantasi di bawah — palet emas/lumut/batu, karakter KayKit
> sebagai benda paling terang, neon yang dikurangi — telah **dibuang total**
> atas keputusan desain. Arah yang berlaku sekarang ada di:
>
> * [`docs/17-keyart-neon-analysis.md`](17-keyart-neon-analysis.md) — palet,
>   kamera, dan spesifikasi efek, diturunkan dari key art
> * [`docs/18-neon-rebuild-roadmap.md`](18-neon-rebuild-roadmap.md) — rencana
>   dan status integrasinya
>
> Yang masih berguna di sini hanyalah prinsip produksinya (*readability beats
> beauty*, batas segitiga, aturan LOD). Setiap angka warna di bawah sudah
> salah.

![Referensi arena 2.5D](images/arena-2_5d-reference.png)

*Referensi 2.5D: kamera miring 40°, arena portrait, crowd merah di atas, player cyan di bawah, bumper magenta simetris, tracer peluru dengan trail.*

---

## 2.1 Pilar Gaya

| Aspek | Keputusan | Alasan produksi |
|---|---|---|
| Art style | **Stylized low-poly 3D**, unlit/simple-lit, tanpa tekstur PBR | Unlit + vertex color = 1 material per tipe, batching maksimal, build kecil |
| Silhouette | Musuh = kapsul-membulat dengan bahu lebar | Terbaca jelas di ukuran 20–40 px saat crowd 200 unit |
| Detail | Detail dari **emissive line**, bukan geometri | Menjaga < 300 tris/musuh tanpa terlihat miskin |
| Kontras | Cyan (aman/milik player) vs Merah-oranye (ancaman) | Pemain harus baca kondisi dalam 0.2 detik di layar kecil |
| Kamera | Perspective, pitch 40°, FOV 60 | Miring cukup untuk kedalaman, tidak cukup untuk menyembunyikan baris belakang crowd |

**Prinsip nomor satu:** *readability beats beauty*. Jika sebuah efek menutupi lintasan peluru selama > 0.15 detik, efek itu dipotong.

---

## 2.2 Palet Warna

### Core palette

Sejak v2.0 arah visualnya **fantasi**, bukan arcade neon: karakter KayKit
Adventurers (CC0) adalah benda paling terang di layar, dan arena berperan
sebagai medan tempur yang redup di sekelilingnya. Neon dikurangi di mana-mana;
yang tersisa hanya satu warna sihir untuk bumper dan chain shot.

| Peran | Hex | Penggunaan |
|---|---|---|
| Obor Emas | `#FFC24D` | Aksen pemain: cincin chain shot, garis HUD, highlight stage |
| Lumut Gelap | `#2C3324` | Lantai arena (tekstur batu-berlumut, `makeGridTexture`) |
| Nat Batu | `#6E7A5E` @ 35% alpha | Garis nat lantai, pengganti grid neon |
| Kayu Pagar | `#4A4336` | Dinding samping arena, palisade |
| Kayu Tong | `#7A5430` | Tong mesiu, tiang |
| Besi | `#60666E` | Simpai tong, palang perisai, baja ksatria |
| Sihir Ungu | `#B46BFF` | Cincin rune bumper, peluru chain shot, trail |
| Bara | `#FFE9A8` | Peluru auto-fire, kilatan moncong, sumbu tong |
| Langit Malam | `#0B1424` | Latar + kabut arena |
| Darah Gerbang | `#C62828` | Garis pertahanan, vignette saat kebobolan |
| Combo Gold | `#FFD54F` | Combo popup, floating text, milestone |

### Warna tiap tipe musuh

Diambil dari karakter KayKit yang mewakilinya (`Config/arena_config.json` →
`enemyTypes[].color`), supaya musuh jauh di jalur MultiMesh berwarna sama
dengan tubuh ber-tulang yang menggantikannya saat mendekat.

| Tipe | Hex | Karakter |
|---|---|---|
| grunt | `#4E9E5F` | Rogue (tunik hijau, belati) |
| runner | `#D8B98A` | Ranger (busur, krem-cokelat) |
| brute | `#C98B5E` | Barbarian (kapak dua tangan) |
| shielder | `#8FA3C4` | Knight baja dingin (perisai persegi) |
| splitter | `#8B6FD4` | Mage (tongkat, jubah ungu) |
| bomber | `#3E6B4A` | Rogue bertudung (bom asap) |

### Tema per varian

| Varian | Primary | Enemy | Bumper | BG | Mood |
|---|---|---|---|---|---|
| 1. Lembah Batu | `#FFC24D` | `#C2503D` | `#9A6BFF` | `#1A2133 → #070A12` | Netral, batu dan obor |
| 2. Menara Kembar | `#E8B44A` | `#B4553A` | `#A15CFF` | `#241A33 → #0A0612` | Lorong sempit, ungu senja |
| 3. Kuil Melayang | `#6FE3C4` | `#D4544F` | `#7A5CFF` | `#0E2630 → #040B0F` | Dingin, giok, melayang |
| 4. Ladang Bara | `#FF9D3C` | `#D9603A` | `#FF5A4D` | `#2E140A → #0C0402` | Panas, bara, berbahaya |
| 5. Labirin Berduri | `#9ADB5E` | `#C2503D` | `#8A5CFF` | `#122A17 → #040D06` | Rimba, gelisah, ritmik |

> Aturan: **aksen pemain selalu hangat** (emas obor) kecuali varian 3 & 5 yang
> menggesernya ke giok dan lumut. Warna aksen adalah jangkar identitas pemain,
> dan tidak pernah dipakai untuk musuh.

---

## 2.3 Lighting

```text
                    Directional Key Light
                    pitch -55°, yaw 160°
                    color #FFF1D0, intensity 1.2
                            \
                             \        [CROWD]  <- rim light dari atas-belakang
                              \        (#FFC93C, intensity 0.8)
                               \
        ambient sky #1B2A5E  -->  [ARENA]
        ambient ground #FF7A3D (bounce hangat, intensity 0.25)
                               /
                            [PLAYER]  <- point light cyan, range 6, intensity 2
                            (#00E5FF)
```

| Light | Tipe | Setting | Fungsi |
|---|---|---|---|
| Key | Directional | Pitch -55°, dari atas-belakang player, `#FFF1D0`, 1.2 | Bentuk umum, satu-satunya shadow caster |
| Rim musuh | Directional (culling mask = Enemy layer) | Dari belakang crowd, `#FFC93C`, 0.8 | Siluet musuh terpisah dari background gelap |
| Player glow | Point | `#00E5FF`, range 6, 2.0 | Menandai zona aman, membaca posisi muzzle |
| Bullet light | Point (hanya 1 aktif, pooled) | `#00E5FF`, range 4, 3.0, **tanpa shadow** | Peluru menerangi lantai saat melintas |
| Ambient | Gradient | Sky `#1B2A5E`, Equator `#2A1B3E`, Ground `#FF7A3D` × 0.25 | Bounce hangat supaya area gelap tidak mati |

**Shadow budget:** hanya **player + boss** yang cast shadow (hard shadow, resolusi 512, distance 25). Crowd memakai *fake blob shadow* — quad transparan di bawah kaki, di-batch dalam satu mesh instancing.

---

## 2.4 Post-processing (URP Volume)

| Efek | Normal | Bullet Time | Catatan |
|---|---|---|---|
| Bloom | threshold 1.1, intensity 0.9, scatter 0.6 | intensity 1.4 | Mobile: `High Quality Filtering = OFF` |
| Vignette | intensity 0.22, smoothness 0.4 | 0.42, tint `#00344D` | Naik via `SlowMoSystem` |
| Chromatic Aberration | 0.0 | 0.45 | **Hanya** saat bullet time — mahal di mobile |
| Color Adjustments | contrast +8, saturation +12 | saturation +25 | Bikin neon "menggigit" |
| Tonemapping | ACES | ACES | Konsisten antar device |
| Motion Blur | **OFF** | **OFF** | Terlalu mahal, dan merusak pembacaan lintasan |
| Depth of Field | **OFF** | OFF (fake via bloom) | Budget |

Semua override disimpan dalam **2 Volume Profile** (`VP_Normal`, `VP_BulletTime`) dan di-blend oleh `SlowMoSystem` dengan `weight` — bukan dengan mengubah parameter satu per satu (lebih murah, no GC).

---

## 2.5 Kamera & Komposisi

```text
  Layar portrait 9:16            Kamera
  ┌──────────────┐                 
  │  HUD atas    │ 12%     Position : player + (0, 12, -18)
  ├──────────────┤         Rotation : pitch 40°, yaw 0°
  │              │         FOV      : 60 (normal) → 40 (bullet time, 0.2s)
  │   SPAWN      │ 22%     Look-at  : player + (0, 0, +6)  [look-ahead]
  │              │         Near/Far : 0.3 / 60
  │   COMBAT     │ 45%     Projection: Perspective (WAJIB — 2.5D butuh parallax)
  │              │
  │   PLAYER     │ 12%
  ├──────────────┤
  │  HUD bawah   │  9%
  └──────────────┘
```

**Aturan framing:**
1. Player **selalu** di 20% bawah safe-area, tidak pernah tertutup HUD.
2. Garis pertahanan (`Z = 5`) selalu terlihat, bahkan saat kamera zoom ke peluru — kalau perlu, kamera clamp agar `Z = 5` tetap di dalam frustum.
3. Saat bullet riding, kamera **tidak** mengikuti peluru 1:1. Ia melakukan *dolly + FOV narrowing* menuju posisi peluru dengan `bulletFollowLerp = 14`, sehingga tetap ada konteks arena.
4. Safe area iOS notch: seluruh HUD dalam `Screen.safeArea`.

---

## 2.6 Material & Shader

| Material | Shader | Properti |
|---|---|---|
| `M_Floor` | URP/Lit (Simple) + custom grid | Base `#03060F`, grid emissive `#1FD3E8`, fake reflection via `_ReflectionStrength = 0.25` (planar mirror murah: render arena ke RT 1/4 resolusi hanya saat device tier ≥ mid) |
| `M_Wall_Bumper` | URP/Unlit + Fresnel emissive | Emissive `#B14DFF`, pulse saat bounce via `MaterialPropertyBlock` (bukan instance material baru) |
| `M_Enemy_*` | URP/Simple Lit, **GPU Instanced** | 1 material per tipe musuh (6 total), warna via `_BaseColor` di MPB |
| `M_Player` | URP/Lit + emissive | Emissive cyan pulse sinkron BPM 120 |
| `M_Bullet` | URP/Unlit additive | Full emissive, `ZWrite Off`, render queue Transparent+10 |
| `M_Trail` | URP/Particles Unlit additive | Gradient cyan → putih → transparan, width curve mengecil |

**Larangan keras:** jangan pernah `renderer.material` (membuat instance & GC). Selalu `MaterialPropertyBlock`.

---

## 2.7 VFX Language

| Event | VFX | Durasi | Budget partikel |
|---|---|---|---|
| Muzzle flash | Ring cyan expand + 6 spark | 0.12s | 8 |
| Bounce | Ring magenta di titik kontak + 4 spark, skala ∝ bounce count | 0.20s | 12 |
| Kill | Pop: 1 quad flash + 5 chunk low-poly | 0.30s | 6 |
| Explosion barrel | Shockwave ring + 20 ember + flash oranye | 0.45s | 30 |
| Combo milestone | Radial burst dari tengah layar (screen-space) | 0.50s | 24 |
| Kill milestone | Confetti dari atas HUD | 1.20s | 40 |
| Slow-mo enter | Ripple ring dari peluru + vignette biru | 0.20s | 10 |
| Perfect clear | Sweep cahaya di garis pertahanan | 0.80s | 16 |

**Hard cap 200 partikel aktif.** `VFXBudget` menolak spawn baru saat cap tercapai, dengan prioritas: `Bounce > Kill > Explosion > Milestone > Ambient dust`.

---

## 2.8 Referensi Visual

| Referensi | Yang diambil |
|---|---|
| **Top War / Last War: Survival** | Kepadatan crowd, keterbacaan unit kecil, skala "ratusan musuh" |
| **State of Survival** | Rim light pada crowd, kontras siluet |
| **Top Royale** | Kesederhanaan bentuk unit, warna flat |
| **Archero** | Framing portrait, posisi HUD, ukuran arena relatif |
| **Survivor.io** | Feel juice: number pop, screen shake ringan, kill chain |
| **Tron / Geometry Wars** | Bahasa neon-on-dark, glow lantai |

**Yang sengaja TIDAK diambil:** realisme material, tekstur detail, karakter bersenjata realistik, UI padat ala mid-core. Game ini harus terbaca dalam 1 detik dari thumbnail store.

# 1. Blueprint Arena — CHAIN RIDER

> **File ini di-generate otomatis** oleh `tools/blueprint_gen.py` dari `Config/arena_config.json`.
> Jangan edit manual — ubah JSON-nya lalu jalankan `python3 tools/blueprint_gen.py`.

## 1.1 Sistem Koordinat

Arena memakai koordinat dunia 3D dengan **origin di tengah dinding bawah**, supaya matematika ricochet dan spawn gampang dibaca:

```text
            Z = 40  (spawn gate / dinding atas)
               ^
               |
  X = -10 <----+----> X = +10      Y = up (tinggi), lantai di Y = 0
               |
            Z = 0   (lantai / belakang player)
```

- Lebar dunia **20 unit**, panjang **40 unit** (rasio 1:2, pas untuk viewport portrait 9:16 dengan kamera miring 40°).
- 1 unit dunia ≈ tinggi 1 musuh grunt. Spacing crowd 0.8 unit → 12 kolom muat pas di lebar arena tanpa menyentuh dinding.

## 1.2 Zona

| Zona | Rentang Z | Ukuran | Fungsi |
|------|-----------|--------|--------|
| **SPAWN ZONE** | `30 .. 40` | 10u | gate musuh |
| **COMBAT ZONE** | `5 .. 30` | 25u | ricochet + crowd |
| **PLAYER ZONE** | `0 .. 5` | 5u | garis pertahanan |

- **Garis pertahanan** pada `Z = 5`. Musuh yang melewatinya → `-1 HP` (total 3 nyawa).
- **Near-miss band**: musuh dalam `0.5` unit di atas garis memicu SFX heartbeat.
- **Player** statis di `(0.0, 2.0)`, menghadap +Z. Tidak ada kontrol gerak — semua mobilitas dari peluru.

## 1.3 Dinding

| Dinding | Posisi | Tipe | Restitution | Catatan |
|---------|--------|------|-------------|---------|
| Kiri | `X = -10` | `ricochet_bumper` | 0.95 | Memantulkan peluru, **tidak** memantulkan musuh |
| Kanan | `X = 10` | `ricochet_bumper` | 0.95 | Idem |
| Atas | `Z = 40` | `spawn_gate_bumper` | 0.95 | Peluru yang keluar di sini mati (bukan pantul) |
| Bawah | `Z = 0` | `defense_line` | 0.0 | Peluru mati, musuh = damage |

## 1.4 Legenda ASCII

```text
|  dinding bumper (kiri/kanan)      O  pillar (r = 1.5–2.4)
=  spawn gate (atas)                o  bumper kecil (r = 0.9)
_  lantai belakang (bawah)          B  barrel explosive
-  GARIS PERTAHANAN (Z = 5)         @  gravity well (inti)
A  player (statis)                  :  radius gravity well
^  arah tembak (+Z)                 #  shield wall (rusak dari belakang)
.  grid lantai neon (tiap 2u)       ~  jalur travel moving platform

Skala: 1 karakter = 0.5 unit X, 1 baris = 1.0 unit Z.
```

## 1.5 Blueprint 5 Varian Arena

### 1. Classic Pit  `id: classic_pit`

> Arena dasar, 4 bumper simetris. Mengajarkan sudut pantul 45 derajat.

| Tema | Musik | Musuh spesial | Boss |
|---|---|---|---|
| `#00E5FF` / `#FF4D3D` / `#B14DFF` | `base_synth` | `runner` | `colossus` |

```text
  X:  -10 -8  -6  -4  -2  0   2   4   6   8   10
      |   |   |   |   |   |   |   |   |   |   |
  40 =========================================
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  35 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
  30 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  25 |                                       |
     |   .   ooo .   .   .   .   . ooo   .   |
     |      ooooo                 ooooo      |
     |   .   ooo .   .   .   .   . ooo   .   |
     |                                       |
  20 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  15 |                                       |
     |   .   ooo .   .   .   .   . ooo   .   |
     |      ooooo                 ooooo      |
     |   .   ooo .   .   .   .   . ooo   .   |
     |                                       |
  10 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
   5 |---------------------------------------|
     |   .   .   .   .   .   .   .   .   .   |
     |                   ^                   |
     |   .   .   .   .   A   .   .   .   .   |
     |                                       |
   0 _________________________________________
```

**Koordinat obstacle**

| # | Type | X | Z | Param |
|---|------|---|---|-------|
| 1 | `bumper` | -5.5 | 13.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |
| 2 | `bumper` | +5.5 | 13.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |
| 3 | `bumper` | -5.5 | 23.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |
| 4 | `bumper` | +5.5 | 23.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |

### 2. Twin Towers  `id: twin_towers`

> Dua pilar besar di tengah membentuk 3 lorong sempit. Peluru mudah terjebak zig-zag bernilai tinggi.

| Tema | Musik | Musuh spesial | Boss |
|---|---|---|---|
| `#00E5FF` / `#FF6A1F` / `#FF3DBE` | `base_synth+arp` | `brute` | `twin_warden` |

```text
  X:  -10 -8  -6  -4  -2  0   2   4   6   8   10
      |   |   |   |   |   |   |   |   |   |   |
  40 =========================================
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  35 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
  30 |   .   .   .   .   .   .   .   .   .   |
     |   ooo                           ooo   |
     |  ooooo.   .   .   .   .   .   .ooooo  |
     |   ooo                           ooo   |
     |   .   .   .   .   .   .   .   .   .   |
  25 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .OOOOOOOO   .   OOOOOOOO.   .   |
     |       OO       O     O       OO       |
  20 |   .   O         O . O         O   .   |
     |       OO       O     O       OO       |
     |   .   .OOOOOOOO   .   OOOOOOOO.   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  15 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   ooo .   .   .   .   .   .   . ooo   |
     |  ooooo                         ooooo  |
  10 |   ooo .   .   .   .   .   .   . ooo   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
   5 |---------------------------------------|
     |   .   .   .   .   .   .   .   .   .   |
     |                   ^                   |
     |   .   .   .   .   A   .   .   .   .   |
     |                                       |
   0 _________________________________________
```

**Koordinat obstacle**

| # | Type | X | Z | Param |
|---|------|---|---|-------|
| 1 | `pillar` | -3.6 | 20.0 | radius=2.4, restitution=0.98, friction=0.05 |
| 2 | `pillar` | +3.6 | 20.0 | radius=2.4, restitution=0.98, friction=0.05 |
| 3 | `bumper` | -7.5 | 11.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |
| 4 | `bumper` | +7.5 | 11.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |
| 5 | `bumper` | -7.5 | 28.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |
| 6 | `bumper` | +7.5 | 28.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |

### 3. Gravity Chamber  `id: gravity_chamber`

> Dua gravity well membelokkan peluru jadi kurva. Lintasan non-linear, reward tinggi.

| Tema | Musik | Musuh spesial | Boss |
|---|---|---|---|
| `#4DFFD2` / `#FF3D6E` / `#8A5CFF` | `base_synth+pad` | `splitter` | `singularity` |

```text
  X:  -10 -8  -6  -4  -2  0   2   4   6   8   10
      |   |   |   |   |   |   |   |   |   |   |
  40 =========================================
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  35 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
  30 |   .   .   .   .   .   :::::::::   .   |
     |                     :::       :::     |
     |   .   .   .   .   .:: .   .   . ::.   |
     |                   :               :   |
     |   .   .   .   .   :   .   @   .   :   |
  25 |                   :               :   |
     |   .   .   .   .   .:: .   .   . ::.   |
     |                     :::       :::     |
     |   .  ooo  .   .   .   :::::::ooo  .   |
     |     ooooo                   ooooo     |
  20 |   .  ooo  .   .   .   .   .  ooo  .   |
     |       :::::::::                       |
     |   . :::   .   ::: .   .   .   .   .   |
     |    ::           ::                    |
     |   :   .   .   .   :   .   .   .   .   |
  15 |   :       @       :                   |
     |   :   .   .   .   :   .   .   .   .   |
     |    ::           ::                    |
     |   . :::   .   ::: .   .   .   .   .   |
     |       :::::::::                       |
  10 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
   5 |---------------------------------------|
     |   .   .   .   .   .   .   .   .   .   |
     |                   ^                   |
     |   .   .   .   .   A   .   .   .   .   |
     |                                       |
   0 _________________________________________
```

**Koordinat obstacle**

| # | Type | X | Z | Param |
|---|------|---|---|-------|
| 1 | `gravityWell` | -4.0 | 15.0 | radius=4.0, force=5.0, duration=3.0, maxCurveDegPerSec=120.0 |
| 2 | `gravityWell` | +4.0 | 26.0 | radius=4.0, force=5.0, duration=3.0, maxCurveDegPerSec=120.0 |
| 3 | `bumper` | -6.0 | 21.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |
| 4 | `bumper` | +6.0 | 21.0 | radius=0.9, restitution=0.95, friction=0.1, bounceBonusDamage=0.05 |

### 4. Explosive Yard  `id: explosive_yard`

> Ladang barrel. Satu pantulan tepat memicu chain explosion sepanjang arena.

| Tema | Musik | Musuh spesial | Boss |
|---|---|---|---|
| `#00E5FF` / `#FF8A2B` / `#FF2D55` | `base_synth+percussion` | `bomber` | `pyro_baron` |

```text
  X:  -10 -8  -6  -4  -2  0   2   4   6   8   10
      |   |   |   |   |   |   |   |   |   |   |
  40 =========================================
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  35 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
  30 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |               BB      BB              |
     |   .   .   .   .   .   .   .   .   .   |
  25 |                                       |
     |   .   . BB.   .   O   .   . BB.   .   |
     |                OOOOOOO                |
     |   .   .   .   .O     O.   .   .   .   |
     |                OOOOOOO                |
  20 |   .   .   .   .   O   .   .   .   .   |
     |                                       |
     |   .   .   .   .   BB  .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  15 |                                       |
     |   .   .   BB  .   .   .   BB  .   .   |
     |                                       |
     |   .   BB  .   .   .   .   .   BB  .   |
     |                                       |
  10 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
   5 |---------------------------------------|
     |   .   .   .   .   .   .   .   .   .   |
     |                   ^                   |
     |   .   .   .   .   A   .   .   .   .   |
     |                                       |
   0 _________________________________________
```

**Koordinat obstacle**

| # | Type | X | Z | Param |
|---|------|---|---|-------|
| 1 | `barrel` | -6.0 | 12.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 2 | `barrel` | -4.0 | 14.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 3 | `barrel` | +4.0 | 14.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 4 | `barrel` | +6.0 | 12.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 5 | `barrel` | +0.0 | 18.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 6 | `barrel` | -5.0 | 24.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 7 | `barrel` | +5.0 | 24.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 8 | `barrel` | -2.0 | 27.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 9 | `barrel` | +2.0 | 27.0 | hp=1, explosionRadius=3.0, explosionDamage=50.0, falloff=linear, chainDelay=0.08, radius=0.6 |
| 10 | `pillar` | +0.0 | 22.0 | radius=1.5, restitution=0.98, friction=0.05 |

### 5. Moving Maze  `id: moving_maze`

> Tiga platform bergerak memaksa timing. Formasi musuh pecah dinamis saat tertahan.

| Tema | Musik | Musuh spesial | Boss |
|---|---|---|---|
| `#7CFF4D` / `#FF4D3D` / `#B14DFF` | `base_synth+glitch` | `shielder` | `shifter` |

```text
  X:  -10 -8  -6  -4  -2  0   2   4   6   8   10
      |   |   |   |   |   |   |   |   |   |   |
  40 =========================================
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  35 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
  30 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .~~~~~~===========~~~~~~.   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
  25 |                                       |
     |   .   .   .   .   .   .   . #######   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
  20 |   .   .~~~~~~===========~~~~~~.   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   ####### .   .   .   .   .   .   .   |
  15 |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .~~~~~~===========~~~~~~.   .   |
     |                                       |
  10 |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
     |                                       |
     |   .   .   .   .   .   .   .   .   .   |
   5 |---------------------------------------|
     |   .   .   .   .   .   .   .   .   .   |
     |                   ^                   |
     |   .   .   .   .   A   .   .   .   .   |
     |                                       |
   0 _________________________________________
```

**Koordinat obstacle**

| # | Type | X | Z | Param |
|---|------|---|---|-------|
| 1 | `movingPlatform` | +0.0 | 12.0 | width=5.0, thickness=0.8, speed=2.0, blocksEnemies=True, blocksBullet=False, travel=6.0, phase=0.0 |
| 2 | `movingPlatform` | +0.0 | 20.0 | width=5.0, thickness=0.8, speed=2.5, blocksEnemies=True, blocksBullet=False, travel=6.0, phase=0.5 |
| 3 | `movingPlatform` | +0.0 | 28.0 | width=5.0, thickness=0.8, speed=1.8, blocksEnemies=True, blocksBullet=False, travel=6.0, phase=0.25 |
| 4 | `shieldWall` | -6.5 | 16.0 | hp=3, width=3.0, thickness=0.4, vulnerableFrom=back |
| 5 | `shieldWall` | +6.5 | 24.0 | hp=3, width=3.0, thickness=0.4, vulnerableFrom=back |

## 1.6 Aturan Penempatan (design rules)

1. **Simetri kiri-kanan wajib** untuk semua bumper — pemain satu jempol harus bisa memprediksi pantulan dari dua sisi dengan model mental yang sama.
2. **Koridor minimum 2.0 unit** antara obstacle dan dinding, supaya peluru ber-radius 0.26 unit tidak pernah stuck.
3. **Tidak ada obstacle di `Z < 7`** — player zone harus bersih agar pemain bisa membaca ancaman yang menembus garis.
4. **Tidak ada obstacle solid di `Z > 32`** — spawn gate harus bebas agar formasi tidak rusak sebelum masuk combat zone.
5. **Obstacle didesain sebagai sumber sudut**: tiap bumper menghasilkan minimal satu lintasan 3-bounce yang menyapu crowd penuh jika pemain steer benar.
6. **Gravity well tidak boleh tumpang-tindih** — akumulasi force membuat lintasan tak terbaca dan merusak determinisme perseptual.


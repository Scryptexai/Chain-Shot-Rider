# 17. Key Art Analysis — "Neon Bullet-Hell Combo Assault"

Dokumen ini membedah **satu gambar referensi** yang mulai sekarang menjadi
**basis utama arah game** (menggantikan arah fantasi v2.0 di docs 02).
Setiap elemen dibaca → diterjemahkan ke besaran yang bisa dipakai engine
(sudut kamera, world unit, warna hex, durasi efek).

> **Catatan file:** gambar referensi dikirim lewat chat (`Neon Bullet-Hell
> Combo Assault.png`) dan belum tersimpan di repo. Sebelum fase implementasi
> VFX dimulai, simpan salinannya ke `docs/images/keyart-neon-master.png`
> supaya seluruh tim/agen punya satu sumber kebenaran visual.

---

## 17.1 Ringkasan satu kalimat

Seorang prajurit cyber tunggal di dasar koridor neon menembakkan **satu peluru
raksasa** yang memantul zig-zag di antara dinding magenta, merantai petir, dan
meledakkan barrel — melawan **ratusan musuh merah** yang menghujani lorong
dengan tracer, sementara counter **x999 COMBO** menyala di pojok kanan atas.

Artinya: *power fantasy ricochet* dalam format **portrait lane-shooter**.
Inilah tepat mekanik `chain shot` yang sudah ada di `sim_world.gd` — gambar ini
bukan arah baru untuk gameplay, melainkan **presentasi yang benar** untuk
gameplay yang sudah ada.

---

## 17.2 Kamera & komposisi (paling penting)

| Properti | Pembacaan dari gambar | Nilai target engine |
|---|---|---|
| Aspect | ~896×1568 ≈ **9:15.7** | portrait 9:16 reference, aman sampai 9:21 |
| Tipe | Perspective, **over-the-shoulder** (bukan top-down 40° murni) | pitch **22,5°** ← lihat catatan |
| Vanishing point | ~x 52%, y **8%** dari atas | lorong terbaca penuh sampai horizon |
| Posisi pemain di layar | pusat badan ~x 50%, y **87%** | player anchor = 0.86–0.88 tinggi layar |
| Skala pemain | tinggi karakter ≈ **19%** tinggi layar | jauh lebih besar dari prototipe sekarang |
| Horizon / crowd | baris musuh terjauh berhenti di y ≈ 7% | kabut menelan ujung lorong, bukan dipotong |
| FOV | kompresi sedang, lorong tetap melebar kuat | FOV vertikal **60°** @ 9:16 |
| Roll | 0° | tidak ada dutch angle |

**Catatan sudut — mata menipu di sini.** Pembacaan pertama saya adalah "pitch
~54°", karena lantai di dekat pemain terlihat sangat miring. Itu salah. Tiga
ukuran di tabel ini (anchor 0,87 · tinggi pemain 0,185 · horizon 0,14) adalah
tiga persamaan dengan tiga variabel (tinggi kamera, kedalaman kamera, pitch),
jadi jawabannya **tertentu, bukan selera**. `tools/solve_framing.py`
menyelesaikannya:

```
heightOffset  15.95
backOffsetZ   11.10
pitchDegrees  22.50
lookTargetZ   27.4   (arena space)
```

Lantai terlihat curam bukan karena pitch-nya besar, melainkan karena **tepi
bawah frame 60°** sudah menunjuk 52° ke bawah dengan sendirinya. Kalau pitch
benar-benar 54°, horizon akan jauh di luar layar dan lorong berubah jadi
papan permainan dari atas.

**Konsekuensi untuk kode:** `camera.pitchDegrees = 40`, `distance = 18`,
`heightOffset = 12` di `arena_config.json` menghasilkan framing *isometrik
datar*. Yang diubah: `_place_camera()` di `scripts/game.gd` (pitch sekarang
di-author, bukan diturunkan dari look_at) dan `_fit_pullback()` — versi lama
bebas mundur sampai seluruh arena 20 unit muat, dan itulah yang mengecilkan
pemain jadi sebesar ibu jari.

**Lebar lorong ikut berubah.** Pada framing ini, dinding di x=±10 baru masuk
layar di z≈20 — separuh pantulan terjadi di luar layar, yang sama saja dengan
mekanik yang tidak ada. Lorong dipersempit **20 → 12 unit** (x=±6); sekarang
kedua dinding terbaca sejak z≈2. Perabot tiap varian ikut diskalakan oleh
`tools/migrate_neon.py`.

### Pembagian layar (zona baca)

```
  0% ─────────────── VP + vortex + kabut ungu ──────────────
  8% ┐
     │  CROWD ZONE      ratusan musuh, tracer merah turun
 35% ┘
 36% ┐
     │  BOUNCE ZONE     dinding magenta kiri+kanan, barrel,
     │                  lintasan peluru zig-zag (fokus mata)
 72% ┘
 73% ┐
     │  PLAYER ZONE     lantai grid cyan, pemain, muzzle flash
100% ┘
```

Peta zona ini cocok 1:1 dengan `arena.spawnZone / combatZone / playerZone`
di config (10 / 25 / 5 world unit). Jadi **pembagian arena tidak perlu
diubah** — hanya pemetaan kamera ke layar.

---

## 17.3 Palet warna (diambil langsung dari gambar)

### Core

| Peran | Hex | Di mana di gambar |
|---|---|---|
| Player Cyan | `#2BE8FF` | grid lantai, muzzle flash, rim armor pemain |
| Player Steel | `#DCE6F2` / `#2E5BD8` | armor putih-biru pemain |
| Bumper Magenta | `#FF2BD6` | dinding pantul kiri & kanan |
| Bumper Core | `#FF9BEE` | inti panas dinding di titik benturan |
| Tracer Red | `#FF2A2A` | hujan tracer musuh (ratusan garis) |
| Enemy Red | `#E03A2F` | armor badan musuh |
| Enemy Orange | `#FF7A18` | aksen bahu/helm musuh |
| Blast Orange | `#FF9A2E` | bola api ledakan |
| Blast Core | `#FFE3A0` | inti ledakan, hampir putih |
| Chain Violet | `#A64BFF` | busur petir di titik pantul |
| Vortex Purple | `#6B2FA8` | black hole & kabut latar |
| Night Base | `#070A14` | latar kota, bayangan |
| Combo Chrome | `#9BF2FF` + outline `#0A2A33` | teks x999 COMBO |
| Brass Bullet | `#D9A441` | selongsong peluru chain shot |

**Aturan kontras:** cyan = milik pemain, magenta = permukaan interaktif
(pantul), merah/oranye = ancaman, ungu = efek chain. Tidak ada warna hijau
atau emas fantasi di mana pun — seluruh palet `docs/02` lama **gugur**.

### Rasio warna layar (penting untuk tidak over-neon)

- ~55% gelap (`#070A14` dan turunannya)
- ~25% merah/oranye (musuh + api)
- ~12% magenta/ungu (dinding + chain)
- ~8% cyan (pemain + grid) ← paling sedikit, tapi paling kontras

Cyan dipakai **hemat**; inilah sebabnya pemain langsung terbaca.

---

## 17.4 Inventaris elemen

### A. Pemain
- Armor hard-surface biru-putih, helm tertutup visor, **tidak ada wajah**.
- Pose: kaki terbuka lebar (stance), satu tangan mengangkat pistol ke depan.
- **Rim light cyan** di seluruh siluet + pantulan di lantai basah.
- Muzzle flash biru kecil, bukan oranye — senjata pemain ≠ senjata musuh.
- Tidak ada squad/pasukan pengiring di gambar → pemain **tunggal & heroik**.

### B. Musuh (crowd)
- Ratusan unit identik, armor merah-oranye, **berbaris rapat grid/wedge**.
- Dirender makin kecil & makin tenggelam kabut ke belakang → LOD natural.
- Beberapa unit di kiri **terlempar ke udara** oleh ledakan (ragdoll pop).
- Setiap unit menembakkan tracer → crowd = sumber bullet-hell.

### C. Dinding pantul (bumper wall)
- Dua slab panel miring magenta di kiri & kanan, **bukan dinding batu**.
- Permukaan bertekstur panel teknis + garis data kecil.
- Saat terkena peluru: **flare putih-magenta** + percikan + busur petir.
- Inilah yang menggantikan `ricochet_bumper` dinding X = ±10.

### D. Barrel / bahan peledak
- Drum merah dengan ikon api & segitiga bahaya.
- Terlihat dalam dua state: utuh (kanan bawah) dan **meledak** (kiri).
- Ledakan: bola api oranye + asap abu volumetrik + puing terbang.
- Cocok dengan `obstacleDefaults.barrel` yang sudah ada.

### E. Lantai
- Lantai gelap basah dengan **grid garis cyan menyala**, refleksi tajam.
- Garis grid lebih tebal di dekat pemain, meredup ke kejauhan.
- Ada panel-panel besar (bukan grid seragam) → baca sebagai pelat logam.

### F. Latar & langit
- Kota/stasiun cyberpunk gelap, siluet menara + papan neon kecil.
- **Vortex ungu** di kanan atas + puing batu melayang.
- Kabut ungu-biru pekat menutup sepertiga atas.

---

## 17.5 Efek serangan — spesifikasi per efek

Ini bagian yang paling menentukan "rasa" game. Enam efek utama:

### E1. Chain Shot Projectile
- **Bentuk:** selongsong peluru brass besar, bukan bola kecil. Skala ~0.6 unit.
- **Orientasi:** mengikuti arah kecepatan, ada sedikit spin.
- **Trail:** pita api oranye lebar yang menyempit ke belakang, panjang
  ~8–10 world unit, menyala (additive), bukan garis tipis.
- **Core glow:** halo oranye-putih di sekeliling peluru + distorsi panas.
- **Elektrik:** filamen ungu tipis menempel di sekeliling trail saat combo tinggi.

### E2. Ricochet Impact (saat kena dinding)
- Flare radial putih→magenta, durasi **~0.12 s**, skala puncak ~2.5 unit.
- **Spark burst** 12–20 partikel oranye yang menyebar sepanjang normal pantul.
- **Arc petir ungu** 2–4 cabang menjalar di permukaan dinding ~0.25 s.
- Dinding ikut **menyala lokal** (emissive naik) lalu mereda ~0.4 s.
- Hitstop pendek + shake kecil — sudah ada di `camera.shake.bounceSmall`.

### E3. Tracer Hujan Musuh
- Garis merah lurus, tipis, panjang (motion-streak), **puluhan sekaligus**.
- Turun dari crowd ke arah pemain, sedikit menyebar ke samping.
- Harus dirender sebagai **batch** (MultiMesh / quad instanced), bukan node.
- Kecerahan rendah per garis, tinggi secara agregat → tidak menutupi peluru.

### E4. Explosion (barrel / bomber)
- Core putih-kuning → shell oranye → asap abu, total **~0.8 s**.
- Shockwave ring tipis melebar di lantai.
- Melempar puing kecil + **mendorong musuh ke udara**.
- Memicu chain ke barrel tetangga (`chainDelay 0.08` sudah ada).

### E5. Chain Lightning (link antar target)
- Busur ungu-magenta zig-zag yang **menghubungkan titik pantul ke target**.
- Lebar tipis, flicker 3–4 frame, hilang < 0.2 s.
- Inilah visualisasi "chain" di nama game — saat ini belum ada di renderer.

### F6. Combo HUD Burst
- Teks chrome-cyan tebal miring, outline gelap, **glow + scanline**.
- Muncul besar lalu mengecil ke sudut; angka memakai digit tabular.
- Milestone = flash putih singkat di seluruh layar + shake + stinger audio.

---

## 17.6 Post-processing (wajib agar gambar ini tercapai)

| Efek | Setting target | Alasan |
|---|---|---|
| Bloom | threshold rendah (~0.6), intensitas tinggi | semua neon di gambar "mekar" |
| Glow bicubic | on (web: fallback ke 1 pass) | halo lembut, bukan kotak |
| Fog volumetrik/depth fog | warna `#2A1340`, mulai z≈28 | ujung lorong larut |
| Screen-space reflection | murah/fake (planar fake) | lantai basah memantulkan neon |
| Chromatic aberration | max 0.25 saat bullet-time | sudah ada di `slowMo` |
| Vignette | 0.35 gelap-ungu | memusatkan mata ke lorong |
| Film grain halus | 0.03 | menyatukan partikel & bloom |
| Tonemap | ACES, exposure ~1.1 | menjaga core ledakan tidak clipping jelek |

---

## 17.7 Delta terhadap build sekarang

| Aspek | Sekarang (v2.0 fantasi) | Target key art | Besar perubahan |
|---|---|---|---|
| Palet | emas/lumut/batu | cyan/magenta/merah neon | **total** |
| Kamera | pitch 40°, pemain kecil | pitch ~54°, pemain besar di bawah | **besar** |
| Pemain | KayKit knight CC0, squad 100 | 1 prajurit cyber armor | **besar** |
| Musuh | 6 tipe fantasi warna-warni | satu bahasa visual merah-oranye | sedang |
| Dinding | palisade kayu/batu | slab panel magenta emissive | **besar** |
| Lantai | tekstur batu berlumut | pelat logam + grid cyan reflektif | **besar** |
| Tracer musuh | tidak ada hujan tracer | wajib ada (bullet-hell) | **fitur baru** |
| Chain lightning | tidak ada | wajib ada | **fitur baru** |
| Ledakan | partikel sederhana | 3-layer + shockwave + ragdoll pop | sedang |
| HUD combo | label emas `x12` | chrome-cyan besar + burst | sedang |
| Post-FX | minimal | bloom/fog/vignette/CA stack | **besar** |
| Rules/sim | chain shot, bounce, barrel, gate | **tidak berubah** | nol |

**Kabar baik:** `scripts/sim/*` (aturan main, 946 LOC `sim_world.gd`) sudah
mendukung semua yang terlihat di gambar — ricochet, combo, barrel chain,
crowd 200+, milestone. Rombakan ini **99% berada di layer view/UI/config**,
sehingga replay determinism dan test headless tetap aman.

---

## 17.8 Yang sengaja TIDAK diambil dari gambar

1. **Black hole raksasa** sebagai gameplay — tetap dekorasi latar (gravity
   well tetap obstacle kecil di lantai), kalau tidak pembacaan lorong rusak.
2. **Kepadatan tracer seperti di gambar** (ratusan) — dibatasi oleh budget
   partikel 200 di docs 08; dipakai ilusi lewat streak panjang, bukan jumlah.
3. **Puing melayang di udara** — hanya di skybox/parallax, bukan collider.
4. **Kamera menengok** — roll/dutch dilarang, merusak prediksi sudut pantul.

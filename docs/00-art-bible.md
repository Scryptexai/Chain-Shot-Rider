# 00 — Art Bible: NEON

**Satu gambar adalah spesifikasi seluruh game ini.**

Key art *"Neon Bullet-Hell Combo Assault"*: seorang prajurit cyber tunggal di
dasar koridor neon menembakkan satu peluru raksasa yang memantul zig-zag di
antara dinding magenta, merantai petir, dan meledakkan drum — melawan ratusan
musuh merah yang menghujani lorong dengan tracer, sementara **x999 COMBO**
menyala di pojok kanan atas.

Setiap angka di dokumen ini diukur dari gambar itu atau dihitung darinya.
Kalau sebuah keputusan visual tidak bisa dilacak kembali ke sini, keputusan
itu salah.

> **Berkas referensi belum ada di repo.** Gambar dikirim lewat chat dan tidak
> tersimpan di filesystem. Simpan salinannya ke
> `docs/images/keyart-master.png` pada kesempatan pertama; sampai itu terjadi,
> dokumen inilah satu-satunya salinan spesifikasinya.

---

## 1. Framing — dihitung, bukan ditebak

Tiga hal diukur dari gambar:

| Ukuran | Nilai |
|---|---|
| Titik tengah badan pemain | **87%** tinggi layar |
| Tinggi pemain | **18,5%** tinggi layar |
| Garis horizon | **14%** tinggi layar |

Tiga ukuran, tiga variabel (tinggi kamera, kedalaman kamera, pitch) — jadi
framing-nya **tertentu**. `tools/solve_framing.py` menyelesaikannya:

```
heightOffset  15.95      FOV vertikal   60° @ 9:16
backOffsetZ   11.10      roll            0°  (dutch angle dilarang)
pitchDegrees  22.50      yaw             0°
lookTargetZ   27.4  (ruang arena)
```

**Pitch-nya rendah, bukan curam.** Pembacaan mata pertama hampir selalu
"sekitar 54°", karena lantai di dekat pemain terlihat sangat miring. Itu
ilusi: tepi bawah frame 60° sudah menunjuk 52° ke bawah dengan sendirinya.
Kalau pitch benar-benar 54°, horizon terlempar jauh ke luar layar dan lorong
berubah jadi papan permainan dilihat dari atas.

### Lebar lorong

Pada framing ini, dinding di x=±10 baru masuk layar di z≈20 — artinya separuh
pantulan peluru terjadi di luar layar, yang sama saja dengan mekanik yang
tidak ada. **Lorong = 12 unit (x = ±6)**, dan kedua dinding terbaca sejak
z≈2. Kebetulan yang menguntungkan: lorong sempit juga persis seperti di key
art, dan lebih banyak pantulan per tembakan.

### Peta zona layar

```
  0% ──────── kabut ungu · siluet kota · vortex ────────
 14%          horizon
 20% ┐
     │  KERUMUNAN JAUH    hiasan, di luar simulasi (z 44..96)
 42% ┤
     │  ARENA             z 40 → 5, musuh + gerbang + hujan tracer
 72% ┤
     │  ZONA PANTUL       dinding magenta, drum, lintasan peluru
 85% ┤
     │  PEMAIN            lantai grid cyan, prajurit, kilatan biru
100% ┘
```

---

## 2. Palet

Sumber tunggal: `Config/arena_config.json` → `artDirection`. **Jangan pernah
menulis hex di kode.**

| Peran | Hex | Di gambar |
|---|---|---|
| Player Cyan | `#2BE8FF` | kisi lantai, kilatan moncong, rim armor |
| Player Steel | `#DCE6F2` | zirah putih-biru |
| Player Deep | `#2E5BD8` | pelat gelap zirah |
| Bumper Magenta | `#FF2BD6` | dinding pantul |
| Bumper Core | `#FF9BEE` | inti panas di titik benturan |
| Tracer Red | `#FF2A2A` | hujan tracer musuh |
| Enemy Red | `#E03A2F` | zirah badan musuh |
| Enemy Orange | `#FF7A18` | aksen bahu/helm musuh |
| Blast Orange | `#FF9A2E` | bola api |
| Blast Core | `#FFE3A0` | inti ledakan |
| Chain Violet | `#A64BFF` | busur petir |
| Vortex Purple | `#6B2FA8` | black hole latar |
| Night Base | `#070A14` | kota, bayangan |
| Combo Chrome | `#9BF2FF` + outline `#0A2A33` | teks x999 COMBO |
| Brass Bullet | `#D9A441` | selongsong chain shot |

**Rasio layar** (kenapa ini tidak terlihat seperti permen neon): ~55% gelap ·
25% merah/oranye · 12% magenta/ungu · **8% cyan**. Cyan adalah warna paling
sedikit di layar dan justru karena itu pemain langsung terbaca.

**Arti warna, dipegang mati-matian:**
cyan = milik pemain · magenta = permukaan pantul · merah/oranye = ancaman ·
ungu = tenaga rantai · brass = peluru.

---

## 3. Elemen

**Pemain** — satu badan. Zirah hard-surface biru-putih, visor tertutup, tanpa
wajah. Stance kaki lebar, satu tangan mengangkat senjata. Rim light cyan di
seluruh siluet, pantulan di lantai basah. Kilatan moncong **biru** — itulah
satu-satunya cara membedakan tembakan sendiri dari hujan tracer musuh dalam
seperlima detik. Digambar 1,35× lebih besar dari unit mana pun: ia jangkar
komposisi.

**Kerumunan** — ratusan unit identik, merah-oranye, berbaris rapat. Perbedaan
tipe dibaca dari **siluet dan nilai warna**, tidak pernah dari hue yang
berbeda; 200 unit harus tetap terbaca sebagai satu pasukan. Makin jauh makin
larut ke kabut. Yang terkena ledakan terlempar ke udara.

**Dinding pantul** — slab panel magenta yang menyala, bukan batu. Permukaan
teknis dengan sambungan dan garis data. Tepi atasnya pita paling terang:
itulah garis yang dipakai pemain memperkirakan sudut. Saat kena peluru:
menyala lokal lalu meredam.

**Drum** — badan gelap merah bertanda bahaya, hanya pita atas yang panas.
Emissive penuh membuatnya terbaca sebagai lampu dan pemain berhenti takut.

**Lantai** — pelat logam gelap, basah, dengan kisi cahaya cyan. Garis
**menebal** dekat pemain dan **meredup** ke horizon: itu yang membuat zona
pemain terbaca sebagai lantai dan zona spawn terbaca sebagai kedalaman.
Pantulan dinding merembes ke lantai dalam bentuk goresan memanjang.

**Latar** — kota cyberpunk gelap dengan jendela menyala, kabut ungu tebal,
vortex berpilin di kanan atas, puing melayang.

---

## 4. Efek serangan

| # | Efek | Spesifikasi |
|---|---|---|
| E1 | **Chain shot** | Selongsong brass (r 0.26, h 0.92) menghadap arah gerak. Jejak pita api 18 titik, menyempit ke ekor, inti putih → oranye, aditif. Filamen ungu saat combo ≥ 20. |
| E2 | **Ricochet impact** | Flare radial 0,12 s · 16 percik searah normal · busur ungu 0,25 s · dinding menyala lokal lalu meredam 0,3 s · hitstop 40 ms · shake kecil. |
| E3 | **Hujan tracer** | Batang tipis merah, satu MultiMesh, cap 160 aktif, umur 0,55 s. Menuju **sekitar** pemain, bukan tepat ke pemain — tembakan yang bertemu di satu titik terbaca sebagai corong, bukan hujan. |
| E4 | **Ledakan** | Inti putih-kuning → kulit oranye → asap, ~0,8 s. Cincin kejut di lantai dengan radius **persis sama** dengan radius ledakan di simulasi; pemain belajar jangkauan drum dari cincin itu. Melempar musuh. |
| E5 | **Chain lightning** | Busur zig-zag 7 segmen dari titik pantul ke tengah lorong. Berkedip, bukan memudar — petir yang memudar terbaca sebagai asap. < 0,2 s, maks 6 aktif. |
| E6 | **Combo burst** | Angka chrome-cyan besar di kanan atas, outline gelap tebal, punch scale saat naik, memutih saat combo tinggi. Milestone: flash + shake + stinger. |

**Aturan yang membatalkan semua efek di atas:** kalau sebuah efek menutupi
lintasan peluru lebih dari 0,15 detik, efek itu dipotong. *Readability beats
beauty.*

---

## 5. Post-processing

| Efek | Nilai | Alasan |
|---|---|---|
| Glow | threshold 0,60 · intensitas 1,15 · bloom 0,28 | semua neon di gambar "mekar" |
| Tonemap | ACES, exposure 1,10, white 6 | inti ledakan hampir putih tanpa jadi bidang rata |
| Fog | `#2A1340`, densitas 0,022 | ujung lorong larut, bukan dipotong |
| Vignette/saturasi | saturasi 1,08 · kontras 1,05 | memusatkan mata ke lorong |
| Chromatic aberration | maks 0,25, hanya saat bullet-time | aksen, bukan gaya tetap |

---

## 6. Yang sengaja TIDAK diambil dari gambar

1. **Vortex sebagai gameplay.** Ia dekorasi latar. Gravity well yang
   sesungguhnya adalah rintangan kecil di lantai; memberi dua benda arti
   gameplay yang sama hanya membingungkan.
2. **Kepadatan tracer seperti di gambar** (ratusan). Dibatasi 160 dan dibuat
   terbaca lewat panjang streak, bukan lewat jumlah.
3. **Puing melayang** hanya di latar, tidak pernah punya collider.
4. **Kamera menengok / dutch angle.** Merusak prediksi sudut pantul, yang
   merupakan seluruh isi permainan ini.

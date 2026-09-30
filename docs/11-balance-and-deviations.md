# 11 — Balance Pass & Deviasi Spec

Dokumen ini mencatat **perubahan yang menyimpang dari spesifikasi awal**, alasannya,
dan angka yang mendasarinya. Semua angka berasal dari `tools/sim_test.js` — harness
headless yang memuat logika gameplay langsung dari `prototype/index.html`, jadi yang
diukur adalah aturan yang benar-benar berjalan, bukan salinannya.

Metode baku: **6 seed × 5 varian = 30 run per konfigurasi**, bot "skilled".
Satu seed tidak dipakai untuk mengambil keputusan (lihat §5).

---

## 1. Ringkasan deviasi

| # | Spec awal | Jadi | Alasan singkat |
|---|---|---|---|
| D1 | Peluru ditembakkan lurus ke depan | Turret **menyapu ±58° @ 75°/detik**, tap menembak pada sudut saat itu | Tanpa ini mekanik inti tidak pernah aktif: 0.10 bounce/peluru |
| D2 | Dinding atas = spawn gate (peluru keluar) | Spawn gate **memantulkan peluru**; musuh tetap masuk lewat sana | Mengembalikan separuh ruang ricochet |
| D3 | Kecepatan musuh 1.2 / 2.2 / 0.6 / 0.9 / 1.0 / 1.4 | 0.6 / 1.1 / 0.5 / 0.5 / 0.5 / 0.7 | Sesi terlalu pendek (55 s); Runner 2.2 melanggar rentang spec sendiri |
| D4 | `bullet.radius` 0.18 | **0.26** | Lever paling efektif untuk kill throughput |
| D5 | `invulnerabilityAfterHit` hanya ada di config | Diterapkan nyata (1 detik) | Tanpa itu 3 kebocoran berbarengan = game over seketika |

D1 dan D2 adalah perubahan **desain**, bukan penyetelan angka — keduanya dijelaskan penuh di bawah.

---

## 2. D1 — Kenapa bidikan harus menyapu

### Gejala
Run terasa hambar. Bot "skilled" dan bot acak menghasilkan skor yang praktis sama,
padahal keduanya bermain sangat berbeda. Itu pertanda **skill tidak punya saluran
untuk berpengaruh**.

### Pengukuran
Instrumentasi pada 63 peluru dalam satu run penuh:

| Metrik | Nilai | Artinya |
|---|---|---|
| Rata-rata bounce per peluru | **0.10** | Peluru hampir tidak pernah menyentuh dinding |
| Peluru yang pernah menyentuh crowd | **7 dari 63** | 89% tembakan tidak melakukan apa pun |
| Musuh yang bisa dijangkau satu tembakan | **3 dari 30** | Hanya yang punya \|x\| < 0.56 |
| Nasib akhir peluru umumnya | keluar di `z = 40` | Mati di spawn gate tanpa memantul |

Akar masalahnya aritmetika sederhana: peluru selalu punya `dx = 0`, sedangkan dinding
samping ada di `x = ±10`. Sebuah vektor dengan komponen-x nol **tidak akan pernah**
mencapai dinding samping. Jadi "ricochet + bullet riding" — inti fantasi game ini —
secara mekanis mustahil terjadi. Ini cacat desain, bukan bug implementasi.

### Kenapa solusinya sapuan otomatis, bukan aim manual
Batasan yang Anda tetapkan: **portrait, satu jempol, tidak ada kontrol gerak**.
Menambah joystick atau drag-to-aim melanggar itu. Sapuan otomatis menyelesaikan
masalah tanpa menambah satu pun gestur baru:

- Gestur tetap persis dua: **tap** (tembak / rem) dan **swipe horizontal** (steer).
- "Tap = tembak" tetap utuh; yang berubah hanya *ke mana* peluru pergi.
- Skill berpindah ke **timing** — memilih saat turret sejajar dengan kerumunan
  terpadat. Ini justru menambah kedalaman yang tadinya tidak ada.

Sudut hanya dimajukan di dalam tick simulasi ber-delta tetap, jadi determinisme aman.

### Hasil
| | Sebelum | Sesudah |
|---|---|---|
| Kill per run | 30 | 131 |
| Combo terbaik | 13 | 54 |
| Durasi run | 30.9 s | 39.5 s |

---

## 3. D2 — Dinding atas memantulkan peluru

Spawn gate yang menyerap peluru membuang separuh permukaan pantul arena: setiap
peluru yang lolos ke atas langsung mati. Karena musuh datang dari atas, peluru
justru paling sering mengarah ke sana.

Perubahannya memisahkan dua peran yang tadinya digabung dalam satu dinding:

- **Untuk musuh** — tetap gerbang: mereka masuk lewat `z = 40` seperti biasa.
- **Untuk peluru** — bumper dengan restitution 0.95.

Efeknya peluru bisa memantul turun kembali dan menyapu crowd dari belakang, yang
menghasilkan chain panjang. Di config: `arena.walls.top.absorbsBullet = false`,
tipe `spawn_gate_bumper`. Di Unity: `IArenaQuery.TopAbsorbsBullet`.

Digabung dengan D1: **kill 131, wave 5 tercapai** untuk pertama kalinya.

---

## 4. D3–D5 — Penyetelan angka

Sweep kecepatan musuh, masing-masing 25–30 run:

| Skala kecepatan | Durasi | Wave | Kill | Sesi dalam 60–180 s |
|---|---|---|---|---|
| ×1.0 (spec awal) | 55 s | 4.2 | 257 | 8/25 |
| ×0.8 | 59 s | 4.4 | 259 | 6/25 |
| ×0.65 | 77 s | 4.8 | 367 | 21/25 |
| **×0.5 (dipakai)** | **104 s** | **5.0** | **455** | **25/25** |

Kecepatan final semuanya tetap di dalam rentang spec 0.5–1.5 u/s:

| Tipe | Semula | Jadi |
|---|---|---|
| Grunt | 1.2 | 0.6 |
| Runner | 2.2 ← melanggar spec | 1.1 |
| Brute | 0.6 | 0.5 |
| Shielder | 0.9 | 0.5 |
| Splitter | 1.0 | 0.5 |
| Bomber | 1.4 | 0.7 |

---

## 5. Lever yang dicoba dan TIDAK berhasil

Dicatat supaya tidak diulang:

| Lever | Hasil |
|---|---|
| `autoReloadDelay` 0.35 → 0.25 → 0.18 | **Nol perubahan.** Amunisi bukan bottleneck |
| Ukuran magazine | Nol perubahan, alasan sama |
| HP Brute 60 → 25 | Hampir tidak berpengaruh |
| `maxBounce` 15 → 25 | Sedikit **memperburuk** |

Pelajaran metodologi: sweep dengan **satu seed tidak bisa dipercaya**. Contoh nyata —
radius 0.18 menghasilkan 260 kill sementara radius 0.24 menghasilkan 190 kill, yaitu
urutan yang terbalik dari yang seharusnya. Variansi antar-seed lebih besar daripada
efek yang diukur. Semua keputusan di dokumen ini memakai minimal 25 run.

---

## 6. Kondisi akhir (terverifikasi)

Konfigurasi final, 30 run, dengan boss aktif:

| Metrik | Hasil | Target |
|---|---|---|
| Durasi rata-rata | **105.2 s** | 60–180 s ✓ |
| Rentang durasi | 58–135 s | — |
| Run dalam jendela target | **29/30** | — |
| Mencapai boss (wave 5) | **30/30** | — |
| Bot menang | **3/30 (10%)** | 5–20% ✓ |
| Pelanggaran invariant | **0** | 0 ✓ |
| Determinisme (5 varian × 120 s) | **identik** | identik ✓ |

Bot menang 10% adalah kurva yang diinginkan: bot ini **pemain medioker** — ia tidak
pernah menembak sambil riding dan hanya mengarahkan ke centroid crowd. Pemain manusia
yang kompeten menang; pemain biasa kalah tipis di boss. Kalau bot menang >50%, game
terlalu mudah untuk manusia.

### Catatan untuk balance pass berikutnya
- Bot belum memanfaatkan steer saat riding secara agresif; angka kemenangan manusia
  kemungkinan lebih tinggi dari 10%. Uji pada perangkat nyata sebelum mengubah lagi.
- Bug determinisme yang sempat lolos: splitter memakai `Math.random()` untuk fase
  sway. Uji determinisme lama hanya berjalan 20 detik, sedangkan splitter baru muncul
  di wave 3 — jadi ujinya **hijau palsu**. Horizon uji sekarang 120 detik penuh.
  Aturannya: apa pun yang menyentuh state simulasi **wajib** lewat `S.rng` /
  `DeterministicRng`; `Math.random()` hanya boleh untuk pitch audio dan shake render.

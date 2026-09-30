# 12 — Perbandingan Mode Bidikan (keputusan MVP v1)

**Keputusan: mode bidik MANUAL.** Sapuan otomatis (deviasi D1 di [doc 11](11-balance-and-deviations.md)) dipensiunkan.

Alat ukur: `tools/aim_ab.js`. Metode: 6 seed × 5 varian = **30 run per konfigurasi**.

---

## 1. Dua mode yang diuji

| | `sweep` | `manual` |
|---|---|---|
| Cara kerja | Turret menyapu kiri-kanan sendiri; tap menembak pada sudut saat itu | Tahan lalu geser mendatar untuk membidik; lepas untuk menembak |
| Tuas yang dikuasai pemain | Waktu tembak saja | Sudut **dan** waktu tembak |
| Jumlah gestur | 2 (tap, geser saat riding) | 2 (geser-lepas, geser saat riding) |
| Satu jempol | Ya | Ya |

Keduanya memajukan sudut **hanya di dalam tick simulasi**, jadi determinisme aman di dua-duanya (terverifikasi, 5 varian × 120 detik).

---

## 2. Hasil

Semua bot dibebani latensi reaksi 200 ms dan laju keputusan 10 Hz. Bot manual tambahan membayar waktu geser jempol dan ongkos tekan-lepas 0.12 detik.

| Kebijakan pemain | Mode | Durasi | 60–180 s | Kill | **Menang** | Tembakan | Bounce/peluru |
|---|---|---|---|---|---|---|---|
| Mahir (geser 300°/s) | manual | 109 s | **30/30** | 483 | **9/30 — 30%** | 111 | 6.44 |
| Mahir (geser 180°/s) | manual | 111 s | 29/30 | 471 | **10/30 — 33%** | 111 | 6.51 |
| Mahir | sweep 75°/s | 88 s | 27/30 | 343 | **0/30 — 0%** | 45 | 7.75 |
| Mahir | sweep 45°/s | 86 s | 28/30 | 332 | **0/30 — 0%** | 43 | 7.92 |
| Pemula | manual | 75 s | 15/30 | 271 | 1/30 — 3% | 60 | 4.95 |
| Pemula | sweep 75°/s | 105 s | 29/30 | 459 | 3/30 — 10% | 84 | 6.63 |
| Pemula | sweep 45°/s | 101 s | 28/30 | 434 | 4/30 — 13% | 75 | 6.74 |

"Pemula" = membidik ke pusat massa crowd. "Mahir" = menilai sudut dengan memprediksi lintasan pantul (fungsi yang sama dengan garis bidik pemain), lalu menembak sesering amunisi mengizinkan.

---

## 3. Alasan keputusan

### Di mode sweep, kemahiran justru merugikan

Angka paling penting di tabel itu bukan jumlah kill, melainkan arah perubahan menang:

| | pemula → mahir |
|---|---|
| manual | 3% → **33%** (naik 11×) |
| sweep | 10% → **0%** (turun) |

Ini bukan kebetulan, melainkan akibat struktur kontrolnya. Di mode sweep pemain hanya menguasai **satu** tuas: kapan menekan. Bermain lebih selektif berarti menembak lebih jarang — tembakan turun dari 84 ke 45 — dan tidak ada cara mengkompensasi, karena sudutnya bukan milik pemain. Usaha untuk bermain lebih baik langsung memotong throughput.

Di mode manual pemain punya **dua** tuas yang saling menguatkan: ia bisa menembak pada laju penuh sekaligus memilih sudut yang bagus. Kemahiran terbayar.

Untuk game yang hidup dari retensi, mode yang menghukum pembelajaran adalah cacat desain, bukan sekadar pilihan rasa.

### Mode manual tetap menyelesaikan masalah asli

Masalah yang melahirkan sapuan otomatis adalah peluru lurus yang tidak pernah memantul: **0.10 bounce/peluru**. Mode manual mengembalikan kendali ke pemain **tanpa** menghidupkan lagi masalah itu — bahkan pemula mencapai 4.95 bounce/peluru, yang mahir 6.44.

### Ongkosnya: pemula lebih menderita

Ini biaya nyata dan harus diakui. Pemula di mode manual hanya 15/30 run yang masuk jendela sesi, dibanding 29/30 di mode sweep. Mode manual punya kurva belajar lebih curam.

Mitigasi yang disarankan untuk v1.1, **bukan** untuk v1 (jangan menyetel sebelum ada data pemain sungguhan):
- Bantuan bidik ringan pada 3 run pertama (snap ±4° ke sudut yang lintasannya mengenai musuh).
- Garis bidik sudah ada dan gratis — biarkan ia yang mengajar, karena ia memperlihatkan pantulan sebelum pemain menembak.

---

## 4. Catatan metodologi (dua kesalahan yang sempat terjadi)

Dicatat karena keduanya sempat menghasilkan kesimpulan yang **terbalik**:

1. **Bot pertama membidik pusat massa crowd.** Formasi game ini simetris, jadi pusat massanya hampir selalu di `x ≈ 0` — bot manual menembak lurus terus dan tidak pernah memakai dinding. Dengan bot itu sweep tampak menang telak (459 vs 352 kill). Yang diukur sebenarnya bukan modenya, melainkan kebijakan bot yang tidak memakai kemampuan mode manual.

2. **Bot "mahir" versi pertama menahan tembakan** sampai sudutnya sempurna, sehingga hanya menembak 26–44 kali per run melawan 75–97 kali milik bot pemula — dan kalah. Itu bukan kemahiran, itu kelambatan. Pemain sungguhan menembak sesering mungkin *sambil* membidik sebaik mungkin. Setelah bot mahir diperbaiki, kesimpulannya berbalik.

Pelajaran: saat membandingkan dua skema kontrol, **kebijakan bot harus adil untuk keduanya**, dan setiap keunggulan buatan harus dibebani ongkos yang setara di dunia nyata (waktu geser jempol, latensi reaksi, laju keputusan).

---

## 5. Konsekuensi untuk implementasi

- `Config/arena_config.json` → `aim.mode = "manual"`. Mode `sweep` **tetap dipertahankan di kode** di belakang flag, karena berguna sebagai mode aksesibilitas dan sebagai pembanding kalau balance berubah.
- Prototipe: tahan-geser-lepas; saat riding, geser tetap berarti steer dan tap berarti rem.
- Unity: `AimController` mendukung kedua mode lewat `AimMode` dari config.
- Garis bidik menjadi **wajib**, bukan hiasan: di mode manual ia satu-satunya umpan balik sebelum menembak.

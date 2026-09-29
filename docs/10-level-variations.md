# 10. Level Variations — 5 Arena

Setiap varian harus mengubah **cara pemain berpikir**, bukan sekadar warna. Aturan desainnya: satu varian = satu pertanyaan taktis baru.

| # | Arena | Pertanyaan taktis | Mekanik pembeda |
|---|---|---|---|
| 1 | Classic Pit | "Berapa sudut yang benar?" | Bumper simetris, pantulan 45° murni |
| 2 | Twin Towers | "Lorong mana yang kubuka?" | Koridor sempit, zig-zag bernilai tinggi |
| 3 | Gravity Chamber | "Kemana peluru ini akan melengkung?" | Lintasan non-linear |
| 4 | Explosive Yard | "Barrel mana yang jadi pemicu?" | Damage tidak langsung, chain |
| 5 | Moving Maze | "Kapan waktunya menembak?" | Timing, bukan sudut |

---

## 1. Classic Pit — *arena pengajar*

| | |
|---|---|
| **Layout** | 4 bumper simetris di `(±5.5, 13)` dan `(±5.5, 23)` |
| **Tema** | Cyan `#00E5FF` / Merah `#FF4D3D` / Ungu `#B14DFF`, BG navy → hitam |
| **Musik** | `base_synth` saja — paling bersih, agar pitch ladder bounce jelas terdengar |
| **Musuh spesial** | **Runner** — cepat, memecah formasi rapat sehingga pemain belajar memprioritaskan |
| **Boss** | **Colossus** — HP 1200, turun lambat, slam tiap 4 detik. Titik lemah terbuka 1.5 detik setelah slam |

**Maksud desain:** ini adalah arena tempat pemain **membangun model mental pantulan**. Empat bumper ditempatkan pada jarak yang membuat tembakan lurus dari player memantul tepat menyapu lebar penuh crowd — hadiah untuk tembakan sempurna, tapi hanya kalau pemain menahan diri untuk tidak menembak terlalu cepat. Tidak ada gangguan lain: tanpa gravity, tanpa timing, tanpa ledakan.

---

## 2. Twin Towers — *arena presisi*

| | |
|---|---|
| **Layout** | 2 pilar `r = 2.4` di `(±3.6, 20)` + 4 bumper di dinding `(±7.5, 11)` dan `(±7.5, 28)` |
| **Koridor** | Tengah **2.4 unit**, sisi **4.0 unit** — keduanya di atas minimum 2.0 |
| **Tema** | Magenta panas `#FF3DBE`, BG ungu klub `#170B2E` |
| **Musik** | `base_synth + arp` (arpeggio 16th) — menaikkan detak, terasa menekan |
| **Musuh spesial** | **Brute** — memantulkan peluru, berfungsi sebagai **bumper hidup** di dalam lorong |
| **Boss** | **Twin Warden** — sepasang, gerak cermin, HP 900 masing-masing. Keduanya harus mati dalam 3 detik atau yang tersisa menyembuhkan pasangannya |

**Maksud desain:** dua pilar membelah arena jadi tiga lorong. Peluru yang masuk lorong sisi dan memantul di antara pilar & dinding bisa mencapai **8–12 bounce dalam 1.5 detik** — combo tertinggi di game, tapi menuntut sudut awal yang presisi. Brute di dalam lorong mengubah geometri secara dinamis.

---

## 3. Gravity Chamber — *arena intuisi*

| | |
|---|---|
| **Layout** | Gravity well `r = 4, force = 5` di `(-4, 15)` dan `(+4, 26)`, diagonal; 2 bumper di `(±6, 21)` |
| **Jarak antar well** | 13.6 unit — jauh melebihi jumlah radius (8), jadi medannya **tidak pernah tumpang-tindih** |
| **Tema** | Teal `#4DFFD2` / Pink `#FF3D6E` / Ungu lembut, BG biru dalam |
| **Musik** | `base_synth + pad` (reverb panjang) — melayang, memperlambat persepsi waktu |
| **Musuh spesial** | **Splitter** — pecah jadi 3 grunt; di dalam medan gravitasi pecahannya tersedot dan menciptakan target sekunder |
| **Boss** | **Singularity** — HP 1000, orbit + pulse tarikan tiap 3 detik. Shield berputar; inti terbuka hanya saat pulse |

**Maksud desain:** ini satu-satunya arena dengan lintasan **non-linear**. Gravity well memutar arah peluru (bukan menambah kecepatan) hingga 120°/detik, jadi peluru melengkung mengelilingi well seperti komet. Dua well diagonal membuat lintasan S yang bisa menyapu dua kelompok crowd sekaligus. Pemain tidak bisa menghitung sudut di sini — ia harus **merasakan**nya.

---

## 4. Explosive Yard — *arena kausalitas*

| | |
|---|---|
| **Layout** | 9 barrel dalam 3 kelompok (`z = 12–14`, `z = 18`, `z = 24–27`) + 1 pilar pusat di `(0, 22)` |
| **Chain** | radius 3.0, delay 0.08 s/tingkat, kedalaman maks 8 |
| **Tema** | Oranye `#FF8A2B` / Merah `#FF2D55`, BG cokelat terbakar `#2B0C05` |
| **Musik** | `base_synth + percussion` (tom + industrial hit) — agresif |
| **Musuh spesial** | **Bomber** — meledak saat mati (r 2.5), menjadi **barrel bergerak** yang masuk sendiri ke kerumunan |
| **Boss** | **Pyro Baron** — HP 1100, menjatuhkan barrel baru ke arena lalu charge. Titik lemah: ledakan barrel-nya sendiri |

**Maksud desain:** di sini **damage terbesar tidak datang dari peluru**. Satu peluru yang mengenai barrel yang tepat memicu rantai sepanjang arena. Jeda 0.08 detik per tingkat sangat penting — tanpa itu, delapan ledakan terbaca sebagai satu kilatan; dengan itu, terbaca sebagai **rantai yang menjalar**, dan itulah momen paling memuaskan di seluruh game. Pilar pusat memastikan peluru bisa dipantulkan kembali ke kelompok barrel yang terlewat.

---

## 5. Moving Maze — *arena ritme*

| | |
|---|---|
| **Layout** | 3 moving platform di `z = 12, 20, 28` (lebar 5, travel ±3, speed 2.0 / 2.5 / 1.8, fase berbeda) + 2 shield wall di `(-6.5, 16)` dan `(+6.5, 24)` |
| **Tema** | Hijau toksik `#7CFF4D`, BG hijau gelap `#06220F` |
| **Musik** | `base_synth + glitch` (stutter + bitcrush) — gelisah, sinkron dengan gerak platform |
| **Musuh spesial** | **Shielder** — kebal dari depan, harus dipukul dari samping/belakang |
| **Boss** | **Shifter** — HP 1400, teleport antar lajur mengikuti platform. Hanya rentan dari punggung |

**Maksud desain:** satu-satunya arena di mana **waktu lebih penting daripada sudut**. Platform menghalangi musuh (bukan peluru), jadi crowd tertahan dan formasi pecah secara dinamis menjadi kelompok-kelompok kecil — target empuk untuk peluru yang menembus. Tiga platform berfase beda menciptakan pola yang berulang tiap ~12 detik. Shield wall memaksa pemain merancang lintasan **memutar** untuk memukul dari belakang. Kombinasi keduanya: pemain belajar menunggu.

---

## Matriks Progresi

| | Arena 1 | Arena 2 | Arena 3 | Arena 4 | Arena 5 |
|---|---|---|---|---|---|
| Kesulitan sudut | ●●○○○ | ●●●●● | ●○○○○ | ●●○○○ | ●●○○○ |
| Kesulitan timing | ●○○○○ | ●●○○○ | ●●○○○ | ●●●○○ | ●●●●● |
| Potensi combo maks | ●●●○○ | ●●●●● | ●●●●○ | ●●●●● | ●●●○○ |
| Ketergantungan RNG | ●○○○○ | ●○○○○ | ●●○○○ | ●●●○○ | ●●○○○ |
| Urutan unlock | awal | 3 run | 6 run | 10 run | 15 run |

## Aturan Menambah Varian Baru

1. Tambahkan entri di `Config/arena_config.json` → `variants[]`.
2. Jalankan `python3 tools/blueprint_gen.py` — blueprint ASCII + tabel koordinat ter-generate otomatis.
3. Buat `SO_Variant_*.asset` lewat `ConfigImporter`.
4. Validasi dengan aturan penempatan di `docs/01-arena-blueprint.md` §1.6:
   koridor ≥ 2.0 u, tidak ada obstacle di `Z < 7` atau `Z > 32`, simetri kiri-kanan, gravity well tidak tumpang-tindih.
5. Uji di prototipe web (`prototype/index.html`) sebelum masuk Unity — iterasi layout di sana **10× lebih cepat**.

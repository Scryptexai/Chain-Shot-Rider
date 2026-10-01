# 14 — ATM dari Last War / Top War

Amati, Tiru, Modifikasi. Dokumen ini memisahkan ketiganya secara eksplisit supaya jelas mana yang dipinjam dan mana yang milik Chain Rider.

---

## Amati — apa yang sebenarnya dijual game itu

Yang perlu dicatat lebih dulu: **runner gate di iklan Last War bukan gamenya.** Game aslinya 4X base-building; minigame gate itu kurang dari 5% gameplay dan dipakai sebagai umpan akuisisi. Kalau kita meniru "Last War" secara utuh, kita membangun game strategi, bukan shooter.

Jadi yang di-ATM adalah **formula runner-nya**, yang memang genre tersendiri (Crowd City, Join Clash, Mob Control) dan terbukti:

| Elemen | Kenapa bekerja |
|---|---|
| Kontrol satu sumbu | Geser kiri-kanan. Tidak ada tutorial yang dibutuhkan. |
| Auto-fire | Dopamin konstan tanpa input. Pemain tidak pernah menganggur. |
| Gate matematika | Keputusan tiap beberapa detik, hasilnya terlihat seketika di jumlah pasukan. |
| Pasukan = HP dan DPS sekaligus | Satu angka yang dipahami langsung. Menang terlihat, kalah terasa. |
| Barrel / pickup | Hadiah opsional untuk pemain yang berani ambil risiko posisi. |
| Elite/boss di ujung | Puncak yang menguji tumpukan yang dibangun sepanjang stage. |

---

## Tiru — yang diambil apa adanya

- Squad di bawah, geser mendatar, **posisi adalah satu-satunya kontrol dasar**.
- Auto-fire terus-menerus; laju tembak naik seiring jumlah pasukan.
- Gate berpasangan turun mendekat, kiri/kanan, satu menguntungkan satu merugikan.
- Jumlah pasukan sebagai mata uang tunggal: naik lewat gate, turun lewat kebocoran musuh.
- Stage pendek, kartu upgrade di antara stage, tangga stage yang terbuka bertahap.

Ini membalik satu aturan lama proyek: dulu "player diam, semua mobilitas dari peluru". Sekarang player bergerak. Perubahan itu diminta secara eksplisit dan sudah berlaku di seluruh kode.

---

## Modifikasi — yang membuatnya bukan kloning

### 1. Chain shot: langit-langit kemahiran yang tidak dimiliki referensinya

Di Last War, skill maksimum pemain adalah memilih pintu yang benar. Setelah itu game main sendiri. Tidak ada cara bermain *indah*.

Chain Rider menambahkan lapisan kedua: peluru terarah yang **memantul dan bisa ditunggangi**. Auto-fire tetap jadi chip damage — dopamin dasarnya utuh — sementara chain shot adalah tempat kemahiran dibayar. Keduanya berbagi satu jempol tanpa bertabrakan:

| Keadaan | Gestur | Aksi |
|---|---|---|
| Idle | geser | menggerakkan squad |
| Idle | tap | menembakkan chain shot |
| Riding | geser | membelokkan peluru |
| Riding | tap | mengerem |

**Posisi squad adalah bidikannya.** Chain shot selalu melesat lurus ke depan, jadi sudut pantulan ditentukan oleh di mana Anda berdiri. Satu sumbu kontrol, dua kedalaman: menggeser untuk memilih gate *sekaligus* menyiapkan geometri pantulan. Inilah yang membuat kontrol Last War dan identitas Chain Rider menyatu, bukan sekadar bertumpuk.

Ini juga menggantikan bidik-drag 116° dari [doc 12](12-aim-mode-comparison.md). Temuan intinya tetap berlaku dan tetap jadi alasan desain ini: **sudut tembak harus milik pemain.** Sekarang pemain memilikinya lewat posisi, bukan lewat sudut drag.

### 2. Gate berlaku untuk peluru juga

Gate yang dilewati **peluru yang sedang ditunggangi** memberi efek ke peluru, bukan ke pasukan: `×` menambah jatah pantulan, `+` menambah sedikit, `−` memotong pantulan, `÷` melemahkan damage.

Efeknya, satu gate bisa dibaca dua cara. Anda bisa menggeser squad untuk mengambil pintu `×3`, atau membelokkan peluru yang sedang ditunggangi menembus pintu itu untuk mengubah satu tembakan jadi panjang sekali. Referensinya tidak punya keputusan semacam ini.

### 3. Hukuman yang skalanya benar

Pengukuran menemukan cacat pada tabel gate versi pertama. `−10` itu fatal saat pasukan 5 dan tidak terasa saat pasukan 60: **hukumannya paling berat justru ketika pemain sudah paling lemah**, yang memicu spiral kekalahan. Operasi negatif sekarang condong ke perkalian (`÷2`) dengan `−6` sebagai pelengkap, sehingga kerugian sebanding dengan tumpukan.

| Konfigurasi | Waktu mentok cap | Mati @ skill 0.5 |
|---|---|---|
| Awal (cap 60, −10) | 13,8% | 2,70 |
| Setelah tuning (cap 100, −6, ÷ lebih sering) | **8,5%** | **2,30** |

Kurva kemahiran setelah tuning, 500 run per baris, pasukan di akhir run 90 detik:

| Skill pemilihan gate | Pasukan akhir | Mati (nyawa 3) |
|---|---|---|
| 1,00 | 90,7 | 0,00 |
| 0,75 | 45,5 | 0,78 |
| 0,50 | 17,2 | 2,30 |
| 0,25 | 5,7 | 4,50 — kalah |

Monotonik dan berjarak lebar: tiap kenaikan kemahiran kira-kira menggandakan hasil, dan pemain koin-lempar bertahan tipis sementara pemain asal-asalan kalah. Itu bentuk kurva yang diinginkan.

**Sisa masalah yang belum selesai:** pemain sempurna masih 8,5% waktunya mentok di cap, dan di sana gate positif tidak bernilai. Perbaikan yang wajar untuk v1.1 adalah mengubah kelebihan pasukan jadi skor, bukan menaikkan cap terus.

---

## Hasil porting ke prototipe web

Loop ini sudah berjalan di `index.html` dan diukur harness. 6 seed × 5 varian per baris, bot mahir vs bot acak:

| | Bot mahir | Bot acak |
|---|---|---|
| Durasi median | 143 s | 90 s |
| Dalam jendela 60–180 s | 25/30 | 24/30 |
| Run buntu | 0/30 | 0/30 |
| Kill | 444 | 298 |
| Pasukan akhir | 70,6 | 3,0 |
| Menang | 22/30 | 1/30 |
| Pelanggaran invariant | 0 | 0 |

Determinisme lulus di 5 varian × 7200 tick, dan `draw()` dijalankan 600 kali tanpa error — dua pemeriksaan yang pernah memberi hasil palsu sebelumnya kalau dilewati.

Pemisahan 70,6 vs 3,0 pasukan itu intinya: kontrol posisi memang mengganjar pembacaan gate yang benar.

### Kebuntuan boss yang ditemukan pengukuran

Porting ini menyingkap bug desain yang tidak kelihatan di kode. Boss `shifter` hanya rentan bila peluru **bergerak turun** (`dz < −0.15`) — aturan yang masuk akal saat satu-satunya sumber damage adalah peluru memantul. Tapi auto-fire selalu bergerak **naik**, jadi auto-fire tidak akan pernah bisa melukainya. Dengan pasukan di cap, pemain juga tidak bisa mati. Hasilnya: 5 dari 30 run tidak pernah berakhir.

**Run buntu lebih buruk daripada kalah.** Kalah memberi informasi; buntu hanya membuang waktu pemain. Dua perbaikan:

1. `bossChipFactor` 0.35 — auto-fire selalu memberi damage kecil yang menembus gerbang kerentanan, sehingga kemajuan selalu ada. Chain shot yang mengenai jendela rentan tetap jauh lebih cepat, jadi jendela itu tetap bermakna sebagai insentif kemahiran.
2. `bossHpScale` 0.4 — model damage berubah total (auto-fire kini DPS utama), jadi HP boss lama tidak lagi relevan.

Sapuan yang dipakai memutuskan: skala 1,00 → 5 buntu; 0,65 → 5; 0,50 → 1; **0,40 → 0**.

---

## Meta progresi

Sengaja tipis. Retensi Last War berasal dari lapisan 4X penuh — itu berbulan-bulan dan game yang berbeda. Yang terbawa di sini: tangga stage, koin, skor terbaik, dan satu kartu upgrade antar-stage dari 8 kartu ([`meta.cards`](../Config/arena_config.json)). Kartu persentase bertumpuk secara perkalian, kartu datar secara penjumlahan — karena itu tabelnya menyimpan `mul` dan `add` terpisah, bukan satu `value` yang ambigu.

Disimpan sebagai JSON di `user://chainrider_save.json`, bukan resource biner, supaya save yang rusak bisa dibaca dan diperbaiki tangan.

# 15 — Menjalankan Project Godot

Project ada di `godot/`. Target: **Godot 4.3**, tanpa modul tambahan, tanpa C#.

```
godot/
  project.godot              setting engine, portrait, 60 Hz fixed tick
  config/arena_config.json   salinan dari Config/ (jangan diedit langsung)
  scenes/main.tscn           hierarki scene
  scripts/
    autoload/game_config.gd  pembaca config yang gagal berisik
    autoload/save_game.gd    meta progresi
    sim/det_rng.gd           xorshift128, algoritma sama dengan prototipe JS
    sim/ricochet.gd          matematika pantulan manual, statis, tanpa physics
    sim/sim_world.gd         SELURUH aturan main, nol dependensi engine
    view/arena_view.gd       render MultiMesh
    view/hud.gd              HUD portrait
    game.gd                  perekat input / simulasi / tampilan
```

Buka folder `godot/` di Godot 4.3 lalu tekan Play. Tidak ada langkah impor, tidak ada menu editor yang harus dijalankan lebih dulu.

Setelah mengubah `Config/arena_config.json`, jalankan `python3 tools/sync_config.py`.

---

## Kenapa Godot, dan di mana batasnya di sini

Godot dipilih karena open source, tanpa lisensi, dan punya binary headless yang bisa menjalankan game dari CLI. Alasan terakhir itu yang paling berharga: engine yang bisa dijalankan tanpa GUI berarti balance dan determinisme bisa diuji otomatis.

**Engine kini terpasang dan project sudah benar-benar dijalankan.** Unduhan otomatis tetap diblokir di sandbox ini (hanya npm dan PyPI yang lolos; GitHub release assets dan godotengine.org tertutup), jadi zip `Godot_v4.3-stable_linux.x86_64.zip` dipasok manual ke root repo dan `tools/install_godot.sh` memungutnya dari sana. Riwayat pemeriksaan statis:

| Pemeriksaan | Alat | Hasil |
|---|---|---|
| Sintaks GDScript | `gdparse` | 8/8 file lolos |
| Aturan gaya & struktur | `gdlint` | bersih |
| Format | `gdformat --check` | 8/8 tidak berubah |
| Jalur config yang dibaca kode | skrip silang | semua ada di JSON |
| Simbol lintas file | skrip silang | nol rujukan menggantung |
| Path resource di `main.tscn` | skrip silang | semua ada |
| Ekonomi gate | Monte Carlo 500 run × 4 skill | lihat [doc 14](14-lastwar-atm.md) |
| Loop penuh (prototipe web) | harness 6 seed × 5 varian | median 143 s, 0 buntu, determinisme lulus |

Semua pemeriksaan itu lolos — dan tetap **melewatkan empat bug** yang langsung muncul pada detik pertama engine dijalankan. Catatan ini layak disimpan: analisis statis pada GDScript memberi rasa aman yang jauh melebihi jangkauannya.

Tiga bug ditemukan oleh pemeriksaan silang itu, bukan oleh linter, dan sudah diperbaiki: `GameConfig.dict("")` mengembalikan kosong sehingga simulasi akan lahir tanpa angka sama sekali; sisi kanan gate memakai polaritas yang salah sehingga kedua pintu bisa merugikan; dan steering peluru tidak dibatasi laju sehingga drag cepat memutar 900°/detik, sepuluh kali batas spec.

### Yang hanya terlihat setelah engine dijalankan

| Bug | Gejala | Sebab |
|---|---|---|
| `chain_dir = Vector2.UP` | 28 chain shot → **0 kill** | `Vector2.UP` adalah `(0, -1)` karena Y layar menghadap ke bawah. Vektor ini hidup di bidang arena `(x, z)` yang z-nya membesar menjauhi pemain, jadi mekanik andalan game ditembakkan ke belakang dan keluar arena dalam beberapa tick. Sekarang ada `const FORWARD := Vector2(0.0, 1.0)`. |
| `spawnInterval` dibaca sebagai skalar | `Invalid call. Nonexistent 'float' constructor` | Nilainya array per-wave. Error itu **membatalkan sisa `_read_config`**, diam-diam mengembalikan `bossHpScale` ke 1.0 (bukan 0.4), `difficultyPerStage` ke 0, dan mengosongkan `comboMilestones`. Tiga dari lima stage jadi buntu. |
| Crowd disebar acak | 12 kill dalam 60 detik; kalah di wave 1, kelima varian | Spawner mengabaikan `spawn.formation`/`columnsRange`/`spacing`. Squad menembak lurus ke atas, jadi kerumunan selebar 18 unit mustahil dijangkau. |
| `_advance_chain` membuang sisa jarak | Peluru merayap di kerumunan; 15 pantulan tak pernah terpakai | `return` setelah kontak pertama, sisa `(1−t)` langkah hilang. |
| Wave menunggu arena kosong | Menggantung di wave 4 selama 300 detik, nyawa masih 3 | Prototipe yang sudah di-tuning memajukan wave dengan timer `spawnInterval`. Auto-fire mentok 9 tembakan/detik, jadi wave 120 musuh selalu mengalahkan jam. |

Dua perbaikan struktural menyertainya. `SimWorld.tick()` kini **membersihkan `events` sendiri**; sebelumnya konsumen yang wajib melakukannya, dan konsumen yang lupa membuat array tumbuh sepanjang sesi (harness headless pertama menghitung 33.375 "kill" dari 12 kill nyata). Lalu semua pembacaan angka config lewat `_num()` yang fail-soft, supaya satu kunci bertipe salah merugikan satu nilai saja, bukan setiap nilai sesudahnya.

---

## Setup di sandbox / CI

```bash
bash tools/install_godot.sh 4.3-stable   # engine + gdtoolkit
python3 tools/validate_godot.py          # cek yang linter tidak bisa
export PATH="$HOME/.cache/venv/bin:$PATH"
gdparse godot/scripts/sim/sim_world.gd
gdlint godot/scripts
gdformat --check godot/scripts
```

Skrip installer sengaja berbeda dari one-liner biasa dalam dua hal, keduanya dipelajari dari kegagalan nyata di sandbox ini:

1. **Ia memverifikasi apa yang diunduh.** Jaringan yang diblokir biasanya menjawab dengan halaman HTML error, dan `unzip` pada berkas itu gagal tiga langkah kemudian dengan pesan yang membingungkan. Di sini magic bytes diperiksa sebelum berkas dipercaya.
2. **Ia selalu memasang gdtoolkit.** Bagian itu tetap berhasil dari PyPI meski unduhan engine diblokir, dan itulah yang memungkinkan validasi GDScript tanpa engine sama sekali.

Ditambah satu hal ketiga setelah engine benar-benar dipasok: **zip lokal diperiksa sebelum jaringan disentuh.** Skrip memungut `Godot_v<versi>_linux.x86_64.zip` dari root repo, cwd, `~/.cache/godot/`, atau `~/Downloads/`. Verifikasi tipe berkas juga tidak lagi memanggil `file` — perintah itu tidak ada di image ramping ini, sehingga zip yang sah pun akan ditolak; sekarang magic bytes `50 4B 03 04` dibaca langsung.

Ekstraksi selalu menuju `~/.cache/godot/`, tidak pernah ke repo: binary-nya 110 MB. Zip 50 MB-nya sendiri sengaja ikut di-commit supaya sandbox offline bisa bootstrap.

Kalau semua mirror tidak terjangkau, skrip keluar dengan kode 3 dan menjelaskan apa yang masih bisa dipakai — bukan gagal diam-diam. Set `GODOT_MIRROR` untuk mirror sendiri.

`tools/validate_godot.py` memeriksa hal-hal yang berada di luar jangkauan linter: setiap jalur `GameConfig.num("...")` benar-benar ada di JSON, setiap simbol lintas file terdefinisi, setiap `res://` di scene dan autoload menunjuk berkas nyata, dan salinan config Godot tidak basi. Tiga bug nyata ditemukan justru oleh pemeriksaan ini, bukan oleh `gdlint`.

### Menjalankan engine

```bash
godot --headless --path godot/ --import   # bangun cache impor
godot --headless --path godot/ --quit     # boot main.tscn sekali
godot --headless --path godot/ --script res://tests/sim_headless.gd
godot --headless --path godot/ --script res://tests/sim_headless.gd -- --trace
godot --headless --path godot/ --script res://tests/sim_headless.gd -- --determinism
```

`--check-only --script <file>` **tidak** bisa dipakai untuk memeriksa berkas yang menyentuh autoload: mode itu memuat skrip tanpa mendaftarkan autoload, jadi `GameConfig` dilaporkan sebagai "Identifier not found" pada lima berkas yang sebenarnya sehat. Boot project penuh adalah pemeriksaan kompilasi yang sah.

### Dua harness, dua lapisan

`godot/tests/smoke.tscn` menjalankan **scene sungguhan** — Game, ArenaView, HUD, Screens — selama 1800 frame per varian sambil menyuntikkan input seperti jempol. Ia harus berupa scene, bukan `--script`, supaya autoload hidup. Dua hal yang ia tangkap dan tidak bisa ditangkap yang lain:

- Skrip yang **gagal dikompilasi** akan dilewati diam-diam oleh `has_method()`, sehingga game berjalan tanpa menggambar apa pun sambil tetap "lulus". Smoke kini memeriksa tiap node punya skrip dan metodenya.
- **Test yang tidak bermain tidak menguji apa-apa.** Versi pertama hanya menonton: tanpa tap, chain shot tak pernah lepas, jadi slow-mo, bullet riding, dan semua efek ricochet tetap kode mati yang "lulus".

`godot/tests/sim_headless.gd` adalah pasangan Godot dari `tools/sim_test.js`: bot bermain lima stage, mencatat hasil, memeriksa invariant tiap tick, lalu membandingkan hash dua run identik sepanjang 7200 tick × 5 varian. Keluar dengan kode 1 bila ada yang gagal, jadi CI bisa menggantung padanya. Keduanya terpisah dengan sengaja — urutan tick-nya berbeda, jadi replay tidak lintas-engine.

Satu pelajaran dari harness ini: **bot yang tidak menyetir peluru membuat harness berbohong.** Chain shot lepas lurus ke atas; tanpa input ia naik, memantul atap, turun lurus, dan keluar — 2 dari 15 pantulan. Bot pertama mengukur permainan yang tidak ada pemainnya. Versi kedua juga keliru dengan cara lain: ia parkir di x=±3 selama gerbang turun, dan karena gerbang hampir selalu ada di layar, ia berhenti menembak selama 45 detik beruntun. Bot sekarang memilih **sisi** gerbang lalu tetap melacak kerumunan di dalam sisi itu.

Catatan sandbox: `.cache` tidak ikut snapshot, jadi tiap sesi baru perlu menjalankan ulang installer. Itu murah — zip-nya sudah ada di repo, ekstraksi ~7 detik.

---

## Aturan arsitektur yang dijaga

**`sim_world.gd` tidak boleh menyentuh engine.** Tidak ada `Node`, `Input`, `delta` dari engine, atau pemanggilan render. Ia maju pada langkah tetap yang diberikan, membaca input dari struct biasa, dan menyimpan state di array datar. Tiga akibatnya: seed yang sama selalu replay identik, aturan bisa diuji headless, dan renderer bisa ditulis ulang tanpa menyentuh satu baris aturan pun.

**Simulasi tidak memakai RNG engine.** `RandomNumberGenerator` milik Godot baik-baik saja, tapi bukan generator yang dipakai harness saat mengukur balance. `det_rng.gd` memakai xorshift128 yang sama persis dengan prototipe web, sehingga satu seed bisa dibandingkan lintas kedua implementasi.

**Tidak ada physics engine untuk pantulan.** Setiap pantulan adalah refleksi bentuk tertutup yang dimiliki simulasi. Physics server akan memantulkan benda dengan senang hati, tapi hasilnya tidak bisa direproduksi: urutan kontak dan akumulasi floating point di dalam engine bukan bagian dari state yang kita simpan.

**Tabrakan memakai sweep, bukan cek jarak.** Pada 25 unit/detik, cek jarak diskrit menembus target kecil di antara dua frame.

**Render pakai MultiMesh, bukan satu node per unit.** 200 musuh ditambah 100 pasukan sebagai node berarti ratusan pembaruan transform per frame di Snapdragon 660.

---

## Sistem yang kini ada di engine

| Sistem | Berkas | Catatan |
|---|---|---|
| Obstacle per varian | `sim/obstacle_field.gd` | bumper (bonus damage), pillar, gravity well (melengkungkan peluru), shield wall (HP 3), moving platform (menahan crowd), barrel (ledakan berantai). Kelima arena akhirnya berbeda, bukan sekadar ganti warna. |
| 5 boss unik | `sim/boss.gd` | HP dan pola gerak dari config: `slow_descend_slam`, `mirror_pair_sidestep`, `orbit_pull_pulse`, `barrel_drop_charge`, `teleport_lane_swap`. Aturan facing **menskalakan** damage, tidak pernah menolkannya — run buntu lebih buruk daripada kalah. |
| Formasi crowd | `sim/formation.gd` | rect / vshape / diamond / circle, fungsi murni supaya replay tetap jujur. |
| Slow-mo, shake, FOV | `view/game_feel.gd` | `Engine.time_scale` sebagai tuas, jadi tick simulasi tidak berubah dan replay tetap identik. Shake memakai sinus meluruh, bukan noise, supaya 30 fps dan 60 fps sepakat. |
| Efek hantaman | `view/arena_view.gd` | 48 shell aditif yang dipakai ulang; alokasi per-kill adalah sampah per-frame yang dilarang budget. |
| Pembacaan config | `sim/cfg.gd` | `Cfg.num()` fail-soft, dipakai bersama oleh sim dan obstacle. |

Hasil terukur setelah semuanya: **0 buntu, 2/5 menang, rata-rata 75,7 detik** (jendela target 60–180), determinisme lulus 7200 tick × 5 varian, dan smoke test menembus renderer di kelima varian dengan slow-mo turun ke 0,30.

---

## Melihat hasil render tanpa GPU

Sandbox ini tidak punya GPU, X server, maupun `libGL` (`ldconfig -p | grep -c libGL`
= 0), dan `apt-get` tidak bisa menjangkau mirror Debian — `sudo apt-get update`
gagal dengan *Connection failed* ke `deb.debian.org`, jadi `xvfb` dan `mesa`
tidak bisa dipasang. Konsekuensinya jujur: **render Godot tidak bisa ditangkap
di sini sama sekali.** Godot hanya jalan `--headless` dengan renderer dummy.

Yang bisa ditangkap adalah prototipe, dan itu ternyata cukup berharga. npm bisa
diakses, dan `@napi-rs/canvas` adalah build Skia yang berdiri sendiri tanpa
dependensi sistem. Prototipe menggambar lewat Canvas2D biasa, jadi mengarahkan
context-nya ke Skia menghasilkan **frame yang sama persis dengan yang dilihat
browser** — `draw()` yang asli di atas state permainan yang asli, bukan mockup
atau diagram:

```bash
npm install --no-save @napi-rs/canvas
node tools/screenshot.js                    # kelima arena, t=42 s
node tools/screenshot.js --variant=2 --at=90
```

Hasil di `screenshots/*.png` (450×800). Harness ini memuat prototipe dengan
kontrak yang sama dengan `tools/sim_test.js` — satu blok `<script>`, boot
`fetch` dibuang, config disuntik dari disk — supaya perubahan yang merusak
salah satunya merusak keduanya dengan berisik, bukan diam-diam menyimpang.

Dua batasan yang harus diingat saat membaca PNG-nya:

1. **HUD tidak ada di gambar.** HUD prototipe adalah overlay DOM (`<div id="score">`,
   `#combo`, `#wave`, `#steerFill`), bukan canvas — di canvas hanya ada dua
   panggilan `fillText`. Jadi skor, nyawa, wave, dan steer meter memang tidak
   ikut tertangkap. Di browser semuanya tetap tampil.
2. **Ini prototipe, bukan Godot.** Keduanya berbagi palet (docs/02), config, dan
   spesifikasi layout (docs/06) — bukan renderer. Kecocokan visual Godot masih
   belum pernah diverifikasi dengan mata.

### Bug yang baru ketahuan setelah benar-benar dilihat

`proj()` memampatkan z = 33–43 ke sekitar 19% teratas layar, dan `zn` dibatasi
di 1.08. Musuh spawn di `baseZ = height + 1` plus kedalaman formasi, sehingga
**semua musuh di z ≥ 43,2 dipetakan ke satu baris layar yang sama** dan
menumpuk jadi lempengan padat tak terbaca di atas garis dinding jauh. Tidak ada
uji headless yang bisa menangkap ini; angka balance-nya sempurna. Perbaikannya
kosmetik murni — ramp alpha selebar 8 unit (z 42 → 34) sehingga zona spawn
terbaca sebagai gradien kedalaman, dan musuh sudah jelas jauh sebelum z = 34
(masih ~29 unit sebelum garis pertahanan di z = 5).

Angka damage yang bertumpuk juga disebar mendatar lewat field `jx`. Sebarannya
diturunkan dari posisi, **bukan dari `S.rng`** — memanggil RNG di jalur simulasi
demi kosmetik akan menggeser urutan acak dan merusak replay. Setelah kedua
perubahan, `tools/sim_test.js` tetap 3/5 menang, rata-rata 146,9 s: tidak ada
yang menyentuh simulasi.

## Yang belum ada

- **Musik** (doc 07 §7.3): SFX sudah lengkap, tapi layer musik per varian, dynamic
  mixing per wave, dan stinger akhir run belum ada. Bus `Music` sudah berdiri dan
  sudah di-duck saat slow-mo — yang kurang tinggal materi audionya.
- **Cue yang belum pernah terpicu di uji**: `combo_milestone`, `heartbeat`,
  `perfect_clear`, `kill_milestone`, `boss_roar`, `steer_warn`, `ui_tap`. Semuanya
  tersambung dan file-nya ada, tapi butuh run lebih panjang atau kondisi spesifik
  (boss di wave 5, 50 kill, combo 10) daripada smoke 30 detik.
- **Kartu upgrade antar-stage**: `SaveGame` sudah mendukung penuh, layarnya belum.
- **Interpolasi render**: tampilan membaca state simulasi langsung, belum ada
  interpolasi alpha antar tick — terasa di 30 fps, tidak di 60.
- **Pemilih arena 5 kartu**, slider volume, dan count-up tween di layar result.
- **Prototipe vs Godot**: prototipe masih memakai loop lama (player diam, bidik drag)
  dan belum mencerminkan desain Last War. Keduanya berbagi config dan palet, bukan kode.
- **27 file `.cs` Unity warisan** di `unity/` — sudah tidak jadi target, tapi masih ada
  di repo dan bisa membingungkan.
- **Komentar Bahasa Indonesia di `prototype/index.html`** melanggar aturan "komentar kode
  dalam English" yang berlaku di repo ini. File `.gd` sudah patuh.

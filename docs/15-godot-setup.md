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

**Batas jujurnya:** di lingkungan tempat kode ini ditulis, binary Godot tidak bisa diunduh — hanya npm dan PyPI yang lolos jaringan, sedangkan GitHub release assets dan godotengine.org diblokir. Jadi project ini **belum pernah dijalankan**. Yang sudah dilakukan:

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

Ini lebih kuat daripada yang bisa dicapai pada versi Unity sebelumnya, tapi tetap **bukan** pengganti menjalankannya. Harapkan penyesuaian pada percobaan pertama, terutama pembingkaian kamera dan skala HUD.

Tiga bug ditemukan oleh pemeriksaan silang itu, bukan oleh linter, dan sudah diperbaiki: `GameConfig.dict("")` mengembalikan kosong sehingga simulasi akan lahir tanpa angka sama sekali; sisi kanan gate memakai polaritas yang salah sehingga kedua pintu bisa merugikan; dan steering peluru tidak dibatasi laju sehingga drag cepat memutar 900°/detik, sepuluh kali batas spec.

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

Kalau semua mirror tidak terjangkau, skrip keluar dengan kode 3 dan menjelaskan apa yang masih bisa dipakai — bukan gagal diam-diam. Set `GODOT_MIRROR` untuk mirror sendiri, atau letakkan zip-nya di `~/.cache/godot/`.

`tools/validate_godot.py` memeriksa hal-hal yang berada di luar jangkauan linter: setiap jalur `GameConfig.num("...")` benar-benar ada di JSON, setiap simbol lintas file terdefinisi, setiap `res://` di scene dan autoload menunjuk berkas nyata, dan salinan config Godot tidak basi. Tiga bug nyata ditemukan justru oleh pemeriksaan ini, bukan oleh `gdlint`.

Catatan sandbox: `.cache` tidak ikut snapshot, jadi tiap sesi baru perlu menjalankan ulang installer. Itu murah — gdtoolkit terpasang dalam beberapa detik.

---

## Aturan arsitektur yang dijaga

**`sim_world.gd` tidak boleh menyentuh engine.** Tidak ada `Node`, `Input`, `delta` dari engine, atau pemanggilan render. Ia maju pada langkah tetap yang diberikan, membaca input dari struct biasa, dan menyimpan state di array datar. Tiga akibatnya: seed yang sama selalu replay identik, aturan bisa diuji headless, dan renderer bisa ditulis ulang tanpa menyentuh satu baris aturan pun.

**Simulasi tidak memakai RNG engine.** `RandomNumberGenerator` milik Godot baik-baik saja, tapi bukan generator yang dipakai harness saat mengukur balance. `det_rng.gd` memakai xorshift128 yang sama persis dengan prototipe web, sehingga satu seed bisa dibandingkan lintas kedua implementasi.

**Tidak ada physics engine untuk pantulan.** Setiap pantulan adalah refleksi bentuk tertutup yang dimiliki simulasi. Physics server akan memantulkan benda dengan senang hati, tapi hasilnya tidak bisa direproduksi: urutan kontak dan akumulasi floating point di dalam engine bukan bagian dari state yang kita simpan.

**Tabrakan memakai sweep, bukan cek jarak.** Pada 25 unit/detik, cek jarak diskrit menembus target kecil di antara dua frame.

**Render pakai MultiMesh, bukan satu node per unit.** 200 musuh ditambah 100 pasukan sebagai node berarti ratusan pembaruan transform per frame di Snapdragon 660.

---

## Yang belum ada

- **Belum dijalankan** (lihat di atas). Ini item nomor satu.
- **Barrel**: config, tabrakan, dan konstanta sudah ada; spawner-nya belum disambung.
- **Layar non-gameplay** (menu, pause, result) di doc 06.3 belum dibangun — baru HUD gameplay.
- **Boss**: satu pola gerak generik, belum 5 pola unik per varian seperti di [doc 05](05-prefab-spec.md).
- **Varian arena**: tema warna dibaca dari config, tapi obstacle per varian (bumper, pillar, gravity well, platform) belum di-spawn di Godot. Logikanya sudah ada dan teruji di prototipe web.
- **Audio, camera shake, partikel**: dirancang di doc 07/08, belum diimplementasikan. Vignette slow-mo sudah ada di HUD, tapi belum ada perlambatan waktu sungguhan.
- **Layar pemilihan kartu**: `SaveGame` sudah mendukung penuh, UI-nya belum.
- **Interpolasi render**: tampilan membaca state simulasi langsung, belum ada interpolasi alpha antar tick.

Prototipe web di `prototype/` masih memakai loop lama (player diam, bidik drag) dan **belum** mencerminkan desain Last War ini. Selama Godot belum bisa dijalankan, keduanya sementara berbeda — menyelaraskan prototipe adalah langkah berikutnya yang masuk akal, karena di situlah balance bisa benar-benar diukur.

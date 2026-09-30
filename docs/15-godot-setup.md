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

Ini lebih kuat daripada yang bisa dicapai pada versi Unity sebelumnya, tapi tetap **bukan** pengganti menjalankannya. Harapkan penyesuaian pada percobaan pertama, terutama pembingkaian kamera dan skala HUD.

Tiga bug ditemukan oleh pemeriksaan silang itu, bukan oleh linter, dan sudah diperbaiki: `GameConfig.dict("")` mengembalikan kosong sehingga simulasi akan lahir tanpa angka sama sekali; sisi kanan gate memakai polaritas yang salah sehingga kedua pintu bisa merugikan; dan steering peluru tidak dibatasi laju sehingga drag cepat memutar 900°/detik, sepuluh kali batas spec.

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
- **Boss**: satu pola gerak generik, belum 5 pola unik per varian seperti di [doc 05](05-prefab-spec.md).
- **Varian arena**: tema warna dibaca dari config, tapi obstacle per varian (bumper, pillar, gravity well, platform) belum di-spawn di Godot. Logikanya sudah ada dan teruji di prototipe web.
- **Audio, slow-motion, camera shake, partikel**: dirancang di doc 07/08, belum diimplementasikan.
- **Layar pemilihan kartu**: `SaveGame` sudah mendukung penuh, UI-nya belum.
- **Interpolasi render**: tampilan membaca state simulasi langsung, belum ada interpolasi alpha antar tick.

Prototipe web di `prototype/` masih memakai loop lama (player diam, bidik drag) dan **belum** mencerminkan desain Last War ini. Selama Godot belum bisa dijalankan, keduanya sementara berbeda — menyelaraskan prototipe adalah langkah berikutnya yang masuk akal, karena di situlah balance bisa benar-benar diukur.

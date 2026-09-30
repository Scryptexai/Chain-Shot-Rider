# 13 — MVP v1: Membuka Project Unity

Project Unity ada di `unity/`. Target editor: **Unity 2022.3 LTS** dengan URP.

---

## Tiga langkah

1. Buka folder `unity/` lewat Unity Hub. Unity akan mengunduh paket di `Packages/manifest.json` dan membuat `Library/` (tidak masuk Git).
2. Menu **ChainRider → Apply Project Settings** — memasang layer 8–15, kunci portrait, linear color, dan mematikan physics engine.
3. Menu **ChainRider → Import Config From JSON** lalu **ChainRider → Build Arena Scene**.

Scene siap main ada di `Assets/ChainRider/Scenes/02_Arena.unity`.

---

## Kenapa scene dan setting dibangun lewat skrip, bukan file YAML

File `.unity` dan `.prefab` adalah graf referensi GUID. Menulisnya tangan di luar editor menghasilkan file yang tampak masuk akal lalu gagal dibuka — atau lebih buruk, terbuka dengan referensi rusak diam-diam. Hal yang sama berlaku untuk `ProjectSettings.asset`: file setting yang ditulis separuh bisa merusak project.

Karena itu keduanya dibangun lewat API editor sungguhan:

| Alat | File | Fungsi |
|---|---|---|
| `ProjectSetup.cs` | `Editor/` | Layer, orientasi portrait, linear color, physics off |
| `ConfigImporter.cs` | `Editor/` | `Config/arena_config.json` → ScriptableObject |
| `ArenaSceneBuilder.cs` | `Editor/` | Scene + prefab placeholder + seluruh wiring |
| `MiniJson.cs` | `Editor/` | Pembaca JSON yang **gagal berisik** saat key hilang |

Konsekuensinya: setiap refactor tinggal satu klik ulang, bukan konflik merge.

`MiniJson` sengaja melempar error dengan path lengkap saat sebuah key tidak ada, bukan mengembalikan nol. Kalau `JsonUtility` dipakai, mengganti nama key di JSON akan diam-diam menghasilkan nilai 0 yang nanti terlihat seperti bug balance, bukan seperti salah konfigurasi.

Seluruh 67 key wajib, semua nilai enum (`formation`, `type` obstacle, `pattern` boss, `specialEnemy`), dan semua warna tema sudah diverifikasi cocok dengan config saat ini.

---

## JSON tetap satu sumber kebenaran

`Config/arena_config.json` adalah yang dijalankan prototipe web **dan** yang diukur `tools/sim_test.js`. Unity membaca angka yang sama, bukan menyimpan salinan kedua. Jadi perubahan balance tidak bisa berlaku di satu sisi saja.

Setelah mengubah JSON, jalankan lagi **Import Config From JSON**.

---

## Skema kontrol MVP

Dipilih lewat pengukuran, lihat [doc 12](12-aim-mode-comparison.md).

| Keadaan | Gestur | Aksi |
|---|---|---|
| Idle | tahan & geser mendatar | membidik turret (layar penuh = 116°) |
| Idle | lepas | menembak pada sudut saat itu |
| Bullet-riding | geser mendatar | membelokkan peluru (15°/swipe, meter 3 detik) |
| Bullet-riding | tap | mengerem peluru |

Satu jempol, dua gestur, tanpa tombol tambahan. Semuanya melewati `InputRouter.ApplyFrame` — satu-satunya tempat `InputFrame` berubah jadi aksi — sehingga input langsung dan replay tidak bisa menyimpang.

`AimController` masih mendukung mode `sweep` lewat `aim.mode` di JSON. Mode itu dipertahankan sebagai opsi aksesibilitas, bukan default.

---

## Yang belum ada di MVP v1

Jujur soal batasnya:

- **Art placeholder.** Prefab memakai primitif dengan warna datar, ukurannya sesuai `docs/05-prefab-spec.md`. Mengganti ke mesh asli cukup mengubah isi prefab.
- **Belum ada audio clip.** `AudioDirector` dan cue sheet sudah ada, file `.ogg`-nya belum.
- **Scene `00_Boot` dan `01_Menu` belum dibangun.** Baru `02_Arena`.
- **Belum pernah dikompilasi.** Tidak ada Unity maupun compiler C# di lingkungan tempat kode ini ditulis; yang bisa diverifikasi hanya keseimbangan kurung, konsistensi namespace/simbol lintas file, dan kecocokan key config. **Error kompilasi pertama harus diharapkan** — laporkan isinya dan akan diperbaiki.
- Yang **sudah** terbukti berjalan adalah prototipe web dan harness: balance, determinisme, boss, dan perbandingan mode bidikan semuanya diukur di sana.

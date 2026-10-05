# 02 — Membangun, menjalankan, memverifikasi

## Bentuk proyek

```
Config/arena_config.json     sumber kebenaran tunggal: aturan, palet, framing
godot/                       target utama (Godot 4.6)
  config/                    salinan config (res:// tidak bisa keluar folder)
  scripts/sim/               ATURAN MAIN — tanpa Node, tanpa delta engine
  scripts/view/              penggambaran; tidak pernah menulis ke sim
  scripts/view/vfx/          efek berkolam tetap, boleh dimatikan total
  scripts/ui/                layar non-gameplay
  shaders/                   lantai, dinding, latar
  tests/                     sim_headless (tanpa jendela), smoke.tscn (scene nyata)
index.html + js/render3d.js  prototipe web: satu-satunya verifikasi visual di sandbox
assets/models/kaykit/        karakter CC0 (KayKit Adventurers)
tools/                       generator, penguji, penangkap layar
```

**Pemisahan yang dijaga:** `SimWorld` maju pada langkah tetap 60 Hz dan tidak
menyentuh engine sama sekali. Semua yang visual membaca keadaan itu dan boleh
tertinggal, melembutkan, atau melebih-lebihkannya — tapi tidak pernah menulis
balik. Itulah yang membuat replay jujur dan membuat renderer bisa dirombak
total (seperti yang baru saja terjadi) tanpa satu pun hasil pertandingan
berubah.

---

## Menyiapkan lingkungan

```bash
bash tools/install_godot.sh 4.6.2-stable   # memakai zip di root kalau jaringan mati
export PATH="$HOME/.cache/venv/bin:$PATH"  # gdlint, gdformat, gdparse
bash tools/setup_chromium.sh               # Chromium + SwiftShader untuk QA visual
npm install --no-save puppeteer-core
```

Zip Godot di root **sengaja ikut git**. Setiap mirror unduhan diblokir dari
sandbox ini; salinan di riwayat git adalah satu-satunya cara engine bertahan
melintasi sesi.

---

## Menjalankan

```bash
godot --headless --path godot/ --import     # sekali setelah menambah class_name baru
godot --headless --path godot/ --quit       # boot sekali, lapor error parse
python3 -m http.server 8000                 # prototipe web di localhost:8000
```

Setelah menambahkan `class_name` baru, `--import` **wajib**: tanpa itu cache
kelas global belum tahu kelas itu ada dan seluruh berkas yang memakainya
gagal parse dengan pesan yang menyesatkan ("Could not find type X").

---

## Memverifikasi

Empat perintah, dijalankan sebelum setiap commit:

```bash
godot --headless --path godot/ --script tests/sim_headless.gd
#   aturan main + determinisme. Harus: "SEMUA UJI LULUS" dan 5/5 IDENTIK.

godot --headless --path godot/ res://tests/smoke.tscn
#   scene sungguhan (Game + ArenaView + HUD + Screens), 1800 frame x 5 varian.
#   Menangkap apa yang headless tidak bisa: material hilang, node bocor,
#   layar yang menumpuk, aktor yang tidak dikembalikan ke kolam.

gdlint godot/scripts && gdformat --check godot/scripts
#   batas 1000 baris per berkas ditegakkan di sini — itulah yang memaksa VFX
#   keluar dari arena_view.gd dan menjadi kelasnya sendiri.

node tools/qa_screenshot.js http://localhost:8000/ --play
#   satu-satunya bukti visual. Menyimpan screenshots/qa-gameplay.png.
```

**Batasan yang harus diketahui:** sandbox tidak punya GPU maupun X server,
jadi build Godot **tidak bisa difoto**. Ia hanya bisa dibuktikan berjalan
lewat `smoke.tscn`. Semua klaim visual dalam proyek ini datang dari prototipe
web di Chromium SwiftShader — itulah sebabnya paritas web (roadmap M3) bukan
pekerjaan kosmetik melainkan infrastruktur pengujian.

---

## Mengubah config

`Config/arena_config.json` adalah sumbernya; `godot/config/` adalah salinan.

```bash
python3 tools/migrate_neon.py    # migrasi arah visual (idempoten)
python3 tools/sync_config.py     # WAJIB setelah mengedit config
python3 tools/solve_framing.py   # hitung ulang kamera kalau ukuran key art berubah
```

Mengubah angka framing dengan tangan adalah kesalahan: tiga angka kamera
saling terkait dan hanya benar sebagai satu solusi. Ubah ukuran key art di
`solve_framing.py`, jalankan, lalu salin hasilnya.

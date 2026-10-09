# CHAIN RIDER

> **Neon bullet-hell combo assault.** Satu prajurit di dasar lorong neon.
> Satu peluru raksasa. Pantulkan di antara dinding magenta, rantai petir,
> ledakkan drum — dan jaga combo tetap hidup.
> Portrait 9:16, satu jempol, sesi 1–3 menit.

Seluruh arah visual game ini diturunkan dari satu key art. Spesifikasinya —
framing yang dihitung, palet, inventaris efek — ada di
[`docs/00-art-bible.md`](docs/00-art-bible.md).

---

## Jalankan

```bash
# Prototipe web (tanpa instalasi apa pun)
python3 -m http.server 8000     # → http://localhost:8000

# Build Godot
bash tools/install_godot.sh 4.6.2-stable
godot --path godot/
```

## Dokumen

| Berkas | Isi |
|---|---|
| [`docs/00-art-bible.md`](docs/00-art-bible.md) | Key art sebagai spesifikasi: framing, palet, elemen, enam efek serangan |
| [`docs/01-roadmap.md`](docs/01-roadmap.md) | Keadaan sekarang dan milestone M1–M6 menuju paritas dengan key art |
| [`docs/02-build-and-verify.md`](docs/02-build-and-verify.md) | Bentuk proyek, setup, dan empat perintah verifikasi |

---

## Isi repo

```
Config/arena_config.json   sumber kebenaran tunggal (aturan, palet, kamera)
godot/                     game (Godot 4.6) — sim murni + view yang bisa dibuang
js/ + index.html           prototipe web; satu-satunya verifikasi visual di CI tanpa GPU
assets/models/kaykit/      karakter CC0
tools/                     generator aset, penguji balance, penangkap layar
```

Pemisahan yang membuat semuanya bekerja: `godot/scripts/sim/` maju pada
langkah tetap 60 Hz dan tidak pernah menyentuh engine. Renderer dirombak
total tanpa satu pun hasil pertandingan berubah — determinisme diuji 5/5
identik setiap commit.

## Verifikasi

```bash
godot --headless --path godot/ --script tests/sim_headless.gd   # aturan + determinisme
godot --headless --path godot/ res://tests/smoke.tscn           # scene nyata, 5 varian
gdlint godot/scripts                                            # batas 1000 baris/berkas
node tools/qa_screenshot.js http://localhost:8000/ --play       # bukti visual
node tools/look_audit.js 14 look                                # adegan penuh untuk menilai arah visual
```

## Lisensi aset

Karakter: [KayKit Adventurers](https://kaylousberg.itch.io/kaykit-adventurers)
(CC0). Audio dan model lain dihasilkan secara prosedural oleh skrip di
`tools/`.

# 01 — Roadmap: dari sekarang ke key art

Basis: [`00-art-bible.md`](00-art-bible.md). Target utama: build Godot di
`godot/`. Prototipe web (`index.html` + `js/render3d.js`) dipertahankan
sebagai **satu-satunya alat verifikasi visual** di lingkungan tanpa GPU, dan
karena itu wajib ikut setiap perubahan framing dan palet.

**Aturan yang tidak dinegosiasikan**

1. `godot/scripts/sim/` adalah aturan main dan determinisme. Rombakan visual
   tidak boleh menyentuhnya. Setiap PR yang mengubahnya harus punya alasan
   gameplay yang ditulis, bukan alasan tampilan.
2. Setiap milestone berakhir pada build yang bisa dimainkan dan uji hijau.
3. Angka warna dan framing hanya hidup di `Config/arena_config.json`.
4. Efek yang menutupi lintasan peluru > 0,15 s dipotong.

---

## Garis dasar hari ini

Sudah berdiri dan terverifikasi:

| Bagian | Keadaan |
|---|---|
| Framing kamera | Diselesaikan dari key art, lorong 12 unit, follow-x parsial, dolly combo |
| Palet | 13 kunci per varian + `artDirection`, lima ruangan neon |
| Lantai | Pelat logam + kisi cyan + pantulan basah + panas combo |
| Dinding | Slab magenta emissive + hit pulse 4 slot |
| Latar | Kota + kabut + vortex prosedural (Godot saja) |
| Pemain | Satu badan, 1,35×, kilatan biru |
| VFX | Jejak api, busur petir, cincin kejut, hujan tracer |
| HUD | Combo chrome kanan atas, POWER, pod kaca |
| Feel | Hitstop 40/90 ms, shake +20% |
| Uji | `smoke.tscn` lulus 5 varian · determinisme 5/5 identik · gdlint bersih |

Jarak yang tersisa ke key art, diurutkan dari yang paling terlihat:

1. Pemain masih memakai rig KayKit fantasi yang diperbesar — bukan zirah
   sci-fi. **Ini perbedaan nomor satu.**
2. Musuh yang mati karena ledakan tidak terlempar; mereka hanya jatuh.
3. Prototipe web belum punya latar kota, kerumunan jauh, maupun hujan tracer,
   jadi ujung lorongnya kosong.
4. Belum ada tingkat kualitas; glow dan pantulan selalu menyala.
5. Balance belum disetel ulang setelah lorong menyempit 20 → 12.

---

## M1 — Prajurit (perbedaan nomor satu) — **SELESAI**

**Masalah:** key art menempatkan satu zirah hard-surface biru-putih sebagai
jangkar komposisi. Yang ada sekarang adalah ksatria fantasi berpedang.

- [x] `PlayerSkin`: override material seluruh mesh rig pemain — badan
      `playerSteel`, pelat `playerDeep`, emisi rim `playerCyan`.
- [x] Buang pedang dan perisai dari soket pemain; pasang senjata sebagai
      bentuk prosedural sederhana (balok + laras + inti menyala) sampai ada
      model CC0 yang benar.
- [ ] Pose: stance kaki lebar saat diam. *(ditunda: butuh klip baru, bukan
      material — nilainya kecil dibanding biayanya)*
- [x] Rim light: satu OmniLight3D cyan beraura kecil mengikuti pemain, cukup
      untuk memisahkan siluet dari lantai gelap.
- [x] Tumpahan cahaya di lantai sekeliling kaki, menggantikan pantulan quad —
      pada jarak kamera ini keduanya tidak bisa dibedakan dan yang ini gratis.

**Lulus kalau:** pada screenshot web dan pada `smoke.tscn`, pemain terbaca
sebagai prajurit sci-fi biru-putih, bukan ksatria. Tidak ada emas tersisa.
→ **Terbukti** di `screenshots/qa-gameplay.png`: badan baja biru dengan
senapan, tanpa satu piksel emas. Godot memakai fresnel sungguhan
(`shaders/player_armor.gdshader`), web memakai emissive tetap — perbedaan
yang tidak terbaca pada ukuran layar ini.

---

## M2 — Kerumunan hidup

- [x] **Death pop:** musuh yang mati oleh `explosion` terlempar — impuls
      visual murni di `CharacterPool.drop_corpse`, sim tetap menghapus unit
      pada tick yang sama. Balistik gravitasi 26 (bukan 9,8: pada skala 2x
      gravitasi sungguhan terbaca seperti gerak lambat), mendarat tanpa
      memantul, jungkir sebanding tenaga lemparan. Sisi Godot saja —
      prototipe web tidak menerima daftar peristiwa dari simulasi, jadi ia
      tidak tahu kematian mana yang disebabkan ledakan. **Itu pekerjaan
      pertama M3.**
- [ ] Musuh yang terkena pantulan tersentak ke arah normal pantul.
- [ ] Warna kerumunan memudar ke kabut mengikuti jarak (sekarang hanya
      kerumunan jauh yang melakukannya).
- [ ] Gerbang spawn berdenyut saat gelombang baru masuk.

**Lulus kalau:** satu ledakan drum di tengah kerumunan menghasilkan gerakan,
bukan sekadar unit yang hilang.

---

## M3 — Paritas web

Prototipe web adalah satu-satunya mata yang kita punya di sandbox ini; kalau
ia tertinggal dua generasi, kita kehilangan kemampuan memverifikasi apa pun.

- [ ] Teruskan `events` simulasi ke renderer web (prasyarat death pop di web)
- [ ] Port latar: kota + kabut + vortex (shader quad → canvas texture).
- [ ] Port kerumunan jauh di balik gerbang.
- [ ] Port hujan tracer.
- [ ] Port jejak api chain shot dan busur petir.
- [ ] `tools/qa_screenshot.js` dijalankan tiap milestone, hasilnya disimpan
      sebagai `screenshots/mN-*.png`.

**Lulus kalau:** screenshot web berdampingan dengan key art terbaca sebagai
game yang sama.

---

## M4 — Tingkat kualitas & performa

- [ ] Tiga tingkat: `low` (tanpa glow, tanpa pantulan lantai, tracer 48),
      `mid` (glow 1 pass, tracer 96), `high` (sekarang).
- [ ] Pemilihan otomatis dari probe FPS tiga detik pertama, bisa ditimpa di
      layar setup.
- [ ] Target: 60 fps pada profil ponsel menengah, lantai 30 fps.

---

## M5 — Balance ulang

Lorong 20 → 12 mengubah semuanya: lebih banyak pantulan per tembakan, musuh
lebih padat, drum lebih sering berantai.

- [ ] Jalankan `tools/sim_test.js` (bot mahir, 5 seed × 5 varian).
- [ ] Target lama tetap berlaku: sesi 60–180 detik, kemenangan bot 5–20%.
- [ ] Perbarui blok `balance` di config dengan hasil **terukur**, bukan
      tebakan.

---

## M6 — Audio neon

- [ ] `bounce_*` jadi lebih metalik/elektrik.
- [ ] Layer desis untuk busur petir.
- [ ] Musik bergeser dari synth fantasi ke darksynth (`tools/gen_music.py`
      sudah prosedural — ganti preset, bukan berkas).

---

## Urutan eksekusi

M1 → M2 → M3 memberi lompatan visual terbesar per jam kerja dan sudah cukup
untuk menilai apakah arahnya benar. M4–M6 adalah pekerjaan pengerasan dan
sebaiknya menunggu sampai tampilannya tidak berubah lagi.

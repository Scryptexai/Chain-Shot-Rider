# 01 — Roadmap: pivot ke key art yang sebenarnya

Basis: [`00-art-bible.md`](00-art-bible.md) v4.0, ditulis dari
`docs/images/keyart-master.jpg`.

## Kenapa roadmap ini ditulis ulang total

Roadmap sebelumnya (M1–M6 "neon lane") dibangun di atas art bible yang ditulis
**tanpa file gambarnya ada di disk**. Setelah file key art ditemukan kembali di
remote, isinya ternyata genre yang berbeda: bukan lorong neon ungu dengan
prajurit berjalan, melainkan **shoot-'em-up udara vertikal** — jet tempur di
atas kota pesisir terbakar, melawan dreadnought terbang.

Jadi: M1–M6 lama **dibatalkan**. Yang di bawah ini menggantikannya.

### Yang tetap dipakai dari pekerjaan sebelumnya

| Aset | Alasan tetap hidup |
| --- | --- |
| Pipeline bloom di `js/render3d.js` | Key art baru justru lebih bergantung pada mekar cahaya |
| `tools/look_audit.js` | Satu-satunya cara melihat hasil di lingkungan tanpa GPU |
| `tools/render3d_test.js` | Kerangka uji framing; isi asersinya diganti angka baru |
| Sim di `godot/scripts/sim/` | Aturan main dan determinisme tidak bergantung genre tampilan |
| Aturan anti-plastik A1–A6 | Tidak bergantung genre |

### Yang mati

Lorong 12 unit, dinding magenta, kisi lantai, kerumunan jauh, pelataran,
vortex ungu, framing anchor 0,87 / horizon 0,14, dan palet `3.0.0-neon`.

---

## Aturan yang tidak dinegosiasikan

1. `godot/scripts/sim/` adalah aturan main. Rombakan visual tidak menyentuhnya.
2. Setiap milestone berakhir pada build yang bisa dimainkan dan uji hijau.
3. Angka warna dan framing hanya hidup di `Config/arena_config.json`.
4. Efek yang menutupi lintasan peluru > 0,15 s dipotong.
5. **Setiap milestone diverifikasi dengan tangkapan layar yang dibandingkan
   langsung ke `docs/images/keyart-master.jpg`.** Aturan ini yang hilang
   sebelumnya, dan karenanya pekerjaan tiga putaran meleset.

---

## N1 — Framing dan langit (pondasi) — **SELESAI**

Bukti: `screenshots/look-n1.png`.

- [x] Kamera diselesaikan ulang dan diturunkan dari konstanta, bukan angka
      ajaib: `PITCH_DEG 11,1` · `DROP_DEG 25,4` · `RANGE 19,8`. Terukur
      50,0% / 72,1% / 33,2%.
- [x] Langit senja sebagai `scene.background` (kanvas 512×1024, gradien
      dimampatkan ke sepertiga atas, awan tiga pita perspektif).
- [x] Laut `#4A5570` dengan riak mendatar dan pantulan api, 6 unit di bawah
      bidang aksi — simulasi tidak tahu apa-apa soal ketinggian terbang.
- [x] Kabut dicocokkan dengan pita cakrawala (`#D9C0A0`, 0,0082) supaya laut
      jauh melebur ke langit tanpa garis potong.
- [x] Ambang bloom dinaikkan 0,74 → 0,88 untuk adegan siang.
- [x] Dibuang: lantai kisi, dinding magenta, latar kota/vortex, pelataran,
      kerumunan jauh (±280 baris). Batas koridor sekarang dua tirai cahaya
      samar; aturan pantul di x=±6 tidak disentuh.
- [x] `tools/render3d_test.js` §1 dan §4 ditulis ulang ke spesifikasi baru.

Sisa yang terlihat di tangkapan layar dan sengaja ditunda: badan pemain masih
rig berjalan kaki (N2), musuh masih pylon (N4), HUD masih lama (N6).

## N2 — Jet pemain

- [ ] Ganti badan prajurit dengan jet: putih-abu `#D8DEE9`, panel `#4A5A7E`,
      aksen `#2BB8FF`, sayap delta, empat nozzle.
- [ ] Semburan mesin (E2): api putih-oranye + pita biru, berdenyut.
- [ ] Roll ringan saat bergerak menyamping; tidak pernah memiringkan kamera.

## N3 — Dunia bawah

- [ ] Dua tepi daratan kiri-kanan, koridor tengah selalu laut terbuka.
- [ ] Gedung terbakar + kolom asap tegak (E9).
- [ ] Parallax tiga lapis mengikuti kecepatan maju.

## N4 — Musuh dan bos

- [ ] Helikopter serang dan drone: siluet gelap, aksen merah, formasi.
- [ ] Bos dreadnought di puncak layar dengan inti menyala (E3 laser radial).
- [ ] Kubah perisai heksagonal (E7) sebagai penanda kebal.

## N5 — Efek serangan

- [ ] E1 aliran peluru biru dua pita.
- [ ] E4 peluru musuh jatuh.
- [ ] E5 rudal dengan ekor asap melengkung — ini penyumbang terbesar rasa kacau.
- [ ] E6 bola api dengan asap mengepul.
- [ ] E8 penanda bidik cyan.
- [ ] Anggaran: partikel aktif ≤ 200, 60 fps ponsel menengah, lantai 30 fps.

## N6 — HUD

- [ ] Potret pilot + bar HP merah / shield biru (kiri atas).
- [ ] Bar BOSS bernama (tengah atas).
- [ ] SCORE + jeda (kanan atas), `COMBO x156` emas miring di bawahnya.
- [ ] Empat tombol bundar berhitung di kiri bawah.
- [ ] Radar bundar dengan blip merah di kanan bawah.

## N7 — Balance dan audio

- [ ] Tala ulang untuk sesi 60–180 detik, 5–20% kemenangan bot.
- [ ] Audio: mesin jet, dentum ledakan, nada combo naik.

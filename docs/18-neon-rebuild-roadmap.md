# 18. Roadmap Rebuild "NEON" — Integrasi Key Art ke Gameplay

Basis: [`docs/17-keyart-neon-analysis.md`](17-keyart-neon-analysis.md).
Target: build Godot (`godot/`) sebagai jalur utama; prototipe web
(`js/render3d.js`, `index.html`) menyusul di fase akhir.

**Prinsip pemandu**

1. **Sim tidak disentuh.** `scripts/sim/*` adalah aturan main dan sumber
   determinisme. Seluruh rombakan hidup di `config/`, `scripts/view/`,
   `scripts/ui/`, `shaders/`, `scenes/`. Setiap PR yang mengubah `sim/` harus
   punya alasan gameplay, bukan alasan visual.
2. **Satu fase = satu build yang bisa dimainkan.** Tidak ada fase yang
   meninggalkan game dalam keadaan rusak.
3. **Readability beats beauty** tetap berlaku: efek yang menutupi lintasan
   peluru > 0.15 s dipotong, berapa pun kerennya.
4. Setiap fase punya **bukti visual** (screenshot headless ke `screenshots/`)
   yang dibandingkan dengan key art.

---

## Peta fase

| Fase | Nama | Fokus | Status |
|---|---|---|---|
| 0 | Fondasi | engine + validator jalan, uji hijau | ✅ selesai |
| 1 | Palet & Data | config + UiTheme jadi neon | ✅ selesai |
| 2 | Kamera & Framing | pitch, skala pemain, FOV, lebar lorong | ✅ selesai |
| 3 | Arena Shell | lantai, dinding magenta, kabut, backdrop | ✅ selesai |
| 4 | Aktor | pemain tunggal, crowd merah, kerumunan jauh | 🟡 sebagian |
| 5 | VFX Serangan | 6 efek di §17.5 | ✅ selesai |
| 6 | Post-FX | ACES, bloom, fog, saturasi | 🟡 sebagian |
| 7 | HUD & UI | combo chrome kanan atas, POWER | ✅ selesai |
| 8 | Feel & Audio | hitstop, shake +20% | 🟡 sebagian |
| 9 | Perf & Web parity | port ke render3d.js | 🟡 sebagian |

### Keputusan yang sudah diambil (eksekusi 2026-10-05)

| # | Keputusan | Hasil |
|---|---|---|
| D1 | Squad 100 → **pemain tunggal** | Sim TIDAK diubah. `troops` tetap mengemudikan laju tembak dan hukuman kebocoran, tapi dibaca sebagai **POWER** senjata. Determinisme replay utuh (`sim_headless` tetap "SEMUA VARIAN IDENTIK"). |
| D2 | Arah fantasi **dibuang** | Palet, nama varian, nama kartu, nama musuh, dan label HUD semuanya diganti. `docs/02` ditandai deprecated. |
| D3 | Model pemain | Masih rig KayKit, diperbesar 1,35x + rim cyan. Model sci-fi CC0 belum diganti. |
| D4 | Godot dulu, web menyusul | Godot lengkap; web dapat palet, kamera, dinding, pemain tunggal. |

---

---

## Apa yang benar-benar sudah berjalan

Bukti, bukan klaim:

```
godot --headless --path godot/ res://tests/smoke.tscn   → SMOKE LULUS (5 varian)
godot --headless --path godot/ --script tests/sim_headless.gd
                                                        → SEMUA UJI LULUS
                                                          determinisme: 5/5 IDENTIK
gdlint godot/scripts                                    → no problems found
node tools/qa_screenshot.js                             → screenshots/qa-gameplay.png
```

**Berkas yang lahir dari rombakan ini**

| Berkas | Isi |
|---|---|
| `tools/solve_framing.py` | Menyelesaikan posisi kamera dari tiga ukuran key art |
| `tools/migrate_neon.py` | Migrasi config: palet, kamera, penyempitan lorong, nama |
| `godot/shaders/bumper_wall.gdshader` | Dinding panel magenta + hit pulse 4 slot |
| `godot/shaders/backdrop.gdshader` | Kota cyberpunk + kabut + vortex, satu quad |
| `godot/scripts/view/vfx/arena_fx.gd` | Hujan tracer, busur petir, cincin kejut |

**Berkas yang dirombak:** `floor_grid.gdshader` (pelat logam + kisi cyan +
pantulan basah), `arena_view.gd` (environment, dinding, pemain tunggal, jejak
peluru, kerumunan jauh, hit pulse), `game.gd` (kamera), `game_feel.gd`
(hitstop), `hud.gd` (combo chrome, POWER), `ui_theme.gd` (palet 13 kunci),
`character_pool.gd` (skala pemain), `js/render3d.js` + `index.html` (web).

---

## Sisa pekerjaan yang diketahui

1. **Model pemain** masih knight KayKit yang di-retexture, bukan armor
   sci-fi. Ini perbedaan paling besar yang tersisa dari key art.
2. **Death pop** (musuh terlempar oleh ledakan) belum ada — musuh masih
   hanya jatuh jadi mayat.
3. **Filamen ungu di jejak peluru saat combo ≥ 20** belum disambungkan.
4. **Quality tier otomatis** (low/mid/high dari FPS probe) belum ada; glow
   dan refleksi selalu menyala.
5. **Backdrop kota + vortex + kerumunan jauh belum diport ke web** — di web
   ujung lorong masih kabut polos.
6. **Belum ada screenshot Godot**: sandbox tidak punya GPU maupun X, jadi
   bukti visual hanya tersedia lewat prototipe web di Chromium SwiftShader.
   Verifikasi Godot sejauh ini lewat `smoke.tscn`, bukan lewat mata.
7. **Balance belum disetel ulang** setelah lorong menyempit 20→12. Lorong
   sempit = lebih banyak pantulan = skor lebih tinggi; `tools/sim_test.js`
   perlu dijalankan ulang dan `balance.result` diperbarui.

---

## Fase 0 — Fondasi

**Tujuan:** bisa melihat perubahan tanpa menebak.

- [ ] Simpan key art ke `docs/images/keyart-neon-master.png` (perlu re-upload).
- [ ] Ekstrak 14 swatch §17.3 ke `docs/images/keyart-palette.png` (script
      `tools/draw_layout.py` bisa dipakai ulang).
- [ ] Unzip `Godot_v4.6.2-stable_linux.x86_64.zip` lewat
      `tools/install_godot.sh`, pastikan `tools/qa_screenshot.js` jalan.
- [ ] Simpan baseline sekarang: `screenshots/neon-00-baseline.png`.
- [ ] Buat `tools/keyart_compare.py` — tempel screenshot di samping key art
      agar tiap fase bisa dinilai mata, bukan opini.

**Acceptance:** satu perintah menghasilkan gambar perbandingan.

---

## Fase 1 — Palet & Data

**File:** `godot/config/arena_config.json`, `godot/scripts/ui/ui_theme.gd`,
`godot/scripts/view/arena_view.gd` (konstanta warna), `Config/arena_config.json`
(mirror, lihat `tools/sync_config.py`).

- [ ] Tambah blok `artDirection` berisi 14 warna core §17.3 sebagai sumber
      tunggal, supaya view/HUD/web membaca tempat yang sama.
- [ ] Perluas `variants[].theme` dengan kunci baru: `player`, `tracer`,
      `chain`, `bumperGlow`, `wallPanel`, `fog`, `vortex`.
- [ ] Tulis ulang 5 tema varian jadi lima rasa neon (bukan lima rasa fantasi):
      `classic_pit`→Neon Dock, `twin_towers`→Data Spires, `gravity_chamber`→
      Singularity Bay, `explosive_yard`→Fuel Yard, `moving_maze`→Shift Grid.
- [ ] `UiTheme.palette()` membaca kunci baru + fallback ke `artDirection`.
- [ ] Ganti `ENEMY_COLORS` di `arena_view.gd` ke satu keluarga merah-oranye
      (varian saturasi/nilai, bukan hue berbeda-beda).
- [ ] `enemyTypes[].color` di config diselaraskan.

**Acceptance:** game lama berjalan, warnanya neon, tidak ada emas/hijau
tersisa. Test `godot/tests/home_screens_suite.gd` hijau.

---

## Fase 2 — Kamera & Framing  ⚠️ fase paling menentukan

**File:** `godot/scripts/game.gd` (`_place_camera`, `_fit_pullback`,
`_update_fov_scale`), `godot/scenes/main.tscn`, blok `camera` di config.

- [ ] Ubah target: `pitchDegrees 40 → 54`, `distance 18 → 11.5`,
      `heightOffset 12 → 15.5`, `lookAheadZ 6 → 9`.
- [ ] Tambah `camera.playerScreenAnchor = 0.87` dan selesaikan posisi kamera
      dari anchor ini, bukan dari angka distance mentah — inilah yang menjaga
      pemain tetap besar di bawah layar pada semua aspect ratio.
- [ ] `_fit_pullback()` dibatasi: hanya boleh mundur sampai pemain masih
      ≥ 15% tinggi layar. Saat ini ia bebas mundur dan itu sumber "pemain
      kecil" di build sekarang.
- [ ] `_update_fov_scale()` tetap width-matched (benar), tapi clamp naik ke 62.
- [ ] Tambah sedikit **dolly dinamis**: kamera maju 0.5 unit saat combo ≥ 20,
      mundur saat crowd penuh. Lerp lambat (≤ 1.5 u/s) agar tidak mabuk.
- [ ] Bullet-time: FOV turun + kamera **miring ke titik pantul berikutnya**
      maksimal 3°, tanpa roll.

**Acceptance:** screenshot menumpuk pada key art dengan deviasi anchor pemain
< 5% dan vanishing point < 8% tinggi layar. Diuji di 9:16, 9:19.5, 9:21, 4:3.

**Risiko:** sudut lebih tinggi memperpendek pembacaan sumbu Z → sudut pantul
jadi lebih sulit dinilai pemain. Mitigasi: garis bantu aim (Fase 5 E1) dan
grid lantai dengan spacing tetap sebagai referensi jarak.

---

## Fase 3 — Arena Shell

**File:** `godot/shaders/floor_grid.gdshader` (+ shader baru),
`arena_view.gd` (`_build_environment`, `_build_floor`, `_build_obstacles`).

- [ ] **Lantai:** pelat logam gelap + grid cyan emissive; garis menebal dekat
      pemain, meredup eksponensial ke horizon. Tambah uniform `wetness`,
      `reflection_strength`, `plate_scale`.
- [ ] **Refleksi palsu:** mirror pass murah dari strip neon utama (dinding,
      ledakan) — bukan SSR penuh, demi WebGL.
- [ ] **Dinding bumper:** ganti `WALL_STONE` dengan slab panel miring,
      material emissive magenta + mask panel. Tambah uniform `hit_pulse`
      (titik + waktu) agar Fase 5 bisa menyalakan dinding lokal.
- [ ] **Defense line:** garis merah menyala di z=5 dengan pulse saat bocor.
- [ ] **Kabut & langit:** `WorldEnvironment` fog ungu mulai z≈28; skybox
      kota cyberpunk + vortex sebagai billboard parallax (dekorasi saja).
- [ ] **Spawn gate (z=40):** gerbang neon yang berdenyut tiap wave.

**Acceptance:** arena kosong tanpa aktor sudah terbaca sebagai key art.

---

## Fase 4 — Aktor

**File:** `godot/scripts/view/character_pool.gd`, `arena_view.gd`,
`assets/models/`.

- [ ] Pemain: ganti knight KayKit → prajurit armor cyber biru-putih
      (opsi: retexture KayKit knight dengan material emissive cyan sebagai
      langkah murah; model baru CC0 sebagai langkah benar).
- [ ] Pose idle lebar + animasi tembak satu tangan, rim light cyan.
- [ ] Crowd: satu bahasa visual merah-oranye; perbedaan tipe lewat **siluet
      kecil + warna aksen**, bukan hue acak.
- [ ] LOD: ber-tulang hanya untuk ~24 unit terdekat (sudah ada), sisanya
      MultiMesh; tambah fade warna ke kabut mengikuti jarak.
- [ ] **Death pop:** musuh terkena ledakan terlempar (impulse visual murni,
      sim tetap menghapus unit seketika).
- [ ] Squad 100 unit: diputuskan di Fase 4 — key art menampilkan pemain
      tunggal. Rekomendasi: kecilkan squad jadi **drone pengiring 4–6 unit**
      agar pemain tetap jadi fokus (perubahan ini **menyentuh sim**, jadi
      butuh keputusan desain eksplisit; defaultnya: pertahankan squad,
      geser ke belakang pemain dan perkecil).

**Acceptance:** 200 musuh + pemain on-screen, 60 fps di profil mid-phone.

---

## Fase 5 — VFX Serangan (jantung rombakan)

**File baru:** `godot/scripts/view/vfx/` — `tracer_field.gd`,
`chain_arc.gd`, `impact_flare.gd`, `explosion_rig.gd`, `bullet_trail.gd`.

- [ ] **E1 Chain Shot:** mesh selongsong brass + trail pita api (Ribbon /
      `ImmediateMesh` dengan taper), halo additive, filamen ungu saat
      combo ≥ 20. Trail panjang 8–10 u, lifetime 0.35 s.
- [ ] **E2 Ricochet Impact:** flare radial 0.12 s + 16 spark + arc ungu di
      permukaan dinding 0.25 s + `hit_pulse` ke shader dinding.
- [ ] **E3 Tracer Field:** satu MultiMesh quad untuk seluruh hujan tracer
      musuh, dikendalikan dari event `auto_fired` musuh; cap 160 streak.
- [ ] **E4 Explosion:** 3 layer (core/shell/smoke) + shockwave ring lantai +
      puing; durasi 0.8 s; chain delay mengikuti config.
- [ ] **E5 Chain Lightning:** arc prosedural zig-zag antar titik pantul dan
      musuh yang mati karena pantulan itu; < 0.2 s, maksimal 6 arc aktif.
- [ ] **E6 Combo Burst:** dipindah ke Fase 7 (HUD) tapi dipicu dari sini.
- [ ] Semua efek lewat **pool** (ikuti pola `_impacts` yang sudah ada), nol
      alokasi saat runtime.

**Acceptance:** rekaman 10 detik gameplay combo tinggi terlihat seperti
potongan dari key art; budget partikel aktif ≤ 200.

---

## Fase 6 — Post-FX

- [ ] `WorldEnvironment`: glow threshold 0.6, intensitas 1.1, bicubic on
      (desktop) / 1-pass (web).
- [ ] Tonemap ACES, exposure 1.1, white 6.
- [ ] Vignette ungu 0.35, grain 0.03, CA maksimal 0.25 saat bullet-time
      (reuse `slowMo.chromaticAberrationMax`).
- [ ] **Quality tiers**: `low / mid / high` otomatis dari FPS probe
      (`tools/perf_probe.js`), glow & refleksi mati duluan di low.

**Acceptance:** tier low tetap terbaca, tier high setara key art.

---

## Fase 7 — HUD & UI

**File:** `godot/scripts/view/hud.gd`, `ui/ui_theme.gd`, `ui/screens.gd`,
`ui/setup_screen.gd`, `ui/squad_screen.gd`.

- [ ] Combo counter chrome-cyan miring + outline gelap + glow, posisi
      **kanan atas** (sekarang di tengah) persis seperti key art.
- [ ] Angka besar `x999` + label kecil `COMBO` di bawahnya, digit tabular.
- [ ] Milestone: scale punch + flash layar + scanline sweep.
- [ ] Chip HUD lain (nyawa, wave, skor) jadi panel kaca gelap garis cyan.
- [ ] Menu/stage map/kartu upgrade dibawa ke bahasa neon yang sama.

**Acceptance:** `screenshots/qa-menu.png` & `qa-cards.png` diperbarui dan
konsisten dengan arena.

---

## Fase 8 — Feel & Audio

- [ ] Hitstop 40 ms per pantulan, 90 ms di pantulan terakhir.
- [ ] Shake dinaikkan ~20% dan diberi arah (searah normal pantul).
- [ ] Bullet-time masuk lebih tajam, keluar lebih lembut.
- [ ] Mix audio: `bounce_*` lebih metalik/elektrik, tambah layer sizzle untuk
      chain lightning; musik geser dari synth fantasi ke **darksynth**
      (`tools/gen_music.py` sudah prosedural — tinggal ganti preset).

---

## Fase 9 — Performa & Paritas Web

- [ ] Profil di 3 tier perangkat; target 60 fps mid, 30 fps floor.
- [ ] Port perubahan ke `js/render3d.js` (kamera, palet, tracer, trail) agar
      prototipe web tidak ketinggalan dua generasi.
- [ ] Rebuild `web_nothreads_release.zip` lewat `tools/export_web.py`.
- [ ] Perbarui `docs/02-visual-style-guide.md` → tandai arah fantasi sebagai
      **deprecated**, rujuk ke docs 17/18.

---

## Keputusan yang butuh persetujuan sebelum eksekusi

| # | Pertanyaan | Default yang saya ambil kalau tidak dijawab |
|---|---|---|
| D1 | Squad 100 prajurit dipertahankan? Key art hanya menampilkan 1 pemain. | Dipertahankan tapi diperkecil & digeser ke belakang pemain |
| D2 | Tema fantasi KayKit dibuang total atau jadi skin alternatif? | Dibuang dari default, disimpan sebagai skin opsional |
| D3 | Model pemain: retexture KayKit (cepat) atau cari model sci-fi CC0 (benar)? | Retexture dulu di Fase 4, ganti model di fase lanjutan |
| D4 | Jalur utama Godot saja, atau web prototype harus paritas tiap fase? | Godot dulu, web menyusul di Fase 9 |
| D5 | Target perangkat terendah masih Snapdragon 660? | Ya — ini yang membatasi budget partikel & glow |

---

## Urutan eksekusi yang disarankan

Fase 1 → 2 → 3 memberi **lompatan visual terbesar per jam kerja** dan sudah
cukup untuk menilai apakah arah ini terasa benar sebelum investasi besar di
Fase 4–5. Saya sarankan berhenti sejenak setelah Fase 3 untuk review
screenshot berdampingan dengan key art.

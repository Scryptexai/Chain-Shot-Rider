# 6. UI Wireframe Portrait — CHAIN RIDER

![Mockup HUD portrait](images/ui-portrait-mockup.png)

Resolusi acuan: **1080 × 1920 (9:16), portrait, mobile-first.** Satu angka di dokumen
ini = satu piksel acuan; layar nyata hanya menskalakannya.

**Tinggi tidak pernah diasumsikan 1920.** Ponsel modern 19,5:9 sampai 20:9, dan memaksa
9:16 di sana berarti dua pita hitam permanen yang membuat game terbaca seperti halaman
web di dalam webview. Jadi aturannya: **lebar dikunci 1080, tinggi boleh tumbuh**, dan
ruang ekstra jatuh ke dek HUD atas/bawah — bukan ke arena. Semua elemen bawah di-anchor
ke tepi bawah, bukan ke koordinat tetap.

| Target | Aturan skala |
|---|---|
| Godot | `stretch/mode = canvas_items`, `stretch/aspect = keep_width`, orientation portrait |
| Web (`index.html`) | `k = vw/1080` bila `vh/vw ≥ 16/9` (`hRef = min(2340, vh/k)`); selain itu `k = vh/1920`, `hRef = 1920` |

**Penjaga aspect (runtime).** Aturan match-width benar untuk ponsel, tapi di jendela
lanskap atau desktop ia melebarkan dunia sampai lorongnya terpotong dan dek bawah
terlempar keluar layar. `Game._apply_aspect_guard()` (dipanggil di `_ready` dan pada
`Window.size_changed`) karena itu berpindah mode:

| Aspect jendela | Mode | Hasil |
|---|---|---|
| `> 9/16` (lanskap, desktop, tablet) | `CONTENT_SCALE_ASPECT_KEEP` | portrait dipertahankan, pillarbox kiri-kanan |
| `9/21 … 9/16` (semua ponsel portrait) | `CONTENT_SCALE_ASPECT_KEEP_WIDTH` | lebar penuh, tinggi ekstra jadi ruang dek |
| `< 9/21` (sangat jangkung / terlipat) | `CONTENT_SCALE_ASPECT_KEEP` | letterbox, daripada dek yang melar tak terbaca |

Web melakukan hal yang sama lewat `fitFrame()`: bingkai di-scale + `translate(-50%,-50%)`,
tidak pernah dengan grid `place-items:center` (bingkai yang meluap terlempar ke pojok).

---

## 6.1 Wireframe Utama (gameplay)

```text
┌─────────────────────────────────────┐ ── 0 px
│            [ SAFE AREA TOP ]        │    notch / punch-hole / Dynamic Island
├─────────────────────────────────────┤ ── 88 px
│ ┌────────┐   ┌──────────┐   ┌────┐  │  TOP ROW — satu HBoxContainer:
│ │ SCORE  │   │ST 03 WAVE│   │ II │  │  skor kiri · chip tengah · jeda kanan
│ │ 12,480 │   │   3/5    │   └────┘  │  · skor 58 px, count-up 0,2 s
│ └────────┘   │ ●●●○○    │           │  · chip 30/28 px + 5 titik wave
│              └──────────┘           │  · jeda 128 × 128 px, chunky
├─────────────────────────────────────┤
│ ╌╌╌╌╌╌╌╌ spawn gate (Z=40) ╌╌╌╌╌╌╌╌ │
│                                     │
│   ▪▪▪▪▪▪▪▪▪▪▪▪   crowd merah        │  SPAWN ZONE
│                                     │
│          BOSS ▓▓▓▓▓▓░░░░  y=370     │  boss bar (hanya wave 5)
│                                     │
│                x12      y=470       │  combo, gold, pulse
│                                     │
│   ┌───────────────────────────┐     │  TOAST PETUNJUK — top 44%
│   │ GESER untuk gerakkan squad│     │  hilang sendiri setelah ~6 s
│   │ TAP untuk chain shot      │     │  atau pada tembakan pertama
│   └───────────────────────────┘     │
│                                     │
│  ◉         ╲   ✦ bullet + trail     │  COMBAT ZONE
│             ╲                       │
│ ─────────── DEFENSE LINE ────────── │  cyan, selalu terlihat
│                 ▲▲▲ squad           │  PLAYER ZONE
├─────────────────────────────────────┤
│ ┌──────────┐                        │  DEK BAWAH (anchor ke tepi bawah,
│ │ ▲ 12     │                        │  grow ke ATAS)
│ │ PASUKAN  │               ╭─────╮  │  · pod pasukan
│ └──────────┘               │  ◎  │  │  · meter steer (hanya saat riding)
│  STEER ▓▓▓▓▓░░░░ 2.1s      │CHAIN│  │  · 3 hati 62 px
│  ♥ ♥ ♡                     │ ●●  │  │  · tombol CHAIN 230 px bundar
│                            ╰─────╯  │    + cincin charge + 2 pip
├─────────────────────────────────────┤ ── −72 px dari dasar
│         [ SAFE AREA BOTTOM ]        │    home indicator / gesture bar
└─────────────────────────────────────┘

      ZONA JEMPOL (sepertiga bawah)
      ╭─────────────────────────────╮
      │ geser di mana saja = squad  │  arena tetap bisa disentuh penuh;
      │ tap di mana saja  = tembak  │  tombol CHAIN adalah jalan kedua,
      │ tombol CHAIN      = tembak  │  bukan satu-satunya
      ╰─────────────────────────────╯
```

**Kenapa ada tombol CHAIN kalau tap di mana saja sudah menembak.** Tap-di-mana-saja
menolak satu postur yang paling sering dipakai: satu tangan, ibu jari sudah menempel di
kanan bawah untuk menggeser squad. Mengangkatnya untuk mengetuk berarti squad berhenti.
Tombol bundar di bawah ibu jari menembak tanpa melepaskan kemudi, dan cincinnya menjawab
"kapan saya bisa menembak lagi" tanpa angka. Keduanya melewati jalur yang sama
(`_pending_tap`), jadi tidak ada aturan tembak kedua yang bisa berbeda perilakunya.

**Jeda.** Sampai revisi ini Godot tidak punya cara apa pun keluar dari run selain kalah —
layar pause sudah ada tapi tak pernah terpanggil. Sekarang: tombol `II` di kanan atas
(jauh dari ibu jari yang sedang bermain, tetap terjangkau) dan `ui_cancel` (Esc / tombol
back Android).

---

## 6.1b Dua Elemen HUD Tambahan

| Elemen | Posisi | Perilaku |
|---|---|---|
| **Garis bidik** (aim indicator) | Dari muzzle, mengikuti posisi squad | Garis putus-putus memprediksi **2 pantulan** ke depan; tiap segmen lebih pudar dan lebih tipis, titik pantul diberi dot. **Disembunyikan saat riding**, karena saat itu tap berarti "rem" bukan "tembak" — indicator yang tetap tampil akan membohongi pemain. |
| **Bar HP boss** | Tengah atas, `y = 370` | Muncul hanya saat wave 5. Nama boss + bar merah. Posisinya diturunkan dari 262 ke 370 agar pod skor yang memuai (font perangkat lebih tinggi dari dugaan) tidak pernah bisa menyentuhnya. Untuk Twin Warden, bar menunjukkan HP **gabungan** kedua bagian, sehingga revive terlihat sebagai bar yang naik lagi. |

Garis bidik memakai prediksi yang sama persis dengan simulasi (`RicochetSolver.PredictWallPath`).
Kalau batas yang dipakai indicator dan simulasi berbeda sedikit saja, indicator akan
berbohong. Diverifikasi numerik: **deviasi terburuk 0.43 unit pada 19 titik pantul**
(dalam toleransi radius peluru + substep).

---

## 6.1c Perubahan untuk loop Last War ATM (v2)

Wireframe awal dibuat untuk loop lama (player diam, magasin 5 peluru). Yang berubah sejak
loop squad + gate:

| Elemen lama | Sekarang | Alasan |
|---|---|---|
| **Ammo** 5 ikon peluru | **Chain charge**: cincin busur di tombol CHAIN + 2 pip 22 px di dalamnya | Tidak ada lagi magasin. Chain shot adalah sumber daya langka; cincin yang tumbuh membaca "berapa lama lagi" tanpa angka, dan menaruhnya di tombol berarti informasi dan aksi ada di tempat yang sama. |
| Pill `SQUAD xN` di bawah wave | **Pod `PASUKAN`** di kiri bawah | Jumlah pasukan adalah HP **dan** DPS sekaligus — angka terpenting di layar. Dipindah ke dek bawah agar masuk sapuan mata yang sama dengan nyawa dan tombol tembak. Merah saat ≤5 sebagai peringatan dini. |
| 3 hati karakter teks `♥` | **3 kotak 62 px** chunky | Teks `♥` mengecil jadi noda merah di layar kecil dan tidak punya keadaan "kosong" yang jelas. Kotak punya dua keadaan yang terbaca dari jarak satu meter. |
| Garis bidik mengikuti sudut turret | Garis bidik **lurus ke depan dari posisi squad** | Posisi squad adalah bidikannya. |

Elemen baru: **label gate** (`x2`, `+8`, `-6`, `/2`) digambar di panel gate itu sendiri,
bukan di HUD — keputusannya ada di dunia, jadi angkanya harus ada di dunia juga.

Steer meter, skor, combo, floating text, damage flash, dan vignette slow-mo tetap.

---

## 6.2 Anatomi Elemen

### Baris atas (`y = 88`, satu `HBoxContainer`, margin samping 44)

| Elemen | Posisi | Ukuran | Style |
|---|---|---|---|
| Pod skor | kiri, shrink-begin | label 22 px + angka 58 px | Pod kaca gelap, border aksen 3 px, radius 30, *count-up tween* 0,2 s |
| Chip stage + wave | tengah | 30 px aksen / 28 px ink | Pod radius 38, format `ST 03` + `WAVE 3/5` |
| Titik wave | di bawah chip | 44 × 12 px, jarak 9 | Lima titik: menyala = aksen, sisanya putih 14%. Dibaca dengan lirikan setengah detik; `WAVE 3/5` tidak |
| Tombol jeda | kanan | **128 × 128** | Tombol chunky, teks `II` |
| Combo | tengah, `y = 470` | 86 px | `#FFD54F`, outline, **scale pulse 1.0→1.15**, disembunyikan di bawah x2 |

> Ketiganya hidup di dalam satu container. Pada koordinat tetap, teks yang pada font
> perangkat ternyata lebih tinggi/lebar dari dugaan membuat pod skor menindih chip stage —
> kegagalan yang tidak terlihat di kode dan terbukti terjadi saat diukur headless.

### Dek bawah (satu `VBoxContainer`, anchor bawah, `grow_vertical = BEGIN`)

| Elemen | Spesifikasi |
|---|---|
| **Pod pasukan** | Glyph ▲ 34 px + angka 52 px + label `PASUKAN` 20 px. Border dan angka berubah `#FF1744` saat ≤5 |
| **Meter steer** | Label `STEER` 24 px + bar tinggi 26 px (expand) + sisa detik 26 px. **Alpha 0 saat tidak aktif**, 1 saat bullet riding; fill menyala putih di 0,5 detik terakhir |
| **Nyawa** | 3 kotak 62 px, jarak 12, radius 20, kaki gelap. Hati hilang → kotak biru gelap + flash merah layar |
| **Tombol CHAIN** | **230 × 230** bundar di kanan bawah, 44 px dari tepi kanan, 72 px dari dasar. Cincin `draw_arc` tebal 13 px = progres muatan, 2 pip di dalamnya = muatan siap, denyut 1.0→1.035 saat siap |

Grow ke atas, bukan ke bawah: elemen yang ternyata lebih tinggi dari dugaan memakan ruang
arena di atasnya dan tidak pernah jatuh ke luar layar atau menindih tetangganya.

### Overlay (tidak memblokir input)

| Elemen | Perilaku |
|---|---|
| **Toast petunjuk** | `top: 44%` — ruang itu kosong di detik-detik pertama, jadi tidak ada yang tertutup justru saat pemain paling perlu melihat. (`bottom: 470/540` menutupi pod + squad; `top: 420` menutupi titik spawn musuh — keduanya terbukti salah lewat screenshot.) Pergi sendiri setelah ~6 s atau pada chain shot pertama |
| **Combo popup** | Milestone x10/x20/x50/x100 di tengah layar. Scale 1.25→1.0, fade 0,25 s, berjalan di **unscaled time** agar tetap cepat walau slow-mo |
| **Floating text** | `+100` di lokasi kill (world→screen), naik 90 px/s, fade kuadratik, 0,8 s. Pool 32; kalau habis, teks **diagregasi** jadi satu popup total |
| **Slow-mo vignette** | Tint biru `#00344D`, alpha → 0,42, mengikuti `chain_riding` |
| **Damage flash** | Full-screen `#FF1744` alpha 0,6 → 0, durasi 0,4 s |

---

## 6.3 Layar Non-Gameplay

```text
        MARKAS (home)                 JEDA            HASIL (menang/kalah)
┌───────────────────────────┐   ┌──────────────┐   ┌──────────────────┐
│ (CR) COMMANDER   ★48210 ✦2│   │              │   │     MENANG       │
│      LV 5                 │   │     JEDA     │   │ STAGE 03·GRAVITY │
│                           │   │              │   │     ★ ★ ★        │
│        CHAIN              │   │ ┌──────────┐ │   │ ┌──────────────┐ │
│        RIDER              │   │ │  LANJUT  │ │   │ │SCORE   48,210│ │
│    RIDE THE RICOCHET      │   │ └──────────┘ │   │ │WAVE       5/5│ │
│                           │   │ ┌──────────┐ │   │ │SQUAD      x12│ │
│ ┌───────────────────────┐ │   │ │ ULANGI   │ │   │ │COINS    +4821│ │
│ │ ░░░ preview lorong ░░░│ │   │ └──────────┘ │   │ └──────────────┘ │
│ │ STAGE 05 / 15         │ │   │ ┌──────────┐ │   │ ┌──────────────┐ │
│ │ MOVING MAZE           │ │   │ │ KE MARKAS│ │   │ │   LANJUT     │ │
│ │ BOSS · SHIFTER   ★★☆  │ │   │ └──────────┘ │   │ └──────────────┘ │
│ └───────────────────────┘ │   └──────────────┘   │   KE MARKAS      │
│ PILIH STAGE   4/15 CLEARED│                      └──────────────────┘
│ ┌──┐┌──┐┌══┐┌──┐┌──┐ →    │   rel mendatar, geser
│ │03││04││05││06││07│      │   kartu 240 × 300
│ └──┘└──┘└══┘└──┘└──┘      │   auto-scroll ke stage berjalan
│ ┌───────────────────────┐ │
│ │        MAIN           │ │   hijau, 150 px, zona jempol
│ └───────────────────────┘ │
└───────────────────────────┘
```

**Menu dan peta stage adalah satu layar.** Dua layar untuk satu pertanyaan ("stage mana
berikutnya?") memaksa satu ketukan ekstra sebelum game dimulai, dan membuat layar pertama
cuma berisi satu tombol.

**Rel kartu, bukan daftar baris.** Daftar 15 baris bergulir vertikal dengan label status
di kanan adalah pola aplikasi. Chapter select di game mobile selalu rel kartu yang bisa
digeser ibu jari, dengan kartu "sekarang" diberi border terang.

**Tombol chunky.** `UiTheme.chunky()` — bevel, kaki gelap 16 px, bayangan jatuh, dan
keadaan ditekan yang memendekkan kaki + menurunkan isi tombol. Touch tidak punya kursor,
jadi keadaan tertekan adalah satu-satunya umpan balik bahwa tap terdaftar. Aksi utama
selalu **hijau** `#5BE34B`; memakai warna aksen arena membuatnya hilang di antara chip lain.

- **Result** memakai count-up tween per baris (0,15 s jeda antar baris).
- **Bintang hasil mengukur run, bukan kesulitan stage**: 3 bintang bila nyawa penuh, 2 bila
  ≥ 2, selain itu 1. Nyawa tersisa adalah satu-satunya hal yang dikendalikan pemain.
- Setelah menang, tombol utama berbunyi **`STAGE 04 →`** (maju), bukan "ulangi" — mengulang
  stage yang baru dibereskan bukan aksi yang dicari pemain.
- Diagnostik (FPS, tick, damage mult), slider volume, dan RESET PROGRESS hidup di tab
  **SETUP**, tidak pernah di layar main. Itu bahasa aplikasi, dan tempatnya bukan di HUD.

### 6.3a Angka terpakai (Godot)

`godot/scripts/ui/screens.gd` — satu `CanvasLayer` (`layer = 2`) berisi keempat layar
(markas, jeda, hasil, draft kartu), karena saling eksklusif dan berbagi skin yang sama.

| Elemen | Nilai terpakai |
|---|---|
| Tinggi tombol aksi | 150 px, jarak antar tombol 24 px |
| Kolom konten | margin samping 60 px, atas = safe-top 88 px, dasar −72 px |
| Pengisi ruang | `_grow(ratio)` — ruang ekstra layar jangkung dibagi proporsional, tidak ada koordinat tetap |
| Scrim | `bg_bottom` varian @ 82% — selalu jelas simulasi sedang berhenti |
| Logo | 112 px × 2 baris + tagline 26 px |
| Kartu chapter | radius 40, strip pratinjau 12 px bertema, nama 64 px |
| Kartu stage (rel) | **240 × 300**, jarak 22, radius 30, border 4 px pada stage berjalan |
| Kartu upgrade | tinggi 190 px, nama 48 px, deskripsi 30 px, seluruh slab bisa ditekan |
| Baris statistik | label 30 px `#8A9BB8`, nilai 46 px aksen, di dalam pod |

### 6.3b Rel stage (campaign ladder)

Alur: **markas → stage → hasil → kartu → kembali ke markas**.

| Aturan | Nilai |
|---|---|
| Jumlah kartu | `meta.stageCount` (15), semuanya dibangun ulang tiap kali dibuka |
| Stage terkunci | **tetap ditampilkan**, hanya `disabled` — melihat apa yang ada di depan adalah satu-satunya alasan layar ini ada |
| Status | `CLEARED` emas `#FFD54F` · `PLAY` aksen varian · `LOCKED` `INK_DIM` |
| Sumber data | `variants[meta.variantCycle[stage % 5]]` — rel menyebut arena yang benar-benar akan dimuat; kesulitan `1 + difficultyPerStage * stage` |
| Auto-scroll | `scroll_horizontal = stage * (240+22) − (lebar_rel − 240)/2`, dijepit Godot ke rentang |
| Timing scroll | disetel **setelah dua `process_frame`** — ScrollContainer melaporkan viewport nol sebelum layout pass, dan offset yang dihitung di frame yang sama selalu mendarat di awal rel |

**Bug progresi yang ikut diperbaiki** — `_on_card_chosen` dulu memanggil `start_stage(_stage)`,
mengulang stage yang baru saja dimenangkan: `_stage` hanya dibaca dari `SaveGame` saat boot,
jadi tangga tidak pernah naik dalam satu sesi.

### 6.3c Bukti layout tanpa GPU

Sandbox pengembangan tidak punya GPU, X server, maupun libGL, jadi build Godot **tidak bisa
di-screenshot sama sekali**. Mesin layout Godot tetap berjalan headless, jadi yang dipakai
sebagai bukti adalah geometri terukur dari `Control.get_global_rect()` pada scene hidup:

- `godot/tests/smoke.gd` mengukur HUD, markas, rel stage, dan draft kartu, lalu menulis
  `screenshots/layout-{hud,stagemap,cards}.json`.
- `python3 tools/draw_layout.py` menggambar JSON itu jadi diagram kotak (**bukan**
  screenshot — warna dan tipografi di diagram itu karangan skrip).
- Yang dijaga uji: ukuran target sentuh, posisi dalam zona ibu jari, tidak ada elemen HUD
  tetap yang saling menindih, tidak ada yang keluar layar, tombol jeda benar-benar
  menjeda, dan tombol CHAIN benar-benar memicu tembakan.

Prototipe web **bisa** dipotret (Chromium + SwiftShader): `node tools/shot.js --states`
menyusuri tujuh keadaan UI pada 390 × 844, `node tools/shot.js` memotret empat ukuran
viewport termasuk desktop lanskap dan layar persegi.

---

## 6.6 Sistem Tema

Semua warna berasal dari **satu** sumber: `variants.N.theme` di `Config/arena_config.json`.

- **Godot** — `godot/scripts/ui/ui_theme.gd` (`class_name UiTheme`) membangun `Theme` dari
  kode, bukan file `.theme`, karena palet baru diketahui saat runtime. `palette()`
  menormalkan dict varian; `panel()`, `slab()`, `bar_fill()`, `bar_track()` untuk bar dan
  chip; **`chunky()`** tombol bevel, **`pod()`** kaca gelap beraksen, **`blob()`** kotak
  padat (hati, titik wave), **`apply_chunky()`** memasang tiga keadaan tombol sekaligus.
  Konstanta netral: `INK #F5F9FF`, `INK_DIM #8A9BB8`, `DANGER #FF1744`, `GOLD #FFD54F`,
  `GO #5BE34B` / `GO_DARK #1E7A2B` untuk aksi utama.
- **Lantai arena** — `godot/shaders/floor_grid.gdshader` (`unshaded`) menerima
  `bg_top/bg_bottom/grid_color/defense_color`.
- **Prototipe web** — `applyTheme()` menulis custom property CSS (`--accent`, `--accentRGB`,
  `--accentLit`, `--enemy`, `--bgTop`, `--bg0`, `--track`) setiap kali varian berganti.
  **Markas ikut tema stage yang akan dimainkan**, jadi menu sudah berwarna arena berikutnya
  sebelum run dimulai. Diverifikasi: 5 varian menghasilkan palet berbeda.

---

## 6.4 Aturan Tipografi

| Peran | Ukuran @1080p | Warna |
|---|---|---|
| Angka besar (skor, combo) | 58–86 px | Putih / `#FFD54F` |
| Judul layar | 76–112 px | Aksen varian / `#FF1744` saat kalah |
| Label | 20–30 px | `#8A9BB8`, uppercase |
| Tombol | 44–56 px | Ink di atas face gelap, `#06240E` di atas hijau |
| Floating text | 40 px | `#FFD54F`, outline |

- Semua label memakai **outline**, bukan drop shadow: outline tetap terbaca di atas lantai
  gelap maupun ledakan terang.
- Kontras minimum **4.5:1** terhadap background tergelap.
- **Tidak ada teks di bawah 20 px.**

---

## 6.5 Safe Area & Ergonomi

| Aturan | Nilai |
|---|---|
| Safe area atas | 88 px, tidak pernah ditempati elemen apa pun |
| Safe area bawah | 72 px (home indicator / gesture bar) |
| Margin horizontal | 44 px (HUD), 60 px (layar menu) |
| Target sentuh minimum | 120 px tinggi (tombol layar), 128 px (jeda), 230 px (chain shot) |
| Jarak antar aksi | ≥ 20 px |
| Zona jempol | sepertiga bawah layar — semua aksi utama ada di sana |
| Elemen yang **tidak boleh** ada di zona jempol | Skor, chip wave (info saja, di atas) |
| Rasio didukung | 9:21 – 9:16 lebar penuh; di luar itu pillarbox portrait (lihat penjaga aspect di atas) |

Referensi ergonomi yang dipakai: target 44 pt iOS / 48 dp Android sebagai lantai mutlak,
postur "subway thumb" (satu tangan, portrait) sebagai postur default, dan prinsip Space Ape
bahwa layar lain hanya **menambah** ruang terhadap aspect dasar — tidak pernah mengurangi.

**Uji wajib:** iPhone SE (16:9), iPhone 15 Pro (19,5:9 + Dynamic Island), Galaxy S23
(19,5:9 punch-hole), desktop lanskap 1440 × 900 (harus pillarbox, bukan melar), layar
persegi 900 × 900.

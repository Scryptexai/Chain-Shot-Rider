# 6. UI Wireframe Portrait — CHAIN RIDER

![Mockup HUD portrait](images/ui-portrait-mockup.png)

Resolusi acuan: **1080 × 1920** (9:16). CanvasScaler: `Scale With Screen Size`, match **width = 1.0** (lebar adalah dimensi kritis di portrait; tinggi bervariasi 18:9 – 21:9).

---

## 6.1 Wireframe Utama (gameplay)

```text
┌─────────────────────────────────────┐ ── 0 px
│            [ SAFE AREA TOP ]        │    notch / punch-hole
├─────────────────────────────────────┤ ── 88 px
│  ┌───────┐              ┌────────┐  │
│  │ 12,480│              │ WAVE 3 │  │  TOP BAR (h = 140 px)
│  │ SCORE │   ╔══════╗   │  /5    │  │  · Skor  : 72 px bold, putih
│  └───────┘   ║ x12  ║   └────────┘  │  · Combo : 84 px, gold #FFD54F, pulse
│              ╚══════╝               │  · Wave  : 44 px, pill outline cyan
├─────────────────────────────────────┤ ── 228 px
│ ╌╌╌╌╌╌╌╌ spawn gate (Z=40) ╌╌╌╌╌╌╌╌ │
│                                     │
│   ▪▪▪▪▪▪▪▪▪▪▪▪   crowd merah        │  SPAWN ZONE
│   ▪▪▪▪▪▪▪▪▪▪▪▪                      │  ≈ 22% tinggi layar
│   ▪▪▪▪▪▪▪▪▪▪▪▪                      │
│                                     │
│  ◉                          ◉       │  COMBAT ZONE
│         ╲                           │  ≈ 45% tinggi layar
│          ╲   ✦ bullet + trail       │  · bumper magenta
│           ╲                         │  · peluru cyan
│  ◉         ╲                ◉       │  · floating text "+100"
│             ╲                       │    muncul di sini
│              ╲                      │
│ ─────────── DEFENSE LINE ────────── │  cyan, selalu terlihat
│                                     │  PLAYER ZONE
│                 ▲ player            │  ≈ 12% tinggi layar
│                                     │
├─────────────────────────────────────┤ ── 1650 px
│  STEER  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░  2.1s   │  BOTTOM BAR (h = 200 px)
│                                     │  · Steer meter: bar penuh lebar
│  ●●●●○      ammo          ♥ ♥ ♡     │  · Ammo kiri, HP kanan
├─────────────────────────────────────┤ ── 1850 px
│         [ SAFE AREA BOTTOM ]        │    home indicator iOS
└─────────────────────────────────────┘ ── 1920 px

      ZONA JEMPOL (thumb zone)
      ╭───────────────────────╮
      │  tap  = tembak / rem  │  seluruh area gameplay
      │  swipe = belokkan     │  bisa disentuh — tidak ada
      ╰───────────────────────╯  tombol yang harus dibidik
```

---

## 6.1b Dua Elemen HUD Tambahan

| Elemen | Posisi | Perilaku |
|---|---|---|
| **Garis bidik** (aim indicator) | Dari muzzle, mengikuti sudut turret | Garis putus-putus memprediksi **2 pantulan** ke depan; tiap segmen lebih pudar dan lebih tipis, titik pantul diberi dot. **Disembunyikan saat riding**, karena saat itu tap berarti "rem" bukan "tembak" — indicator yang tetap tampil akan membohongi pemain. |
| **Bar HP boss** | Atas layar, di bawah HUD wave (`top: 96px`) | Muncul hanya saat wave 5. Nama boss + bar merah-oranye. Untuk Twin Warden, bar menunjukkan HP **gabungan** kedua bagian, sehingga revive terlihat sebagai bar yang naik lagi. |

Garis bidik memakai prediksi yang sama persis dengan simulasi (`RicochetSolver.PredictWallPath`).
Kalau batas yang dipakai indicator dan simulasi berbeda sedikit saja, indicator akan
berbohong. Diverifikasi numerik: **deviasi terburuk 0.43 unit pada 19 titik pantul**
(dalam toleransi radius peluru + substep).

---

## 6.2 Anatomi Elemen

### Top Bar (`y: 88–228 px`)

| Elemen | Posisi | Ukuran | Style |
|---|---|---|---|
| Skor | anchor top-left, `(48, -48)` | 72 px | Bold, putih, angka tumbuh dengan *count-up tween* 0.2 s |
| Label "SCORE" | di bawah skor | 28 px | `#8A9BB8`, uppercase, letter-spacing +8% |
| Combo multiplier | anchor top-center | 84 px | `#FFD54F`, outline hitam 4 px, **scale pulse 1.0→1.15** tiap kenaikan |
| Wave counter | anchor top-right, `(-48, -48)` | 44 px | Pill outline cyan 3 px, format `WAVE 3/5` |

> Combo **tidak ditampilkan** saat bernilai 0 atau 1 — mengurangi kebisingan visual saat pemain belum membangun apa pun.

### Bottom Bar (`y: 1650–1850 px`)

| Elemen | Posisi | Spesifikasi |
|---|---|---|
| **Steer meter** | full width − 96 px margin, tinggi 24 px | `Image` filled horizontal, fill `#00E5FF`, track `#12233A`. **Alpha 0.25 saat tidak aktif**, 1.0 saat bullet riding. Menyala putih di 0.5 detik terakhir sebagai peringatan. |
| Sisa detik | kanan bar | 32 px, format `2.1s` |
| **Ammo** | bawah-kiri, `(48, 48)` | 5 ikon peluru 44 px, jarak 12 px. Ikon kosong = outline. Isi ulang otomatis (tidak ada tombol reload) dengan animasi fill 0.35 s. |
| **HP** | bawah-kanan, `(-48, 48)` | 3 hati 56 px. Hati hilang = outline + shake 0.3 s + flash merah layar. |

### Overlay (tidak memblokir input)

| Elemen | Perilaku |
|---|---|
| **Combo popup** | Muncul di tengah layar pada milestone x10/x20/x50/x100. Scale 0.4→1.25→1.0, alpha in 0.12 s, hold 0.6 s, out 0.25 s. Berjalan di **unscaled time** agar tetap cepat walau slow-mo. |
| **Floating text** | `+100` di lokasi kill (world→screen), naik 90 px/s, fade kuadratik, 0.8 s. Pool 32; kalau habis, teks **diagregasi** jadi satu popup total — lebih terbaca DAN lebih murah. |
| **Slow-mo vignette** | Vignette 0.22→0.42 + chromatic aberration 0→0.45 + tint biru `#00344D`. Blend mengikuti `SlowMoSystem.Blend`. |
| **Damage flash** | Full-screen `#FF1744` alpha 0.6 → 0, durasi 0.4 s. |
| **Near-miss warning** | Banner tipis di atas garis pertahanan, pulse merah, + heartbeat SFX. |
| **Perfect clear** | Sweep cahaya di garis pertahanan + banner "PERFECT" 0.8 s + `+50 coins`. |

---

## 6.3 Layar Non-Gameplay

```text
   MAIN MENU              PAUSE              RESULT (win/lose)
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│              │    │              │    │   VICTORY    │
│ CHAIN RIDER  │    │   PAUSED     │    │              │
│   (logo)     │    │              │    │ SCORE 24,180 │
│              │    │  ▶ RESUME    │    │ KILLS   312  │
│  ┌────────┐  │    │  ↻ RESTART   │    │ BEST x47     │
│  │  PLAY  │  │    │  ⌂ MENU      │    │ COINS  +180  │
│  └────────┘  │    │              │    │              │
│              │    │  ♪ ─────○    │    │ ┌──────────┐ │
│ [1][2][3]    │    │  ♫ ────○─    │    │ │  RETRY   │ │
│ [4][5] arena │    │              │    │ └──────────┘ │
│              │    └──────────────┘    │   ⌂ MENU     │
│  ⚙  🏆  🛒   │                        └──────────────┘
└──────────────┘
```

- **Pemilih arena** di menu: 5 kartu dengan thumbnail tema warna masing-masing + status "locked/unlocked".
- **Result screen** memakai count-up tween per baris (0.15 s jeda antar baris) — membuat angka terasa "diraih".
- Tombol utama minimum **160 × 160 px** (≈ 9 mm), berada di sepertiga bawah layar (zona jempol).

---

## 6.4 Aturan Tipografi

| Peran | Font | Ukuran @1080p | Warna |
|---|---|---|---|
| Angka besar (skor, combo) | Display Bold SDF | 72–84 px | Putih / `#FFD54F` |
| Label | Sans Semibold | 28–32 px | `#8A9BB8` |
| Tombol | Sans Bold | 44 px | Putih di atas `#00E5FF` |
| Floating text | Display Bold SDF | 40 px | `#FFD54F`, outline 3 px |
| Banner besar | Display Black SDF | 96 px | Putih, outline 6 px |

- **Semua teks memakai TextMeshPro SDF** — tajam di semua DPI, satu atlas, satu draw call.
- Kontras minimum **4.5:1** terhadap background tergelap.
- **Tidak ada teks di bawah 28 px.**
- Angka memakai *tabular figures* agar tidak "bergoyang" saat count-up.

---

## 6.5 Safe Area & Ergonomi

```csharp
// SafeAreaFitter.cs — dipasang di child pertama Canvas
Rect safe = Screen.safeArea;
rt.anchorMin = new Vector2(safe.xMin / Screen.width,  safe.yMin / Screen.height);
rt.anchorMax = new Vector2(safe.xMax / Screen.width,  safe.yMax / Screen.height);
```

| Aturan | Nilai |
|---|---|
| Margin horizontal minimum | 48 px |
| Jarak HUD ke area gameplay | 24 px |
| Elemen interaktif minimum | 160 × 160 px |
| Zona jempol nyaman | 0–35% tinggi layar dari bawah |
| Elemen yang **tidak boleh** ada di zona jempol | Skor, wave counter (info saja, di atas) |
| Rasio didukung | 16:9 sampai 21:9 (arena di-crop vertikal, HUD tetap) |

**Uji wajib:** iPhone SE (16:9, 375 pt), iPhone 15 Pro (19.5:9 + Dynamic Island), Galaxy S23 (19.5:9 punch-hole), tablet 4:3 (HUD tidak boleh melar — clamp lebar maksimum 1200 px).

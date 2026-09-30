# 7. Audio Cue Sheet — CHAIN RIDER

Prinsip: **telinga membaca combo lebih cepat daripada mata.** Di game ini, satu-satunya feedback yang tidak boleh gagal adalah *pitch ladder* bounce — pemain harus tahu combo-nya tumbuh tanpa melihat HUD.

---

## 7.1 Cue Sheet SFX

| # | Cue ID | Trigger | Deskripsi suara | Panjang | Vol | Pitch | Cooldown | Prioritas | Variasi |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `Shot` | `OnBulletFired` | Punchy: layer sub-bass 60 Hz + transient klik 4 kHz | 0.18 s | 0.85 | 1.00 | 0.05 s | **0** | 3 |
| 2 | `Bounce` | `OnBounce` | "Ting" metalik pendek, **naik 1 semitone tiap bounce** | 0.12 s | 0.70 | ladder | 0.02 s | **0** | 4 |
| 3 | `Kill` | `OnEnemyKilled` | Pop kecil kering, sedikit noise | 0.08 s | 0.45 | 0.95–1.05 | **0.04 s** | 3 | 5 |
| 4 | `ComboMilestone` | combo x10/20/50/100 | Chime naik 3 nada (arpeggio mayor) | 0.60 s | 0.90 | 1.00 | 0.30 s | 1 | 4 (per tier) |
| 5 | `Explosion` | `OnExplosion` | Boom berat, sub 40 Hz + debris | 0.90 s | 1.00 | 0.92–1.08 | 0.08 s | **0** | 3 |
| 6 | `ChainSpark` | chain depth > 0 | Sizzle pendek, pitch naik per depth | 0.15 s | 0.55 | +2 st/depth | 0.06 s | 2 | 2 |
| 7 | `SlowMoEnter` | masuk bullet time | Whoosh turun + filter sweep + detak jantung masuk | 0.40 s | 0.80 | 1.00 | 0.50 s | 1 | 1 |
| 8 | `SlowMoExit` | keluar bullet time | Whoosh naik, pitch-up, "snap" | 0.25 s | 0.70 | 1.00 | 0.50 s | 1 | 1 |
| 9 | `Heartbeat` | musuh ≤ 0.5 u dari garis | Detak jantung ganda, loop pelan | 0.70 s | 0.65 | 1.00 | 0.90 s | 1 | 1 |
| 10 | `Breach` | musuh lewat garis | Alarm rendah + impact tumpul | 0.50 s | 0.95 | 1.00 | 0.35 s | **0** | 2 |
| 11 | `PerfectClear` | wave bersih | Chord naik cerah + shimmer | 1.20 s | 0.85 | 1.00 | — | 1 | 1 |
| 12 | `KillMilestone` | 50/100/200 kill | Fanfare pendek + confetti rustle | 0.90 s | 0.85 | 1.00 | — | 1 | 3 |
| 13 | `BulletExpire` | peluru habis/rem | "Fizz" turun, tail reverb pendek | 0.30 s | 0.50 | 1.00 | 0.10 s | 2 | 2 |
| 14 | `SteerWarn` | steer meter < 0.5 s | Beep tipis berulang | 0.10 s | 0.40 | 1.00 | 0.25 s | 2 | 1 |
| 15 | `UITap` | tombol UI | Klik kering | 0.06 s | 0.55 | 1.00 | 0.05 s | 3 | 2 |
| 16 | `BossRoar` | boss spawn | Growl rendah + riser | 2.00 s | 1.00 | 1.00 | — | **0** | 1 (per boss) |

**Prioritas:** `0` = tidak pernah dibuang. Saat 8 voice penuh, cue prioritas angka lebih besar dicuri terlebih dahulu.

---

## 7.2 Pitch Ladder Bounce (fitur audio paling penting)

```text
bounce  1    2    3    4    5    6    7    8   ...  14  (cap)
semitone 1    2    3    4    5    6    7    8   ...  14
pitch  1.06 1.12 1.19 1.26 1.33 1.41 1.50 1.59 ... 2.24
                      ▲                   ▲
                 milestone 5         milestone 10
              (+ flash + slow-mo     (+ chime layer)
                    pulse)
```

```csharp
_bounceLadder = Mathf.Min(_bounceLadder + 1, 14);   // cap: di atas ini terdengar seperti tikus
float pitch = Mathf.Pow(1.05946f, _bounceLadder);   // 2^(1/12)
Play(CueId.Bounce, pitchOverride: pitch);
```

Ladder **reset saat peluru mati** (`OnBulletExpired`). Kenaikan semitone (bukan linear) membuat telinga mendengarnya sebagai tangga nada — secara musikal terasa "menanjak menuju sesuatu", yang persis emosi yang kita inginkan dari combo.

---

## 7.3 Musik

| Properti | Nilai |
|---|---|
| Format | OGG Vorbis q70, **streaming** |
| Panjang loop | 60 detik |
| BPM | **120** (2 beat/detik — mudah disinkronkan dengan pulse grid lantai) |
| Key | A minor (netral, tidak melelahkan dalam sesi 3 menit) |
| Struktur | 8 bar intro → 16 bar A → 16 bar B → 16 bar A' (loop point di akhir bar 56) |

### Layer per varian arena

| Varian | Layer tambahan | Karakter |
|---|---|---|
| 1. Classic Pit | `base_synth` saja | Netral, arcade murni |
| 2. Twin Towers | + `arp` (arpeggio 16th) | Tegang, sempit |
| 3. Gravity Chamber | + `pad` (pad reverb panjang) | Melayang, dingin |
| 4. Explosive Yard | + `percussion` (tom + industrial hit) | Agresif, panas |
| 5. Moving Maze | + `glitch` (stutter + bitcrush) | Gelisah, ritmik |

Layer di-crossfade lewat **AudioMixer Snapshot** (0.5 s), bukan dengan memutar/menghentikan AudioSource.

### Dynamic music

| Kondisi | Reaksi musik |
|---|---|
| Wave 1–2 | Hanya layer base |
| Wave 3–4 | + layer varian, volume naik 3 dB |
| Wave 5 (boss) | + drum fill, filter terbuka penuh |
| HP = 1 | High-pass sweep + tambahan sub pulse per beat |
| Slow-mo | pitch → 0.85×, low-pass 1200 Hz, volume −6 dB |
| Run berakhir | fade 1.5 s → stinger |

> Pitch musik saat slow-mo **tidak** diturunkan sampai 0.3×. Di bawah 0.8× rekaman terdengar rusak, bukan sinematik. 0.85× + low-pass memberi kesan waktu melar tanpa artefak.

---

## 7.4 Mixing & Ducking

```text
Master
├── Music        (-6 dB)  → duck -6 dB + LPF 1200 Hz saat slow-mo
├── SFX          ( 0 dB)
│   ├── Impact   ( 0 dB)  Shot, Bounce, Explosion, Breach   ← prioritas 0
│   ├── Crowd    (-4 dB)  Kill pop (dengan cooldown 0.04 s)
│   └── Ambient  (-12 dB) dust, hum arena
└── UI           (-3 dB)
```

| Aturan mix | Nilai |
|---|---|
| Voice pool | **8** AudioSource (2D, spatialBlend = 0) |
| Limiter di Master | threshold −1 dB, ratio 4:1 |
| Duck musik saat slow-mo | −6 dB, attack 0.15 s, release 0.4 s |
| Duck Crowd saat Explosion | −5 dB selama 0.3 s |
| Sidechain | Kick musik → duck Ambient −2 dB |

### Kenapa cooldown 0.04 s pada `Kill`?

Saat 200 musuh mati dalam 0.5 detik, memutar 200 pop akan: menghabiskan voice budget OS, menghasilkan clipping, dan terdengar seperti *pasir*. Dengan cooldown 40 ms, maksimum 25 pop/detik — cukup untuk terasa "brutal" dan tetap terbaca sebagai pop individual.

Untuk kill massal, yang menjual rasanya bukan jumlah pop melainkan **`ComboMilestone` chime + `Explosion` boom** di atas lapisan pop yang lebih jarang.

---

## 7.5 Timing Diagram — Satu Siklus Tembakan

```text
t=0.00  TAP
        │ Shot (punchy)                    ████
t=0.18  │
t=0.42  ├─ peluru menyentuh crowd pertama
        │ SlowMoEnter (whoosh)             ██████
        │ musik: duck -6dB, LPF 1200 Hz    ░░░░░░░░░░░░░░░░░░
        │ Kill pop ×N (cooldown 0.04)      · · · · · · · ·
t=0.55  ├─ bounce 1   Bounce (+1 st)       ▪
t=0.71  ├─ bounce 2   Bounce (+2 st)       ▪
t=0.90  ├─ bounce 3   Bounce (+3 st)       ▪
t=1.05  ├─ COMBO x10  ComboMilestone       ████████
t=1.20  ├─ barrel     Explosion            ██████████
        │             ChainSpark ×3        ▪ ▪ ▪
t=2.10  ├─ bounce 12 (sisa 3) → slow-mo 0.15
        │ musik: LPF 800 Hz                ░░░░░░░░
t=2.80  ├─ peluru habis
        │ BulletExpire (fizz)              ███
        │ musik: kembali normal (0.4 s)    ▒▒▒▒
t=3.20  └─ siap tembak lagi
```

---

## 7.6 Budget Audio

| Metrik | Target |
|---|---|
| Ukuran total audio dalam build | **< 12 MB** |
| SFX | mono, 22 kHz, ADPCM/PCM, Decompress on Load |
| Musik | stereo, 44.1 kHz, Vorbis q70, **Streaming** |
| Voice aktif maksimum | 8 SFX + 1 musik |
| DSP buffer | `Best Latency` (256 sample) — game timing-critical |
| Audio CPU | < 4% pada device target |

**Uji wajib:** mainkan wave 5 (200 musuh + chain explosion + combo x50) sambil memantau Audio Profiler. Tidak boleh ada voice stealing pada cue prioritas 0, dan tidak boleh ada clipping di Master.


---

## 7.7 Status implementasi (Godot)

Semua 16 cue di §7.1 sudah berbunyi di engine. Tidak ada aset audio berlisensi
yang bisa dijangkau dari sandbox ini, jadi setiap cue **disintesis secara
prosedural** oleh `tools/gen_sfx.py` ke `godot/audio/sfx/*.wav`.

Itu ternyata cocok dengan proyek ini, bukan sekadar terpaksa:

- **Deterministik.** Seed tetap, jadi WAV hasilnya byte-identik tiap run.
  (Versi pertama memakai `hash(name)` — Python mengacak hash string per proses,
  sehingga cue diam-diam berubah tiap regenerasi. Sekarang `zlib.crc32`.)
- **Kecil.** 36 file mono 22 kHz = **748 KB**, jauh di bawah budget 12 MB di §7.6.
- **Spesifikasinya memang sudah bahasa sintesis.** "Sub-bass 60 Hz + transient
  klik 4 kHz" memetakan langsung ke kode.

Pitch **tidak** di-bake. Ladder 14 semitone di §7.2 diterapkan saat play lewat
`pitch_scale`, jadi ladder bisa ditune tanpa merender ulang apa pun.

### Verifikasi tanpa bisa mendengar

Sandbox tidak punya perangkat audio, jadi cue-cue ini tidak bisa didengar di
sini. Itu persis kondisi yang melahirkan bug `Vector2.UP` dan bug lempengan
horizon: kode yang lolos semua pemeriksaan sambil salah di satu dimensi yang
tidak pernah diperiksa. Karena itu ada `tools/audit_sfx.js`, yang mengukur tiap
klip dan menggambar contact sheet gelombang (`screenshots/sfx-waveforms.png`).

Yang ditangkapnya, dan semuanya nyata:

| Temuan | Akibat |
|---|---|
| `declick` simetris 3 ms | Puncak cue perkusif ada di milidetik pertama, jadi ramp-nya merusak transien — `ui_tap` terukur peak 0,18 dari target 0,60. Diperbaiki jadi asimetris: attack 0,5 ms, release 8 ms. |
| `shot` centroid 112 Hz | Klik 4 kHz tenggelam oleh sub. |
| `explosion` tanpa transien onset | Debris baru mulai di t=0,12 s, jadi onsetnya sub murni tanpa "crack". |
| `hash()` tidak stabil | Cue berubah antar-run; klaim reproducible ternyata palsu. |

Satu catatan jujur soal metrik: ambang `centroid` dan `hfMin` adalah **batas
desain yang dikalibrasi**, bukan hukum fisika. Percobaan awal menetapkan `shot`
ke 90–400 Hz *dan* 6% energi onset — kombinasi yang tidak bisa dipenuhi suara
mana pun sekaligus. Ambang sekarang longgar cukup agar tidak saling tarik, tapi
tetap ketat cukup untuk menjepret jika ada edit yang menumpulkan transien.

### Mixing yang benar-benar berjalan

`godot/scripts/view/audio_director.gd` mengimplementasikan §7.4: voice pool 8,
pohon bus (`Music -6 dB`, `Impact 0`, `Crowd -4`, `Ambient -12`, `UI -3`),
limiter −1 dB di Master, duck musik −6 dB dengan attack 0,15 s / release 0,4 s
saat slow-mo, dan duck Crowd −5 dB selama 0,3 s setiap ledakan.

Dua hal yang dijaga ketat:

1. **Jitter pitch memakai RNG sendiri**, tidak pernah RNG simulasi. Menarik satu
   angka dari RNG sim untuk memvariasikan pop kill akan menggeser seluruh undian
   berikutnya dan merusak determinisme replay.
2. **Cooldown memakai waktu unscaled.** Kalau tidak, slow-mo akan meregangkan
   cooldown kill 0,04 s jadi seperempat detik.

Terukur di smoke test: balance tetap 2/5 menang, rata-rata 75,7 s, dan
determinisme 5×7200 tick tetap IDENTIK setelah audio masuk.


---

## 7.8 Status implementasi musik

Enam stem + dua stinger ada di `godot/audio/music/*.ogg`, disintesis oleh
`tools/gen_music.py`. **Total seluruh audio 4,50 MB** dari budget 12 MB di §7.6.

Format sesuai spesifikasi — Ogg Vorbis, stereo, 44,1 kHz, streaming. Encoder-nya
datang dari libsndfile yang dibundel wheel `soundfile`; di sandbox ini tidak ada
ffmpeg, oggenc, maupun sox.

### Satu inkonsistensi di §7.3 yang harus diputuskan

Bagian itu menyebut **loop 60 detik** sekaligus struktur **8 + 16 + 16 + 16 bar**
dengan loop point di akhir bar 56. Pada 120 BPM 4/4 satu bar = 2 detik, jadi
56 bar = 112 detik. Keduanya tidak bisa benar bersamaan.

Saya memilih **60 detik**, karena itu angka yang disandari bagian lain proyek:
budget audio §7.6, dan sesi 1–3 menit yang hampir tidak tertutup satu kali putar
oleh loop 112 detik. Proporsi seksi dipertahankan dengan membaginya dua:
**6 intro / 8 A / 8 B / 8 A' = 30 bar = tepat 60 detik**.

### Verifikasi

`tools/audit_music.py` mengukur tiap stem dan menggambar
`screenshots/music-structure.png`. Tiga hal yang tidak berlaku pada SFX:

| Cek | Kenapa perlu |
|---|---|
| **Sambungan loop** | Stem berputar selamanya; kalau sampel terakhir tidak menyambung ke yang pertama, akan berbunyi klik tiap 60 detik |
| **Grid 120 BPM** | Onset perkusi harus jatuh di grid, kalau melenceng lapisan tidak bisa ditumpuk |
| **Struktur** | Stem yang merender satu bar lalu mengulanginya lolos semua metrik lain sambil mati secara musikal |

Keempat temuannya nyata, dan yang ketiga memalukan:

1. **`glitch` clipping peak 1,26** meski dinormalisasi ke 0,82 — Vorbis melakukan
   overshoot saat decode pada gelombang kotak beralias. Diperbaiki dengan
   low-pass 5,2 kHz dan headroom turun ke 0,72.
2. **Sambungan `drums_fill` melompat 32×** — ekor tom di bar terakhir terpotong.
   `place()` sekarang membungkus ke awal, persis seperti yang terjadi pada
   putaran kedua. Turun ke 1,0.
3. **Struktur intro/A/B/A' praktis tidak ada** (spread RMS 0,0015). Saya menulis
   satu pola lalu mengulangnya 30 bar — persis kegagalan yang saya tulis sendiri
   di komentar pengujian. Sekarang intro benar-benar lebih lapang (bass half-note,
   satu kick per bar, arp separuh kerapatan), B berpindah ke `F–C–G–Am` dengan
   stab tiap ketukan dan filter lebih terbuka, A' menggandakan satu oktaf di atas.
4. **`hash()` Python** (di generator SFX) diacak per proses.

Satu catatan jujur soal metrik, sama seperti di §7.7: tiga dari empat "masalah"
yang tersisa setelah perbaikan ternyata **metrik saya yang salah sasaran**, bukan
musiknya — menguji grid ritmis pada pad, menguji arp bernot 1/16 terhadap grid
1/8, dan mengukur sambungan loop terhadap gerak *rata-rata* sehingga loop drum
mana pun yang dibuka dengan hentakan tampak rusak. Ambang seam sekarang
dibandingkan ke persentil 99, dan cek grid dibatasi ke stem yang memang ritmis.

### Dynamic music yang berjalan

`godot/scripts/view/music_director.gd`: tiga player berputar bersamaan di bus
`Music` dan **diaransemen lewat volume, bukan lewat start/stop**, supaya
lapisannya tidak pernah lepas sinkron.

| Kondisi | Reaksi |
|---|---|
| Wave 1–2 | Base saja |
| Wave 3–4 | + layer varian, +3 dB |
| Wave 5 (boss) | + `drums_fill`, filter terbuka penuh |
| Slow-mo | pitch 0,85×, low-pass 1200 Hz |
| Run berakhir | fade → stinger menang/kalah |

Duck −6 dB saat slow-mo sengaja **tidak** diulang di sini; itu sudah dikerjakan
`AudioDirector` di bus `Music`.

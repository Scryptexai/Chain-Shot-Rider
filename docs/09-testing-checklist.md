# 9. Testing Checklist — CHAIN RIDER

Tiga kelompok: **A. Performa**, **B. Determinisme**, **C. Gameplay & UX**.
Sebuah build dinyatakan lolos hanya kalau **seluruh item wajib (⚑)** hijau di device target.

---

## A. Performa

### A.1 Device Target

| Tier | Device uji | Target FPS | Toleransi |
|---|---|---|---|
| **Mid (baseline wajib)** ⚑ | Snapdragon 660 (mis. Redmi Note 7) | **60 FPS** | ≥ 58 FPS rata-rata, tidak ada frame > 33 ms |
| Low | Snapdragon 439 / RAM 2 GB | 30 FPS | ≥ 28 FPS rata-rata |
| High | Snapdragon 8 Gen 1 / A15 | 60 FPS | frame time ≤ 10 ms |
| iOS baseline ⚑ | iPhone 8 (A11) | 60 FPS | ≥ 58 FPS |

### A.2 Skenario Stress

| # | Skenario | Kriteria lolos |
|---|---|---|
| A2-1 ⚑ | **200 musuh aktif** + 1 peluru terbang | ≥ 58 FPS selama 30 detik |
| A2-2 ⚑ | 200 musuh + chain explosion 8 barrel | Tidak ada frame > 33 ms |
| A2-3 | 260 musuh (cap maksimum) | ≥ 50 FPS (degradasi anggun, tidak crash) |
| A2-4 ⚑ | Combo x50 + confetti + 200 partikel | Partikel aktif **tidak pernah > 200** |
| A2-5 | Slow-mo 0.15 selama 5 detik | Transisi mulus, tidak ada pop FOV |
| A2-6 | 5 wave berturut-turut tanpa jeda | Memori stabil, tidak menanjak |
| A2-7 | Semua 5 varian arena, 3 menit masing-masing | Tidak ada kebocoran antar varian |

### A.3 Memori & GC

| # | Item | Kriteria |
|---|---|---|
| A3-1 ⚑ | **`GC.Alloc` selama gameplay** | **0 B/frame.** Satu byte pun berarti ada alokasi di hot path. |
| A3-2 ⚑ | Total RAM | < 200 MB (Profiler → Total Reserved) |
| A3-3 | Mono heap | Stabil setelah 60 detik; tidak boleh tumbuh monoton |
| A3-4 ⚑ | Tidak ada GC spike | Tidak ada frame > 16.6 ms yang disebabkan `GC.Collect` |
| A3-5 | Build size | Android AAB < 100 MB, iOS IPA < 120 MB |
| A3-6 | Pool high-water mark | Semua pool < 90% kapasitas (kalau 100% → pool kekecilan) |

**Cara uji A3-1:** Profiler → Hierarchy → kolom `GC Alloc`, urutkan menurun, jalankan wave 5. Tersangka umum: `string` concat, `foreach` `Dictionary`, closure lambda, `GetComponent`, `renderer.material`, boxing struct ke `object`.

### A.4 Draw Call & GPU

| # | Item | Kriteria |
|---|---|---|
| A4-1 ⚑ | Draw call | ≤ 45 |
| A4-2 | SetPass call | ≤ 20 |
| A4-3 | Batch musuh | ≤ 6 (1 per tipe) untuk 200 musuh |
| A4-4 | Tris on-screen | ≤ 80 k |
| A4-5 | Overdraw | Tidak ada area > 4× (cek Rendering Debugger) |
| A4-6 | Thermal | Setelah 15 menit bermain, FPS tidak turun > 10% |

### A.5 Baterai & Termal

- [ ] 15 menit sesi berturut-turut: suhu perangkat < 42 °C.
- [ ] Konsumsi baterai < 8%/15 menit di tier mid.
- [ ] `Application.targetFrameRate = 60` dan vSync OFF (bukan unlimited FPS yang membakar baterai).

---

## B. Determinisme (constraint wajib: "bisa direplay")

| # | Item | Cara uji | Kriteria |
|---|---|---|---|
| B-1 ⚑ | **Replay identik** | Rekam run 3 menit (seed + `InputFrame` stream), putar ulang | Skor akhir, total kill, best combo **identik persis** |
| B-1b ⚑ | **Horizon uji harus menutup SEMUA wave** | `node tools/sim_test.js --determinism` (120 detik penuh, 5 varian) | Identik. **Jangan uji hanya 20–30 detik**: musuh Splitter baru muncul di wave 3, dan bug `Math.random()` pada fase sway-nya pernah lolos karena uji lama berhenti sebelum itu |
| B-2 ⚑ | **Checksum simulasi** | `ReplayRecorder.Checksum()` tiap 60 tick, bandingkan run vs replay | Seluruh urutan checksum identik |
| B-3 ⚑ | **Lintas device** | Replay yang sama di Android & iOS | Checksum identik |
| B-4 ⚑ | **Lintas frame rate** | Jalankan replay pada 30, 60, 120 FPS (cap manual) | Hasil identik (fixed-step bekerja) |
| B-5 | **Dengan slow-mo** | Replay yang memicu bullet time berkali-kali | Identik — slow-mo hanya mengubah frekuensi tick |
| B-6 | **Audit `UnityEngine.Random`** | `grep -rn "Random\." Scripts/` | Hanya muncul di kode kosmetik (VFX/pitch), **tidak** di jalur simulasi |
| B-6b | **Audit `Math.random()` di prototipe** | `grep -n "Math.random()" prototype/index.html` | Hanya 2 kemunculan, keduanya bertanda `// kosmetik` (pitch SFX, shake render). Semua keacakan simulasi lewat `S.rng` |
| B-7 | **Audit `Time.deltaTime`** | `grep -rn "Time.deltaTime\|Time.time" Scripts/` | Hanya di kode render/UI; simulasi memakai `SimClock` |
| B-8 | **Urutan iterasi** | Review kode | Tidak ada `foreach` `Dictionary`/`HashSet` yang memengaruhi state |
| B-9 | Pause/resume | Pause 10 detik di tengah run, lanjutkan | Tidak ada lompatan posisi; akumulator waktu dibuang dengan benar |
| B-10 | App backgrounding | Minimize 30 detik, buka lagi | Tidak ada burst tick (clamp `Advance` bekerja) |

**Skrip audit cepat:**
```bash
grep -rn "UnityEngine.Random\|Random.Range\|Random.value" unity/Assets/ChainRider/Scripts/ \
  --include="*.cs" | grep -v "Camera\|Vfx\|Audio\|// kosmetik"
grep -rn "Time.deltaTime\|Time.time\b" unity/Assets/ChainRider/Scripts/ \
  --include="*.cs" | grep -v "unscaled\|UI/\|Camera/"
```

---

## C. Gameplay & UX

### C.1 Ricochet

| # | Item | Kriteria |
|---|---|---|
| C1-1 ⚑ | Pantulan dinding simetris | Tembak 45° ke kiri dan ke kanan → lintasan cermin sempurna |
| C1-2 ⚑ | **Tidak ada tunneling** | Kecepatan 150% + substep 4: peluru tidak pernah menembus dinding/pilar |
| C1-3 ⚑ | Tidak ada peluru "menempel" | Tembak hampir sejajar dinding → `ReflectSafe` memaksa ≥ 12° keluar |
| C1-4 | Sudut arena | Tembak ke pojok → memantul benar, tidak terjebak loop |
| C1-5 | Bounce count akurat | Counter UI = jumlah pantulan sebenarnya |
| C1-6 | Damage stacking | Bounce ke-10 = damage × 1.15¹⁰ ≈ 4.05× |
| C1-7 | Speed cap | Speed multiplier tidak pernah > 1.50 |
| C1-8 | Peluru mati dengan benar | Bounce habis / keluar arena / boss shield / tap rem |

### C.2 Bullet Riding

| # | Item | Kriteria |
|---|---|---|
| C2-1 ⚑ | Riding aktif saat kontak musuh pertama | Slow-mo + zoom FOV 60→40 dalam 0.2 s |
| C2-2 ⚑ | Steer maksimum 15°/swipe | Tidak bisa 180° instan (rate limit 90°/s) |
| C2-3 | Steer meter 3 detik | Habis → auto-pantul + waktu kembali normal |
| C2-4 | Swipe bolak-balik | Koreksi halus bekerja (delta per frame, bukan posisi absolut) |
| C2-5 | Rem | Tap saat riding → peluru berhenti, bukan menembak peluru baru |
| C2-6 | Steer saat tidak riding | Diabaikan total, tidak ada efek samping |

### C.3 Crowd

| # | Item | Kriteria |
|---|---|---|
| C3-1 ⚑ | 5 formasi terbentuk benar | rect / V / diamond / line / circle — visual dicek per wave |
| C3-2 ⚑ | Formasi tidak menembus dinding | Semua musuh dalam `X ∈ [-10, 10]` |
| C3-3 | Separation | Musuh tidak tumpang-tindih total; sedikit sentuhan diperbolehkan |
| C3-4 | Sway | Terlihat hidup, tidak kaku, tidak kejang |
| C3-5 ⚑ | Garis pertahanan | Musuh lewat → −1 HP, musuh dihapus (tidak menumpuk) |
| C3-6 | Invulnerability 1 s | 10 musuh lewat bersamaan ≠ langsung game over |
| C3-7 | Near-miss | Heartbeat berbunyi **sekali** per musuh, tidak spam |
| C3-8 | Splitter | Pecah jadi 3 grunt; tidak crash saat pool hampir penuh |
| C3-9 | Bomber | Ledakan membunuh tetangga; chain tidak infinite |
| C3-10 ⚑ | Pool habis | Spawn ditolak dengan anggun, **tidak ada `Instantiate`** |

### C.4 Obstacle

| # | Item | Kriteria |
|---|---|---|
| C4-1 | Barrel chain | 8 barrel meledak berurutan dengan jeda 0.08 s, terbaca sebagai rantai |
| C4-2 | Gravity well | Lintasan melengkung; kecepatan **tidak** bertambah |
| C4-3 | Dua gravity well | Tidak saling tumpang-tindih; lintasan tetap terbaca |
| C4-4 ⚑ | Moving platform | Menghalangi musuh, **tidak** memantulkan peluru |
| C4-5 ⚑ | Shield wall | Dari depan memantul tanpa damage; dari belakang hancur setelah 3 hit |
| C4-6 | Pillar Twin Towers | Lorong tengah ≥ 2.0 unit — peluru tidak pernah stuck |

### C.5 UI & Input

| # | Item | Kriteria |
|---|---|---|
| C5-1 ⚑ | Satu jempol | Seluruh game bisa dimainkan dengan ibu jari kanan saja, tanpa mengubah genggaman |
| C5-2 ⚑ | Safe area | iPhone 15 Pro (Dynamic Island), Galaxy S23 (punch-hole): tidak ada HUD tertutup |
| C5-3 | Rasio 16:9 – 21:9 | Garis pertahanan & player selalu terlihat |
| C5-4 | Tap vs swipe | Tap < 0.25 s dan geser < 1.5% lebar layar → tembak; selain itu → steer |
| C5-5 | Keterbacaan | Semua teks ≥ 28 px, kontras ≥ 4.5:1 |
| C5-6 | Floating text | Pool habis → agregasi, tidak ada spam/stutter |
| C5-7 | Combo popup saat slow-mo | Tetap cepat (unscaled time), tidak ikut melambat |
| C5-8 | Count-up skor | Tidak pernah menampilkan angka yang lebih kecil dari sebelumnya |

### C.6 Kamera

| # | Item | Kriteria |
|---|---|---|
| C6-1 ⚑ | **Garis pertahanan selalu terlihat**, bahkan saat zoom ke peluru | Framing clamp bekerja |
| C6-2 | Transisi FOV | 60→40 mulus dalam 0.2 s, tidak ada pop |
| C6-3 | Shake tidak menumpuk | 10 ledakan beruntun tidak membuat kamera liar |
| C6-4 | Shake berjalan unscaled | Tidak ikut melambat saat slow-mo |
| C6-5 | Framing portrait | Player di 20% bawah safe area di semua rasio |

### C.7 Flow Run

| # | Item | Kriteria |
|---|---|---|
| C7-1 ⚑ | Durasi sesi | 1–3 menit untuk 5 wave |
| C7-2 | Kurva kesulitan | 30 → 50 → 80 → 120 → 200 musuh terasa menanjak, bukan melompat |
| C7-3 | Menang | Wave 5 bersih → Victory + skor akhir |
| C7-4 | Kalah | HP 0 → Defeat + skor akhir |
| C7-5 | Perfect clear | Nol kebocoran → +50 koin + banner |
| C7-6 ⚑ | Restart | Tidak ada state yang bocor dari run sebelumnya (skor, combo, pool, event bus) |
| C7-7 | Ganti varian arena | Obstacle lama dibersihkan total |
| C7-8 ⚑ | `GameEvents.ClearAll()` | Dipanggil saat keluar scene — tidak ada listener hantu |

---

## D. Prosedur Sign-Off

```text
1. Build release IL2CPP + managed stripping Medium
2. Pasang di Redmi Note 7 (SD660) dan iPhone 8
3. Jalankan PerfHud, mainkan 5 varian × 3 menit
4. Rekam replay tiap run, putar ulang, bandingkan checksum
5. Profiler: cek GC.Alloc = 0, draw call ≤ 45, RAM < 200 MB
6. Uji termal: 15 menit sesi berturut-turut
7. Semua item ⚑ hijau → build dinyatakan lolos
```

| Kondisi blocking (build ditolak) |
|---|
| Ada frame > 33 ms di tier mid pada skenario A2-1 atau A2-2 |
| `GC.Alloc` > 0 B/frame selama gameplay |
| Replay tidak identik (B-1 / B-2 / B-3 / B-4) |
| Musuh menembus dinding, atau peluru tunneling |
| HUD tertutup notch di device mana pun |
| Crash atau kebocoran memori setelah 10 run berturut-turut |

---

## Mengukur keseimbangan kartu upgrade

Mode `--cards` membandingkan 8 kartu `meta.cards` terhadap baseline tanpa kartu:

```
godot --headless --path godot/ --script res://tests/sim_headless.gd -- --cards
godot --headless --path godot/ --script res://tests/sim_headless.gd -- --cards-noise
godot --headless --path godot/ --script res://tests/sim_headless.gd -- --cards-replicate
```

### Kenapa metriknya bocor-per-menit, bukan skor

Tiga metrik dicoba dan dua gugur. Angkanya diukur, bukan diperkirakan:

| Metrik | Lantai derau | Kenapa gugur |
|---|---|---|
| Skor akhir run | **1,54×** | Tebing menang/kalah mendominasi; run yang mati awal melewatkan wave penuh. |
| Bunuh dalam jendela tetap | 1,07× | **Mentok pasokan spawn** — pemain sudah membunuh hampir semua yang muncul, jadi kartu tak terlihat. |
| **Bocor per menit hidup** | **1,03×** | Tidak mentok dan tidak dihukum karena bertahan hidup. Dipakai. |

Lantai derau diukur dengan menjalankan **konfigurasi identik tanpa kartu pada blok
seed berbeda**. Itu wajib dilakukan sebelum tabel kartu dipercaya: versi pertama uji
ini punya sebaran kartu 1,17× di bawah lantai derau 1,54×, artinya ia lulus ambang
1,6× tanpa mengukur apa pun.

### Guard yang membuat uji ini jujur sendiri

- `CARD_CONTROL_LIMIT` (1,12) — baris `(kontrol, seed lain)` adalah baseline kedua
  pada seed lain. Kalau dua pengukuran konfigurasi yang sama meleset lebih dari ini,
  sampelnya terlalu kecil dan uji **gagal**, bukan meluluskan tabel yang tak terbaca.
- `CARD_SPREAD_LIMIT` (1,25) — rasio kartu terkuat:terlemah.
- Mode kartu memakai `_endless_cfg()` (nyawa 9999) supaya setiap run menempuh jendela
  90 detik yang sama. Tanpa itu, kebocoran berhenti dihitung saat pemain mati dan
  kartu yang membuat pemain bertahan justru tercatat sebagai kerugian.

### Temuan: RNG bersama memalsukan hasil kartu

`extra_troops` awalnya terukur 0,78× / 0,86× / 0,81× pada tiga blok seed — konsisten,
di luar derau, dan **salah**. Audit kode menunjukkan `troops` hanya memberi makan
auto-fire yang sudah mentok 9/detik plus cadangan nyawa; tidak ada jalur mekanis ke
kebocoran. Penyebab sebenarnya: sebaran auto-fire menarik dari `_rng` yang sama dengan
polaritas gate, spawn wave, dan formasi. Fire rate naik seiring jumlah pasukan, jadi
setiap kartu penambah pasukan menarik lebih banyak undian dan **menggeser seluruh dunia
ke urutan acak lain**. Kartunya tidak lemah — ia bermain di arena yang berbeda.

Perbaikannya di `sim_world.gd`: `_fx_rng` terpisah untuk sebaran kosmetik. Setelah itu
`extra_troops` menjadi 0,98× (dalam derau). Aturannya sekarang: **undian yang tidak
memengaruhi aturan main tidak boleh berbagi aliran dengan pembangkitan dunia.**

### Hasil terukur (6 seed × 5 varian, jendela 90 s)

| Kartu | Bocor/mnt | Efektivitas |
|---|---|---|
| (tanpa kartu) | 28,17 | 1,00× |
| (kontrol, seed lain) | 28,97 | 0,97× |
| Trigger Discipline | 25,10 | **1,12×** |
| Heavy Core | 25,67 | **1,10×** |
| Hollow Points | 27,41 | 1,03× |
| Light Boots | 27,55 | 1,02× |
| Overcharge | 27,67 | 1,02× |
| Good Intel | 27,81 | 1,01× |
| Live Wire | 28,18 | 1,00× |
| Reinforcements | 28,65 | 0,98× |

Sebaran 1,14×, derau 1,03×. Dua kartu teratas adalah yang langsung menambah DPS
penahan garis — urutan yang masuk akal secara desain, dan itulah tanda pertama bahwa
pengukurannya benar.

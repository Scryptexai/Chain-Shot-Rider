# 00 — Art Bible CHAIN RIDER (v4.0, dari key art asli)

Sumber tunggal: `docs/images/keyart-master.jpg` (720×1280, 9:16).

> **Catatan koreksi.** Art bible v3.0 ("neon lane") ditulis tanpa file gambarnya
> ada di disk dan ternyata **salah total**: ia menggambarkan lorong neon ungu
> dengan pasukan berjalan kaki. Key art yang sebenarnya adalah **shoot-'em-up
> udara vertikal**. Seluruh dokumen ini ditulis ulang dengan gambar di depan
> mata. Kalau ada konflik dengan kode atau dokumen lama, **gambar yang menang**.

---

## 1. Genre dan kamera

Pesawat tempur dilihat dari **belakang-atas**, terbang ke arah layar bagian
atas, di atas kota pesisir yang terbakar saat senja. Dunia bergulir **menjauh
dari penonton**, bukan lorong yang didekati.

| Properti | Nilai terbaca | Catatan |
| --- | --- | --- |
| Rasio | 9:16 potret | 720×1280 |
| Sudut pandang | belakang-atas, pitch **11,1°** ke bawah | taksiran mata 25–30° salah: dengan FOV vertikal 60°, cakrawala 0,33 mengunci pitch di 11,1° (lihat N1) |
| Jangkar pemain X | 0.50 (tengah) | bukan 0.87 seperti spec lama |
| Jangkar pemain Y | ~0.72 dari atas | hidung jet ~0.60, nozzle ~0.80 |
| Tinggi pemain | ~**20%** tinggi layar | ujung sayap ke ujung sayap ~38% lebar layar |
| Cakrawala | ~**0.33** dari atas | laut bertemu awan; sepertiga atas = langit |
| Bos | puncak layar, 0.03–0.25 | mengisi ~60% lebar |
| Roll | 0 | jet lurus, horizon datar |

Konsekuensi langsung: kamera lorong (pitch 22,5°, anchor 0,87, horizon 0,14)
**tidak berlaku lagi**.

**Solusi kamera N1 (terpasang, terbukti di `tools/render3d_test.js` §4):**
pitch 11,1° · jet 25,4° di bawah horizontal dari kamera · jarak miring 19,8 ·
kamera 8,5 di atas dan 17,9 di belakang jet · FOV 60° · roll 0.
Terukur: jangkar X **50,0%**, jangkar Y **72,1%**, cakrawala **33,2%**.

Jarak dinaikkan dari 17,7 (nilai murni dari "jet 20% tinggi layar") ke 19,8
karena pada 17,7 lebar pandang di baris jet hanya 11,4 unit sementara koridor
pantul selebar 12 — pantulan di samping pemain terjadi di luar layar. Jet jadi
18% dan bukan 20%; keterbacaan pantulan lebih mahal daripada dua persen itu.

---

## 2. Lapisan kedalaman (jauh → dekat)

1. **Langit senja** — biru baja gelap di puncak (`#2E3E4E`) turun ke awan
   kumulus keemasan (`#F8D496`), dengan celah cahaya hangat di kiri.
2. **Bos dreadnought** — kapal udara raksasa abu metalik, menara dan antena
   bertingkat, lampu merah dan biru kecil di lambung, **inti bundar menyala
   oranye-putih** (`#FFFDD7`) di tengah bawahnya.
3. **Skuadron** — ~20 helikopter serang dan drone, siluet gelap dengan aksen
   merah, tersebar di sepertiga atas, beberapa menyeberang bingkai.
4. **Laut** — abu-biru dingin (`#67738B`) dengan pantulan api.
5. **Kota pesisir** — dua tepi daratan kiri-kanan, gedung terbakar, kolom
   asap tegak (`#D89988`), api oranye di permukaan tanah.
6. **Jet pemain** — putih-abu dengan panel biru, di tengah bawah.
7. **HUD** — melayang di atas segalanya.

Kota tidak pernah sampai ke tengah layar: koridor tengah selalu laut terbuka,
supaya peluru terbaca.

---

## 3. Palet (disampel dari gambar)

| Peran | Hex |
| --- | --- |
| Langit puncak | `#2E3E4E` |
| Awan senja | `#F8D496` |
| Sorot awan | `#FFD9A0` |
| Laut | `#67738B` |
| Asap | `#D89988` |
| Inti ledakan | `#FFEDA0` |
| Api ledakan | `#FF9A2E` |
| Tepi ledakan | `#E8571A` |
| Peluru pemain (inti) | `#EAFFFF` |
| Peluru pemain (pendar) | `#3FA9FF` |
| Laser/tracer musuh | `#FF3B2F` |
| Kubah perisai | `#2E8BFF` + tepi `#00D0FF` |
| Badan jet | `#D8DEE9`, panel `#4A5A7E`, aksen `#2BB8FF` |
| Semburan mesin | putih → `#FF8A2E` → `#2BB8FF` |
| Lambung bos | `#8A94A6`, inti `#FFD24A` |
| COMBO emas | `#FFC83A` / `#FFEBA1` |

Suasananya **hangat-dingin**, bukan ungu. Oranye api melawan biru peluru;
ungu hampir tidak ada.

---

## 4. Senjata dan efek serangan (inventaris lengkap)

| # | Efek | Deskripsi terbaca | Catatan implementasi |
| --- | --- | --- | --- |
| E1 | Aliran peluru pemain | dua pita rapat kapsul biru-putih naik dari hidung, sedikit melebar | kapsul additive, ~8/detik/pita, pendar biru |
| E2 | Semburan mesin | 4 nozzle, lidah api putih-oranye, pita biru memanjang ke bawah | selalu menyala, berdenyut |
| E3 | Laser radial bos | ~12 berkas merah memancar dari inti bos ke segala arah | garis tebal + inti putih, berdenyut |
| E4 | Peluru musuh | kapsul oranye-merah jatuh, kadang berekor | arah turun, lebih lambat dari peluru pemain |
| E5 | Rudal | titik api dengan **ekor asap putih panjang melengkung** | ini yang memberi gambar rasa kacau; wajib ada |
| E6 | Ledakan bola api | bola oranye-putih dengan asap mengepul, beberapa serentak | inti terang, tepi berasap, umur ~0.6 s |
| E7 | Kubah perisai heksagonal | bola biru transparan bermotif heksagon mengelilingi musuh | dua terlihat; menandai musuh yang kebal |
| E8 | Penanda target | lingkaran bidik tipis cyan di depan jet | mengunci musuh terdekat |
| E9 | Asap kota | kolom asap tegak dari daratan terbakar | lambat, parallax jauh |
| E10 | Kilau/bloom | semua sumber cahaya mekar kuat | pipeline bloom yang sudah ada tetap dipakai |

---

## 5. HUD (tata letak terbaca)

| Posisi | Elemen |
| --- | --- |
| Kiri atas | potret pilot kotak + **dua bar**: HP merah, shield biru |
| Tengah atas | bar **BOSS** merah + nama "Dreadnought Leviathan" |
| Kanan atas | `SCORE 2,487,360` kecil di atas, tombol jeda bundar |
| Kanan, di bawah skor | **`COMBO x156`** emas miring, angka jauh lebih besar dari label |
| Kiri bawah | kolom 4 tombol bundar: rudal `12`, bom biru `8`, perisai `3`, bidik |
| Kanan bawah | **radar bundar** dengan blip merah dan sapuan |

Gaya: bingkai tipis cyan, isi gelap tembus pandang, tipografi kondensat.

---

## 6. Aturan anti-plastik (tetap berlaku)

| # | Aturan |
| --- | --- |
| A1 | Tidak ada isian rata di permukaan besar — selalu gradien, panel, atau noise |
| A2 | Logam butuh env map; metalness tinggi tanpa environment = hitam |
| A3 | Proporsi dewasa; kendaraan ramping, bukan gemuk mainan |
| A4 | Satu bahasa bentuk untuk satu faksi |
| A5 | Pengulangan tekstur tidak lebih rapat dari ~7 unit dunia |
| A6 | HUD memakai garis neon tipis, bukan ikon mengilap |

---

## 7. Bloom (post-processing)

Ditulis tangan di `js/render3d.js` karena three.js r128 yang di-vendor tidak
membawa `EffectComposer`/`UnrealBloomPass`:

| Tahap | Isi | Nilai |
| --- | --- | --- |
| scene RT | resolusi penuh, `LinearEncoding` | — |
| bright pass | luminansi, `smoothstep(t, t+0.35, l)` | ambang **0.74** |
| blur | gaussian 9 ketuk, separable H/V, 2 putaran | setengah resolusi |
| composite | additive + ACES + vignette + sRGB manual | kekuatan **0.85**, exposure **0.92**, vignette **0.42** |

Tiga aturan yang mahal dipelajari:

1. RT scene harus `LinearEncoding`; kalau ditandai sRGB, warnanya dikonversi
   dua kali dan adegan pucat.
2. Composite wajib `pow(c, 1/2.2)` **sendiri** — `ShaderMaterial` buatan
   sendiri tidak ikut jalur encoding otomatis three.js.
3. Ambang rendah membuat lantai ikut mekar dan hitam terangkat jadi abu.

Ambang perlu **dinaikkan lagi** untuk key art baru: di sana yang mekar hanya
api, peluru, dan inti bos — langit siang hari tidak mekar.

Jatuh-balik: kalau render target gagal dibuat, `renderWithBloom()` kembali ke
`renderer.render()` langsung.

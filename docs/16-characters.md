# 16 — Karakter (v2.1 — KayKit Adventurers, dipakai apa adanya)

Sampai v0.5 setiap unit di CHAIN RIDER adalah bentuk: kapsul di Godot, kubus
dan bola bercahaya di web. v1.0 menggantinya dengan delapan karakter ber-rig
yang ditulis sendiri oleh `tools/rigkit.py` — cukup untuk membuktikan seluruh
jalur animasi hidup, tapi tetap terlihat seperti mainan kayu.

v2.0 mengganti tubuhnya dengan **KayKit Adventurers 2.0 FREE** (Kay Lousberg,
lisensi **CC0**) — tapi lewat sebuah pipeline yang membangun ulang pack itu
jadi GLB turunan: sembilan mesh digabung jadi satu primitif, UV dipanggang jadi
vertex color, LOD jauh didesimasi, warna digeser per peran. Semua demi
anggaran draw call.

**v2.1 membuang pipeline itu seluruhnya.** Yang tampil di layar sekarang
adalah berkas yang keluar dari pack, dimuat apa adanya:

| Berkas pack | Isi | Dipakai sebagai |
| --- | --- | --- |
| `Characters/gltf/Knight.glb` | 9 mesh, 1 material, 23 tulang, 5.800 tris | tubuh |
| `Animations/gltf/Rig_Medium/*.glb` | 26 klip untuk rig yang sama | gerak |
| `Assets/gltf/sword_1handed.gltf` | 1 mesh + .bin + .png | senjata di tangan |

Tidak ada langkah build untuk karakter. Tidak ada berkas turunan di repo.
Tiga berkas itu baru bertemu di runtime, di dalam renderer masing-masing
target — persis cara pack ini dirancang untuk dipakai.

Satu-satunya perlakuan terhadap geometrinya terjadi di memori dan bersifat
lossless: kesembilan potongan tubuh disambung jadi satu mesh (§2e). Jumlah
verteks dan segitiganya tetap sama sampai angka terakhir, dan dua tes
memverifikasinya terhadap isi berkas pack.

---

## 1. Dari mana asetnya

| Berkas | Isi |
| --- | --- |
| `KayKit_Adventurers_2.0_FREE.zip` | Pack asli dari pembuatnya, 13 MB, disimpan utuh di akar repo sebagai sumber yang bisa dilacak |
| `assets/models/kaykit/` | Subset yang benar-benar dipakai (6 karakter, 2 GLB animasi, 30 aset senjata, `License.txt`), diekstrak berdampingan supaya kedua target membuka berkas yang sama. Godot **mengimpor** folder ini — tidak ada lagi `.gdignore` di situ, karena justru berkas inilah yang dimainkan |
**Tidak ada perintah build untuk karakter.** Dulu ada
(`python3 tools/build_kaykit.py`); skrip itu beserta `tools/build_rigged.py`
dan `tools/rigkit.py` sudah dihapus dari repo, berikut seluruh GLB turunannya
di `assets/models/rigged/`. `tools/build_assets.py` (yang butuh trimesh) kini
hanya membangun **props** arena — tong, bumper, dinding perisai.

Resep peran hidup di dua tempat yang harus selalu kembar: `CAST` di
`js/render3d.js` dan `CharacterPool.CAST` di
`godot/scripts/view/character_pool.gd`. Isinya hanya pemilihan — karakter
mana, senjata apa, klip tembak mana, ukuran berapa — bukan satu pun angka yang
mengubah isi berkas.

### Peta peran → karakter

| Peran | Karakter KayKit | Tangan kanan | Tangan kiri | Klip `shoot` | Mesh tubuh | Tris tubuh | Tinggi asli |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `trooper` (squad) | Knight | `sword_1handed` | `shield_round_color` | `Throw` | 9 | 5.800 | 2,54 |
| `grunt` | Rogue | `dagger` | — | `Throw` | 7 | 7.562 | 2,18 |
| `runner` | Ranger | `bow_withString` | — | `Throw` | 8 | 8.900 | 2,28 |
| `brute` | Barbarian | `axe_2handed` | — | `Throw` | 7 | 7.123 | 2,40 |
| `splitter` | Mage | `staff` | `spellbook_closed` | `Use_Item` | 8 | 6.668 | 2,66 |
| `bomber` | Rogue_Hooded | `smokebomb` | — | `Throw` | 8 | 7.185 | 2,17 |
| `shielder` | Knight | `sword_1handed` | `shield_square_color` | `Throw` | 9 | 5.800 | 2,54 |
| `boss` | Knight (2× besar) | `sword_2handed_color` | — | `Throw` | 9 | 5.800 | 2,54 |

Senjatanya murah: 172 tris (dagger) sampai 684 (busur), satu mesh satu
material masing-masing. Enam berkas karakter untuk delapan peran — Knight
dipakai tiga kali, dibedakan oleh senjata, perisai, dan ukuran.

Tinggi di layar disamakan ke **`CHAR_HEIGHT` = 1,92 unit** (boss 2× = 3,84),
angka yang sama dengan versi sebelumnya, jadi kamera, kotak tabrakan, dan jarak
formasi tidak perlu disetel ulang. Karena tinggi asli tiap karakter berbeda
(kolom terakhir di atas), faktor skalanya dihitung saat dimuat dari kotak batas
berkasnya sendiri: `CHAR_HEIGHT / tinggi_asli × size`. Yang diubah hanya
`scale` node pemegang. Isi berkasnya tidak disentuh.

Setiap senjata membawa atlas-nya sendiri, jadi ia memang satu material
tambahan di samping material tubuh. Dulu hal itu dihindari mati-matian (satu
atlas per aktor = satu draw call); sekarang ongkosnya diterima — lihat
docs/08 — karena alternatifnya adalah mengarang ulang tekstur orang lain.

**Warna bawaan tidak digeser sama sekali.** Versi pertama pipeline ini memakai
pengali warna per peran supaya kawan terlihat dingin dan lawan kemerahan;
pendekatan itu dibuang. Menggeser palet KayKit sama saja dengan mengedit
karakternya, dan karakter yang diedit berhenti terlihat seperti karakter
aslinya. Peran dibedakan lewat tiga hal yang tidak merusak aset: **pilihan
karakternya** (Knight, Rogue, Ranger, Barbarian, Mage, Rogue_Hooded),
**senjatanya**, dan **skalanya** (boss 2×).

---

## 2. Yang dilakukan runtime, dan yang TIDAK dilakukan siapa pun

Perakitan satu aktor terdiri dari lima langkah. Empat pertama murni
penempatan; yang kelima menyentuh susunan mesh tapi tidak satu pun verteks,
UV, tekstur, atau warna di dalamnya:

**a. Pilih berkas.** Peran menentukan karakter mana yang dimuat. Knight
dipakai tiga peran (`trooper`, `shielder`, `boss`), jadi berkasnya dimuat
sekali dan dipakai bersama.

**b. Skala node.** Satu angka, dihitung dari tinggi asli berkasnya, dipasang
di `scale` node akar salinan. Cara yang sama dipakai setiap engine untuk
menaruh aset ke dalam dunia dengan satuan berbeda.

**c. Gantung senjata di tulang.** Rig KayKit menyediakan `handslot.l` dan
`handslot.r` — tulang kosong di telapak tangan — dan senjata diekspor pada
titik asal supaya cukup di-parent ke situ tanpa offset apa pun. Di web itu
`bone.add(weapon)`, di Godot `BoneAttachment3D`. Senjata tetap mesh
terpisah dengan materialnya sendiri; ia tidak di-skin ulang, tidak digabung
ke tubuh, dan tidak diubah sedikit pun.

**d. Pasang klip.** Berkas karakter tidak membawa animasi sama sekali (ia
hanya tubuh + rig); klipnya ada di dua berkas animasi terpisah yang memakai
rig yang sama. Keduanya dimuat sekali untuk seluruh cast, lalu lima klip yang
dipakai game diberi nama peran (`idle`, `run`, ...) **pada salinan di memori**.

> Yang bikin ini mulus dan hampir mencurigakan: jalur track di berkas animasi
> Godot berbunyi `Rig_Medium/Skeleton3D:hips`, dan struktur node berkas
> karakter juga `Knight/Rig_Medium/Skeleton3D`. Jadi klipnya cocok tanpa
> retarget, tanpa pemetaan nama, tanpa satu baris pun kode konversi. Di web
> hal yang sama berlaku karena `AnimationMixer` mengikat track lewat nama node.

**e. Satukan potongan tubuhnya — di memori.** KayKit mengirim tiap tubuh
sebagai 7–9 mesh (lengan kiri, lengan kanan, badan, jubah, kepala, helm, …).
Digambar apa adanya itu 7–9 draw call per aktor, dan dengan 74 musuh di lorong
angkanya terukur **694**. Yang membuat penyatuannya aman adalah bentuk
berkasnya sendiri: kesembilan mesh memakai **skin yang sama, material yang
sama, dan node tanpa transform**. Jadi menyambung atributnya berturut-turut
(posisi, normal, UV, indeks tulang, bobot, indeks segitiga yang digeser)
menghasilkan mesh yang identik verteks-per-verteks dengan aslinya.

| | Sebelum | Sesudah |
| --- | --- | --- |
| Draw call puncak (web, 74 musuh) | 694 | **184** |
| Pengikatan tekstur | 203 | **36** |
| Segitiga | 651.790 | **651.790** |

Segitiga yang tidak bergerak satu angka pun adalah buktinya: tidak ada yang
disederhanakan, tidak ada yang dipanggang, tidak ada yang hilang. Yang berubah
hanya berapa kali GPU dipanggil. Kalau syaratnya tidak terpenuhi (material
berbeda, skin berbeda, ada transform sendiri), kedua renderer **membatalkan**
penyatuan dan menggambar karakter sebagai sembilan mesh seperti di berkasnya —
`mergeBody()` di `js/render3d.js`, `_merge_body()` di `character_pool.gd`.

Dua tes menjaganya tetap lossless: `rig_test.js` mencocokkan jumlah verteks
tiap peran dengan jumlah POSITION di berkas pack (5.328 untuk Knight, 7.734
Ranger, …), dan `tests/smoke.tscn` memeriksa tiap aktor Godot hanya punya satu
mesh tubuh dengan jumlah segitiga yang cocok dengan salah satu karakter pack.

### Jalan buntu yang ditinggalkan (jangan diulang)

Empat "optimasi" di bawah ini pernah dikerjakan, semuanya berhasil secara
angka, dan semuanya salah secara hasil. Dicatat di sini supaya tidak ada yang
menemukannya kembali sebagai ide bagus:

| Yang dicoba | Keuntungan | Kenapa dibuang |
| --- | --- | --- |
| **Menulis ulang GLB** hasil penggabungan ke `assets/models/rigged/` | 208 → 26 draw call | Pack-nya berhenti jadi pack-nya: begitu berkas ditulis ulang, yang dimainkan bukan lagi karya aslinya, dan tiap selisih kecil menumpuk. Penggabungan yang sama sekarang dilakukan di memori (§2e) — manfaat yang sama, berkas tetap utuh |
| Panggang atlas jadi `COLOR_0` | nol pengikatan tekstur | Satu verteks hanya bisa menyimpan satu warna; garis mata, tepi emblem, dan gradien di dalam satu permukaan hilang |
| Desimasi untuk LOD jauh | 6k → 2k tris | Wajah rusak, dan sel yang cukup besar untuk hemat selalu menyeberangi batas petak atlas |
| Tint warna per peran | kawan/lawan lebih terbaca | Menggeser palet KayKit = mengedit karakternya. Peran dibedakan lewat pilihan karakter, senjata, dan skala |

Ongkos yang tetap dibayar, dicatat terbuka di docs/08 §8.0: **184 draw call**
pada gelombang terpadat (satu tubuh + satu-dua senjata per aktor) dan **652k
segitiga**. Keduanya di atas anggaran lama yang ditulis untuk kapsul. Itu
keputusan yang memang harus diambil pemilik project, bukan diam-diam oleh
pipeline.

---

## 2b. Unit di luar anggaran skinning

Musuh yang jauh tidak mendapat skeleton sendiri — tapi ia tetap karakter yang
sama, bukan model pengganti.

**Web:** satu salinan beku per peran. Pose siaga dihitung sekali, lalu semua
instance berbagi satu skeleton yang tidak pernah maju lagi. Geometri, tekstur,
dan senjatanya identik dengan versi animasinya; yang tidak ada hanyalah mixer.

**Godot:** masih MultiMesh kapsul berwarna untuk ekor barisan, seperti
sebelumnya. Anggaran musuh ber-tulang dinaikkan 16 → 24 supaya pita yang
benar-benar terbaca di layar semuanya karakter sungguhan. Ini satu-satunya
perbedaan visual yang tersisa antara kedua target, dan ia disengaja: MultiMesh
Godot butuh satu Mesh, sementara karakter KayKit adalah sembilan mesh.

## 3. Rig_Medium — 23 tulang, sama untuk keenam karakter

```
root ── hips ── spine ── chest ── head
                 │        ├── upperarm.l ── lowerarm.l ── wrist.l ── hand.l ── handslot.l
                 │        └── upperarm.r ── lowerarm.r ── wrist.r ── hand.r ── handslot.r
                 ├── upperleg.l ── lowerleg.l ── foot.l ── toes.l
                 └── upperleg.r ── lowerleg.r ── foot.r ── toes.r
```

Rig yang identik di keenam berkas adalah sebab kenapa pendekatan "muat apa
adanya" bisa bekerja sama sekali: dua berkas animasi melayani seluruh cast,
dan renderer tidak perlu tahu sedang memainkan siapa.

**Soket efek.** Versi lama menanam tulang tambahan bernama `muzzle` di ujung
senjata saat build. Sekarang tidak ada yang ditanam — kilatan dan titik
kelahiran peluru memakai `handslot.r` langsung. Selisih posisinya beberapa
sentimeter di dunia, tidak terlihat di layar ponsel, dan harganya nol
modifikasi berkas.

> Catatan nama: three.js r128 membuang titik dari nama node, jadi
> `handslot.r` di berkas menjadi `handslotr` di memori web. Godot
> mempertahankan nama aslinya. Kedua renderer menyimpan konstanta `SOCKET`
> masing-masing dengan ejaan yang benar untuk platformnya.

## 4. Lima klip, nama sama di semua unit

Tier gratis tidak punya animasi serang, jadi `shoot` dipinjam dari gerak
terdekat: `Throw` untuk ayunan senjata, `Use_Item` untuk rapalan penyihir.

| Klip game | Klip pack | Berkas | Ulang |
| --- | --- | --- | --- |
| `idle` | `Idle_A` | `Rig_Medium_General.glb` | ya |
| `run` | `Running_A` | `Rig_Medium_MovementBasic.glb` | ya |
| `shoot` | `Throw` / `Use_Item` | `Rig_Medium_General.glb` | tidak |
| `hit` | `Hit_A` | `Rig_Medium_General.glb` | tidak |
| `die` | `Death_A` | `Rig_Medium_General.glb` | tidak |

Dua puluh enam klip lain ikut termuat tapi tidak dipakai (`Jump_*`,
`Walking_*`, `Spawn_*`, `PickUp`, `Interact`, pose kematian) — bahan jadi
kalau nanti perlu, tanpa menyentuh apa pun.

glTF tidak menyimpan "klip ini berulang". Tanpa menyetel `idle` dan `run` ke
mode berulang secara eksplisit, karakter melangkah **satu langkah** lalu
membeku di udara — bug yang sudah dua kali ditemukan ulang di project ini,
sekali di web dan sekali di Godot.

Variasi antar unit datang dari `rate` acak per aktor (0,92–1,08×) plus fase
awal acak, bukan dari klip yang berbeda. Itu yang membuat kerumunan terbaca
sebagai banyak makhluk.

## 5. Anggaran LOD

Satu unit ber-skin = satu skeleton yang pose-nya dihitung ulang tiap frame.
Pada gelombang 200 musuh itu 200 skeleton untuk siluet selebar dua piksel.

| Anggaran | Jumlah | Konstanta |
| --- | --- | --- |
| Prajurit ber-tulang | 10 (barisan depan) | `SKIN.troops` / `BUDGET.troops` |
| Musuh ber-tulang | 24 terdekat (urut `z`) | `SKIN.enemies` / `BUDGET.enemies` |
| Mayat | 8 sekaligus | `SKIN.corpses` / `BUDGET.corpses` |
| Bos | selalu | — |

Puncaknya 10 + 24 + bos = 35 aktor ber-skeleton; `smoke.tscn` mengukur 34 pada
gelombang terpadat. Angka musuh naik dari 16 karena ekor barisan di Godot
masih kapsul, dan semakin sedikit kapsul yang terlihat semakin baik.

Sisanya: **web** memakai salinan beku berpose siaga (geometri sama, mixer
dimatikan), **Godot** memakai MultiMesh kapsul berwarna.

---

## 6. Web — `js/render3d.js`

Tabel resep (`KIT`, `CAST`, `CLIP_NAMES`, `CHAR_HEIGHT`, `SOCKET`, `SKIN`) ada
di kepala berkas, berpasangan satu-satu dengan konstanta Godot. Sisanya:

- `loadRigs()` memuat enam GLB karakter, dua GLB animasi, dan sepuluh `.gltf`
  senjata lewat GLTFLoader yang sama dengan props. Klip disalin per peran dan
  diberi nama game; `idle`/`run` dipaksa `LoopRepeat`.
- `mergeBody()` menyatukan 7–9 potongan tubuh jadi satu SkinnedMesh saat
  berkas selesai dimuat (§2e), dengan sederet penjaga: satu material, satu
  induk, transform sama, bind matrix sama, daftar tulang sama persis.
  GLTFLoader membuat objek `Skeleton` baru per mesh dari daftar tulang yang
  sama, jadi yang dibandingkan adalah tulangnya, bukan objek skeleton-nya.
- `cloneSkinned()` — salinan SkinnedMesh yang benar. `Object3D.clone()` biasa
  **tidak cukup**: salinannya tetap berbagi skeleton asli, jadi seluruh pasukan
  bergerak serempak seperti satu tubuh. three.js r128 yang di-vendor di repo
  ini tidak membawa `SkeletonUtils`, jadi rebind-nya ditulis tangan. Material
  ikut di-clone per aktor supaya kedip merah tidak menular ke segelombang.
- `frozenIdle()` membuat prototipe unit jauh: geometri, tekstur, dan senjata
  sama persis, mixer di-`update(0)` sekali lalu tidak pernah maju lagi.
- `attachWeapons()` — `bone.add(copy)` di `handslotr` / `handslotl`.
- `frustumCulled = false` untuk mesh ber-rig: bounding box-nya masih bind
  pose, jadi unit yang roboh berkedip hilang di tepi layar.
- `assetURL()` membungkus setiap pemuatan aset supaya build satu-berkas bisa
  mengalihkannya ke data URI (lihat docs/14).
- Deteksi kematian lewat `id` musuh yang hilang antar frame → `spawnCorpse`.
  Deteksi tembakan memakai keberadaan peluru di dekat tangan, **bukan** panjang
  `S.autoBullets`: peluru bisa lahir dan mati di frame yang sama, jadi
  tembakan justru terlewat saat layar paling ramai.

---

## 7. Godot — `godot/scripts/view/character_pool.gd`

Satu-satunya tempat di proyek Godot yang tahu soal Skeleton3D,
AnimationPlayer, dan BoneAttachment3D. `ArenaView` hanya meminta "beri aku
seorang grunt di sini, sedang berlari".

Empat hal yang khas Godot:

1. **Klip tidak ikut di berkas karakter.** `_load_clips()` membuka dua GLB
   animasi sekali, menyalin lima klip ke `AnimationLibrary` baru dengan nama
   game, dan menyetel `LOOP_LINEAR` untuk `idle`/`run` (importer Godot
   menandai semua klip glTF sebagai sekali-jalan).
2. **`AnimationPlayer.root_node` dibiarkan default (`..`).** Player ditambahkan
   sebagai anak akar karakter, jadi track `Rig_Medium/Skeleton3D:<tulang>`
   resolve apa adanya. Mengubahnya ke `.` memutus seluruh animasi.
3. **Senjata lewat `BoneAttachment3D`** dengan `bone_name = "handslot.r"`.
   Indeks tulangnya berbeda antar berkas (13 di Knight, 18 di manekin
   animasi) dan itu tidak jadi soal karena track mengalamatkan tulang lewat
   nama.

4. **`_merge_body()`** menyatukan potongan tubuh lewat
   `surface_get_arrays()` → satu `ArrayMesh`, sekali per karakter lalu
   di-cache (`_merged`). Penjaganya `_parts_uniform()` dan `_same_skin()`:
   kalau material, format verteks, atau bind pose-nya berbeda, penyatuan
   dibatalkan dan karakter digambar seperti di berkasnya.

Satu aktor = satu `Node3D` pemegang + hierarki hasil `instantiate()` + 1 mesh
tubuh + senjata. Efek memudar mayat tetap mengiterasi `Actor.meshes` (daftar
semua mesh termasuk senjata) — jangan kembali ke asumsi `Actor.mesh` tunggal.

Aset dijangkau lewat symlink `godot/assets -> ../assets` supaya kedua target
membuka berkas yang sama persis. Sekali per mesin perlu

```bash
godot --headless --path godot/ --import
```

agar cache impor terbentuk. Berkas `*.import` ikut di-commit.

---

## 8. Apa yang membuktikan semuanya hidup

| Perintah | Yang dibuktikan |
| --- | --- |
| `node tools/rig_test.js` | Berkas pack sendiri: SkinnedMesh, 23 tulang, soket `handslot`, kelima klip, **jumlah verteks sama persis dengan berkas pack** (penyatuan lossless), dan **tulang yang seharusnya bergerak memang bergerak** (kaki saat `run`, kepala saat `die`, tangan kanan saat `shoot`) |
| `node tools/perf_probe.js` | Beban renderer sungguhan saat bertempur: draw call, segitiga, tekstur, program shader — angka yang dipakai docs/08 §8.0 |
| `node tools/char_test.js` | Karakter hidup **di dalam game**: aktor muncul saat bertempur, anggaran LOD dihormati, klip berbeda sesuai keadaan, tiap aktor punya fase sendiri, senjata ada di tangan, mayat roboh lalu dibersihkan, tanpa error konsol |
| `godot --headless --path godot/ res://tests/smoke.tscn` | Godot memuat kedelapan peran dari pack, mencapai puncak 34 aktor, dan mengenali kelima klip |
| `python3 tools/run_game.py --check` | Lima varian, 1800 frame per varian, hasil simulasi identik |
| `bash tools/export_web.sh` + `node tools/godot_web_test.js … --play` | Build Godot **benar-benar jalan di browser** memakai export template `web_nothreads_*.zip`, dengan karakter KayKit di layar |
| `node tools/cast_sheet.js <url> screenshots/kaykit-cast.png` | Lembar kontak kedelapan peran untuk diperiksa mata: senjata di tangan yang benar, tekstur utuh, pose tidak kusut |

Yang **tidak** dibuktikan tes mana pun: apakah karakternya enak dilihat. Itu
hanya bisa dinilai mata — `screenshots/qa-gameplay.png` (web),
`screenshots/godot-web-play.png` (Godot di browser), atau di ponsel.

---

## 9. Batas yang diketahui

- **184 draw call dan 652k segitiga** pada gelombang terpadat (terukur,
  `tools/perf_probe.js`). Anggaran lama ≤45 sudah tidak berlaku; docs/08 §8.0
  mencatat angka pengganti dan tuas yang belum ditarik.
- Ekor barisan di Godot masih kapsul MultiMesh, sementara web memakai salinan
  beku karakter. Satu-satunya perbedaan visual antar target yang tersisa:
  MultiMesh butuh satu Mesh, karakter KayKit sembilan.
- Bos memakai Knight yang dibesarkan 2×, bukan model bos tersendiri — tier
  gratis tidak punya satu pun.
- `shoot` adalah `Throw`/`Use_Item`; tidak ada animasi serang sungguhan di
  tier gratis.
- Mayat maks 8 dan hilang setelah 1,5 detik — pilihan anggaran.
- `die` adalah klip, bukan ragdoll.
- Belum diuji di Snapdragon 660 sungguhan.

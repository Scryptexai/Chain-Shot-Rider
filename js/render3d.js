/**
 * render3d.js — WebGL renderer for CHAIN RIDER.
 *
 * Same approach Last Harbor uses to show a game in the browser without
 * installing an engine: vendored Three.js (r128, UMD, classic script tag),
 * a real perspective camera, real lights, real meshes. No build step, no CDN,
 * no npm at runtime.
 *
 * This file only DRAWS. It never touches simulation state, never consumes the
 * simulation RNG, and never decides gameplay — it reads `S` once per frame and
 * moves meshes to match. Keeping it read-only is what lets the browser build
 * and the Godot build stay in step.
 *
 * World mapping: simulation (x, z) -> three.js (x, y, -z), matching the Godot
 * convention. Simulation z grows away from the player; three.js -z does too.
 *
 * Exposed as window.R3D (classic script, no modules, so file:// and any static
 * host work the same).
 */

(function (global) {
  'use strict';

  // --- Framing ---------------------------------------------------------------
  // Over-the-shoulder NEON framing, sama persis dengan build Godot. Angkanya
  // diselesaikan dari tiga ukuran key art (docs/17 §17.2) oleh
  // tools/solve_framing.py: pemain di 87% tinggi layar, setinggi 18.5% layar,
  // horizon di 14%. Kamera lama (fov 40, tinggi 47) membingkai arena dari
  // atas seperti papan permainan dan membuat pemain sebesar ibu jari.
  var CAM = {
    fov: 60,            // vertical FOV in degrees at 9:16
    pos: [0, 15.95, 11.1],
    // Titik bidik di lantai, bukan di nol: pitch 22.5 derajat ke bawah.
    look: [0, 0, -27.4],
    near: 0.5,
    far: 200,
  };

  // Lorong dipersempit 20 -> 12 bersama config: pada framing baru dinding di
  // x=+-10 baru masuk layar di z~20, artinya separuh pantulan terjadi di luar
  // layar. Lihat tools/migrate_neon.py.
  var ARENA = { halfWidth: 6, depth: 40, defenseLineZ: 5, playerZ: 2 };
  // Lantai dan dinding dipanjangkan ke arah kamera melewati garis pertahanan.
  // Arena logis tetap 0..40; tambahan ini murni visual, supaya tanah mengisi
  // tepi bawah layar alih-alih berhenti di tengah-tengah dan menyisakan pita
  // hitam di bawah HUD — persis cacat yang terlihat di build sebelumnya.
  var APRON = 34;
  // Lantai juga diteruskan jauh melewati gerbang spawn, supaya ujung lorong
  // larut dalam kabut alih-alih berhenti sebagai garis potong di sepertiga
  // atas layar — cacat yang langsung terlihat begitu kamera direndahkan.
  var APRON_FAR = 120;

  // Palet dunia bergaya fantasi: tanah berlumut, pagar kayu-batu, dan cahaya
  // obor — bukan neon. Warna aksen per stage tetap datang dari config
  // (variants[].theme), yang di sini hanya dipakai sebagai sorotan, supaya
  // arena tidak pernah lebih terang daripada karakternya sendiri.
  // Palet NEON, diambil dari config.artDirection (docs/17 §17.3). Nilai di
  // sini adalah cadangan untuk halaman yang memuat renderer sebelum config
  // selesai diunduh; begitu config ada, warnanya menang.
  var PAL = {
    bg: 0x070a14,
    floor: 0x0e1322,
    floorFar: 0x06080f,
    grid: 0x2be8ff,
    wall: 0x2a1b3d,
    wallGlow: 0xff2bd6,
    danger: 0xff2a2a,
    gatePos: 0x2be8ff,
    gateNeg: 0xff2a2a,
    bullet: 0xd9a441,
    chain: 0xa64bff,
    fog: 0x2a1340,
    tracer: 0xff2a2a,
    blast: 0xff9a2e,
    // Zirah pemain. Kembar dari artDirection di Config/arena_config.json.
    playerSteel: 0xdce6f2,
    playerDeep: 0x2e5bd8,
    playerCyan: 0x2be8ff,
  };

  // Props arena (tools/build_assets.py). Hanya benda mati: karakter TIDAK ada
  // di daftar ini lagi, lihat CAST di bawah.
  // Hanya dinding perisai yang masih datang dari berkas. Bumper dan drum
  // dulu memakai prop GLB hasil build_assets.py — kubah abu-abu dan tong
  // cokelat yang, dengan pencahayaan apa pun, terbaca sebagai mainan
  // plastik. Keduanya sekarang dibangun prosedural sebagai benda teknis
  // (lihat makePylon / makeDrum): bukan soal jumlah poligon, melainkan soal
  // benda itu memancarkan cahaya atau tidak.
  var MODELS = {
    shieldWall: 'assets/models/shield_wall.glb',
  };
  var loaded = {};      // name -> Object3D prototype
  var loadCount = 0;

  // --- Karakter: berkas KayKit APA ADANYA ------------------------------------
  //
  // Tidak ada langkah build dan tidak ada GLB turunan. Yang dimuat di sini
  // persis berkas yang keluar dari pack-nya:
  //
  //   Characters/gltf/Knight.glb          sembilan mesh, satu material, 5.800 tris
  //   Animations/gltf/Rig_Medium/*.glb    26 klip untuk rig yang sama
  //   Assets/gltf/sword_1handed.gltf      senjata, lengkap dengan .bin + .png
  //
  // Percobaan sebelumnya MENULIS ULANG karakter jadi GLB baru demi anggaran
  // draw call: satu primitif, atlas dipanggang jadi vertex color, LOD jauh
  // didesimasi. Hasilnya lebih murah tapi bukan lagi karakter KayKit, dan itu
  // bukan keputusan yang boleh diambil pipeline sendiri.
  //
  // Yang tersisa dari ide itu hanya bagian yang tidak mengubah apa pun:
  // mergeBody() menyambung kesembilan potongan tubuh jadi satu mesh DI MEMORI
  // (lihat fungsinya di bawah). Jumlah verteks dan segitiganya tetap sama
  // persis; yang hilang cuma delapan panggilan GPU per aktor. Angka terukur
  // ada di docs/08 §8.0.
  var KIT = 'assets/models/kaykit/';
  var ANIM_FILES = [
    KIT + 'Animations/gltf/Rig_Medium/Rig_Medium_General.glb',
    KIT + 'Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb',
  ];

  // Peran -> karakter, senjata, dan klip. Hanya PEMILIHAN; tidak ada satu pun
  // angka di sini yang mengubah isi berkasnya.
  var CAST = {
    // Pemain tidak memakai senjata pack: pedang dan perisai fantasi dibuang,
    // zirahnya dicat ulang, senapannya dibangun prosedural. Kembar dari CAST
    // di godot/scripts/view/character_pool.gd. Lihat docs/00-art-bible.md §3.
    trooper: { model: 'Knight', skin: 'armor' },
    grunt: { model: 'Rogue', right: 'dagger' },
    runner: { model: 'Ranger', right: 'bow_withString' },
    brute: { model: 'Barbarian', right: 'axe_2handed' },
    splitter: { model: 'Mage', right: 'staff', left: 'spellbook_closed', shoot: 'Use_Item' },
    bomber: { model: 'Rogue_Hooded', right: 'smokebomb' },
    shielder: { model: 'Knight', right: 'sword_1handed', left: 'shield_square_color' },
    boss: { model: 'Knight', right: 'sword_2handed_color', size: 2.0 },
  };

  // Nama klip di pack, dipetakan ke nama yang dipakai state machine game.
  // Klip tidak di-rename di dalam berkas; pemetaan hidup di sini saja.
  var CLIP_NAMES = {
    idle: 'Idle_A', run: 'Running_A', shoot: 'Throw', hit: 'Hit_A', die: 'Death_A',
  };

  // Tinggi karakter di dunia game. Karakter KayKit lahir setinggi 2,2–2,7
  // unit; arena ini memakai 1,92 (angka yang sama dengan versi sebelumnya,
  // jadi kamera, formasi, dan kotak tabrakan tidak perlu disetel ulang).
  // Yang diubah hanya `scale` node pemegangnya — berkasnya tidak disentuh.
  var CHAR_HEIGHT = 1.92;

  // Tulang tempat senjata digantung. Rig KayKit menyediakannya khusus untuk
  // ini; three.js membuang titik dari nama node saat memuat glTF, jadi
  // `handslot.r` di berkas menjadi `handslotr` di memori.
  var SOCKET = { right: 'handslotr', left: 'handslotl' };

  // Anggaran skinning. Satu gelombang bisa berisi 90 musuh; memberi semuanya
  // skeleton berarti 90 x 16 matriks tulang dan 90 draw call per frame, dan
  // ponsel kelas menengah langsung jatuh ke 20 fps. Yang dekat kamera mendapat
  // animasi penuh, sisanya tetap memakai mesh statis yang sudah ada — pada
  // jarak itu selisihnya beberapa piksel, sementara biayanya berlipat.
  var SKIN = { troops: 10, enemies: 16, corpses: 8 };
  // Tinggi manusia 0,96 unit di lorong selebar 20 unit itu benar secara
  // skala, tapi di layar ponsel 9:16 jadi 24 piksel — siluet, senjata, dan
  // animasi tulang tidak akan pernah terbaca. Semua unit (ber-tulang maupun
  // statis) dibesarkan dengan faktor yang sama supaya tidak ada lompatan
  // ukuran saat sebuah unit berpindah antara jalur skinned dan jalur statis.
  // Simulasi tidak ikut diubah: radius tabrakan tetap apa adanya.
  var CHAR_SCALE = 2.0;
  var rigs = {};        // name -> gltf {scene, animations}
  var rigCount = 0;
  var actorPools = {};  // name -> pool of actors
  var corpses = [];     // mayat yang sedang memainkan klip 'die'
  var aliveIds = {};    // id musuh -> {kind, x, z} frame sebelumnya
  var trail = [];       // jejak peluru chain
  var lastShotCount = 0;
  var lastFrameMs = 0;

  var THREE = null;
  var renderer = null, scene = null, camera = null, canvas = null;
  var groups = {};
  var pools = {};
  var labelCache = {};
  var baseFov = CAM.fov;
  var accentColor = 0x00e5ff;

  // ---------------------------------------------------------------------------
  // Small object pool: meshes are reused across frames so a wave of 200 enemies
  // never allocates mid-frame.
  // ---------------------------------------------------------------------------
  function makePool(parent, factory) {
    return {
      items: [], used: 0,
      begin: function () { this.used = 0; },
      take: function () {
        var it = this.items[this.used];
        if (!it) { it = factory(); this.items.push(it); parent.add(it); }
        this.used++; it.visible = true; return it;
      },
      end: function () {
        for (var i = this.used; i < this.items.length; i++) this.items[i].visible = false;
      },
    };
  }

  /**
   * Memuat semua GLB. Game tetap jalan sebelum selesai memuat: primitif dipakai
   * sampai modelnya siap, jadi tidak ada layar kosong menunggu aset.
   */
  /**
   * Alamat satu aset. Build satu-berkas (tools/build_standalone.py) menanam
   * seluruh GLB sebagai data URI dan menaruh petanya di `window.INLINE_MODELS`;
   * di situ path biasa tidak bisa dipakai karena protokol file:// memblokir
   * fetch. Semua pemuatan aset lewat fungsi ini supaya kedua mode (server dan
   * berkas tunggal) memakai jalur yang sama.
   */
  function assetURL(path) {
    var table = global.INLINE_MODELS;
    return (table && table[path]) ? table[path] : path;
  }

  function loadModels(onDone) {
    // Prop prosedural tidak perlu diunduh: ia sudah jadi begitu halaman
    // dibaca, jadi arena tidak pernah tampil dengan silinder sementara.
    loaded.bumper = makePylon();
    loaded.barrel = makeDrum();
    loadCount += 2;
    if (!THREE.GLTFLoader) { if (onDone) onDone(loadCount); return; }
    var loader = new THREE.GLTFLoader();
    var names = Object.keys(MODELS), pending = names.length;
    names.forEach(function (name) {
      loader.load(assetURL(MODELS[name]), function (gltf) {
        var root = gltf.scene;
        root.traverse(function (c) {
          if (!c.isMesh) return;
          // Jaring pengaman: tanpa atribut NORMAL, Lambert menghitung cahaya nol
          // dan modelnya tampil hitam pekat.
          if (!c.geometry.attributes.normal) c.geometry.computeVertexNormals();
          // Props dibangun sendiri dengan vertex color, jadi materialnya murah
          // dan cocok dengan tiga lampu yang sudah ada. Karakter TIDAK lewat
          // sini — materialnya datang utuh dari berkas KayKit.
          c.material = new THREE.MeshLambertMaterial({ vertexColors: true });
        });
        loaded[name] = root;
        loadCount++;
        if (--pending === 0 && onDone) onDone(loadCount);
      }, undefined, function () {
        if (--pending === 0 && onDone) onDone(loadCount);
      });
    });
  }

  /**
   * Memuat karakter KayKit apa adanya.
   *
   * Urutannya penting: dua berkas animasi dulu (keduanya dipakai bersama oleh
   * seluruh cast), lalu tiap karakter unik sekali saja — Knight dipakai tiga
   * peran, jadi memuatnya per peran berarti mengunduh berkas yang sama tiga
   * kali. Senjata menyusul belakangan karena ia hanya ditempel ke tulang.
   *
   * Material TIDAK disentuh sama sekali. GLTFLoader sudah membuat
   * MeshStandardMaterial dengan tekstur, sRGB, dan `skinning` yang benar;
   * setiap kali kode ini menggantinya dengan material buatan sendiri, yang
   * terjadi justru karakter menggelap atau memutih. Satu-satunya penyesuaian
   * adalah `frustumCulled = false`, karena bounding box bind pose membuat unit
   * yang roboh berkedip hilang di tepi layar.
   */
  function loadRigs(onDone) {
    if (!THREE.GLTFLoader) { if (onDone) onDone(0); return; }
    var loader = new THREE.GLTFLoader();
    var clipLib = {};
    var kinds = Object.keys(CAST);

    // Daftar berkas unik, bukan per peran.
    var charFiles = {}, itemFiles = {};
    kinds.forEach(function (kind) {
      charFiles[CAST[kind].model] = true;
      ['right', 'left'].forEach(function (hand) {
        if (CAST[kind][hand]) itemFiles[CAST[kind][hand]] = true;
      });
    });

    var scenes = {}, items = {};
    var pending = ANIM_FILES.length + Object.keys(charFiles).length + Object.keys(itemFiles).length;

    function done() {
      if (--pending > 0) return;
      kinds.forEach(function (kind) { buildRig(kind, scenes, items, clipLib); });
      if (onDone) onDone(rigCount);
    }

    ANIM_FILES.forEach(function (url) {
      loader.load(assetURL(url), function (gltf) {
        gltf.animations.forEach(function (clip) { clipLib[clip.name] = clip; });
        done();
      }, undefined, done);
    });

    Object.keys(charFiles).forEach(function (name) {
      loader.load(assetURL(KIT + 'Characters/gltf/' + name + '.glb'), function (gltf) {
        mergeBody(gltf.scene);
        gltf.scene.traverse(function (c) {
          if (c.isMesh || c.isSkinnedMesh) c.frustumCulled = false;
        });
        scenes[name] = gltf.scene;
        done();
      }, undefined, done);
    });

    Object.keys(itemFiles).forEach(function (name) {
      loader.load(assetURL(KIT + 'Assets/gltf/' + name + '.gltf'), function (gltf) {
        gltf.scene.traverse(function (c) { if (c.isMesh) c.frustumCulled = false; });
        items[name] = gltf.scene;
        done();
      }, undefined, done);
    });
  }


  /**
   * Menyatukan potongan tubuh menjadi satu SkinnedMesh — di memori, sekali,
   * saat berkas selesai dimuat.
   *
   * Setiap karakter KayKit dikirim sebagai 7–9 mesh terpisah (lengan kiri,
   * lengan kanan, badan, jubah, kepala, helm, ...). Di layar itu berarti 7–9
   * draw call per aktor, dan dengan 90 musuh di lorong angkanya tembus 600.
   *
   * Yang membuat penyatuannya aman adalah bentuk berkasnya sendiri: kesembilan
   * mesh memakai **skin yang sama, material yang sama, dan node tanpa
   * transform**. Jadi menyambung atributnya berturut-turut menghasilkan
   * geometri yang identik verteks-per-verteks dengan aslinya — UV, normal,
   * bobot tulang, dan tekstur dibawa apa adanya. Tidak ada yang
   * disederhanakan, tidak ada yang dipanggang, tidak ada yang hilang; yang
   * berubah hanya berapa kali GPU dipanggil untuk menggambarnya.
   *
   * Kalau sebuah berkas ternyata tidak memenuhi syarat itu (lebih dari satu
   * material, atau mesh-nya punya transform sendiri), fungsi ini diam-diam
   * tidak melakukan apa-apa dan karakter digambar seperti aslinya.
   */
  function mergeBody(root) {
    var parts = [];
    root.traverse(function (n) { if (n.isSkinnedMesh) parts.push(n); });
    if (parts.length < 2) return;

    var first = parts[0];
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      if (p.material !== first.material && p.material.map !== first.material.map) return;
      if (p.parent !== first.parent) return;
      if (!p.geometry.index) return;
      p.updateMatrix();
      if (!p.matrix.equals(first.matrix)) return;
      // GLTFLoader membuat objek Skeleton baru per mesh, tapi dari daftar
      // tulang yang sama persis. Yang harus sama adalah tulangnya (urutan dan
      // identitas) dan bind matrix-nya, bukan objek Skeleton-nya.
      if (!p.bindMatrix.equals(first.bindMatrix)) return;
      if (p.skeleton.bones.length !== first.skeleton.bones.length) return;
      for (var b = 0; b < p.skeleton.bones.length; b++) {
        if (p.skeleton.bones[b] !== first.skeleton.bones[b]) return;
      }
    }

    var attrs = ['position', 'normal', 'uv', 'skinIndex', 'skinWeight'];
    for (var a = 0; a < attrs.length; a++) {
      for (var k = 0; k < parts.length; k++) {
        if (!parts[k].geometry.attributes[attrs[a]]) return;
      }
    }

    var total = 0, idxTotal = 0;
    parts.forEach(function (p) {
      total += p.geometry.attributes.position.count;
      idxTotal += p.geometry.index.count;
    });

    var merged = new THREE.BufferGeometry();
    attrs.forEach(function (name) {
      var size = first.geometry.attributes[name].itemSize;
      var Ctor = name === 'skinIndex' ? Uint16Array : Float32Array;
      var out = new Ctor(total * size);
      var at = 0;
      parts.forEach(function (p) {
        var src = p.geometry.attributes[name].array;
        out.set(src, at);
        at += src.length;
      });
      merged.setAttribute(name, new THREE.BufferAttribute(out, size));
    });

    var index = new Uint32Array(idxTotal);
    var vOff = 0, iOff = 0;
    parts.forEach(function (p) {
      var src = p.geometry.index.array;
      for (var i = 0; i < src.length; i++) index[iOff + i] = src[i] + vOff;
      iOff += src.length;
      vOff += p.geometry.attributes.position.count;
    });
    merged.setIndex(new THREE.BufferAttribute(index, 1));
    merged.computeBoundingSphere();

    var body = new THREE.SkinnedMesh(merged, first.material);
    body.name = (root.name || 'char') + '_merged';
    body.bindMode = first.bindMode;
    body.bindMatrix.copy(first.bindMatrix);
    body.bindMatrixInverse.copy(first.bindMatrixInverse);
    body.bind(first.skeleton, first.bindMatrix);

    var parent = first.parent;
    parts.forEach(function (p) { parent.remove(p); });
    parent.add(body);
  }

  /**
   * Merakit satu peran dari berkas yang sudah dimuat.
   *
   * "Merakit" di sini hanya berarti: menunjuk scene karakter mana yang
   * dipakai, klip mana yang berlaku, dan berapa faktor skala supaya tingginya
   * cocok dengan arena. Tidak ada geometri yang disentuh.
   */
  function buildRig(kind, scenes, items, clipLib) {
    var recipe = CAST[kind];
    var scene = scenes[recipe.model];
    if (!scene) return;

    var clips = [];
    Object.keys(CLIP_NAMES).forEach(function (role) {
      // `shoot` boleh dialihkan per peran (penyihir melempar mantra, bukan
      // pisau), sisanya seragam untuk seluruh cast.
      var wanted = role === 'shoot' && recipe.shoot ? recipe.shoot : CLIP_NAMES[role];
      var clip = clipLib[wanted];
      if (!clip) return;
      // Klip disalin lalu diberi nama peran. Salinan, karena satu klip yang
      // sama dipakai delapan peran sekaligus dan nama di dalam objek klip
      // adalah kunci yang dipakai mixer.
      var copy = clip.clone();
      copy.name = role;
      clips.push(copy);
    });

    var box = new THREE.Box3().setFromObject(scene);
    var height = Math.max(0.001, box.max.y - box.min.y);
    rigs[kind] = {
      scene: scene,
      animations: clips,
      scale: (CHAR_HEIGHT / height) * (recipe.size || 1),
      right: recipe.right ? items[recipe.right] : null,
      left: recipe.left ? items[recipe.left] : null,
    };
    rigCount++;
    loaded[kind === 'trooper' ? 'soldier' : kind] = frozenIdle(rigs[kind], kind);
  }

  /**
   * Versi beku dari karakter yang sama, untuk unit di luar anggaran skinning.
   *
   * Ini BUKAN model LOD hasil desimasi — geometrinya sama persis, teksturnya
   * sama persis, senjatanya sama persis. Yang tidak ada hanyalah mixer: pose
   * siaga dihitung sekali, lalu semua salinan berbagi satu skeleton, sehingga
   * tiga puluh musuh di ujung lorong tidak menelan tiga puluh pembaruan
   * tulang per frame.
   */
  function frozenIdle(rig, kind) {
    var proto = cloneSkinned(rig.scene);
    attachWeapons(proto, rig);
    if (kind && CAST[kind].skin === 'armor') wearArmor(proto);
    else if (kind) wearThreat(proto, kind);
    fixProportions(proto);
    var idle = rig.animations.filter(function (c) { return c.name === 'idle'; })[0];
    if (idle) {
      var mixer = new THREE.AnimationMixer(proto);
      mixer.clipAction(idle).play();
      // Satu langkah nol: pose frame pertama, tanpa pernah maju lagi.
      mixer.update(0);
    }
    // Skala TIDAK dipasang di sini. Pemanggil (jalur crowd) memakai
    // rigs[kind].scale lewat holder-nya, sama seperti aktor ber-animasi,
    // supaya tidak ada lompatan ukuran saat unit berpindah jalur.
    proto.updateMatrixWorld(true);
    return proto;
  }

  /** Menelusuri dua hierarki identik berbarengan. */
  function parallelTraverse(a, b, visit) {
    visit(a, b);
    for (var i = 0; i < a.children.length; i++) {
      parallelTraverse(a.children[i], b.children[i], visit);
    }
  }

  /**
   * Menyalin karakter ber-tulang.
   *
   * `Object3D.clone()` biasa tidak cukup: salinannya tetap menunjuk skeleton
   * milik model asli, jadi sepuluh prajurit akan berbagi satu pose dan
   * bergerak serempak seperti satu makhluk. Skeleton harus disalin lalu
   * di-rebind ke tulang hasil salinan — ini isi SkeletonUtils.clone, yang
   * tidak ikut di bundel three.min.js yang di-vendor.
   */
  function cloneSkinned(source) {
    var sourceLookup = new Map(), cloneLookup = new Map();
    var clone = source.clone();
    parallelTraverse(source, clone, function (src, dst) {
      sourceLookup.set(dst, src);
      cloneLookup.set(src, dst);
    });
    clone.traverse(function (node) {
      if (!node.isSkinnedMesh) return;
      var srcMesh = sourceLookup.get(node);
      var srcBones = srcMesh.skeleton.bones;
      node.skeleton = srcMesh.skeleton.clone();
      node.bindMatrix.copy(srcMesh.bindMatrix);
      node.skeleton.bones = srcBones.map(function (bone) { return cloneLookup.get(bone); });
      node.bind(node.skeleton, node.bindMatrix);
      // Material per aktor: kedip merah saat kena tembak tidak boleh menular
      // ke seluruh gelombang.
      node.material = node.material.clone();
    });
    return clone;
  }

  /**
   * Menggantung senjata di tulang tangan.
   *
   * Inilah cara pack ini memang dirancang dipakai: `handslot.l` / `handslot.r`
   * adalah tulang kosong di telapak tangan, dan senjata KayKit diekspor pada
   * titik asal supaya cukup di-parent ke situ tanpa offset apa pun. Tidak ada
   * verteks yang dipindah, tidak ada mesh yang digabung — persis seperti
   * menaruh benda di tangan.
   */
  /**
   * Mengecat rig jadi zirah sci-fi dan menggantungkan senapan prosedural.
   *
   * Key art menunjukkan satu prajurit hard-surface biru-putih; rig yang
   * tersedia adalah ksatria fantasi bertekstur emas. Teksturnya dibuang
   * sepenuhnya (bukan dibaurkan — sisa emas 10% pun langsung terbaca sebagai
   * fantasi) dan diganti material metalik steel dengan emissive cyan tipis,
   * yang menjaga siluet tetap terpisah dari lantai gelap.
   *
   * Kembar dari shaders/player_armor.gdshader; Godot melakukan hal yang sama
   * dengan fresnel sungguhan, yang tidak sepadan biayanya di WebGL ini.
   */
  function wearArmor(root) {
    // Warna dasar DIGELAPKAN dari playerSteel. Steel terang dipakai di key
    // art sebagai sorotan pada pelat yang menghadap cahaya, bukan sebagai
    // warna seluruh badan; memakainya rata menghasilkan patung abu-abu pucat
    // tanpa bentuk — persis tampilan boneka plastik. Logam gelap dengan
    // metalness tinggi memantulkan tiga lampu ruangan dan memahat zirahnya.
    var armor = new THREE.MeshStandardMaterial({
      color: col(0x6d7f9b),
      emissive: col(PAL.playerCyan),
      emissiveIntensity: 0.14,
      // 0,78 dan bukan 0,95: logam penuh hanya memantul, jadi bagian yang
      // tidak menghadap sumber cahaya jatuh ke hitam dan siluetnya hilang.
      metalness: 0.78,
      roughness: 0.26,
      envMapIntensity: 1.4,
    });
    root.traverse(function (node) {
      if (node.isMesh || node.isSkinnedMesh) node.material = armor;
    });
    var bone = root.getObjectByName(SOCKET.right);
    if (bone) bone.add(makeRifle(armor));
  }

  /**
   * Senapan: popor, badan, laras, inti menyala. Prosedural karena pada ukuran
   * di layar ini satu-satunya hal yang harus benar adalah siluetnya — balok
   * panjang dengan satu titik panas cyan di ujung.
   */
  function makeRifle(armor) {
    var gun = new THREE.Group();
    [[0.09, 0.22, 0.12, 0.02], [0.11, 0.34, 0.16, 0.30]].forEach(function (p) {
      var box = new THREE.Mesh(new THREE.BoxGeometry(p[0], p[1], p[2]), armor);
      box.position.y = p[3];
      gun.add(box);
    });
    var barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.045, 0.42, 8), armor);
    barrel.position.y = 0.66;
    gun.add(barrel);
    var core = new THREE.Mesh(
      new THREE.SphereGeometry(0.055, 8, 6),
      new THREE.MeshBasicMaterial({ color: col(PAL.playerCyan) })
    );
    core.position.y = 0.88;
    gun.add(core);
    return gun;
  }

  /**
   * Mengecat musuh sebagai ANCAMAN, bukan sebagai cast fantasi.
   *
   * Rig yang tersedia adalah rogue hijau, ranger cokelat, penyihir berjubah
   * biru — delapan skema warna yang saling bertabrakan dan, di ujung lorong,
   * melebur jadi bubur cokelat-hijau. Key art melakukan hal sebaliknya:
   * ratusan unit dengan SATU bahasa warna (merah-oranye), dibedakan hanya
   * oleh siluet. Itu yang membuat kerumunan terbaca sebagai satu pasukan,
   * dan itu juga yang menghapus sisa terakhir tampilan mainan.
   *
   * Nilai warnanya digeser tipis per peran supaya dua tipe yang berdiri
   * berdampingan tidak melebur — tapi hue-nya tidak pernah berpindah.
   */
  var THREAT_SHADE = {
    grunt: 0.0, runner: 0.18, brute: -0.12, splitter: 0.26, bomber: -0.2,
    shielder: 0.08, boss: -0.06,
  };

  function wearThreat(root, kind) {
    var shade = THREAT_SHADE[kind] || 0;
    var body = new THREE.Color(0x6e1a14).offsetHSL(0, 0, shade * 0.35);
    var skin = new THREE.MeshStandardMaterial({
      color: body.convertSRGBToLinear(),
      emissive: col(PAL.blast),
      // Emissive sangat rendah: musuh harus memungut cahaya lorong, bukan
      // memancarkannya. Yang menyala di dunia ini hanya dinding, peluru,
      // dan pemain.
      emissiveIntensity: 0.12,
      metalness: 0.55, roughness: 0.55,
    });
    root.traverse(function (node) {
      if (node.isMesh || node.isSkinnedMesh) node.material = skin;
    });
  }

  /**
   * Mengecilkan kepala rig.
   *
   * Karakter KayKit digambar dengan proporsi chibi — kepalanya sekitar
   * seperempat tinggi badan (rasio 4 kepala), yang merupakan bahasa bentuk
   * mainan konstruksi. Key art memakai proporsi dewasa (kira-kira 7 kepala).
   * Satu skala tulang mengubah siluetnya dari boneka menjadi prajurit, dan
   * karena ia dikerjakan pada pose tulang, seluruh animasi tetap jalan.
   *
   * 0,76 dan bukan lebih kecil: di bawah itu helm mulai menembus bahu.
   */
  function fixProportions(root) {
    var head = root.getObjectByName('head') || root.getObjectByName('Head');
    if (head) head.scale.setScalar(0.74);
  }

  function attachWeapons(root, rig) {
    ['right', 'left'].forEach(function (hand) {
      var item = rig[hand];
      if (!item) return;
      var bone = root.getObjectByName(SOCKET[hand]);
      if (!bone) return;
      var copy = item.clone(true);
      bone.add(copy);
    });
  }

  /**
   * Faktor skala satu peran. Tiap karakter KayKit lahir dengan tinggi
   * berbeda (Rogue 2,17 unit, Mage 2,66), jadi faktornya dihitung per peran
   * saat dimuat; di sini hanya dibaca.
   */
  function charScale(kind) {
    var rig = rigs[kind];
    return rig ? rig.scale : CHAR_SCALE;
  }

  /** Satu karakter hidup: hierarki + mixer + klip + soket moncong. */
  function makeActor(kind) {
    var rig = rigs[kind];
    if (!rig) return null;
    var root = cloneSkinned(rig.scene);
    root.scale.setScalar(rig.scale);
    attachWeapons(root, rig);
    if (CAST[kind].skin === 'armor') wearArmor(root); else wearThreat(root, kind);
    fixProportions(root);
    var mixer = new THREE.AnimationMixer(root);
    var actions = {};
    rig.animations.forEach(function (clip) {
      var action = mixer.clipAction(clip);
      if (clip.name === 'shoot' || clip.name === 'hit' || clip.name === 'die') {
        action.setLoop(THREE.LoopOnce, 1);
        action.clampWhenFinished = true;
      }
      actions[clip.name] = action;
    });
    return {
      kind: kind, root: root, mixer: mixer, actions: actions,
      // Peluru lahir dari tangan senjata. Versi lama menanam tulang bernama
      // `muzzle` ke dalam GLB hasil build; berkas KayKit asli tidak punya itu
      // dan tidak boleh ditambahi, jadi soket tangan kanan yang dipakai —
      // tulang yang memang disediakan pack untuk memegang senjata.
      muzzle: root.getObjectByName(SOCKET.right) || root.getObjectByName('handr'),
      // Fase acak per aktor. Tanpa ini semua mixer mulai di detik nol dan
      // maju dengan dt yang sama: tiga puluh musuh melangkah seperti satu
      // tubuh, dan pasukan terlihat seperti barisan baris-berbaris. Acak
      // kosmetik ini memakai Math.random, BUKAN RNG simulasi, jadi hasil
      // permainan tetap bisa diulang persis.
      phase: Math.random(),
      // Kecepatan langkah dibedakan tipis supaya barisan tidak pernah
      // mengunci ulang ke fase yang sama setelah beberapa detik.
      rate: 0.92 + Math.random() * 0.16,
      current: '', lock: 0,
    };
  }

  /**
   * Memainkan klip dengan crossfade.
   *
   * `lock` adalah sisa waktu klip sekali-jalan (tembak, kena, mati). Selama
   * masih terkunci, permintaan 'run' atau 'idle' diabaikan — tanpa ini state
   * machine akan memotong recoil di frame berikutnya dan tembakan terlihat
   * seperti tidak pernah terjadi.
   */
  function play(actor, name, fade) {
    if (!actor || !actor.actions[name] || actor.current === name) return;
    var next = actor.actions[name];
    var prev = actor.actions[actor.current];
    next.reset();
    next.setEffectiveWeight(1);
    // Klip berulang masuk di titik acak lintasannya; aksi sesaat (tembak,
    // kena pukul, roboh) harus mulai dari frame nol atau pukulannya meleset
    // dari momen yang memicunya.
    if (next.loop === THREE.LoopRepeat) {
      next.time = actor.phase * (next.getClip().duration || 1);
      next.setEffectiveTimeScale(actor.rate);
    }
    next.play();
    if (prev && prev !== next) prev.crossFadeTo(next, fade === undefined ? 0.12 : fade, false);
    actor.current = name;
  }

  function oneShot(actor, name, seconds) {
    if (!actor || actor.lock > 0) return;
    play(actor, name, 0.05);
    actor.lock = seconds;
  }

  /** Pool aktor per jenis unit. */
  function actorPool(kind) {
    var pool = actorPools[kind];
    if (!pool) {
      pool = actorPools[kind] = { items: [], used: 0 };
      actorPools[kind] = pool;
    }
    return pool;
  }

  function takeActor(kind, parent) {
    if (!rigs[kind]) return null;
    var pool = actorPool(kind);
    var actor = pool.items[pool.used];
    if (!actor) {
      actor = makeActor(kind);
      if (!actor) return null;
      pool.items.push(actor);
      parent.add(actor.root);
    }
    pool.used++;
    actor.root.visible = true;
    return actor;
  }

  /** Salinan model siap pakai, atau null kalau belum/gagal dimuat. */
  function instance(name) {
    var proto = loaded[name];
    if (!proto) return null;
    var obj = proto.clone(true);
    // Material disalin per instance supaya kedip terkena tembak tidak menular.
    obj.traverse(function (c) { if (c.isMesh) c.material = c.material.clone(); });
    return obj;
  }

  /**
   * Memastikan wadah berisi visual yang benar. Mengganti isi hanya saat jenisnya
   * berubah, sehingga pergantian tipe musuh tidak mengalokasi tiap frame.
   */
  function ensureVisual(holder, kind, fallback) {
    // Jenis sama DAN sudah memakai model -> tidak ada yang perlu diganti.
    // Kalau isinya masih primitif sementara modelnya baru selesai dimuat,
    // wadah harus dibangun ulang; tanpa ini primitif awal akan menetap selamanya.
    if (holder.userData.kind === kind &&
        (holder.userData.isModel || !loaded[kind])) return holder.children[0];
    holder.remove.apply(holder, holder.children.slice());
    var vis = instance(kind) || fallback();
    holder.userData.kind = kind;
    holder.userData.isModel = !!loaded[kind];
    holder.add(vis);
    return vis;
  }

  function setEmissive(holder, hex) {
    holder.traverse(function (c) {
      if (c.isMesh && c.material && c.material.emissive) c.material.emissive.setHex(hex);
    });
  }

  /**
   * Peta lingkungan prosedural: satu scene mini berisi gradien lorong, lalu
   * diproses PMREM supaya bisa dipakai sebagai pantulan oleh semua material.
   */
  function makeEnvironment() {
    var probe = document.createElement('canvas').getContext('2d');
    if (!canPaint(probe) || !THREE.PMREMGenerator) return null;
    var env = new THREE.Scene();
    var geo = new THREE.SphereGeometry(10, 12, 8);
    var c = document.createElement('canvas');
    c.width = 16; c.height = 64;
    var g = c.getContext('2d');
    var grad = g.createLinearGradient(0, 0, 0, 64);
    grad.addColorStop(0, '#05070f');     // langit malam
    grad.addColorStop(0.42, '#2a1340');  // kabut ungu
    grad.addColorStop(0.58, '#ff2bd6');  // pita dinding — sumber pantulan utama
    grad.addColorStop(0.72, '#2a1340');
    grad.addColorStop(1, '#0b1a24');     // pantulan kisi di lantai
    g.fillStyle = grad; g.fillRect(0, 0, 16, 64);
    var tex = new THREE.CanvasTexture(c);
    tex.encoding = THREE.sRGBEncoding;
    env.add(new THREE.Mesh(geo, new THREE.MeshBasicMaterial({
      map: tex, side: THREE.BackSide,
    })));
    var pmrem = new THREE.PMREMGenerator(renderer);
    pmrem.compileEquirectangularShader();
    var target = pmrem.fromScene(env, 0.04);
    pmrem.dispose();
    return target.texture;
  }

  /**
   * Latar: kota cyberpunk, kabut ungu, dan vortex — satu quad di ujung lorong.
   *
   * Tanpa ini, 40% layar bagian atas adalah hitam kosong, dan itulah
   * perbedaan paling besar antara tangkapan layar kita dan key art. Gambar
   * itu tidak pernah punya ruang kosong: di atas horizon ada kota yang
   * menyala, kabut tebal, dan pusaran yang menelan langit.
   *
   * Dibuat sebagai tekstur kanvas dan bukan shader karena ia tidak pernah
   * berubah, tidak pernah bergerak, dan tidak pernah diinteraksi — satu
   * gambar statis di kejauhan adalah bentuk paling murah dari kedalaman.
   */
  /**
   * Geometri latar, dihitung dan bukan dikira-kira.
   *
   * Quad berdiri di z=150, sejauh 161 unit dari kamera. Pada framing ini
   * (pitch 22,5°, FOV 60°) tepi atas layar memotong bidang itu di y=37,2 dan
   * horizon ada di y=15,95 — jadi HANYA pita 21 unit itu yang pernah
   * terlihat. Percobaan sebelumnya menaruh kota di tengah tekstur: yang
   * muncul di layar adalah potongan kabutnya saja, lengkap dengan tepi bawah
   * quad sebagai garis lurus melintang.
   *
   * Dengan quad y=-2..40, horizon (y=15,95) jatuh pada 57% dari bawah =
   * baris 146 dari 256. Di situlah kaki kota harus berdiri; di bawahnya hanya
   * kabut setipis mungkin, di atasnya langit dan vortex. Angka-angka ini
   * diverifikasi dengan memproyeksikan titik lewat kamera game — bukan
   * dengan trigonometri di kepala, yang sudah salah dua kali.
   */
  // y0=-2 menaruh tepi bawah quad di 24,5% layar — sedikit DI BAWAH ujung
  // lantai (23,6%), supaya keduanya bertumpang tindih dan tidak pernah ada
  // celah hitam di antaranya. Tepi itu sendiri dihapus dengan gradien alfa,
  // karena tepi lurus melintang layar adalah cacat yang paling cepat
  // terlihat dari semuanya.
  var BACKDROP = { z: 150, y0: -2, y1: 40, width: 320, horizonRow: 146 };

  function makeBackdropTexture() {
    var c = document.createElement('canvas');
    c.width = 512; c.height = 256;
    var g = c.getContext('2d');
    if (!canPaint(g)) return null;
    var HZ = BACKDROP.horizonRow;

    // Langit malam hampir hitam, menghangat jadi ungu hanya tepat di atas
    // horizon. Di key art ungu adalah KABUT, bukan warna langit; langit yang
    // ikut ungu membuat sepertiga layar bersinar lebih terang daripada
    // arena, dan mata berhenti melihat lorong.
    var sky = g.createLinearGradient(0, 0, 0, HZ);
    sky.addColorStop(0, '#04050b');
    sky.addColorStop(0.55, '#0a0718');
    sky.addColorStop(0.85, '#1b0d2e');
    sky.addColorStop(1, '#2a1340');
    g.fillStyle = sky; g.fillRect(0, 0, 512, HZ);
    // Di bawah horizon: warna kabut murni, supaya sambungan dengan lantai
    // berkabut tidak pernah terlihat sebagai garis.
    g.fillStyle = '#2a1340'; g.fillRect(0, HZ, 512, 256 - HZ);

    var seed = 0x5EED11;
    function rnd() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }

    // Vortex: cincin elips berpilin, duduk di langit di atas kota.
    var vx = 384, vy = 54;
    for (var r = 40; r > 3; r -= 2.6) {
      g.strokeStyle = 'rgba(150,72,224,' + (0.1 + (40 - r) / 40 * 0.62).toFixed(3) + ')';
      g.lineWidth = 1 + (40 - r) / 16;
      g.beginPath();
      g.ellipse(vx + (40 - r) * 0.14, vy, r, r * 0.5, (40 - r) * 0.07, 0, 6.28);
      g.stroke();
    }
    // Halo di sekeliling pusaran, lalu lubang gelap di tengahnya: tanpa halo
    // ia hanya terbaca sebagai coretan, dengan halo ia terbaca sebagai benda
    // yang menyedot cahaya.
    var halo = g.createRadialGradient(vx, vy, 4, vx, vy, 46);
    halo.addColorStop(0, 'rgba(167,96,238,0.42)');
    halo.addColorStop(1, 'rgba(107,47,168,0)');
    g.fillStyle = halo;
    g.beginPath(); g.ellipse(vx, vy, 46, 26, 0, 0, 6.28); g.fill();
    g.fillStyle = 'rgba(5,2,10,0.96)';
    g.beginPath(); g.ellipse(vx + 5, vy, 7, 3.4, 0, 0, 6.28); g.fill();

    // Kota: dua lapis siluet berdiri di baris horizon. Lapis belakang lebih
    // pucat dan lebih pendek — kabut di antaranya yang menciptakan jarak.
    [{ pale: true, max: 48, fill: '#130b22' }, { pale: false, max: 84, fill: '#07040d' }]
      .forEach(function (layer) {
        var x = -12;
        while (x < 524) {
          var w = 12 + rnd() * 30;
          var h = layer.max * (0.22 + rnd() * 0.78);
          g.fillStyle = layer.fill;
          g.fillRect(x, HZ - h, w, h + 6);
          if (!layer.pale) {
            // Jendela menyala hanya di menara depan, dan jarang: kota yang
            // seluruh jendelanya hidup terbaca sebagai papan sirkuit.
            for (var wy = HZ - h + 5; wy < HZ - 3; wy += 6) {
              for (var wx = x + 3; wx < x + w - 3; wx += 5) {
                if (rnd() > 0.86) {
                  g.fillStyle = rnd() > 0.45 ? 'rgba(43,232,255,0.8)' : 'rgba(255,43,214,0.65)';
                  g.fillRect(wx, wy, 2, 2);
                }
              }
            }
          }
          x += w + 2 + rnd() * 9;
        }
      });

    // Kabut yang menelan kaki kota.
    var haze = g.createLinearGradient(0, HZ - 46, 0, HZ + 10);
    haze.addColorStop(0, 'rgba(42,19,64,0)');
    haze.addColorStop(0.65, 'rgba(42,19,64,0.68)');
    haze.addColorStop(1, 'rgba(42,19,64,1)');
    g.fillStyle = haze; g.fillRect(0, HZ - 46, 512, 56);

    // Puing melayang. Siluet saja, tidak pernah punya collider.
    for (var d = 0; d < 22; d++) {
      var dx = rnd() * 512, dy = 14 + rnd() * 96, ds = 1 + rnd() * 2.5;
      g.fillStyle = 'rgba(9,5,15,' + (0.35 + rnd() * 0.5).toFixed(2) + ')';
      g.fillRect(dx, dy, ds * (1 + rnd()), ds);
    }

    // Bagian di bawah horizon dihapus perlahan: quad harus LARUT ke dalam
    // lantai berkabut, bukan berakhir pada sebuah garis.
    var fade = g.createLinearGradient(0, HZ + 4, 0, 256);
    fade.addColorStop(0, 'rgba(0,0,0,0)');
    fade.addColorStop(1, 'rgba(0,0,0,1)');
    g.globalCompositeOperation = 'destination-out';
    g.fillStyle = fade; g.fillRect(0, HZ + 4, 512, 256 - HZ - 4);
    g.globalCompositeOperation = 'source-over';

    var tex = new THREE.CanvasTexture(c);
    tex.encoding = THREE.sRGBEncoding;
    return tex;
  }

  function buildBackdrop() {
    var tex = makeBackdropTexture();
    if (!tex) return;
    var h = BACKDROP.y1 - BACKDROP.y0;
    var mesh = new THREE.Mesh(
      new THREE.PlaneGeometry(BACKDROP.width, h),
      // fog: false — latar ADALAH kabutnya. Kalau ia ikut dikaburkan sekali
      // lagi oleh FogExp2, kotanya hilang dan kita kembali ke hitam.
      new THREE.MeshBasicMaterial({
        map: tex, fog: false, depthWrite: false, transparent: true,
      })
    );
    mesh.position.set(0, BACKDROP.y0 + h / 2, -BACKDROP.z);
    mesh.renderOrder = -10;
    scene.add(mesh);
  }

  /**
   * Kerumunan jauh: ratusan siluet di balik gerbang spawn.
   *
   * Key art memperlihatkan pasukan yang tidak ada habisnya sampai ke kabut.
   * Simulasi tidak akan pernah menjalankan 220 unit — dan tidak perlu:
   * mereka di luar lorong yang bisa dimainkan (z 44..96), tidak pernah
   * bergerak, tidak pernah bisa ditembak. Fungsinya satu, yaitu mengatakan
   * "yang kamu lawan hanyalah barisan pertama".
   */
  function buildFarCrowd() {
    if (!THREE.InstancedMesh) return;
    var count = 220;
    // Silinder bersisi enam, bukan kapsul: three.js r128 belum punya
    // CapsuleGeometry, dan pada ukuran dua puluh piksel di balik kabut,
    // perbedaannya tidak pernah sampai ke mata.
    var geo = new THREE.CylinderGeometry(0.55, 0.62, 2.0, 6);
    var mesh = new THREE.InstancedMesh(
      geo, new THREE.MeshLambertMaterial({ color: col(PAL.danger) }), count);
    var m = new THREE.Matrix4();
    var color = new THREE.Color();
    var seed = 0x43524F57;
    function rnd() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }
    for (var i = 0; i < count; i++) {
      var t = i / count;
      var z = 44 + t * 52;
      // Melebar ke belakang: barisan yang melebihi lebar lorong membuat
      // pasukan terbaca sebagai lautan, bukan sebagai antrean.
      var spread = ARENA.halfWidth + 2 + t * 26;
      m.makeTranslation((rnd() * 2 - 1) * spread, 1.1, -(z + rnd() * 3));
      mesh.setMatrixAt(i, m);
      // Makin jauh makin larut ke kabut — persis seperti di gambar.
      color.copy(col(PAL.danger)).lerp(col(PAL.fog), 0.35 + t * 0.6);
      mesh.setColorAt(i, color);
    }
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    scene.add(mesh);
  }

  /**
   * Hujan tracer musuh (docs/00-art-bible.md §4 E3).
   *
   * Inilah yang membuat layar terbaca sebagai bullet hell tanpa satu pun
   * peluru musuh ada di simulasi: musuh di game ini melukai pemain dengan
   * MENEROBOS garis pertahanan, bukan dengan menembak. Tracer adalah bahasa
   * visual yang menjelaskan ancaman itu — dan karena ia tidak pernah
   * menyentuh aturan, kepadatannya bebas disetel demi tampilan.
   *
   * Arahnya menuju SEKITAR pemain, tidak pernah tepat ke badannya: berkas
   * yang bertemu di satu titik terbaca sebagai corong, bukan sebagai hujan.
   */
  var TRACER_POOL = 120, TRACER_LIFE = 0.55;
  var tracers = [], tracerNext = 0, tracerClock = 0;

  function buildTracers() {
    var geo = new THREE.BoxGeometry(0.06, 0.06, 1);
    var mat = new THREE.MeshBasicMaterial({
      color: col(PAL.tracer), transparent: true, opacity: 0.9,
      blending: THREE.AdditiveBlending, depthWrite: false,
    });
    for (var i = 0; i < TRACER_POOL; i++) {
      var m = new THREE.Mesh(geo, mat);
      m.visible = false;
      groups.fx.add(m);
      tracers.push({ mesh: m, life: 0, from: new THREE.Vector3(), to: new THREE.Vector3() });
    }
  }

  function updateTracers(S, dt) {
    if (!tracers.length) return;
    var enemies = S.enemies || [];
    var rate = Math.max(4, Math.min(70, enemies.length * 0.9));
    tracerClock += dt;
    while (tracerClock > 1 / rate && enemies.length) {
      tracerClock -= 1 / rate;
      var e = enemies[(Math.random() * enemies.length) | 0];
      var slot = tracers[tracerNext % tracers.length];
      tracerNext++;
      slot.from.set(e.x, 1.1, -e.z);
      slot.to.set(
        (S.squadX || 0) + (Math.random() * 6 - 3), 0.6,
        -(ARENA.playerZ + (Math.random() * 4 - 2))
      );
      slot.life = TRACER_LIFE;
    }
    for (var i = 0; i < tracers.length; i++) {
      var t = tracers[i];
      if (t.life <= 0) continue;
      t.life -= dt;
      if (t.life <= 0) { t.mesh.visible = false; continue; }
      var k = 1 - t.life / TRACER_LIFE;
      var head = t.from.clone().lerp(t.to, Math.min(1, k * 1.15));
      var tail = t.from.clone().lerp(t.to, Math.max(0, k * 1.15 - 0.16));
      t.mesh.visible = true;
      t.mesh.position.copy(head).add(tail).multiplyScalar(0.5);
      t.mesh.lookAt(head);
      t.mesh.scale.set(1, 1, Math.max(0.4, head.distanceTo(tail)));
    }
  }

  /** Builds the perspective camera. Shared with the test so framing is proven. */
  function makeCamera(aspect) {
    var cam = new THREE.PerspectiveCamera(CAM.fov, aspect, CAM.near, CAM.far);
    cam.position.set(CAM.pos[0], CAM.pos[1], CAM.pos[2]);
    cam.lookAt(CAM.look[0], CAM.look[1], CAM.look[2]);
    cam.updateMatrixWorld(true);
    cam.updateProjectionMatrix();
    return cam;
  }

  /**
   * Lantai: pelat logam yang disikat, dengan sambungan dan kisi cahaya.
   *
   * Versi sebelumnya menebar bercak elips acak sebagai "logam basah". Pada
   * layar itu terbaca sebagai karpet berlumut — permukaan lunak, dan
   * permukaan lunak adalah setengah dari alasan sebuah adegan terlihat
   * seperti mainan. Yang membuat logam terbaca sebagai logam adalah GARIS
   * LURUS: goresan sikat searah, sambungan pelat yang tegas, dan pantulan
   * yang memanjang. Tidak ada satu pun bentuk organik di sini sekarang.
   */
  function makeGridTexture() {
    var c = document.createElement('canvas');
    c.width = c.height = 256;
    var g = c.getContext('2d');
    if (!canPaint(g)) return null;
    g.fillStyle = '#0b0f1b'; g.fillRect(0, 0, 256, 256);

    var seed = 20260929;
    function rnd() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }

    // Goresan sikat: garis tipis searah sumbu lorong, nilai terang-gelap
    // sangat rapat supaya tidak pernah membentuk motif yang terbaca.
    for (var i = 0; i < 220; i++) {
      var x = rnd() * 256;
      g.strokeStyle = rnd() < 0.5 ? 'rgba(26,34,56,0.30)' : 'rgba(5,7,13,0.35)';
      g.lineWidth = 0.6 + rnd() * 1.6;
      g.beginPath(); g.moveTo(x, rnd() * 60); g.lineTo(x + (rnd() - 0.5) * 6, 256); g.stroke();
    }
    // Sambungan pelat: satu salib gelap dengan sisi terang di bawahnya,
    // seperti tepi pelat yang menangkap cahaya ruangan.
    g.strokeStyle = 'rgba(3,4,9,0.9)'; g.lineWidth = 4;
    g.beginPath(); g.moveTo(128, 0); g.lineTo(128, 256); g.moveTo(0, 128); g.lineTo(256, 128); g.stroke();
    g.strokeStyle = 'rgba(70,86,124,0.22)'; g.lineWidth = 1;
    g.beginPath(); g.moveTo(131, 0); g.lineTo(131, 256); g.moveTo(0, 131); g.lineTo(256, 131); g.stroke();
    // Baut di sudut pelat: detail terkecil yang masih terbaca pada jarak ini,
    // dan satu-satunya hal yang memberi skala pada lantai.
    g.fillStyle = 'rgba(96,116,160,0.25)';
    [[16, 16], [240, 16], [16, 240], [240, 240]].forEach(function (b) {
      g.beginPath(); g.arc(b[0], b[1], 2.4, 0, 6.28); g.fill();
    });

    // Kisi cahaya cyan di tepi petak, dengan halo tipis di sisinya.
    g.strokeStyle = 'rgba(43,232,255,0.16)'; g.lineWidth = 7;
    g.beginPath(); g.moveTo(0, 1); g.lineTo(256, 1); g.moveTo(1, 0); g.lineTo(1, 256); g.stroke();
    g.strokeStyle = 'rgba(43,232,255,0.85)'; g.lineWidth = 2;
    g.beginPath(); g.moveTo(0, 1); g.lineTo(256, 1); g.moveTo(1, 0); g.lineTo(1, 256); g.stroke();

    var tex = new THREE.CanvasTexture(c);
    // Kanvas berisi warna sRGB. Tekstur yang lupa ditandai akan dianggap data
    // linear lalu dicerahkan sekali lagi — lantai gelap berubah pucat.
    tex.encoding = THREE.sRGBEncoding;
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(ARENA.halfWidth, ARENA.depth / 2);
    tex.anisotropy = 4;
    return tex;
  }

  /**
   * Dinding pantul: panel data, bukan pita magenta rata.
   *
   * Ini adalah perbedaan terbesar antara "dunia neon" dan "balok plastik
   * berwarna". Warna rata tidak punya permukaan: tidak ada sambungan, tidak
   * ada arah, tidak ada tanda bahwa benda itu dibuat. Tekstur ini menambahkan
   * tiga hal dan hanya tiga: sambungan panel vertikal, garis data horizontal,
   * dan satu pita panas di tepi atas — pita yang sama yang dipakai pemain
   * untuk memperkirakan sudut pantul.
   */
  function makeWallTexture() {
    var c = document.createElement('canvas');
    c.width = 128; c.height = 256;
    var g = c.getContext('2d');
    if (!canPaint(g)) return null;
    g.fillStyle = '#20132f'; g.fillRect(0, 0, 128, 256);

    // Gradien vertikal: pangkal dinding gelap, puncaknya panas.
    var grad = g.createLinearGradient(0, 256, 0, 0);
    grad.addColorStop(0, 'rgba(8,5,14,0.97)');
    grad.addColorStop(0.62, 'rgba(48,14,56,0.80)');
    grad.addColorStop(0.92, 'rgba(150,26,122,0.80)');
    grad.addColorStop(1, 'rgba(255,43,214,0.90)');
    g.fillStyle = grad; g.fillRect(0, 0, 128, 256);

    // Sambungan panel.
    g.strokeStyle = 'rgba(4,2,8,0.85)'; g.lineWidth = 5;
    g.beginPath(); g.moveTo(4, 0); g.lineTo(4, 256); g.moveTo(124, 0); g.lineTo(124, 256); g.stroke();
    g.strokeStyle = 'rgba(255,155,238,0.35)'; g.lineWidth = 1.5;
    g.beginPath(); g.moveTo(9, 0); g.lineTo(9, 256); g.stroke();

    // Garis data horizontal, jaraknya tidak teratur supaya tidak terbaca
    // sebagai tangga.
    [44, 96, 118, 170, 206].forEach(function (y, i) {
      g.strokeStyle = i % 2 ? 'rgba(255,155,238,0.5)' : 'rgba(6,3,12,0.7)';
      g.lineWidth = i % 2 ? 1.5 : 3;
      g.beginPath(); g.moveTo(14, y); g.lineTo(114, y); g.stroke();
    });

    // Pita panas tepi atas — tipis. Inilah garis yang dibaca pemain untuk
    // memperkirakan sudut pantul, jadi ia harus tajam, bukan lebar.
    g.fillStyle = '#ff9bee'; g.fillRect(0, 0, 128, 4);

    var tex = new THREE.CanvasTexture(c);
    tex.encoding = THREE.sRGBEncoding;
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(1, 1);
    return tex;
  }

  /**
   * Bumper sebagai pylon teknis: silinder logam gelap dengan dua cincin yang
   * menyala dan tutup panas di atasnya.
   *
   * Yang diganti adalah kubah abu-abu bertudung ungu — bentuk jamur matte
   * yang, lebih dari apa pun di layar, membuat arena terbaca sebagai mainan.
   * Siluetnya sekarang tegak dan bersudut, dan ia MEMANCARKAN cahaya, jadi
   * ia menjadi bagian dari dunia neon alih-alih benda yang ditaruh di
   * atasnya.
   */
  function makePylon() {
    var grp = new THREE.Group();
    var shell = new THREE.MeshStandardMaterial({
      color: col(0x241536), metalness: 0.9, roughness: 0.3,
    });
    var hot = new THREE.MeshBasicMaterial({ color: col(PAL.wallGlow) });
    // Proporsi menentukan segalanya di sini: pendek-dan-gemuk terbaca sebagai
    // mainan apa pun materialnya, tinggi-dan-ramping terbaca sebagai alat.
    // Tingginya 2,1 dengan jari-jari 0,42 — rasio 5:1, mendekati tiang
    // sungguhan, bukan kubah.
    var base = new THREE.Mesh(new THREE.CylinderGeometry(0.58, 0.72, 0.16, 8), shell);
    base.position.y = 0.08; grp.add(base);
    var body = new THREE.Mesh(new THREE.CylinderGeometry(0.38, 0.44, 1.74, 8), shell);
    body.position.y = 1.03; grp.add(body);
    // Garis nyala tipis, bukan pita tebal: cahaya harus terbaca sebagai celah
    // di antara pelat, bukan sebagai cat berwarna.
    [0.34, 0.86, 1.38].forEach(function (y, i) {
      var r = 0.47 - i * 0.04;
      var ring = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.045, 8), hot);
      ring.position.y = y; grp.add(ring);
    });
    var head = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.36, 0.26, 8), shell);
    head.position.y = 2.03; grp.add(head);
    var tip = new THREE.Mesh(new THREE.CylinderGeometry(0.17, 0.17, 0.08, 8), hot);
    tip.position.y = 2.2; grp.add(tip);
    return grp;
  }

  /**
   * Drum peledak: badan logam merah gelap, hanya pita atasnya yang panas.
   *
   * Emissive penuh akan membuatnya terbaca sebagai lampu, dan pemain berhenti
   * takut pada benda yang menyala ramah (docs/00-art-bible.md §3).
   */
  function makeDrum() {
    var grp = new THREE.Group();
    var steel = new THREE.MeshStandardMaterial({
      color: col(0x4a1410), metalness: 0.8, roughness: 0.45,
    });
    var body = new THREE.Mesh(new THREE.CylinderGeometry(0.62, 0.62, 1.5, 14), steel);
    body.position.y = 0.75; grp.add(body);
    [0.42, 1.08].forEach(function (y) {
      var rib = new THREE.Mesh(new THREE.CylinderGeometry(0.66, 0.66, 0.1, 14), steel);
      rib.position.y = y; grp.add(rib);
    });
    var band = new THREE.Mesh(
      new THREE.CylinderGeometry(0.64, 0.64, 0.22, 14),
      new THREE.MeshBasicMaterial({ color: col(PAL.blast) })
    );
    band.position.y = 1.42; grp.add(band);
    return grp;
  }

  /**
   * Warna hex dunia ini ditulis sebagai warna sRGB (sama seperti di CSS dan
   * di config). Dengan keluaran renderer sRGB, three.js r128 menganggap
   * `material.color` sudah linear, jadi tiap warna harus dikonversi sekali —
   * kalau tidak, seluruh arena tampak satu tingkat terlalu terang dan pucat.
   */
  /**
   * Apakah context kanvas ini benar-benar bisa menggambar?
   *
   * Uji geometri (tools/render3d_test.js) menjalankan berkas ini di Node
   * dengan kanvas tiruan yang setiap metodenya no-op. Tekstur prosedural
   * harus menyerah dengan rapi di sana, bukan melempar — kalau tidak, satu
   * gradien menjatuhkan seluruh suite yang sebenarnya menguji matematika
   * kamera dan tidak peduli pada piksel.
   */
  function canPaint(g) {
    if (!g || typeof g.createLinearGradient !== 'function') return false;
    var probe = g.createLinearGradient(0, 0, 0, 1);
    return !!(probe && typeof probe.addColorStop === 'function');
  }

  function col(hex) {
    return new THREE.Color(hex).convertSRGBToLinear();
  }

  /**
   * Label gerbang sebagai HOLOGRAM, bukan papan nama.
   *
   * Versi sebelumnya adalah persegi hijau/merah pekat dengan teks sistem —
   * bahasa visual aplikasi anak-anak, dan satu-satunya benda di layar yang
   * tidak mungkin ada di dunia key art. Yang menggantikannya: kaca gelap
   * tipis, bingkai neon, sudut penanda, dan angka bercahaya. Hijau dibuang
   * sama sekali; gerbang baik memakai cyan pemain, gerbang buruk memakai
   * merah ancaman, persis seperti arti warna di art bible.
   */
  function labelTexture(text, positive) {
    var key = text + (positive ? '+' : '-');
    if (labelCache[key]) return labelCache[key];
    var c = document.createElement('canvas');
    c.width = 256; c.height = 128;
    var g = c.getContext('2d');
    if (!canPaint(g)) return null;
    var neon = positive ? '#2be8ff' : '#ff2a2a';

    // Kaca: gelap di tengah, sedikit lebih terang ke tepi atas.
    var glass = g.createLinearGradient(0, 128, 0, 0);
    glass.addColorStop(0, positive ? 'rgba(6,24,34,0.55)' : 'rgba(34,6,8,0.55)');
    glass.addColorStop(1, positive ? 'rgba(14,52,70,0.30)' : 'rgba(70,12,14,0.30)');
    g.fillStyle = glass; g.fillRect(0, 0, 256, 128);

    // Garis pindai horizontal: tanda paling murah bahwa ini proyeksi.
    g.strokeStyle = positive ? 'rgba(43,232,255,0.10)' : 'rgba(255,42,42,0.10)';
    g.lineWidth = 2;
    for (var y = 6; y < 128; y += 9) {
      g.beginPath(); g.moveTo(0, y); g.lineTo(256, y); g.stroke();
    }

    // Bingkai: hanya sudut, tidak tertutup penuh. Bingkai penuh terbaca
    // sebagai papan; sudut terbaca sebagai antarmuka.
    g.strokeStyle = neon; g.lineWidth = 5;
    [[8, 8, 1, 1], [248, 8, -1, 1], [8, 120, 1, -1], [248, 120, -1, -1]].forEach(function (k) {
      g.beginPath();
      g.moveTo(k[0] + k[2] * 34, k[1]);
      g.lineTo(k[0], k[1]);
      g.lineTo(k[0], k[1] + k[3] * 26);
      g.stroke();
    });
    // Pita tipis atas-bawah menyatukan keempat sudut tanpa mengurungnya.
    g.globalAlpha = 0.45;
    g.lineWidth = 2;
    g.beginPath(); g.moveTo(8, 8); g.lineTo(248, 8); g.moveTo(8, 120); g.lineTo(248, 120); g.stroke();
    g.globalAlpha = 1;

    // Angka: bercahaya, bukan sekadar berwarna.
    g.font = 'bold 72px ui-monospace, "SF Mono", Menlo, monospace';
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.shadowColor = neon; g.shadowBlur = 26;
    g.fillStyle = neon; g.fillText(text, 128, 66);
    g.shadowBlur = 12;
    g.fillStyle = '#ffffff'; g.fillText(text, 128, 66);

    var tex = new THREE.CanvasTexture(c);
    tex.encoding = THREE.sRGBEncoding;
    labelCache[key] = tex;
    return tex;
  }

  function gateText(op) {
    if (!op) return '?';
    if (op.op === 'mul') return 'x' + op.value;
    if (op.op === 'add') return (op.value >= 0 ? '+' : '') + op.value;
    if (op.op === 'sub') return '-' + Math.abs(op.value);
    if (op.op === 'div') return '/' + op.value;
    return String(op.value);
  }

  /** One soldier: cylinder body + sphere head. Cheap, readable at this scale. */
  function makeTroop(color) {
    var grp = new THREE.Group();
    var mat = new THREE.MeshLambertMaterial({ color: color, emissive: color, emissiveIntensity: 0.22 });
    var body = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.32, 0.85, 8), mat);
    body.position.y = 0.42;
    var head = new THREE.Mesh(new THREE.SphereGeometry(0.24, 10, 8), mat);
    head.position.y = 1.02;
    grp.add(body); grp.add(head);
    return grp;
  }

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------
  function init(cv) {
    if (!global.THREE) return false;
    THREE = global.THREE;
    canvas = cv;

    renderer = new THREE.WebGLRenderer({
      canvas: canvas, antialias: false,
      powerPreference: 'high-performance', precision: 'mediump',
    });
    renderer.setPixelRatio(Math.min(global.devicePixelRatio || 1, 1.25));
    // Pipeline warna yang benar, dan ini syarat mutlak agar karakter KayKit
    // tampil seperti di render resminya. GLTFLoader menandai tekstur
    // baseColor sebagai sRGB; kalau keluaran renderer dibiarkan Linear
    // (bawaan r128), shader mengubah sRGB->linear lalu menampilkannya mentah,
    // dan zirah peraknya jadi abu lumpur. Dulu ini "diperbaiki" dengan
    // memalsukan encoding tekstur — cara yang salah, karena ia juga membuat
    // warna lain di scene meleset. Sekarang keluarannya yang diperbaiki.
    renderer.outputEncoding = THREE.sRGBEncoding;

    scene = new THREE.Scene();
    // Langit GELAP, kabut ungu. Dulu keduanya memakai warna kabut supaya
    // ujung lantai melebur ke langit — dan itu berhasil, tapi akibatnya
    // seluruh sepertiga atas layar menjadi bidang ungu rata seterang
    // #2A1340, lebih terang daripada arena itu sendiri. Di key art langit
    // nyaris hitam; ungu hanya muncul sebagai kabut di sekitar horizon dan
    // sebagai pusaran. Peleburan ujung lantai sekarang diurus oleh quad
    // latar, yang memang menggambar kabut itu di tempat yang tepat.
    scene.background = col(0x080610);
    scene.fog = new THREE.FogExp2(col(PAL.fog).getHex(), 0.022);

    camera = makeCamera(9 / 16);

    // Cahaya: langit malam dingin dari atas, matahari-obor hangat dari depan
    // kanan, dan pantulan api lemah dari belakang. Karakter KayKit memakai
    // MeshStandardMaterial bawaan berkasnya, jadi lampu di sini benar-benar
    // menentukan terang-gelapnya — bukan sekadar memberi arah.
    // Intensitas diturunkan sejak keluaran renderer pindah ke sRGB: dengan
    // pipeline warna yang benar, total 3,8 yang dulu terasa pas langsung
    // membakar lantai jadi hijau pucat dan menghapus bayangan di zirah.
    // Cahaya NEON: langit ungu dingin dari atas, kunci putih-biru dari depan
    // kanan (ini yang memahat zirah pemain), dan isian magenta lemah dari
    // sisi dinding supaya karakter ikut memungut warna lorong.
    // Environment map: lorong itu sendiri, disederhanakan jadi enam sisi.
    //
    // Tanpa ini, setiap material metalness tinggi menjadi hitam pekat —
    // logam hanyalah permukaan yang memantulkan sekitarnya, dan kalau tidak
    // ada sekitar untuk dipantulkan, ia tidak punya apa-apa untuk
    // ditampilkan. Inilah satu perbedaan teknis terbesar antara render yang
    // terbaca "plastik" dan yang terbaca "logam": bukan warna, bukan
    // poligon, melainkan ada-tidaknya pantulan.
    //
    // Isinya sengaja kasar: gelap di atas, magenta dari kedua sisi (dinding),
    // cyan lemah dari bawah (kisi lantai). Delapan piksel pun sudah cukup,
    // karena yang dibaca mata hanyalah ARAH datangnya cahaya.
    var envMap = makeEnvironment();
    if (envMap) scene.environment = envMap;

    scene.add(new THREE.HemisphereLight(0x6b7fd4, 0x14091f, 0.55));
    var sun = new THREE.DirectionalLight(0xdce6f2, 1.25);
    sun.position.set(10, 26, 16); scene.add(sun);
    var fill = new THREE.DirectionalLight(0xff2bd6, 0.35);
    fill.position.set(-18, 8, -12); scene.add(fill);

    // --- static world ---
    var floorMat = new THREE.MeshLambertMaterial({ map: makeGridTexture() });
    var floorLen = ARENA.depth + APRON + APRON_FAR;
    var floor = new THREE.Mesh(
      new THREE.PlaneGeometry(ARENA.halfWidth * 2, floorLen), floorMat);
    floor.rotation.x = -Math.PI / 2;
    floor.position.set(0, 0, -ARENA.depth / 2 + (APRON - APRON_FAR) / 2);
    scene.add(floor);

    var wallLen = ARENA.depth + APRON;
    var wallTex = makeWallTexture();
    // Satu panel tiap 7 unit. Percobaan pertama memakai 2,5 dan hasilnya
    // deretan balok terang yang terbaca sebagai gigi — pengulangan yang
    // terlalu rapat selalu berubah jadi motif, dan motif terbaca sebagai
    // mainan. Panel lebar memberi skala tanpa menjadi pola.
    // Sumbu u tekstur berjalan di sepanjang lorong pada sisi panjang kotak,
    // jadi pengulangan dipasang di u — bukan di v. Versi pertama memasangnya
    // di v: gradien gelap-ke-magenta berulang sepuluh kali ke ARAH TINGGI
    // dinding, yang di layar terbaca sebagai tumpukan batu bata terang.
    if (wallTex) wallTex.repeat.set(wallLen / 7, 1);
    var panelMat = new THREE.MeshStandardMaterial({
      map: wallTex, emissiveMap: wallTex,
      color: wallTex ? new THREE.Color(0xffffff) : col(PAL.wall),
      emissive: wallTex ? new THREE.Color(0xffffff) : col(PAL.wallGlow),
      emissiveIntensity: 0.55, metalness: 0.45, roughness: 0.42,
    });
    var darkMat = new THREE.MeshStandardMaterial({
      color: col(0x120a1c), metalness: 0.6, roughness: 0.5,
    });
    // Tepi atas dibuat sebagai material tersendiri dan bukan bagian dari
    // tekstur: permukaan atas kotak memakai pemetaan UV yang sama sekali
    // berbeda dari sisinya, dan memaksakan satu tekstur ke keduanya adalah
    // persis yang membuat dinding tadi belang.
    var crestMat = new THREE.MeshBasicMaterial({ color: col(PAL.wallGlow) });
    // Urutan material BoxGeometry: +x, -x, +y, -y, +z, -z.
    var wallMats = [panelMat, panelMat, crestMat, darkMat, darkMat, darkMat];
    [-1, 1].forEach(function (s) {
      var w = new THREE.Mesh(new THREE.BoxGeometry(0.45, 1.8, wallLen), wallMats);
      w.position.set(s * (ARENA.halfWidth + 0.22), 0.9, -ARENA.depth / 2 + APRON / 2);
      scene.add(w);

      // Tumpahan cahaya dinding ke lantai. Tanpa bloom sungguhan (tiga.js di
      // sini tidak membawa EffectComposer), inilah yang membuat neon terbaca
      // sebagai CAHAYA dan bukan sebagai cat: satu pita aditif yang
      // melebar di lantai persis di kaki dinding.
      var spill = new THREE.Mesh(
        new THREE.PlaneGeometry(2.2, wallLen),
        new THREE.MeshBasicMaterial({
          color: col(PAL.wallGlow), transparent: true, opacity: 0.16,
          blending: THREE.AdditiveBlending, depthWrite: false,
        })
      );
      spill.rotation.x = -Math.PI / 2;
      spill.position.set(s * (ARENA.halfWidth - 0.7), 0.02, -ARENA.depth / 2 + APRON / 2);
      scene.add(spill);

      // Halo tegak di sisi dalam dinding: tepi yang mekar, bukan tepi yang
      // dipotong pisau.
      var halo = new THREE.Mesh(
        new THREE.PlaneGeometry(1.1, wallLen),
        new THREE.MeshBasicMaterial({
          color: col(PAL.wallGlow), transparent: true, opacity: 0.22,
          blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
        })
      );
      halo.rotation.y = Math.PI / 2;
      halo.position.set(s * (ARENA.halfWidth - 0.04), 1.5, -ARENA.depth / 2 + APRON / 2);
      scene.add(halo);
    });

    var line = new THREE.Mesh(
      new THREE.BoxGeometry(ARENA.halfWidth * 2, 0.07, 0.3),
      new THREE.MeshBasicMaterial({ color: col(PAL.danger), transparent: true, opacity: 0.85 })
    );
    line.position.set(0, 0.04, -ARENA.defenseLineZ);
    scene.add(line);
    groups.defenseLine = line;

    // --- dynamic groups ---
    ['troops', 'enemies', 'bullets', 'gates', 'obstacles', 'boss', 'fx'].forEach(function (k) {
      groups[k] = new THREE.Group();
      groups[k].name = k;           // named so tests can walk the real scene graph
      scene.add(groups[k]);
    });

    // Lapisan NEON: latar, kerumunan jauh, hujan tracer. Ketiganya dibangun
    // setelah grup ada karena tracer hidup di dalam groups.fx.
    buildBackdrop();
    buildFarCrowd();
    buildTracers();

    pools.troops = makePool(groups.troops, function () { return new THREE.Group(); });
    pools.enemies = makePool(groups.enemies, function () { return new THREE.Group(); });
    pools.bullets = makePool(groups.bullets, function () {
      return new THREE.Mesh(new THREE.SphereGeometry(1, 8, 6),
        new THREE.MeshBasicMaterial({ color: PAL.bullet }));
    });
    pools.gatePanels = makePool(groups.gates, function () {
      return new THREE.Mesh(new THREE.PlaneGeometry(1, 1),
        new THREE.MeshBasicMaterial({
          transparent: true, opacity: 0.95, side: THREE.DoubleSide,
          // Aditif: hologram menambah cahaya ke lorong, tidak menutupinya.
          blending: THREE.AdditiveBlending, depthWrite: false,
        }));
    });
    pools.obstacles = makePool(groups.obstacles, function () { return new THREE.Group(); });
    pools.bossParts = makePool(groups.boss, function () { return new THREE.Group(); });

    // --- efek: tiga bentuk dasar, semuanya additive dan tanpa depth-write ---
    // Cincin untuk gelombang kejut di lantai, bilah untuk kilatan moncong dan
    // percikan, bola untuk ledakan. Tiga geometri yang dipakai ulang jauh
    // lebih murah daripada sistem partikel, dan pada kecepatan permainan ini
    // mata tidak bisa membedakannya.
    pools.rings = makePool(groups.fx, function () {
      return new THREE.Mesh(
        new THREE.RingGeometry(0.72, 1, 24),
        new THREE.MeshBasicMaterial({
          color: 0xffffff, transparent: true, depthWrite: false,
          blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
        })
      );
    });
    pools.flashes = makePool(groups.fx, function () {
      return new THREE.Mesh(
        new THREE.PlaneGeometry(1, 1),
        new THREE.MeshBasicMaterial({
          color: 0xffffff, transparent: true, depthWrite: false,
          blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
        })
      );
    });
    pools.blobs = makePool(groups.fx, function () {
      return new THREE.Mesh(
        new THREE.SphereGeometry(1, 10, 8),
        new THREE.MeshBasicMaterial({
          color: 0xffffff, transparent: true, depthWrite: false,
          blending: THREE.AdditiveBlending,
        })
      );
    });

    loadModels(function (n) { api.modelsLoaded = n; });
    loadRigs(function (n) { api.rigsLoaded = n; });

    api.ready = true;
    return true;
  }

  /**
   * Mewarnai prajurit sesuai tema arena.
   *
   * Hanya berlaku untuk prajurit primitif. Model GLB sudah punya vertex color
   * yang dipanggang, dan menimpanya dengan satu warna solid akan menghapus
   * detailnya. Wadah pool juga berisi Group, bukan Mesh, jadi penelusuran harus
   * lewat traverse dan memeriksa material sebelum menyentuhnya.
   */
  function setAccent(hex) {
    accentColor = hex;
    if (!pools.troops) return;
    pools.troops.items.forEach(function (holder) {
      if (holder.userData && holder.userData.isModel) return;
      holder.traverse(function (c) {
        if (!c.isMesh || !c.material || !c.material.color) return;
        c.material.color.setHex(hex);
        if (c.material.emissive) c.material.emissive.setHex(hex);
      });
    });
  }

  /**
   * Resizes the drawing buffer. `w`/`h` are DEVICE pixels, not CSS pixels: the
   * page owns the 1080x1920 reference frame and already knows the scale factor
   * it is displayed at, so letting three.js apply a second device-pixel-ratio
   * on top would either waste a quarter of the fill rate on desktop or render
   * below panel resolution on a 3x phone.
   */
  function resize(w, h) {
    if (!renderer) return;
    renderer.setPixelRatio(1);
    renderer.setSize(Math.max(1, Math.round(w)), Math.max(1, Math.round(h)), false);
    camera.aspect = w / h;
    // Lebar yang dipertahankan, bukan tinggi. Arena itu lorong selebar 20 unit:
    // kalau layar lebih jangkung dari 9:16 dan FOV vertikal dibiarkan tetap,
    // dinding samping terpotong. Dengan mengunci FOV horizontal, layar yang
    // lebih jangkung memperlihatkan lorong LEBIH PANJANG — persis perilaku
    // "keep_width" di project Godot, jadi dua build membingkai dunia yang sama.
    baseFov = widthMatchedFov(camera.aspect);
    camera.fov = baseFov;
    camera.updateProjectionMatrix();
  }

  /** FOV vertikal yang menjaga bukaan horizontal tetap sama seperti pada 9:16. */
  function widthMatchedFov(aspect) {
    var rad = Math.PI / 180;
    var tanH = Math.tan(CAM.fov * 0.5 * rad) * (9 / 16);   // setengah lebar pada 9:16
    var fov = 2 * Math.atan(tanH / Math.max(0.0001, aspect)) / rad;
    // Batas atas: pada layar sangat jangkung, lorong yang terlalu panjang
    // membuat musuh jauh jadi beberapa piksel saja.
    return Math.min(58, Math.max(CAM.fov * 0.85, fov));
  }

  // ---------------------------------------------------------------------------
  // MAYAT
  // ---------------------------------------------------------------------------
  // Musuh yang mati tidak boleh sekadar lenyap: klip 'die' adalah satu-satunya
  // umpan balik yang membuktikan tembakan mengenai sasaran. Mayat hidup di
  // luar pool per-frame karena ia harus bertahan setelah entitasnya tidak ada
  // lagi di simulasi — jumlahnya dibatasi keras supaya gelombang besar tidak
  // menumpuk skeleton tanpa batas.
  var corpseStore = {};

  function countCorpses() {
    var n = 0;
    for (var kind in corpseStore) {
      for (var i = 0; i < corpseStore[kind].length; i++) {
        if (corpseStore[kind][i].life > 0) n++;
      }
    }
    return n;
  }

  function spawnCorpse(kind, x, z) {
    if (!rigs[kind] || countCorpses() >= SKIN.corpses) return;
    var list = corpseStore[kind] || (corpseStore[kind] = []);
    var slot = null;
    for (var i = 0; i < list.length; i++) if (list[i].life <= 0) { slot = list[i]; break; }
    if (!slot) {
      if (list.length >= 3) return;
      var actor = makeActor(kind);
      if (!actor) return;
      groups.enemies.add(actor.root);
      slot = { actor: actor, life: 0 };
      list.push(slot);
    }
    slot.life = 1.5;
    var root = slot.actor.root;
    root.visible = true;
    root.position.set(x, 0, -z);
    root.rotation.y = Math.PI;
    slot.actor.current = '';
    slot.actor.lock = 0;
    for (var name in slot.actor.actions) slot.actor.actions[name].stop();
    slot.actor.actions.die.reset().play();
    slot.actor.current = 'die';
  }

  function updateCorpses(dt) {
    for (var kind in corpseStore) {
      var list = corpseStore[kind];
      for (var i = 0; i < list.length; i++) {
        var slot = list[i];
        if (slot.life <= 0) continue;
        slot.life -= dt;
        slot.actor.mixer.update(dt);
        // Memudar di setengah detik terakhir, bukan hilang mendadak.
        var alpha = Math.min(1, Math.max(0, slot.life / 0.5));
        slot.actor.root.traverse(function (node) {
          if (!node.isSkinnedMesh) return;
          node.material.transparent = alpha < 1;
          node.material.opacity = alpha;
        });
        if (slot.life <= 0) slot.actor.root.visible = false;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // EFEK
  // ---------------------------------------------------------------------------
  /** Cincin gelombang kejut, rebah di lantai. */
  function ring(x, z, radius, color, alpha, y) {
    var m = pools.rings.take();
    m.rotation.set(-Math.PI / 2, 0, 0);
    m.position.set(x, y === undefined ? 0.06 : y, -z);
    m.scale.setScalar(Math.max(0.01, radius));
    m.material.color.setHex(color);
    m.material.opacity = Math.max(0, alpha);
  }

  /** Bilah menghadap kamera — kilatan, percikan, kilau moncong. */
  function flash(x, y, z, size, color, alpha, spin) {
    var m = pools.flashes.take();
    m.position.set(x, y, -z);
    m.quaternion.copy(camera.quaternion);
    if (spin) m.rotateZ(spin);
    m.scale.setScalar(Math.max(0.01, size));
    m.material.color.setHex(color);
    m.material.opacity = Math.max(0, alpha);
  }

  function blob(x, y, z, radius, color, alpha) {
    var m = pools.blobs.take();
    m.position.set(x, y, -z);
    m.scale.setScalar(Math.max(0.01, radius));
    m.material.color.setHex(color);
    m.material.opacity = Math.max(0, alpha);
  }

  function hexOf(value, fallback) {
    if (typeof value === 'string' && value.charAt(0) === '#') {
      return parseInt(value.slice(1), 16);
    }
    return fallback;
  }

  /**
   * Menggambar seluruh `S.fx`.
   *
   * Daftar efek itu sudah ada sejak build 2D dan selama ini diabaikan renderer
   * 3D — ledakan barrel, percikan pantulan, dan kematian musuh terjadi tanpa
   * satu piksel pun yang menandainya. Simulasi tetap pemilik waktunya; di sini
   * hanya dibaca `t/max` sebagai progres 1 → 0.
   */
  function drawEffects(S) {
    var fx = S.fx || [];
    for (var i = 0; i < fx.length; i++) {
      var f = fx[i];
      var life = f.max > 0 ? Math.max(0, f.t / f.max) : 0;   // 1 = baru
      var age = 1 - life;
      var tint = hexOf(f.color, 0xffd54f);
      if (f.kind === 'boom') {
        ring(f.x, f.z, 0.8 + age * 3.4, 0xff8a2b, life * 0.9);
        blob(f.x, 0.6 + age * 0.5, f.z, 0.5 + age * 1.6, 0xffc93c, life * life * 0.8);
        flash(f.x, 0.9, f.z, 2.2 + age * 2.0, 0xfff3c4, life * life);
      } else if (f.kind === 'kill') {
        // Pecahan: empat bilah yang terlempar keluar. Kematian harus punya
        // bentuk, bukan sekadar unit yang hilang.
        ring(f.x, f.z, 0.3 + age * 1.3, tint, life * 0.75);
        for (var k = 0; k < 4; k++) {
          var ang = k * 1.5708 + f.x;
          flash(
            f.x + Math.cos(ang) * age * 0.9, 0.5 + age * 0.7,
            f.z + Math.sin(ang) * age * 0.9,
            0.42 * life, tint, life, ang
          );
        }
      } else if (f.kind === 'bounce') {
        ring(f.x, f.z, 0.25 + age * 1.1, PAL.chain, life * 0.9, 0.5);
        flash(f.x, 0.5, f.z, 1.1 * life, 0x9bf6ff, life);
      } else {
        ring(f.x, f.z, 0.4 + age * 1.0, PAL.grid, life * 0.5);
      }
    }
  }

  /**
   * Jejak peluru chain.
   *
   * Peluru itu satu bola kecil yang bergerak 25 unit/detik: pada 60 fps ia
   * melompat hampir setengah meter per frame, dan mata kehilangan jejaknya
   * tepat saat pemain harus memutuskan belokan. Jejak sepuluh titik membuat
   * arahnya terbaca tanpa menambah satu pun objek dinamis ke simulasi.
   */
  var trailMesh = null, lastDir = 0;

  function buildTrailMesh() {
    var geo = new THREE.BufferGeometry();
    var max = 18 * 2;
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(max * 3), 3));
    geo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(max * 3), 3));
    geo.setIndex(new THREE.BufferAttribute(new Uint16Array((18 - 1) * 6), 1));
    trailMesh = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({
      vertexColors: true, transparent: true, opacity: 0.95,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    }));
    trailMesh.frustumCulled = false;
    groups.fx.add(trailMesh);
  }

  /**
   * Jejak chain shot: pita api yang menyempit ke ekor.
   *
   * Versi sebelumnya adalah dua belas bola ungu — rangkaian manik yang
   * terbaca sebagai kalung, bukan sebagai lintasan. Key art menunjukkan satu
   * pita menyala yang LEBAR di kepala dan menipis ke belakang; lebar itulah
   * yang memberi tahu mata ke mana peluru bergerak, dan penyempitannya yang
   * memberi tahu dari mana ia datang.
   *
   * Warnanya inti putih di kepala menuju oranye di ekor; pada combo >= 20
   * ekornya bergeser ke ungu rantai (E1 di art bible).
   */
  function drawTrail(S) {
    if (!trailMesh) buildTrailMesh();
    var live = null;
    var cb = S.bullets || [];
    for (var i = 0; i < cb.length; i++) if (cb[i].alive) { live = cb[i]; break; }
    if (!live) { trail.length = 0; trailMesh.visible = false; return; }

    trail.push({ x: live.x, z: live.z });
    if (trail.length > 18) trail.shift();
    if (trail.length < 3) { trailMesh.visible = false; return; }
    trailMesh.visible = true;

    // Pantulan terdeteksi dari pembalikan arah mendatar, bukan dari event:
    // renderer tidak pernah bertanya apa pun pada simulasi.
    var dir = Math.sign(trail[trail.length - 1].x - trail[trail.length - 2].x);
    if (dir && lastDir && dir !== lastDir) {
      spawnArc(trail[trail.length - 1].x, trail[trail.length - 1].z);
    }
    if (dir) lastDir = dir;

    var pos = trailMesh.geometry.attributes.position.array;
    var colr = trailMesh.geometry.attributes.color.array;
    var idx = trailMesh.geometry.index.array;
    var hot = col(0xffe3a0), mid = col(PAL.blast);
    var tail = (S.combo || 0) >= 20 ? col(PAL.chain) : col(PAL.blast);
    var c = new THREE.Color();
    for (var t = 0; t < trail.length; t++) {
      var k = t / (trail.length - 1);          // 0 = ekor, 1 = kepala
      var p = trail[t];
      var nx = 0, nz = 0;
      var a = trail[Math.max(0, t - 1)], b = trail[Math.min(trail.length - 1, t + 1)];
      var dx = b.x - a.x, dz = b.z - a.z;
      var len = Math.hypot(dx, dz) || 1;
      nx = -dz / len; nz = dx / len;           // normal mendatar lintasan
      var w = 0.08 + k * k * 0.42;             // menyempit ke ekor
      pos[t * 6 + 0] = p.x + nx * w; pos[t * 6 + 1] = 0.5; pos[t * 6 + 2] = -(p.z + nz * w);
      pos[t * 6 + 3] = p.x - nx * w; pos[t * 6 + 4] = 0.5; pos[t * 6 + 5] = -(p.z - nz * w);
      c.copy(tail).lerp(mid, Math.min(1, k * 1.4)).lerp(hot, Math.max(0, k * 2 - 1));
      c.multiplyScalar(0.25 + k * 0.75);       // ekor meredup, bukan terpotong
      colr[t * 6 + 0] = colr[t * 6 + 3] = c.r;
      colr[t * 6 + 1] = colr[t * 6 + 4] = c.g;
      colr[t * 6 + 2] = colr[t * 6 + 5] = c.b;
      if (t < trail.length - 1) {
        var v = t * 2, o = t * 6;
        idx[o] = v; idx[o + 1] = v + 1; idx[o + 2] = v + 2;
        idx[o + 3] = v + 1; idx[o + 4] = v + 3; idx[o + 5] = v + 2;
      }
    }
    trailMesh.geometry.setDrawRange(0, (trail.length - 1) * 6);
    trailMesh.geometry.attributes.position.needsUpdate = true;
    trailMesh.geometry.attributes.color.needsUpdate = true;
    trailMesh.geometry.index.needsUpdate = true;
  }

  /**
   * Busur petir di titik pantul (E5).
   *
   * Berkedip, tidak memudar: petir yang memudar terbaca sebagai asap.
   */
  var ARC_POOL = 6, arcs = [], arcNext = 0;

  function spawnArc(x, z) {
    if (!arcs.length) {
      for (var i = 0; i < ARC_POOL; i++) {
        var geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(8 * 3), 3));
        var line = new THREE.Line(geo, new THREE.LineBasicMaterial({
          color: col(PAL.chain), transparent: true, opacity: 0.9,
          blending: THREE.AdditiveBlending, depthWrite: false,
        }));
        line.frustumCulled = false;
        line.visible = false;
        groups.fx.add(line);
        arcs.push({ line: line, life: 0 });
      }
    }
    var slot = arcs[arcNext % arcs.length];
    arcNext++;
    var p = slot.line.geometry.attributes.position.array;
    for (var k = 0; k < 8; k++) {
      var t = k / 7;
      p[k * 3 + 0] = x * (1 - t) + (Math.random() * 2 - 1) * 1.6 * (1 - t) * t * 6;
      p[k * 3 + 1] = 0.7 + Math.sin(t * 3.14) * 1.1;
      p[k * 3 + 2] = -(z + (Math.random() * 2 - 1) * 1.2);
    }
    slot.line.geometry.attributes.position.needsUpdate = true;
    slot.line.visible = true;
    slot.life = 0.2;
  }

  function updateArcs(dt) {
    for (var i = 0; i < arcs.length; i++) {
      if (arcs[i].life <= 0) continue;
      arcs[i].life -= dt;
      // Kedip, bukan pudar.
      arcs[i].line.visible = arcs[i].life > 0 && Math.random() > 0.25;
      if (arcs[i].life <= 0) arcs[i].line.visible = false;
    }
  }

  // ---------------------------------------------------------------------------
  // SYNC — read simulation state, move meshes. Read-only on S.
  // ---------------------------------------------------------------------------
  /**
   * Membaurkan pose tick sebelumnya ke pose sekarang. Entitas yang baru lahir
   * di tengah tick belum punya nilai sebelumnya, jadi dipakai nilai sekarang
   * supaya tidak melesat dari titik nol.
   */
  function lerpFrom(prev, cur, a) {
    return prev === undefined ? cur : prev + (cur - prev) * a;
  }

  function sync(S, CFG, alpha) {
    if (!api.ready || !CFG) return;
    // Nama sengaja panjang: 'a' sudah dipakai loop peluru di scope yang sama,
    // dan var di JavaScript tidak punya scope blok.
    var lerpA = (alpha === undefined || alpha < 0 || alpha > 1) ? 1 : alpha;

    // Delta animasi diambil dari jam dinding lalu dikalikan timeScale simulasi:
    // saat slow-mo menyala, karakter ikut melambat. Kalau tidak, peluru
    // merayap sementara kaki tetap berlari dan ilusinya pecah seketika.
    var now = (global.performance && global.performance.now) ? global.performance.now() : Date.now();
    var raw = lastFrameMs ? (now - lastFrameMs) / 1000 : 0.016;
    lastFrameMs = now;
    var dt = Math.min(0.1, Math.max(0, raw)) * (S.timeScale === undefined ? 1 : S.timeScale);

    for (var poolKind in actorPools) actorPools[poolKind].used = 0;
    pools.rings.begin(); pools.flashes.begin(); pools.blobs.begin();

    // Slow-mo pulls the camera in, mirroring the FOV 60->40 spec.
    camera.fov = baseFov * (0.82 + 0.18 * (S.fov === undefined ? 1 : S.fov));
    // Screen shake is cosmetic only: it must never feed back into the sim.
    var sh = S.shake || 0;
    camera.position.set(CAM.pos[0] + (sh ? (Math.random() - 0.5) * sh * 0.5 : 0),
      CAM.pos[1], CAM.pos[2]);
    camera.lookAt(CAM.look[0], CAM.look[1], CAM.look[2]);
    camera.updateProjectionMatrix();

    groups.defenseLine.material.opacity = 0.55 + 0.35 * Math.abs(Math.sin((S.elapsed || 0) * 2));

    // --- squad: a block formation centred on squadX ---
    pools.troops.begin();
    // Satu prajurit, bukan peleton (docs/18 Fase 4, keputusan D1). `troops`
    // tetap jadi angka aturan — laju tembak dan hukuman kebocoran — tapi
    // dibaca sebagai POWER senjata, bukan jumlah badan. Keputusan tampilan
    // murni: simulasinya tidak diubah sebaris pun.
    var shown = (S.troops || 0) > 0 ? 1 : 0;
    var perRow = 1, sx = lerpFrom(S.prevSquadX, S.squadX || 0, lerpA);
    // Jarak formasi ikut membesar bersama CHAR_SCALE, kalau tidak bahu
    // prajurit saling menembus dan barisan jadi bubur.
    var spread = 0.42 * CHAR_SCALE;
    var sz = (CFG.arena && CFG.arena.playerSpawn ? CFG.arena.playerSpawn.z : 2);
    // Tembakan baru terdeteksi dari posisi, bukan dari jumlah peluru: peluru
    // bisa lahir dan mati di frame yang sama, dan menghitung panjang array
    // akan melewatkan tembakan justru saat layar paling ramai.
    var muzzleZ = sz + ((CFG.arena.muzzleOffset && CFG.arena.muzzleOffset.z) || 0);
    var fresh = false;
    var ab0 = S.autoBullets || [];
    for (var fb = 0; fb < ab0.length; fb++) {
      if (Math.abs(ab0[fb].z - muzzleZ) < 0.9) { fresh = true; break; }
    }
    var moving = Math.abs((S.squadX || 0) - (S.prevSquadX === undefined ? S.squadX || 0 : S.prevSquadX)) > 0.004;
    var muzzleWorld = new THREE.Vector3();
    for (var i = 0; i < shown; i++) {
      var row = Math.floor(i / perRow), col = i % perRow;
      var tx = sx + (col - (perRow - 1) / 2) * spread;
      var tz = sz - row * 0.4 * CHAR_SCALE;
      // Baris depan mendapat skeleton; barisan belakang tetap mesh statis.
      // Itu barisan yang paling dekat kamera dan satu-satunya yang siluetnya
      // benar-benar terbaca.
      var actor = (i < SKIN.troops) ? takeActor('trooper', groups.troops) : null;
      if (actor) {
        actor.root.position.set(tx, 0, -tz);
        actor.root.rotation.y = 0;              // menghadap -Z, arah musuh
        if (actor.lock <= 0) play(actor, moving ? 'run' : 'idle');
        // Pemain digambar lebih besar: ia jangkar komposisi key art.
        // 2,53 = PLAYER_H 4,86 / CHAR_HEIGHT 1,92. Kembar dari PLAYER_SCALE
        // di arena_view.gd; keduanya harus berubah bersama, karena angka itu
        // bagian dari solusi kamera, bukan selera.
        actor.root.scale.setScalar(charScale('trooper') * 2.53);
        if (fresh) {
          oneShot(actor, 'shoot', 0.22);
          if (actor.muzzle) {
            actor.muzzle.getWorldPosition(muzzleWorld);
            // Kilatan digambar di koordinat scene langsung: soketnya sudah
            // ikut berayun bersama lengan, jadi memakai posisi karakter
            // akan menempelkan api di udara kosong.
            var fm = pools.flashes.take();
            fm.position.copy(muzzleWorld);
            fm.quaternion.copy(camera.quaternion);
            fm.scale.setScalar(0.85);
            // Kilatan moncong BIRU: satu-satunya cara membedakan tembakan
            // sendiri dari hujan tracer musuh dalam seperlima detik.
            fm.material.color.setHex(0x2be8ff);
            fm.material.opacity = 0.95;
            blob(muzzleWorld.x, muzzleWorld.y, -muzzleWorld.z, 0.2, PAL.grid, 0.9);
          }
        }
        continue;
      }
      var t = pools.troops.take();
      ensureVisual(t, 'soldier', function () { return makeTroop(accentColor); });
      t.scale.setScalar(t.userData.isModel ? charScale('trooper') : CHAR_SCALE);
      t.position.set(tx, 0, -tz);
    }
    pools.troops.end();

    // --- enemies ---
    // LOD: yang paling dekat garis pertahanan (z terkecil) mendapat skeleton.
    // Mereka yang terbesar di layar dan yang sedang diputuskan nasibnya oleh
    // pemain; musuh di ujung lorong tingginya 20 piksel dan animasinya tidak
    // akan pernah terbaca.
    pools.enemies.begin();
    var list = S.enemies || [];
    var order = [];
    for (var oi = 0; oi < list.length; oi++) order.push(oi);
    order.sort(function (p, q) { return (list[p].z || 0) - (list[q].z || 0); });
    var skinned = {};
    for (var si = 0; si < Math.min(SKIN.enemies, order.length); si++) skinned[order[si]] = true;

    var nextAlive = {};
    for (var e = 0; e < list.length; e++) {
      var en = list[e];
      var kind = en.type || 'grunt';
      var ex = lerpFrom(en.rx, en.x, lerpA), ez = lerpFrom(en.rz, en.z, lerpA);
      if (en.id !== undefined) nextAlive[en.id] = { kind: kind, x: en.x, z: en.z };

      var actor = skinned[e] ? takeActor(kind, groups.enemies) : null;
      if (actor) {
        actor.root.position.set(ex, 0, -ez);
        actor.root.rotation.y = Math.PI;        // menatap pemain
        if (en.hit > 0) oneShot(actor, 'hit', 0.3);
        else if (actor.lock <= 0) play(actor, (en.speed || 1) > 0 ? 'run' : 'idle');
        // Kedip merah saat kena: material sudah per-aktor, jadi aman.
        actor.root.traverse(function (node) {
          if (node.isSkinnedMesh && node.material.emissive) {
            node.material.emissive.setHex(en.hit > 0 ? 0x993333 : 0x000000);
          }
        });
        continue;
      }

      var m = pools.enemies.take();
      var vis = ensureVisual(m, kind, function () {
        return new THREE.Mesh(new THREE.SphereGeometry(1, 10, 8),
          new THREE.MeshLambertMaterial({ color: en.color || '#ff4d3d' }));
      });
      if (m.userData.isModel) {
        m.scale.setScalar(charScale(kind));
        m.position.set(ex, 0, -ez);
        m.rotation.y = Math.PI;              // model menghadap -Z, musuh menatap pemain
      } else {
        var r = (en.r || 0.4) * 1.75;
        vis.scale.set(r, r * 1.35, r);
        m.position.set(ex, r * 1.25, -ez);
      }
      setEmissive(m, en.hit > 0 ? 0x884444 : 0x000000);
    }
    pools.enemies.end();

    // Musuh yang hilang antar frame = musuh yang mati. Simulasi tidak
    // mengirim event kematian ke renderer, tapi identitas yang lenyap adalah
    // sinyal yang sama persis — dan tidak menambah kopling ke aturan main.
    for (var oldId in aliveIds) {
      if (!nextAlive[oldId]) spawnCorpse(aliveIds[oldId].kind, aliveIds[oldId].x, aliveIds[oldId].z);
    }
    aliveIds = nextAlive;

    // --- bullets: auto fire + the single chain bullet ---
    pools.bullets.begin();
    var ab = S.autoBullets || [];
    for (var a = 0; a < ab.length; a++) {
      var bm = pools.bullets.take();
      bm.scale.setScalar(0.2);
      bm.position.set(ab[a].x, 0.45, -ab[a].z);
      bm.material.color.setHex(PAL.bullet);
    }
    var cb = S.bullets || [];
    for (var b = 0; b < cb.length; b++) {
      if (!cb[b].alive) continue;
      var cm = pools.bullets.take();
      cm.scale.setScalar(0.46);
      cm.position.set(cb[b].x, 0.5, -cb[b].z);
      cm.material.color.setHex(PAL.chain);
    }
    pools.bullets.end();

    // --- gates: two panels with their operation printed on them ---
    pools.gatePanels.begin();
    var G = CFG.gates, gl = S.gates || [];
    if (G) {
      var gap = G.centerGapX || 0.6, hw = G.halfWidth || 4.7;
      var panelW = hw - gap;
      for (var g = 0; g < gl.length; g++) {
        var gt = gl[g];
        [['left', gt.left, -1], ['right', gt.right, 1]].forEach(function (side) {
          var op = side[1], dir = side[2];
          var p = pools.gatePanels.take();
          p.scale.set(panelW, 1.7, 1);
          p.position.set(dir * (gap + panelW / 2), 0.9, -lerpFrom(gt.rz, gt.z, lerpA));
          p.material.map = labelTexture(gateText(op), !!(op && op.positive));
          p.material.color.setHex(0xffffff);
          p.material.needsUpdate = true;
        });
      }
    }
    pools.gatePanels.end();

    // --- obstacles ---
    pools.obstacles.begin();
    var ob = S.obstacles || [];
    for (var o = 0; o < ob.length; o++) {
      var os = ob[o];
      if (!os.alive) continue;
      var om = pools.obstacles.take();
      var okind = os.kind === 'shieldWall' ? 'shieldWall'
        : (os.kind === 'barrel' ? 'barrel' : 'bumper');
      var ovis = ensureVisual(om, okind, function () {
        return new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 1, 10),
          new THREE.MeshLambertMaterial({ color: 0x1fd3e8 }));
      });
      if (om.userData.isModel) {
        om.scale.setScalar(okind === 'shieldWall' ? (os.w || 4) / 4 : 1);
        om.position.set(os.x, 0, -os.z);
      } else {
        ovis.scale.set(os.r || 0.9, 0.7, os.r || 0.9);
        om.position.set(os.x, 0.5, -os.z);
      }
    }
    pools.obstacles.end();

    // --- boss ---
    pools.bossParts.begin();
    if (S.boss && S.boss.parts) {
      for (var p2 = 0; p2 < S.boss.parts.length; p2++) {
        var part = S.boss.parts[p2];
        if (!part.alive) continue;
        var pr = part.r || 1.8;
        var bx = lerpFrom(part.rx, part.x, lerpA), bz = lerpFrom(part.rz, part.z, lerpA);
        // Boss selalu ber-skeleton: cuma ada satu sampai tiga bagian, dan ia
        // satu-satunya hal di layar yang pemain tatap lama-lama.
        var bossActor = takeActor('boss', groups.boss);
        if (bossActor) {
          bossActor.root.position.set(bx, 0, -bz);
          bossActor.root.rotation.y = Math.PI;
          bossActor.root.scale.setScalar(charScale('boss') * pr / 1.8);
          if (part.hit > 0) oneShot(bossActor, 'hit', 0.3);
          else if (bossActor.lock <= 0) play(bossActor, 'idle');
          bossActor.root.traverse(function (node) {
            if (node.isSkinnedMesh && node.material.emissive) {
              node.material.emissive.setHex(part.hit > 0 ? 0xaa2222 : 0x220000);
            }
          });
          // Inti dada berdenyut: penanda titik lemah yang terbaca dari jauh.
          var core = bossActor.root.getObjectByName('core');
          if (core) {
            var cw = new THREE.Vector3();
            core.getWorldPosition(cw);
            var pulse = 0.5 + 0.2 * Math.sin((S.elapsed || 0) * 6);
            blob(cw.x, cw.y, -cw.z, pulse, 0xffd54f, 0.5);
          }
          continue;
        }
        var pm = pools.bossParts.take();
        var pvis = ensureVisual(pm, 'boss', function () {
          return new THREE.Mesh(new THREE.SphereGeometry(1, 14, 10),
            new THREE.MeshLambertMaterial({ color: 0xff4d3d }));
        });
        if (pm.userData.isModel) {
          pm.scale.setScalar(charScale('boss') * pr / 1.8);
          pm.position.set(bx, 0, -bz);
          pm.rotation.y = Math.PI;
        } else {
          pvis.scale.setScalar(pr);
          pm.position.set(bx, pr, -bz);
        }
        setEmissive(pm, part.hit > 0 ? 0xaa2222 : 0x220000);
      }
    }
    pools.bossParts.end();

    // --- efek dan animasi ---
    drawTrail(S);
    updateTracers(S, dt);
    updateArcs(dt);
    drawEffects(S);
    pools.rings.end(); pools.flashes.end(); pools.blobs.end();

    // Mixer hanya dijalankan untuk aktor yang dipakai frame ini; sisa pool
    // disembunyikan dan dibekukan supaya skeleton yang tidak terlihat tidak
    // ikut dibayar.
    for (var ak in actorPools) {
      var pool = actorPools[ak];
      for (var ai = 0; ai < pool.items.length; ai++) {
        var a2 = pool.items[ai];
        if (ai < pool.used) {
          if (a2.lock > 0) a2.lock = Math.max(0, a2.lock - dt);
          a2.mixer.update(dt);
        } else {
          a2.root.visible = false;
        }
      }
    }
    updateCorpses(dt);

    renderer.render(scene, camera);
  }

  var api = {
    ready: false,
    init: init, sync: sync, resize: resize, setAccent: setAccent,
    makeCamera: makeCamera, CAM: CAM, ARENA: ARENA, modelsLoaded: 0, rigsLoaded: 0,
    SKIN: SKIN,
    // Dipakai tools/char_test.js untuk memeriksa aktor hidup tanpa menebak
    // dari piksel: berapa yang ber-skeleton, berapa mayat, klip apa yang jalan.
    _actors: function () {
      var out = [];
      for (var kind in actorPools) {
        var pool = actorPools[kind];
        for (var i = 0; i < pool.used; i++) {
          out.push({ kind: kind, clip: pool.items[i].current, y: pool.items[i].root.position.y });
        }
      }
      return out;
    },
    _corpses: countCorpses,
    // Berapa keping efek yang benar-benar terpakai pada frame terakhir.
    _fx: function () {
      return { rings: pools.rings ? pools.rings.used : 0,
               flashes: pools.flashes ? pools.flashes.used : 0,
               blobs: pools.blobs ? pools.blobs.used : 0 };
    },
    // Angka draw call sungguhan dari WebGLRenderer. Dipakai tools/perf_probe.js
    // supaya anggaran di docs/08 adalah hasil ukur, bukan hasil hitung tangan.
    _info: function () {
      if (!renderer) return null;
      var r = renderer.info.render, m = renderer.info.memory;
      return { calls: r.calls, triangles: r.triangles,
               geometries: m.geometries, textures: m.textures,
               programs: renderer.info.programs ? renderer.info.programs.length : 0 };
    },
    _setThree: function (t) { THREE = t; },   // for the headless geometry test
    _scene: function () { return scene; },    // ditto
    // Jalur muat karakter dibuka untuk tes dan lembar kontak. Keduanya DULU
    // memuat GLB turunan sendiri; sejak karakter dipakai apa adanya dari pack,
    // tidak ada berkas turunan untuk dimuat — jadi tes harus melewati jalur
    // yang sama persis dengan game, yang justru membuat tesnya lebih jujur.
    _loadCast: function (cb) { loadRigs(cb); },
    _rig: function (kind) { return rigs[kind]; },
    _makeActor: makeActor,
    _play: play,
    _cast: function () { return Object.keys(CAST); },
  };
  global.R3D = api;
})(typeof window !== 'undefined' ? window : globalThis);

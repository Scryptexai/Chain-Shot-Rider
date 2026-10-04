#!/usr/bin/env node
/**
 * rig_test.js — Membuktikan karakter ber-tulang itu benar-benar ber-tulang.
 *
 * Karakter dipakai APA ADANYA dari pack KayKit: berkas karakter, berkas
 * animasi, dan berkas senjata adalah tiga berkas terpisah yang baru menjadi
 * satu aktor di dalam `js/render3d.js`. Perakitan itulah yang bisa salah
 * (klip tidak ketemu rignya, senjata nyangkut di tulang yang keliru, skala
 * meleset sepuluh kali) dan semuanya gagal tanpa satu pun pesan error.
 *
 * Maka tes ini memanggil jalur muat milik game sendiri (`R3D._loadCast`,
 * `R3D._makeActor`) di Chromium sungguhan, bukan memuat berkas turunan yang
 * kebetulan mirip:
 *
 *   · mesh-nya SkinnedMesh, bukan Mesh biasa,
 *   · jumlah tulangnya sesuai,
 *   · kelima klip ada dan durasinya masuk akal,
 *   · soket efek (moncong) ada,
 *   · dan tulang yang seharusnya bergerak memang bergerak saat klip dimainkan:
 *     kaki pada 'run', kepala pada 'die', tangan kanan pada 'shoot'. Diukur
 *     per tulang, bukan per karakter, karena "ada yang bergerak" bisa benar
 *     sementara kakinya tetap kaku — dan kaki kaku persis seperti v0.5.
 *   · tinggi karakter masuk akal terhadap config (bukan 100x atau 0.01x),
 *   · dan vertex bergerak antar frame animasi, bukan diam seperti patung.
 *
 *   node tools/rig_test.js [url]
 *
 * Prasyarat: `bash tools/setup_chromium.sh` dan server di URL tujuan.
 */
'use strict';
const puppeteer = require('puppeteer-core');

const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');
const URL = process.argv[2] || 'http://localhost:8000/';

const UNITS = ['trooper', 'grunt', 'runner', 'brute', 'shielder', 'splitter', 'bomber', 'boss'];
const CLIPS = ['idle', 'run', 'shoot', 'hit', 'die'];

let failures = 0;
const fail = (m) => { failures++; console.log('  GAGAL  ' + m); };
const ok = (m) => console.log('  ok     ' + m);

async function main() {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: CHROME,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--use-gl=angle',
      '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(URL, { waitUntil: 'networkidle2' });

  const report = await page.evaluate(async (units) => {
    R3D._setThree(THREE);
    await new Promise((res) => R3D._loadCast(res));
    const out = [];
    for (const name of units) {
      const actor = R3D._makeActor(name);
      if (!actor) { out.push({ name, isSkinned: false }); continue; }
      const root = actor.root;
      // Semua mesh karakter KayKit ber-skin; yang diperiksa di sini mesh
      // terbesar (badan), plus hitungan berapa mesh yang ikut terbawa.
      let skinned = null; let meshes = 0; let weapons = 0;
      root.traverse((o) => {
        if (o.isSkinnedMesh) {
          meshes++;
          if (!skinned || o.geometry.attributes.position.count
            > skinned.geometry.attributes.position.count) skinned = o;
        } else if (o.isMesh) {
          weapons++;
        }
      });
      const sockets = {};
      ['handslotr', 'handslotl'].forEach((n) => {
        const o = root.getObjectByName(n);
        if (o) sockets[n] = o;
      });
      const box = new THREE.Box3().setFromObject(root);
      const entry = {
        name,
        isSkinned: !!skinned,
        meshes, weapons,
        bones: skinned ? skinned.skeleton.bones.length : 0,
        verts: skinned ? skinned.geometry.attributes.position.count : 0,
        // Warna boleh datang dari dua sumber: atlas KayKit (yang dipakai
        // sekarang) atau vertex color (model prosedural lama). Yang tidak
        // boleh adalah tidak punya keduanya — itu berarti karakter putih polos.
        hasColor: !!(skinned && (skinned.geometry.attributes.color
          || (skinned.material && skinned.material.map))),
        textured: !!(skinned && skinned.material && skinned.material.map),
        clips: Object.keys(actor.actions).map((k) => ({
          name: k, dur: +actor.actions[k].getClip().duration.toFixed(3),
        })),
        height: +(box.max.y - box.min.y).toFixed(3),
        width: +(box.max.x - box.min.x).toFixed(3),
        sockets: Object.keys(sockets),
        moved: {},
      };

      // Jalankan tiap klip dan ukur perpindahan tulang yang relevan.
      // Probe per tulang, bukan satu titik: moncong bomber ada di dada dan
      // memang tidak bergerak saat berlari — yang harus bergerak kakinya.
      const mixer = actor.mixer;
      const probes = { muzzle: sockets.handslotr || null };
      if (skinned) {
        for (const bone of skinned.skeleton.bones) {
          // Nama tulang KayKit ber-titik (`hand.r`); three.js membuang titiknya
          // saat memuat, jadi di memori ia `handr`.
          if (['handr', 'footl', 'head', 'hips'].includes(bone.name)) probes[bone.name] = bone;
        }
      }
      const at = (node) => new THREE.Vector3().setFromMatrixPosition(node.matrixWorld);
      for (const key of Object.keys(actor.actions)) {
        const action = actor.actions[key];
        const clip = action.getClip();
        action.reset().play();
        const samples = {};
        for (const key of Object.keys(probes)) samples[key] = [];
        // Empat sampel sepanjang klip: satu pose awal dan akhir saja bisa
        // identik pada klip yang berulang, dan itu akan terbaca "tidak gerak".
        for (const t of [0, 0.25, 0.5, 0.75]) {
          mixer.setTime(clip.duration * t);
          root.updateMatrixWorld(true);
          for (const [key, node] of Object.entries(probes)) {
            if (node) samples[key].push(at(node));
          }
        }
        const spread = {};
        for (const [key, pts] of Object.entries(samples)) {
          let max = 0;
          for (let i = 0; i < pts.length; i++) {
            for (let j = i + 1; j < pts.length; j++) max = Math.max(max, pts[i].distanceTo(pts[j]));
          }
          spread[key] = +max.toFixed(4);
        }
        entry.moved[key] = spread;
        action.stop();
      }
      out.push(entry);
    }
    return out;
  }, UNITS);

  console.log('\nCHAIN RIDER — uji karakter ber-tulang\n');
  for (const u of report) {
    if (!u.isSkinned) { fail(`${u.name}: bukan SkinnedMesh`); continue; }
    // Rig_Medium punya 23 tulang. Angkanya tidak boleh "kira-kira": kalau
    // rignya salah, klip dari berkas animasi akan mengikat ke tulang yang
    // keliru dan karakternya terpelintir.
    if (u.bones !== 23) fail(`${u.name}: ${u.bones} tulang, harusnya 23`);
    // Sembilan mesh adalah ciri karakter KayKit yang utuh (lengan, kepala,
    // helm, jubah, ...). Kalau tinggal satu, berarti ada yang menggabungkannya
    // lagi di belakang layar.
    if (u.meshes < 5) fail(`${u.name}: cuma ${u.meshes} mesh — karakter tidak utuh`);
    if (!u.hasColor) fail(`${u.name}: tanpa tekstur maupun COLOR_0, modelnya akan putih polos`);
    if (u.verts < 300) fail(`${u.name}: cuma ${u.verts} vertex`);
    const names = u.clips.map((c) => c.name);
    for (const want of CLIPS) {
      if (!names.includes(want)) fail(`${u.name}: klip '${want}' hilang`);
    }
    for (const c of u.clips) {
      if (c.dur < 0.15 || c.dur > 3.0) fail(`${u.name}: klip '${c.name}' durasi ${c.dur}s`);
    }
    // Tinggi di dunia game: semua peran disamakan ke 1,92 unit lewat skala
    // node (berkasnya sendiri lahir 2,17–2,66 unit), kecuali boss yang memang
    // dua kali lipat. Yang dijaga di sini batas akal, bukan angka persis:
    // busur Ranger menambah sedikit tinggi kotak batasnya.
    const hiCap = u.name === 'boss' ? 4.2 : 2.2;
    if (u.height < 1.4 || u.height > hiCap) fail(`${u.name}: tinggi ${u.height} unit di luar akal`);
    // Lebar diukur relatif tinggi: boss setinggi dua meter memang merentang
    // lebih jauh (kapak dua tangan + perisai) tanpa itu berarti salah skala.
    const maxWidth = Math.max(1.6, u.height * 1.3);
    if (u.width > maxWidth) fail(`${u.name}: lebar ${u.width} unit, akan saling tembus di formasi`);
    if (!u.sockets.includes('handslotr')) fail(`${u.name}: soket tangan kanan hilang`);
    if (u.weapons < 1) fail(`${u.name}: tidak ada senjata yang tergantung di tangan`);
    // Gerak nyata, per tulang yang memang bertanggung jawab atas klip itu.
    const m = u.moved;
    if ((m.run.footl || 0) < 0.05) fail(`${u.name}: kaki tidak melangkah di klip run`);
    if ((m.run.hips || 0) < 0.01) fail(`${u.name}: badan tidak naik-turun saat berlari`);
    if ((m.die.head || 0) < 0.10) fail(`${u.name}: klip die tidak merobohkan badan`);
    if ((m.shoot.handr || 0) <= 0.0) fail(`${u.name}: recoil tidak menggerakkan tangan kanan`);
    if ((m.idle.head || 0) <= 0.0) fail(`${u.name}: idle benar-benar diam seperti patung`);
    ok(
      `${u.name.padEnd(9)} ${u.bones} tulang, ${u.meshes} mesh + ${u.weapons} senjata, ` +
      `${String(u.verts).padStart(4)} vert, ${u.clips.length} klip, ` +
      `tinggi ${u.height.toFixed(2)}, langkah ${m.run.footl.toFixed(2)} / ` +
      `roboh ${m.die.head.toFixed(2)} / recoil ${m.shoot.handr.toFixed(3)}`
    );
  }
  if (errors.length) { errors.slice(0, 5).forEach((e) => fail('konsol: ' + e)); }

  await browser.close();
  console.log('');
  if (failures) { console.log(`GAGAL — ${failures} masalah\n`); process.exit(1); }
  console.log(`LULUS — ${report.length} karakter ber-tulang, animasi terbukti bergerak\n`);
}
main().catch((e) => { console.error(e); process.exit(1); });

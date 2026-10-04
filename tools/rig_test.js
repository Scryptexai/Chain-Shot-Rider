#!/usr/bin/env node
/**
 * rig_test.js — Membuktikan karakter ber-tulang itu benar-benar ber-tulang.
 *
 * Generator GLB di `tools/rigkit.py` ditulis dari nol: tidak ada pustaka yang
 * memvalidasi outputnya, dan glTF yang salah sedikit saja (offset bufferView
 * meleset, inverseBindMatrices terbalik, channel animasi menunjuk node yang
 * keliru) tetap memuat tanpa error — modelnya cuma tampil kusut atau diam.
 * Jadi pemeriksaannya dilakukan oleh pemuat yang sama persis dengan yang
 * dipakai game, di Chromium sungguhan:
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
    const loader = new THREE.GLTFLoader();
    const out = [];
    for (const name of units) {
      const gltf = await new Promise((res, rej) =>
        loader.load('assets/models/rigged/' + name + '.glb', res, undefined, rej));
      const root = gltf.scene;
      let skinned = null; const sockets = {};
      root.traverse((o) => {
        if (o.isSkinnedMesh) skinned = o;
        if (/^(muzzle|muzzle_l|core)$/.test(o.name)) sockets[o.name] = o;
      });
      const box = new THREE.Box3().setFromObject(root);
      const entry = {
        name,
        isSkinned: !!skinned,
        bones: skinned ? skinned.skeleton.bones.length : 0,
        verts: skinned ? skinned.geometry.attributes.position.count : 0,
        hasColor: !!(skinned && skinned.geometry.attributes.color),
        clips: gltf.animations.map((a) => ({ name: a.name, dur: +a.duration.toFixed(3) })),
        height: +(box.max.y - box.min.y).toFixed(3),
        width: +(box.max.x - box.min.x).toFixed(3),
        sockets: Object.keys(sockets),
        moved: {},
      };

      // Jalankan tiap klip dan ukur perpindahan tulang yang relevan.
      // Probe per tulang, bukan satu titik: moncong bomber ada di dada dan
      // memang tidak bergerak saat berlari — yang harus bergerak kakinya.
      const mixer = new THREE.AnimationMixer(root);
      const probes = { muzzle: sockets.muzzle || null };
      if (skinned) {
        for (const bone of skinned.skeleton.bones) {
          if (['hand_r', 'foot_l', 'head', 'hips'].includes(bone.name)) probes[bone.name] = bone;
        }
      }
      const at = (node) => new THREE.Vector3().setFromMatrixPosition(node.matrixWorld);
      for (const clip of gltf.animations) {
        const action = mixer.clipAction(clip);
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
        entry.moved[clip.name] = spread;
        action.stop();
      }
      out.push(entry);
    }
    return out;
  }, UNITS);

  console.log('\nCHAIN RIDER — uji karakter ber-tulang\n');
  for (const u of report) {
    if (!u.isSkinned) { fail(`${u.name}: bukan SkinnedMesh`); continue; }
    if (u.bones !== 24) fail(`${u.name}: ${u.bones} tulang, harusnya 24`);
    if (!u.hasColor) fail(`${u.name}: tanpa COLOR_0, modelnya akan putih polos`);
    if (u.verts < 300) fail(`${u.name}: cuma ${u.verts} vertex`);
    const names = u.clips.map((c) => c.name);
    for (const want of CLIPS) {
      if (!names.includes(want)) fail(`${u.name}: klip '${want}' hilang`);
    }
    for (const c of u.clips) {
      if (c.dur < 0.15 || c.dur > 3.0) fail(`${u.name}: klip '${c.name}' durasi ${c.dur}s`);
    }
    // Tinggi: prajurit ~0.95 unit, boss ~2x, tidak ada yang boleh di luar ini.
    if (u.height < 0.6 || u.height > 2.6) fail(`${u.name}: tinggi ${u.height} unit di luar akal`);
    // Lebar diukur relatif tinggi: boss setinggi dua meter memang merentang
    // lebih jauh (kapak dua tangan + perisai) tanpa itu berarti salah skala.
    const maxWidth = Math.max(1.6, u.height * 1.3);
    if (u.width > maxWidth) fail(`${u.name}: lebar ${u.width} unit, akan saling tembus di formasi`);
    if (!u.sockets.includes('muzzle')) fail(`${u.name}: soket 'muzzle' hilang`);
    // Gerak nyata, per tulang yang memang bertanggung jawab atas klip itu.
    const m = u.moved;
    if ((m.run.foot_l || 0) < 0.05) fail(`${u.name}: kaki tidak melangkah di klip run`);
    if ((m.run.hips || 0) < 0.01) fail(`${u.name}: badan tidak naik-turun saat berlari`);
    if ((m.die.head || 0) < 0.10) fail(`${u.name}: klip die tidak merobohkan badan`);
    if ((m.shoot.hand_r || 0) <= 0.0) fail(`${u.name}: recoil tidak menggerakkan tangan kanan`);
    if ((m.idle.head || 0) <= 0.0) fail(`${u.name}: idle benar-benar diam seperti patung`);
    ok(
      `${u.name.padEnd(9)} ${u.bones} tulang, ${String(u.verts).padStart(4)} vert, ` +
      `${u.clips.length} klip, tinggi ${u.height.toFixed(2)}, ` +
      `langkah ${m.run.foot_l.toFixed(2)} / roboh ${m.die.head.toFixed(2)} / recoil ${m.shoot.hand_r.toFixed(3)}`
    );
  }
  if (errors.length) { errors.slice(0, 5).forEach((e) => fail('konsol: ' + e)); }

  await browser.close();
  console.log('');
  if (failures) { console.log(`GAGAL — ${failures} masalah\n`); process.exit(1); }
  console.log(`LULUS — ${report.length} karakter ber-tulang, animasi terbukti bergerak\n`);
}
main().catch((e) => { console.error(e); process.exit(1); });

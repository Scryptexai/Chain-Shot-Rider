#!/usr/bin/env node
/**
 * char_test.js — Membuktikan karakter ber-tulang itu benar-benar HIDUP DI DALAM
 * GAME, bukan cuma benar sebagai file.
 *
 * `rig_test.js` memeriksa delapan GLB satu per satu di ruang kosong: tulangnya
 * ada, klipnya ada, vertexnya bergerak. Yang TIDAK dibuktikannya adalah apakah
 * game memakai semua itu — renderer bisa saja memuat rig lalu menggambar kubus
 * lama, memainkan satu klip untuk semua unit, atau meng-clone SkinnedMesh
 * secara keliru sehingga seluruh pasukan bergerak serempak seperti satu tubuh.
 *
 * Tes ini memainkan stage sungguhan di Chromium lalu memeriksa:
 *   · kedelapan rig termuat lewat jalur game (R3D.rigsLoaded),
 *   · saat bertempur ada aktor ber-skeleton di layar, dan jumlahnya TIDAK
 *     melebihi anggaran LOD (kalau melebihi, ponsel kentang yang membayar),
 *   · aktor memainkan klip yang berbeda-beda sesuai keadaannya (prajurit
 *     menembak, musuh berlari/kena pukul) — bukan satu klip untuk semuanya,
 *   · tulang dua aktor sejenis berada di fase berbeda: bukti skeleton benar-
 *     benar di-clone, bukan dibagi pakai bersama,
 *   · tulang bergerak antar frame saat game berjalan,
 *   · efek tembakan/ledakan terpakai (kilatan moncong, cincin, bola cahaya),
 *   · mayat muncul saat musuh mati lalu dibersihkan sendiri,
 *   · tidak ada error konsol selama bertempur.
 *
 *   node tools/char_test.js [url]
 *
 * Prasyarat: `bash tools/setup_chromium.sh` dan server di URL tujuan.
 */
'use strict';
const puppeteer = require('puppeteer-core');

const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');
const URL = process.argv[2] || 'http://localhost:8000/';

let failures = 0;
const fail = (m) => { failures++; console.log('  GAGAL  ' + m); };
const ok = (m) => console.log('  ok     ' + m);
const check = (cond, m) => (cond ? ok(m) : fail(m));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  console.log('\nCHAIN RIDER — karakter hidup di dalam game');
  console.log('='.repeat(72));

  const browser = await puppeteer.launch({
    headless: true,
    executablePath: CHROME,
    args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader',
           '--enable-unsafe-swiftshader'],
  });
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
  await page.goto(URL, { waitUntil: 'networkidle2' });
  await sleep(2500);

  // --- 1. aset termuat lewat jalur game -------------------------------------
  const loaded = await page.evaluate(() => ({
    rigs: window.R3D ? R3D.rigsLoaded : -1,
    models: window.R3D ? R3D.modelsLoaded : -1,
    skin: window.R3D ? R3D.SKIN : null,
  }));
  check(loaded.rigs === 8, `8 rig ber-tulang termuat renderer — ${loaded.rigs}`);
  check(loaded.models >= 11, `model statis LOD jauh tetap ada — ${loaded.models}`);

  // --- 2. bertempur ---------------------------------------------------------
  await page.evaluate(() => startStage(0));
  await sleep(1200);

  let peakActors = 0, peakFx = { rings: 0, flashes: 0, blobs: 0 }, peakCorpses = 0;
  const clipsSeen = new Set();
  const kindsSeen = new Set();
  for (let i = 0; i < 16; i++) {
    await page.mouse.move(195 + Math.sin(i * 0.7) * 95, 700);
    await sleep(700);
    const snap = await page.evaluate(() => ({
      actors: R3D._actors(), fx: R3D._fx(), corpses: R3D._corpses(),
    }));
    peakActors = Math.max(peakActors, snap.actors.length);
    peakCorpses = Math.max(peakCorpses, snap.corpses);
    for (const k in peakFx) peakFx[k] = Math.max(peakFx[k], snap.fx[k]);
    snap.actors.forEach((a) => { clipsSeen.add(a.clip); kindsSeen.add(a.kind); });
  }

  const budget = loaded.skin.troops + loaded.skin.enemies + 3;  // +3 bagian boss
  check(peakActors > 8, `aktor ber-skeleton muncul saat bertempur — puncak ${peakActors}`);
  check(peakActors <= budget,
    `anggaran LOD dihormati — puncak ${peakActors} <= ${budget}`);
  check(kindsSeen.size >= 2,
    `lebih dari satu jenis unit ber-tulang — ${[...kindsSeen].join(', ')}`);
  check(clipsSeen.size >= 3,
    `klip berbeda dimainkan sesuai keadaan — ${[...clipsSeen].join(', ')}`);
  check(clipsSeen.has('run') || clipsSeen.has('idle'), 'ada unit berjalan/siaga');
  check(clipsSeen.has('shoot') || clipsSeen.has('hit'),
    'ada aksi sesaat (tembak / kena pukul)');

  // --- 3. skeleton benar-benar di-clone, bukan dibagi bersama ---------------
  // Dua prajurit sejenis yang animasinya berbagi skeleton akan punya tulang di
  // titik yang persis sama relatif terhadap akarnya. Yang diperiksa adalah
  // posisi lokal tulang kaki, bukan posisi dunia (itu beda karena formasi).
  const phases = await page.evaluate(() => {
    const out = [];
    const seen = new Set();
    R3D._scene().traverse((n) => {
      if (!n.isSkinnedMesh || !n.visible || !n.skeleton) return;
      if (seen.has(n.skeleton.uuid)) return;          // satu entri per skeleton
      seen.add(n.skeleton.uuid);
      // Klip menganimasikan rotasi, jadi yang dibandingkan adalah rotasi
      // seluruh tulang — posisi lokalnya memang konstan di rig mana pun, dan
      // tulang tertentu (telapak kaki, telapak tangan) tidak ikut bergerak di
      // semua klip.
      let sig = 0;
      n.skeleton.bones.forEach((b) => { sig += b.quaternion.x * 7 + b.quaternion.z * 13; });
      out.push({ kind: n.name, q: n.name + ':' + sig.toFixed(5) });
    });
    return out;
  });
  const uniq = new Set(phases.map((p) => p.q));
  // Dibandingkan per jenis unit: dua trooper boleh mirip kebetulan, tapi
  // dua puluh aktor dengan satu pose identik berarti skeleton dipakai bersama.
  check(phases.length >= 4, `tulang terbaca dari ${phases.length} skeleton terpisah`);
  check(uniq.size >= Math.min(4, phases.length),
    `aktor punya fase animasi sendiri-sendiri — ${uniq.size} pose berbeda dari ${phases.length} aktor`);

  // --- 4. tulang bergerak antar frame --------------------------------------
  const probe = () => page.evaluate(() => {
    let sum = 0, n = 0;
    R3D._scene().traverse((o) => {
      if (!o.isSkinnedMesh || !o.visible || !o.skeleton) return;
      o.skeleton.bones.forEach((b) => { sum += b.position.y + b.position.z + b.quaternion.x; n++; });
    });
    return { sum: sum, n: n };
  });
  const a = await probe();
  await sleep(260);
  const b = await probe();
  check(a.n > 0 && Math.abs(a.sum - b.sum) > 1e-4,
    `tulang bergerak antar frame — selisih ${Math.abs(a.sum - b.sum).toFixed(4)}`);

  // --- 5. senjata dan efek --------------------------------------------------
  const sockets = await page.evaluate(() => {
    let muzzles = 0, meshes = 0;
    R3D._scene().traverse((o) => {
      if (o.name === 'muzzle') muzzles++;
      if (o.isSkinnedMesh) meshes++;
    });
    return { muzzles: muzzles, meshes: meshes };
  });
  check(sockets.muzzles > 0,
    `soket senjata ikut ter-clone ke dalam adegan — ${sockets.muzzles} moncong`);
  check(peakFx.flashes > 0, `kilatan moncong tergambar — puncak ${peakFx.flashes}`);
  check(peakFx.rings + peakFx.blobs > 0,
    `efek hantaman tergambar — cincin ${peakFx.rings}, bola ${peakFx.blobs}`);

  // --- 6. mayat -------------------------------------------------------------
  check(peakCorpses > 0, `musuh yang mati roboh di tempat — puncak ${peakCorpses} mayat`);
  check(peakCorpses <= loaded.skin.corpses,
    `mayat dibatasi anggaran — ${peakCorpses} <= ${loaded.skin.corpses}`);
  await sleep(2200);
  const settled = await page.evaluate(() => R3D._corpses());
  check(settled < loaded.skin.corpses, `mayat dibersihkan sendiri — tersisa ${settled}`);

  // --- 7. bersih ------------------------------------------------------------
  check(errors.length === 0, `tanpa error konsol — ${errors.slice(0, 3).join(' | ') || 'bersih'}`);

  await browser.close();
  console.log('='.repeat(72));
  console.log(failures === 0 ? 'SEMUA LULUS\n' : `${failures} GAGAL\n`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });

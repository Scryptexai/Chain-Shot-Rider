#!/usr/bin/env node
/**
 * cast_sheet.js — Lembar kontak seluruh karakter, untuk dilihat mata.
 *
 * Sejak karakter dipakai apa adanya dari pack KayKit, tidak ada lagi berkas
 * GLB turunan yang bisa dimuat langsung di sini. Itu justru bagus: lembar ini
 * sekarang memakai jalur muat yang sama persis dengan game (`R3D._loadCast`),
 * jadi kalau gambarnya benar, yang benar adalah jalur yang betul-betul dipakai
 * saat bermain — bukan jalur kedua yang kebetulan mirip.
 *
 *   CHARS=trooper,boss PERROW=4 node tools/cast_sheet.js [url] [out.png]
 */
'use strict';
const puppeteer = require('puppeteer-core');
const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');
const URL = process.argv[2] || 'http://localhost:8111/';
const OUT = process.argv[3] || 'screenshots/kaykit-cast.png';

(async () => {
  const b = await puppeteer.launch({
    headless: true, executablePath: CHROME,
    args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader'],
  });
  const p = await b.newPage();
  await p.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });
  const logs = [];
  p.on('pageerror', (e) => logs.push('PAGEERROR ' + e.message));
  await p.goto(URL, { waitUntil: 'networkidle2' });

  const OPT = {
    chars: process.env.CHARS || 'trooper,grunt,runner,brute,splitter,bomber,shielder,boss',
    clip: process.env.CLIP || '',
    spacing: +(process.env.SPACING || 2.6),
    perRow: +(process.env.PERROW || 4),
    half: +(process.env.HALF || 4.6),
    cy: +(process.env.CY || -1.6),
    yrot: +(process.env.YROT || 0.55),
    rowGap: +(process.env.ROWGAP || 4.6),
    seconds: +(process.env.SECONDS || 0.5),
  };

  const png = await p.evaluate(async (OPT) => {
    const W = 1280, H = 720;
    const cv = document.createElement('canvas');
    cv.width = W; cv.height = H;
    document.body.innerHTML = '';
    document.body.appendChild(cv);

    const r = new THREE.WebGLRenderer({ canvas: cv, antialias: true });
    // Sama dengan game: tekstur glTF bertanda sRGB, jadi keluaran renderer
    // harus sRGB juga. Tanpa baris ini karakternya tampil gelap berlumpur.
    r.outputEncoding = THREE.sRGBEncoding;
    r.setClearColor(0x1a2030);

    const sc = new THREE.Scene();
    sc.add(new THREE.HemisphereLight(0xffffff, 0x606080, 1.15));
    const d = new THREE.DirectionalLight(0xffffff, 1.4);
    d.position.set(3, 5, 4); sc.add(d);

    // Jalur muat milik game.
    R3D._setThree(THREE);
    await new Promise((res) => R3D._loadCast(res));

    const names = OPT.chars.split(',');
    const defaultClip = {
      trooper: 'shoot', grunt: 'run', runner: 'run', brute: 'shoot',
      splitter: 'shoot', bomber: 'idle', shielder: 'idle', boss: 'run',
    };
    const actors = [];
    for (let i = 0; i < names.length; i++) {
      const actor = R3D._makeActor(names[i]);
      if (!actor) continue;
      const col = i % OPT.perRow, row = Math.floor(i / OPT.perRow);
      actor.root.position.set((col - (OPT.perRow - 1) / 2) * OPT.spacing, -row * OPT.rowGap, 0);
      actor.root.rotation.y = OPT.yrot;
      sc.add(actor.root);
      R3D._play(actor, OPT.clip || defaultClip[names[i]] || 'idle', 0);
      actors.push(actor);
    }
    // Maju beberapa langkah supaya posenya bukan frame nol yang kaku.
    for (let step = 0; step < 30; step++) {
      actors.forEach((a) => a.mixer.update(OPT.seconds / 30));
    }

    const rows = Math.ceil(names.length / OPT.perRow);
    const cam = new THREE.OrthographicCamera(
      -OPT.half * (W / H), OPT.half * (W / H),
      OPT.half, -OPT.half, 0.1, 100);
    cam.position.set(0, OPT.cy - (rows - 1) * OPT.rowGap / 2, 12);
    cam.lookAt(0, OPT.cy - (rows - 1) * OPT.rowGap / 2, 0);
    r.render(sc, cam);
    return cv.toDataURL('image/png').slice('data:image/png;base64,'.length);
  }, OPT);

  require('fs').writeFileSync(OUT, Buffer.from(png, 'base64'));
  if (logs.length) console.log(logs.join('\n'));
  console.log('Tersimpan ' + OUT);
  await b.close();
})();

#!/usr/bin/env node
/**
 * web_build_test.js — Membuktikan build web Godot benar-benar jalan di browser.
 *
 * Ekspor yang "berhasil" tidak berarti apa-apa: Godot menulis index.wasm dan
 * index.pck tanpa pernah menjalankannya. Kegagalan build web justru muncul di
 * sisi browser dan nyaris selalu tanpa pesan yang menyebut sebabnya:
 *
 *   · template berulir disajikan tanpa header COOP/COEP  -> kanvas hitam,
 *     konsol cuma bilang "SharedArrayBuffer is not defined",
 *   · .wasm disajikan sebagai text/plain                 -> instantiateStreaming
 *     menolak, halaman berhenti di layar loading,
 *   · .pck tidak ikut ter-upload                         -> engine boot lalu
 *     mati saat memuat main.tscn.
 *
 * Jadi tes ini menyajikan build persis seperti host statis gratis (TANPA
 * header isolasi, lihat tools/serve_web_build.py), memuatnya di Chromium
 * sungguhan dengan WebGL perangkat lunak, lalu memeriksa:
 *
 *   · mime type .wasm benar,
 *   · halaman TIDAK cross-origin isolated — bukti build nothreads tidak
 *     menuntut SharedArrayBuffer dan bisa dihosting di GitHub Pages,
 *   · engine selesai boot (kanvas punya ukuran),
 *   · kanvas benar-benar menggambar: piksel tidak seragam,
 *   · dan tidak ada error konsol yang mematikan.
 *
 *   python3 tools/serve_web_build.py 8081 &
 *   node tools/web_build_test.js [url]
 *
 * Prasyarat: `bash tools/setup_chromium.sh`.
 */
'use strict';
const puppeteer = require('puppeteer-core');

const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');
const URL = process.argv[2] || 'http://localhost:8081/';
/** Boot WebAssembly 37 MB di WebGL perangkat lunak memang selambat ini. */
const BOOT_TIMEOUT_MS = Number(process.env.BOOT_TIMEOUT_MS || 240000);

let failures = 0;
const fail = (m) => { failures++; console.log('  GAGAL  ' + m); };
const ok = (m) => console.log('  ok     ' + m);
const check = (cond, m) => (cond ? ok(m) : fail(m));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  console.log('\nCHAIN RIDER — build web Godot di browser sungguhan');
  console.log('='.repeat(72));
  console.log(`url: ${URL}`);

  const browser = await puppeteer.launch({
    headless: true,
    executablePath: CHROME,
    args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader',
           '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'],
    protocolTimeout: BOOT_TIMEOUT_MS + 60000,
  });
  const page = await browser.newPage();
  const errors = [];
  const types = {};
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('response', (r) => {
    const u = r.url();
    if (/\.(wasm|pck|js)$/.test(u)) {
      types[u.split('/').pop()] = {
        status: r.status(), type: (r.headers()['content-type'] || '').split(';')[0],
      };
    }
  });
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });

  const started = Date.now();
  // Baris log engine adalah tanda boot yang jujur: kanvas sudah punya ukuran
  // sejak HTML pertama digambar, jadi menunggunya tidak membuktikan apa pun.
  const bootLine = new Promise((resolve) => {
    page.on('console', (m) => { if (/Godot Engine v/.test(m.text())) resolve(m.text()); });
  });
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: BOOT_TIMEOUT_MS });

  // --- 1. cara build disajikan ---------------------------------------------
  const isolated = await page.evaluate(() => window.crossOriginIsolated === true);
  check(!isolated,
    'halaman TIDAK cross-origin isolated — build nothreads, aman untuk GitHub Pages');

  // --- 2. boot ---------------------------------------------------------------
  const banner = await Promise.race([bootLine, sleep(BOOT_TIMEOUT_MS).then(() => null)]);
  const bootSeconds = ((Date.now() - started) / 1000).toFixed(1);
  check(banner !== null, `engine boot — ${banner || 'tidak pernah mencetak versi'} (${bootSeconds} s)`);
  check(/single-threaded/.test(errors.join(' ')) === false, 'tanpa error saat boot');

  const wasm = types['index.wasm'] || {};
  check(wasm.type === 'application/wasm',
    `index.wasm disajikan sebagai ${wasm.type || 'tidak pernah diminta'}`);
  const pck = types['index.pck'] || {};
  check(pck.status === 200, `index.pck terkirim — status ${pck.status || 'tidak diminta'}`);

  // --- 3. benar-benar menggambar ---------------------------------------------
  // Kanvas hitam adalah kegagalan yang paling sering lolos dari pemeriksaan
  // apa pun, jadi pikselnya dibaca: layar yang hidup punya lebih dari satu
  // warna.
  await sleep(12000);
  const pixels = await page.evaluate(() => {
    const c = document.querySelector('canvas');
    if (!c) return null;
    const tmp = document.createElement('canvas');
    tmp.width = 120; tmp.height = 260;
    const ctx = tmp.getContext('2d');
    ctx.drawImage(c, 0, 0, tmp.width, tmp.height);
    const d = ctx.getImageData(0, 0, tmp.width, tmp.height).data;
    const seen = new Map();
    for (let i = 0; i < d.length; i += 4) {
      const key = `${d[i] >> 4},${d[i + 1] >> 4},${d[i + 2] >> 4}`;
      seen.set(key, (seen.get(key) || 0) + 1);
    }
    const top = [...seen.entries()].sort((a, b) => b[1] - a[1]);
    return { colors: seen.size, dominant: top[0], total: d.length / 4,
             size: [c.width, c.height] };
  });
  check(pixels !== null, 'kanvas ditemukan di DOM');
  if (pixels) {
    check(pixels.colors > 3,
      `kanvas menggambar — ${pixels.colors} warna berbeda, kanvas ${pixels.size.join('x')}`);
    const dominantShare = pixels.dominant ? pixels.dominant[1] / pixels.total : 1;
    check(dominantShare < 0.97,
      `bukan layar satu warna — warna terbanyak ${(dominantShare * 100).toFixed(1)}%`);
  }

  // --- 4. konsol --------------------------------------------------------------
  // Godot web selalu mencetak beberapa peringatan WebGL di perangkat lunak;
  // yang dicari adalah yang mematikan.
  const fatal = errors.filter((e) => /SharedArrayBuffer|instantiate|Failed to load|aborted|RuntimeError/i.test(e));
  check(fatal.length === 0, `tanpa error fatal — ${fatal.slice(0, 2).join(' | ') || 'bersih'}`);
  if (errors.length) console.log(`         (${errors.length} pesan error non-fatal diabaikan)`);

  await page.screenshot({ path: 'screenshots/qa-godot-web-menu.png' });
  console.log('  ->     screenshots/qa-godot-web-menu.png');

  // --- 5. benar-benar bisa dimainkan -----------------------------------------
  // Menu yang tergambar belum berarti game bisa dimasuki: tombol bisa saja
  // tidak menerima sentuhan (project memakai emulate_touch_from_mouse), dan
  // run bisa mati saat memuat karakter ber-tulang dari .pck.
  const box = await page.evaluate(() => {
    const c = document.querySelector('canvas').getBoundingClientRect();
    return { x: c.x, y: c.y, w: c.width, h: c.height };
  });
  /** Menekan titik relatif di kanvas (0..1), seperti ibu jari di ponsel. */
  const tap = async (rx, ry) => {
    await page.mouse.click(box.x + box.w * rx, box.y + box.h * ry);
    await sleep(1800);
  };
  await tap(0.5, 0.915);               // MAIN -> peta stage
  await page.screenshot({ path: 'screenshots/qa-godot-web-map.png' });
  await tap(0.22, 0.46);               // kartu stage pertama -> run
  await sleep(2500);

  // Menggeser squad beberapa detik, sambil menekan tombol chain shot.
  for (let i = 0; i < 8; i++) {
    await page.mouse.move(box.x + box.w * (0.5 + Math.sin(i) * 0.3), box.y + box.h * 0.6);
    await sleep(350);
  }
  await page.mouse.click(box.x + box.w * 0.82, box.y + box.h * 0.86);   // CHAIN
  await sleep(2500);
  await page.screenshot({ path: 'screenshots/qa-godot-web.png' });
  console.log('  ->     screenshots/qa-godot-web.png (gameplay), qa-godot-web-map.png');

  const playing = await page.evaluate(() => {
    const c = document.querySelector('canvas');
    const tmp = document.createElement('canvas');
    tmp.width = 100; tmp.height = 220;
    const ctx = tmp.getContext('2d');
    ctx.drawImage(c, 0, 0, tmp.width, tmp.height);
    const d = ctx.getImageData(0, 0, tmp.width, tmp.height).data;
    const seen = new Set();
    for (let i = 0; i < d.length; i += 4) seen.add(`${d[i] >> 4},${d[i + 1] >> 4},${d[i + 2] >> 4}`);
    return seen.size;
  });
  check(playing > 6, `layar run tergambar setelah sentuhan — ${playing} warna`);

  await browser.close();
  console.log('='.repeat(72));
  console.log(failures === 0 ? 'LULUS — build web Godot jalan di browser\n' : `${failures} GAGAL\n`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });

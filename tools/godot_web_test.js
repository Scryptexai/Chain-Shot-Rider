#!/usr/bin/env node
/**
 * godot_web_test.js — Membuktikan build web Godot benar-benar jalan di browser.
 *
 * Tes headless Godot (smoke.tscn, sim_headless.gd) menjalankan logika tanpa
 * renderer. Build web adalah satu-satunya cara melihat target Godot
 * menggambar sungguhan, dan juga satu-satunya tempat sekelompok bug khas web
 * muncul: wasm gagal di-instantiate, `.pck` tidak terkirim, audio worklet
 * ditolak, atau layar hitam karena WebGL2 tidak tersedia.
 *
 * Yang diperiksa:
 *   - wasm + pck termuat tanpa request gagal
 *   - kanvas punya ukuran > 0 dan isinya bukan satu warna rata (ada gambar)
 *   - tidak ada pageerror
 *
 * Pemakaian:
 *   bash tools/export_web.sh
 *   python3 tools/serve_web.py 8090 &
 *   node tools/godot_web_test.js [url] [detik-tunggu] [--play]
 *
 * `--play` menekan tombol MAIN lewat klik mouse sungguhan di kanvas, lalu
 * memotret arena. Itu satu-satunya cara memastikan karakter KayKit benar-benar
 * tergambar di target Godot, bukan cuma di web renderer three.js.
 */

'use strict';
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');

const ROOT = path.resolve(__dirname, '..');
const URL = process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2] : 'http://localhost:8090/index.html';
// Booting Godot 4 di SwiftShader lambat: wasm 35 MB dikompilasi tanpa
// akselerasi apa pun. 60 detik adalah angka yang terbukti cukup di sandbox ini.
const WAIT = Number(process.argv[3] || 60);
const OUT = path.join(ROOT, 'screenshots');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });
  if (!fs.existsSync(CHROME)) {
    console.error(`\nChromium tidak ada di ${CHROME}. Jalankan: bash tools/setup_chromium.sh\n`);
    process.exit(2);
  }

  const browser = await puppeteer.launch({
    headless: true,
    executablePath: CHROME,
    args: [
      '--no-sandbox', '--disable-setuid-sandbox',
      '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
      // Build nothreads tidak butuh SharedArrayBuffer, tapi memori wasm-nya
      // tetap besar; tanpa ini tab-nya kadang dibunuh di sandbox kecil.
      '--js-flags=--max-old-space-size=2048',
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 480, height: 854, deviceScaleFactor: 1 });

  const logs = [];
  const failed = [];
  page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => logs.push(`[PAGEERROR] ${e.message}`));
  page.on('requestfailed', (r) => {
    const why = (r.failure() && r.failure().errorText) || '?';
    // `index.wasm — ERR_ABORTED` normal: Emscripten memulai fetch streaming,
    // lalu membatalkannya begitu instantiateStreaming selesai memakai body-nya.
    // Mesinnya tetap boot, jadi ini bukan kegagalan.
    if (r.url().endsWith('.wasm') && why === 'net::ERR_ABORTED') return;
    failed.push(`${r.url()} — ${why}`);
  });

  console.log(`\nMembuka ${URL} (menunggu ${WAIT} dtk untuk boot wasm)`);
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await sleep(WAIT * 1000);

  const info = await page.evaluate(() => {
    const c = document.querySelector('canvas');
    if (!c) return { canvas: false };
    const probe = document.createElement('canvas');
    probe.width = c.width; probe.height = c.height;
    const ctx = probe.getContext('2d');
    ctx.drawImage(c, 0, 0);
    const d = ctx.getImageData(0, 0, probe.width, probe.height).data;
    const tally = new Map();
    for (let i = 0; i < d.length; i += 4 * 97) {
      const k = `${d[i]},${d[i + 1]},${d[i + 2]}`;
      tally.set(k, (tally.get(k) || 0) + 1);
    }
    const top = [...tally.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3);
    const total = [...tally.values()].reduce((a, b) => a + b, 0);
    return {
      canvas: true, w: c.width, h: c.height,
      warna: tally.size,
      dominanPct: Math.round((top[0][1] / total) * 100),
      top: top.map(([k, n]) => `${k} (${Math.round((n / total) * 100)}%)`),
    };
  });

  const shot = path.join(OUT, 'godot-web.png');
  await page.screenshot({ path: shot });

  if (process.argv.includes('--play')) {
    // Godot menerima input lewat event pointer di kanvas, jadi klik ini harus
    // mouse sungguhan (bukan dispatch sintetis) agar sampai ke tombol MAIN.
    const box = await page.evaluate(() => {
      const r = document.querySelector('canvas').getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height };
    });
    await page.mouse.click(box.x + box.w * 0.5, box.y + box.h * 0.9);
    await sleep(12000);
    const shot2 = path.join(OUT, 'godot-web-play.png');
    await page.screenshot({ path: shot2 });
    console.log(`Tersimpan ${path.relative(ROOT, shot2)}`);
  }
  await browser.close();

  console.log('\n--- KANVAS ---');
  console.log('  ' + JSON.stringify(info));
  if (failed.length) {
    console.log('\n--- REQUEST GAGAL ---');
    failed.forEach((f) => console.log('  ' + f));
  }
  console.log('\n--- KONSOL (20 terakhir) ---');
  logs.slice(-20).forEach((l) => console.log('  ' + l));
  console.log(`\nTersimpan ${path.relative(ROOT, shot)}`);

  const problems = [];
  if (!info.canvas) problems.push('tidak ada elemen <canvas>');
  if (info.canvas && (info.w < 2 || info.h < 2)) problems.push('kanvas nyaris nol piksel');
  // Satu warna rata = layar hitam/abu, artinya renderer tidak menggambar.
  if (info.canvas && info.warna < 8) problems.push(`kanvas hanya ${info.warna} warna — kemungkinan layar kosong`);
  if (failed.length) problems.push(`${failed.length} request gagal`);
  if (logs.some((l) => l.startsWith('[PAGEERROR]'))) problems.push('ada pageerror');

  if (problems.length) {
    console.log('\nGAGAL — ' + problems.join('; ') + '\n');
    process.exit(1);
  }
  console.log('\nLULUS — build web Godot boot dan menggambar\n');
}

main().catch((e) => { console.error(e); process.exit(1); });

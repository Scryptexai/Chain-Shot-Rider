#!/usr/bin/env node
/**
 * qa_screenshot.js — Membuka game di Chromium sungguhan dan memotretnya.
 *
 * Sebelum ini semua klaim visual saya tidak punya bukti: sandbox tidak punya
 * GPU, jadi renderer WebGL tidak pernah benar-benar dijalankan. Chromium dengan
 * SwiftShader menyediakan WebGL lewat perangkat lunak, sehingga halaman bisa
 * dimuat, error konsol tertangkap, dan hasilnya bisa dipotret.
 *
 * Yang dilaporkan:
 *   - semua pesan konsol dan error halaman (sumber kebenaran kalau layar hitam)
 *   - apakah WebGL benar-benar aktif (R3D_ON) atau jatuh ke Canvas 2D
 *   - piksel non-latar, untuk membuktikan ada yang digambar
 *   - berkas PNG di screenshots/
 *
 * Pemakaian:
 *   python3 -m http.server 8000 &
 *   node tools/qa_screenshot.js [url] [--play]
 */

'use strict';
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

// Chromium tidak bisa diunduh di sandbox ini (CDN Google diblokir), tetapi
// paket npm @sparticuz/chromium membundel binary-nya berikut SwiftShader.
// tools/setup_chromium.sh yang mengekstraknya ke /tmp/chr.
const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');

const ROOT = path.resolve(__dirname, '..');
const URL = process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2] : 'http://localhost:8000/';
const OUT = path.join(ROOT, 'screenshots');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

  if (!fs.existsSync(CHROME)) {
    console.error(`\nChromium tidak ada di ${CHROME}.\nJalankan dulu: bash tools/setup_chromium.sh\n`);
    process.exit(2);
  }
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: CHROME,
    args: [
      '--no-sandbox', '--disable-setuid-sandbox',
      // WebGL lewat perangkat lunak: tanpa ini kanvas benar-benar kosong.
      '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 480, height: 854, deviceScaleFactor: 1 });

  const logs = [];
  page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => logs.push(`[PAGEERROR] ${e.message}`));
  page.on('requestfailed', (r) =>
    logs.push(`[GAGAL MUAT] ${r.url()} — ${r.failure() && r.failure().errorText}`));

  console.log(`\nMembuka ${URL}`);
  await page.goto(URL, { waitUntil: 'networkidle2', timeout: 30000 });
  await sleep(1500);

  // Status renderer diambil dari halaman, bukan diasumsikan.
  const state = await page.evaluate(() => {
    const probe = { webgl: null, r3dOn: null, ready: null, err: null };
    try {
      probe.r3dOn = window.eval('typeof R3D_ON !== "undefined" ? R3D_ON : null');
      probe.ready = window.R3D ? window.R3D.ready : null;
      probe.three = typeof window.THREE !== 'undefined' ? window.THREE.REVISION : null;
      const c = document.createElement('canvas');
      probe.webgl = !!(c.getContext('webgl') || c.getContext('experimental-webgl'));
      probe.cfg = window.eval('typeof CFG !== "undefined" && CFG ? "loaded" : "null"');
      probe.metaVisible = (document.getElementById('meta') || {}).style
        ? document.getElementById('meta').style.display : 'n/a';
      probe.stageRows = document.querySelectorAll('.stageRow').length;
      const g = document.getElementById('webgl-canvas');
      probe.glSize = g ? `${g.width}x${g.height}` : 'n/a';
      const c2 = document.getElementById('c');
      probe.c2Size = c2 ? `${c2.width}x${c2.height}` : 'n/a';
    } catch (e) { probe.err = String(e); }
    return probe;
  });

  console.log('\n--- STATUS HALAMAN ---');
  console.log(`  WebGL tersedia : ${state.webgl}`);
  console.log(`  THREE revision : ${state.three}`);
  console.log(`  R3D_ON         : ${state.r3dOn}   (true = render WebGL, false = fallback 2D)`);
  console.log(`  R3D.ready      : ${state.ready}`);
  console.log(`  Config         : ${state.cfg}`);
  console.log(`  Overlay meta   : ${state.metaVisible}`);
  console.log(`  Baris stage    : ${state.stageRows}`);
  console.log(`  Kanvas WebGL   : ${state.glSize}   (0x0 = layar hitam)`);
  console.log(`  Kanvas 2D      : ${state.c2Size}`);
  if (state.err) console.log(`  probe error    : ${state.err}`);

  console.log('\n--- KONSOL (' + logs.length + ' pesan) ---');
  if (!logs.length) console.log('  (bersih)');
  logs.slice(0, 40).forEach((l) => console.log('  ' + l));

  await page.screenshot({ path: path.join(OUT, 'qa-menu.png') });
  console.log('\nTersimpan screenshots/qa-menu.png');

  // Masuk ke stage 1 lalu biarkan berjalan, supaya arena yang dipotret.
  if (process.argv.includes('--play') || true) {
    const clicked = await page.evaluate(() => {
      const r = document.querySelector('.stageRow:not([disabled])');
      if (!r) return false;
      r.click(); return true;
    });
    console.log(`Klik stage 1: ${clicked}`);
    await sleep(4000);
    await page.screenshot({ path: path.join(OUT, 'qa-gameplay.png') });
    console.log('Tersimpan screenshots/qa-gameplay.png');

    const live = await page.evaluate(() => window.eval(
      '({ state:S.state, tick:S.tick, troops:S.troops, enemies:S.enemies.length,' +
      ' gates:S.gates.length, score:S.score })'));
    console.log('\n--- SIMULASI BERJALAN ---');
    console.log('  ' + JSON.stringify(live));
  }

  // Apakah benar ada yang digambar? Hitung piksel yang bukan latar.
  const px = await page.evaluate(() => {
    const gl = document.getElementById('webgl-canvas');
    const c2 = document.getElementById('c');
    const src = (gl && gl.classList.contains('on')) ? gl : c2;
    if (!src) return { err: 'kanvas tidak ditemukan' };
    const tmp = document.createElement('canvas');
    tmp.width = 160; tmp.height = 284;
    const g = tmp.getContext('2d');
    g.drawImage(src, 0, 0, tmp.width, tmp.height);
    const d = g.getImageData(0, 0, tmp.width, tmp.height).data;
    let nonEmpty = 0, total = tmp.width * tmp.height;
    const hist = {};
    for (let i = 0; i < d.length; i += 4) {
      const key = `${d[i] >> 5},${d[i + 1] >> 5},${d[i + 2] >> 5}`;
      hist[key] = (hist[key] || 0) + 1;
      if (d[i] + d[i + 1] + d[i + 2] > 40) nonEmpty++;
    }
    const top = Object.entries(hist).sort((a, b) => b[1] - a[1]).slice(0, 4);
    return { source: src.id, nonEmptyPct: Math.round(nonEmpty / total * 100), top };
  });
  console.log('\n--- ISI KANVAS ---');
  console.log('  ' + JSON.stringify(px));

  await browser.close();
  console.log('');
}

main().catch((e) => { console.error('qa_screenshot gagal:', e); process.exit(1); });

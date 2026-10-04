#!/usr/bin/env node
/**
 * perf_probe.js — Mengukur beban renderer sungguhan, bukan menghitungnya di
 * atas kertas.
 *
 * Anggaran draw call di docs/08 dulu ditulis dari penalaran ("satu material
 * per aktor, jadi satu draw call"). Penalaran itu benar sampai karakter
 * dipakai apa adanya dari pack KayKit, yang membawa sembilan mesh per tubuh.
 * Daripada menebak angka barunya, skrip ini membuka game di Chromium, memainkan
 * satu stage sampai ramai, lalu membaca `renderer.info` tiap detik dan
 * melaporkan puncaknya.
 *
 * Pemakaian:
 *   python3 -m http.server 8111 &
 *   bash tools/setup_chromium.sh            # sekali per mesin
 *   node tools/perf_probe.js [url] [detik]
 */

'use strict';
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');

const URL = process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2] : 'http://localhost:8111/index.html';
const SECONDS = Number(process.argv[3]) || 40;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
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
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 480, height: 854, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e.message)));

  console.log(`\nMembuka ${URL}`);
  await page.goto(URL, { waitUntil: 'networkidle2', timeout: 60000 });
  await sleep(2500);

  const started = await page.evaluate(() => {
    const r = document.querySelector('.stageRow:not([disabled])');
    if (!r) return false;
    r.click();
    return true;
  });
  if (!started) { console.error('Tidak bisa memulai stage.'); process.exit(1); }

  const samples = [];
  for (let i = 0; i < SECONDS; i++) {
    await sleep(1000);
    const s = await page.evaluate(() => {
      const info = window.R3D && window.R3D._info ? window.R3D._info() : null;
      if (!info) return null;
      const live = window.eval('({ tick:S.tick, state:S.state, troops:S.troops,'
        + ' enemies:S.enemies.length, boss: !!S.boss })');
      const actors = window.R3D._actors ? window.R3D._actors().length : 0;
      return Object.assign(info, live, { actors: actors, corpses: window.R3D._corpses() });
    });
    if (s) samples.push(s);
  }
  await browser.close();

  if (!samples.length) { console.error('Tidak ada sampel — renderer WebGL tidak aktif?'); process.exit(1); }

  const peak = (k) => samples.reduce((a, s) => Math.max(a, s[k] || 0), 0);
  const at = samples.reduce((a, s) => (s.calls > a.calls ? s : a), samples[0]);

  console.log('\n--- PUNCAK TERUKUR (' + samples.length + ' sampel, 1 Hz) ---');
  console.log(`  draw call      : ${peak('calls')}`);
  console.log(`  segitiga       : ${peak('triangles').toLocaleString('en-US')}`);
  console.log(`  geometri       : ${peak('geometries')}`);
  console.log(`  tekstur        : ${peak('textures')}`);
  console.log(`  program shader : ${peak('programs')}`);
  console.log(`  aktor skinned  : ${peak('actors')}   mayat: ${peak('corpses')}`);
  console.log(`  musuh di sim   : ${peak('enemies')}  pasukan: ${peak('troops')}`);
  console.log('\n  Saat draw call puncak: ' + JSON.stringify({
    calls: at.calls, actors: at.actors, enemies: at.enemies,
    troops: at.troops, boss: at.boss, tick: at.tick,
  }));
  if (errors.length) {
    console.log('\n--- ERROR HALAMAN ---');
    errors.slice(0, 10).forEach((e) => console.log('  ' + e));
  }
  console.log('');
}

main().catch((e) => { console.error('perf_probe gagal:', e); process.exit(1); });

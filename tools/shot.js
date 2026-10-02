#!/usr/bin/env node
/**
 * shot.js — QA visual untuk prototipe web: memuat game di Chromium sungguhan
 * dan menyimpan PNG, supaya setiap klaim tentang layout punya gambar di
 * belakangnya. Sandbox ini tidak punya GPU, jadi WebGL dijalankan lewat
 * SwiftShader — lambat, tapi pikselnya nyata.
 *
 * Dua mode:
 *
 *   node tools/shot.js [url] [prefix]
 *       Memotret menu dan permainan pada empat ukuran viewport (ponsel,
 *       ponsel jangkung, desktop lanskap, dan layar persegi). Ini yang
 *       membuktikan bingkai 9:16 bertahan di luar ukuran yang didesain.
 *
 *   node tools/shot.js --states [url]
 *       Menyusuri tujuh keadaan UI pada satu ponsel 390x844: markas, tab
 *       squad, tab setup, permainan, jeda, hasil, dan draft kartu. Satu layar
 *       bisa benar sendirian dan tetap salah sebagai rangkaian — toast yang
 *       menutupi spawn musuh hanya terlihat kalau layar mainnya dipotret
 *       setelah run benar-benar berjalan beberapa detik.
 *
 * Prasyarat: `bash tools/setup_chromium.sh` dan sebuah server di URL tujuan
 * (`python3 -m http.server 8000`).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const CHROME = process.env.CHROME_BIN || '/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');

const ARGS = process.argv.slice(2);
const STATES = ARGS.includes('--states');
const REST = ARGS.filter((a) => !a.startsWith('--'));
const URL = REST[0] || 'http://localhost:8000/';
const PREFIX = REST[1] || 'shot';
const OUT = path.resolve(__dirname, '..', 'screenshots', 'wip');

// Empat ukuran, dipilih karena masing-masing mematahkan asumsi yang berbeda:
// 390x844 iPhone 14 (19.5:9), 412x915 Android jangkung (20:9), 1440x900
// desktop lanskap, dan 900x900 persegi — bentuk yang tidak pernah ada di
// ponsel tapi langsung memperlihatkan bingkai yang tidak terkunci.
const SIZES = [
  ['phone', 390, 844],
  ['tall', 412, 915],
  ['desktop', 1440, 900],
  ['square', 900, 900],
];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function launch() {
  return puppeteer.launch({
    headless: true,
    executablePath: CHROME,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--use-gl=angle',
      '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
}

function watch(page, errors) {
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
}

/** Menu dan permainan pada setiap ukuran viewport. */
async function shootSizes(browser) {
  for (const [name, w, h] of SIZES) {
    const page = await browser.newPage();
    const errors = [];
    watch(page, errors);
    await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
    await page.goto(URL, { waitUntil: 'networkidle2' });
    await sleep(1800);
    await page.screenshot({ path: path.join(OUT, `${PREFIX}-${name}-menu.png`) });
    await page.evaluate(() => {
      const btn = document.querySelector('[data-qa="play"]')
        || Array.from(document.querySelectorAll('button')).find((b) => /PLAY|MULAI|MAIN/i.test(b.textContent));
      if (btn) btn.click();
    });
    await sleep(2500);
    await page.mouse.move(w * 0.5, h * 0.8);
    await sleep(1500);
    await page.screenshot({ path: path.join(OUT, `${PREFIX}-${name}-play.png`) });
    if (errors.length) console.log(`[${name}] errors:`, errors.slice(0, 6));
    await page.close();
  }
}

/** Tujuh keadaan UI berurutan pada satu ponsel. */
async function shootStates(browser) {
  const page = await browser.newPage();
  const errors = [];
  watch(page, errors);
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1 });
  await page.goto(URL, { waitUntil: 'networkidle2' });
  await sleep(1500);

  // Profil palsu dengan progres nyata: markas kosong tidak memperlihatkan
  // badge CLEARED, bintang, maupun rail yang tergulir.
  await page.evaluate(() => {
    META.unlocked = 4;
    META.cards = ['fire_rate', 'chain_bounces'];
    META.best = 48210;
    showMap();
  });
  await sleep(600);
  await page.screenshot({ path: path.join(OUT, 'state-home.png') });

  await page.evaluate(() => document.querySelectorAll('.tab')[1].click());
  await sleep(400);
  await page.screenshot({ path: path.join(OUT, 'state-squad.png') });

  await page.evaluate(() => document.querySelectorAll('.tab')[2].click());
  await sleep(400);
  await page.screenshot({ path: path.join(OUT, 'state-setup.png') });

  // Stage 3: tema arena yang berbeda dari stage 1, jadi pergantian tema HUD
  // ikut terbukti. Dua setengah detik agar gelombang pertama sudah di layar.
  await page.evaluate(() => startStage(2));
  await sleep(2500);
  await page.screenshot({ path: path.join(OUT, 'state-play.png') });

  await page.evaluate(() => showPause());
  await sleep(500);
  await page.screenshot({ path: path.join(OUT, 'state-pause.png') });

  await page.evaluate(() => {
    resumeRun();
    S.score = 48210;
    S.kills = 388;
    S.bestCombo = 61;
    S.coins = 120;
    showResult(true);
  });
  await sleep(1200);
  await page.screenshot({ path: path.join(OUT, 'state-result.png') });

  await page.evaluate(() => showCards(2));
  await sleep(500);
  await page.screenshot({ path: path.join(OUT, 'state-cards.png') });

  if (errors.length) console.log('errors:', errors.slice(0, 6));
  await page.close();
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await launch();
  if (STATES) await shootStates(browser);
  else await shootSizes(browser);
  await browser.close();
  console.log('saved to', OUT);
}
main().catch((e) => { console.error(e); process.exit(1); });

/**
 * Potret adegan untuk menilai ARAH VISUAL, bukan untuk membuktikan game jalan.
 *
 * qa_screenshot.js memotret empat detik setelah stage dimulai: overlay tutorial
 * masih menutupi lorong dan musuh belum sampai. Untuk menilai apakah dunianya
 * terbaca sebagai mainan plastik atau sebagai arena neon, yang dibutuhkan
 * adalah adegan yang penuh — musuh dekat, peluru hidup, dinding kena.
 *
 *   node tools/look_audit.js [detik] [nama]
 */
const path = require('path');
const fs = require('fs');
const puppeteer = require('puppeteer-core');

// Binary @sparticuz membawa pustakanya sendiri; tanpa ini Chromium gagal
// memuat libnspr4.
process.env.LD_LIBRARY_PATH = '/tmp/chr/lib:' + (process.env.LD_LIBRARY_PATH || '');

const SECONDS = Number(process.argv[2] || 16);
const NAME = process.argv[3] || 'look';
const OUT = path.join(__dirname, '..', 'screenshots');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await puppeteer.launch({
    executablePath: '/tmp/chr/chromium',
    headless: true,
    args: [
      '--no-sandbox', '--disable-setuid-sandbox',
      '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
    ],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 480, height: 854, deviceScaleFactor: 2 });
  await page.goto('http://localhost:8000/', { waitUntil: 'networkidle2' });
  await sleep(2500);
  await page.evaluate(() => {
    const r = document.querySelector('.stageRow:not([disabled])');
    if (r) r.click();
  });
  await sleep(1200);

  // Buang overlay tutorial, lalu tembak terus supaya ada peluru, pantulan,
  // dan ledakan di layar saat dipotret.
  const canvas = { x: 240, y: 600 };
  for (let i = 0; i < Math.max(1, SECONDS - 2); i++) {
    await page.mouse.click(canvas.x + (i % 5 - 2) * 40, canvas.y);
    await sleep(1000);
  }
  await page.screenshot({ path: path.join(OUT, `${NAME}.png`) });
  const live = await page.evaluate(() => window.eval(
    '({ state:S.state, tick:S.tick, enemies:S.enemies.length, score:S.score })'));
  console.log(JSON.stringify(live), '->', `screenshots/${NAME}.png`);
  await browser.close();
})();

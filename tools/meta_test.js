#!/usr/bin/env node
/**
 * meta_test.js — Uji DOM untuk lapisan meta CHAIN RIDER (peta stage + kartu).
 *
 * sim_test.js menguji simulasi tempur dengan DOM yang distub habis, sehingga
 * layar meta sengaja dilewati (UI_READY tetap false di sana). File ini menutup
 * celah itu: memuat index.html di dalam jsdom — DOM sungguhan, event
 * klik sungguhan, localStorage sungguhan — lalu menelusuri alur kampanye:
 *
 *   peta 15 stage -> main stage 1 -> menang -> draft 3 kartu -> pilih kartu
 *   -> stage 2 terbuka -> kartu benar-benar mengubah parameter simulasi
 *   -> progres bertahan setelah halaman dimuat ulang
 *
 * Yang TIDAK diuji di sini: piksel. Tanpa GPU di sandbox, kanvas distub; klaim
 * visual harus dibuktikan di browser sungguhan.
 *
 * Pemakaian: npm install --no-save jsdom && node tools/meta_test.js
 */

'use strict';
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'index.html');
const CONFIG = path.join(ROOT, 'Config/arena_config.json');

let failures = 0;
let checks = 0;

function check(label, cond, detail) {
  checks++;
  if (cond) {
    console.log(`  OK   ${label}${detail ? '  — ' + detail : ''}`);
  } else {
    failures++;
    console.log(`  GAGAL ${label}${detail ? '  — ' + detail : ''}`);
  }
}

/**
 * Membuka prototipe di jsdom.
 *
 * Catatan jujur: jsdom memberi localStorage TERPISAH untuk tiap instance, jadi
 * "muat ulang halaman" tidak otomatis mewarisi simpanan seperti di browser.
 * Agar uji reload tetap sahih, isi storage dari sesi sebelumnya disemai di sini
 * sebelum skrip jalan — persis seperti browser menyerahkan storage origin yang
 * sama ke halaman yang baru dimuat. Yang dibuktikan tetap hal yang penting:
 * halaman mampu MEMBACA KEMBALI apa yang tadi ia TULIS sendiri.
 */
function openPage(seedStorage) {
  const html = fs.readFileSync(HTML, 'utf8');
  const cfgText = fs.readFileSync(CONFIG, 'utf8');

  const dom = new JSDOM(html, {
    url: 'http://localhost/',
    runScripts: 'dangerously',
    beforeParse(window) {
      if (seedStorage) {
        for (const [k, v] of Object.entries(seedStorage)) window.localStorage.setItem(k, v);
      }
      // Config dilayani dari memori, bukan jaringan.
      window.fetch = () => Promise.resolve({
        json: () => Promise.resolve(JSON.parse(cfgText)),
      });
      // Tidak ada GPU: matikan loop render, simulasi digerakkan manual oleh tes.
      window.requestAnimationFrame = () => 0;
      window.cancelAnimationFrame = () => {};
      const ctx = new Proxy({}, {
        get: (t, k) => (k === 'createLinearGradient' || k === 'createRadialGradient')
          ? () => ({ addColorStop() {} })
          : () => {},
        set: () => true,
      });
      window.HTMLCanvasElement.prototype.getContext = () => ctx;
      const audioStub = function () {
        return new Proxy({}, { get: () => () => ({ connect() {}, start() {}, stop() {} }) });
      };
      window.AudioContext = audioStub;
      window.webkitAudioContext = audioStub;
    },
  });
  return dom;
}

/** Menunggu sampai boot (fetch config) selesai dan peta tampil. */
function waitForBoot(dom) {
  return new Promise((resolve, reject) => {
    const t0 = Date.now();
    const poll = () => {
      const meta = dom.window.document.getElementById('meta');
      if (meta && meta.style.display === 'flex') return resolve();
      if (Date.now() - t0 > 5000) return reject(new Error('boot tidak selesai dalam 5 s'));
      setTimeout(poll, 10);
    };
    poll();
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Prototipe memakai `let`/`const` di tingkat atas skrip klasik, sehingga
 * variabelnya hidup di script scope dan TIDAK menempel di window. Satu eval
 * ini membuka getter hidup ke state yang sama yang dipakai halaman.
 */
function bind(win) {
  return win.eval(`({
    get S(){ return S; }, get CFG(){ return CFG; }, get META(){ return META; },
    simulate, startStage, endRun, showMap, variantForStage
  })`);
}

async function main() {
  console.log('\nCHAIN RIDER — uji lapisan meta di DOM (jsdom)');
  console.log('='.repeat(78));

  // -------------------------------------------------------------------------
  console.log('\n[1] Boot bersih dan peta stage terbentuk');
  const dom = openPage();
  const win = dom.window;
  const doc = win.document;
  const G = bind(win);
  const errors = [];
  win.addEventListener('error', (e) => errors.push(e.message || String(e.error)));
  await waitForBoot(dom);

  const meta = doc.getElementById('meta');
  const rows = doc.querySelectorAll('.stageRow');
  const total = G.CFG.meta.stageCount;
  check('tidak ada error JS saat boot', errors.length === 0, errors.join(' | ') || 'bersih');
  check('overlay peta tampil', meta.style.display === 'flex');
  check(`jumlah baris stage = ${total}`, rows.length === total, `terbaca ${rows.length}`);
  check('stage 1 bisa dimainkan', !rows[0].disabled && /PLAY/.test(rows[0].textContent));
  check('stage 2 terkunci di awal', rows[1].disabled && /LOCKED/.test(rows[1].textContent));
  check('stage 15 terkunci di awal', rows[total - 1].disabled);
  check('simulasi tidak jalan di balik menu', G.S.state === 'menu', `state=${G.S.state}`);

  // Varian tiap stage mengikuti variantCycle dari config, bukan angka karangan.
  const cyc = G.CFG.meta.variantCycle;
  const expectName = G.CFG.variants[cyc[4 % cyc.length]].name;
  check('stage 5 memakai varian sesuai variantCycle',
    rows[4].textContent.includes(expectName), `menampilkan "${expectName}"`);

  // -------------------------------------------------------------------------
  console.log('\n[2] Mulai stage 1 dari peta');
  rows[0].click();
  check('overlay tertutup saat main', meta.style.display === 'none');
  check('state kembali playing', G.S.state === 'playing', `state=${G.S.state}`);
  check('stage aktif = 0', G.S.stage === 0);
  check('difficulty stage 1 = 1.00', Math.abs(G.S.diff - 1) < 1e-9, `diff=${G.S.diff}`);
  const baseTroops = G.S.troops;
  check('pasukan awal = startTroops config (belum ada kartu)',
    baseTroops === G.CFG.squad.startTroops, `troops=${baseTroops}`);

  // Simulasi benar-benar melangkah (bukan layar beku).
  const tickBefore = G.S.tick;
  for (let i = 0; i < 120; i++) G.simulate(1 / 60);
  check('simulasi melangkah 120 tick', G.S.tick - tickBefore === 120,
    `tick ${tickBefore} -> ${G.S.tick}`);

  // -------------------------------------------------------------------------
  console.log('\n[3] Menang -> draft kartu muncul');
  G.endRun(true);
  await sleep(1800);                       // endRun menunda layar 1,6 s
  const cards = doc.querySelectorAll('.upCard');
  const want = G.CFG.meta.cardsOffered;
  check(`draft menawarkan ${want} kartu`, cards.length === want, `tampil ${cards.length}`);
  const names = Array.from(cards).map((c) => c.querySelector('span').textContent);
  check('nama kartu diambil dari config', names.every((n) => n && n.length > 0), names.join(' / '));
  check('tidak ada kartu kembar dalam satu draft', new Set(names).size === names.length);

  // -------------------------------------------------------------------------
  console.log('\n[4] Pilih kartu -> tersimpan & stage 2 terbuka');
  const pickedId = cards[0].dataset.id;
  const pickedCard = G.CFG.meta.cards.find((c) => c.id === pickedId);
  cards[0].click();
  check('kartu masuk ke simpanan', G.META.cards.includes(pickedId), `dipilih "${pickedId}"`);
  const saved = JSON.parse(win.localStorage.getItem('chainrider.meta.v1'));
  check('progres ditulis ke localStorage', !!saved && saved.cards.includes(pickedId));
  check('stage 2 terbuka setelah menang', saved.unlocked >= 1, `unlocked=${saved.unlocked}`);
  const rows2 = doc.querySelectorAll('.stageRow');
  check('peta menandai stage 1 CLEARED', /CLEARED/.test(rows2[0].textContent));
  check('peta membuka stage 2', !rows2[1].disabled && /PLAY/.test(rows2[1].textContent));

  // -------------------------------------------------------------------------
  console.log('\n[5] Kartu benar-benar mengubah simulasi (bukan hiasan)');
  rows2[1].click();                        // main stage 2
  check('stage aktif = 1', G.S.stage === 1);
  const expectDiff = 1 + G.CFG.meta.difficultyPerStage * 1;
  check('difficulty naik di stage 2', Math.abs(G.S.diff - expectDiff) < 1e-9,
    `diff=${G.S.diff.toFixed(2)} (harap ${expectDiff.toFixed(2)})`);

  const stat = pickedCard.stat;
  const applied = G.S.upg[stat];
  const expected = pickedCard.mul !== undefined ? pickedCard.mul : pickedCard.add;
  check(`stat "${stat}" aktif di S.upg`, Math.abs(applied - expected) < 1e-9,
    `nilai=${applied} (harap ${expected})`);

  // Efek yang bisa diukur langsung tanpa menebak jalur internal.
  if (stat === 'startTroops') {
    check('pasukan awal bertambah sesuai kartu',
      G.S.troops === G.CFG.squad.startTroops + pickedCard.add,
      `troops=${G.S.troops}`);
  }

  // Pembanding adil: stat yang TIDAK dimiliki harus tetap netral.
  const unowned = G.CFG.meta.cards.find((c) => c.stat !== stat);
  check(`stat tak dimiliki ("${unowned.stat}") tetap netral`,
    G.S.upg[unowned.stat] === undefined);

  // -------------------------------------------------------------------------
  console.log('\n[6] Determinisme tetap terjaga setelah lapisan meta');
  const snap = (n) => {
    G.startStage(1);
    for (let i = 0; i < n; i++) G.simulate(1 / 60);
    return `${G.S.score}|${G.S.kills}|${G.S.troops}|${G.S.enemies.length}|` +
           `${G.S.squadX.toFixed(6)}`;
  };
  const a = snap(900);
  const b = snap(900);
  check('stage sama + input sama -> hasil identik', a === b, a);
  G.startStage(0);
  for (let i = 0; i < 900; i++) G.simulate(1 / 60);
  const other = `${G.S.score}|${G.S.kills}|${G.S.troops}|${G.S.enemies.length}|` +
                `${G.S.squadX.toFixed(6)}`;
  check('stage berbeda -> aliran berbeda', other !== a, `stage1=${other}`);

  // -------------------------------------------------------------------------
  console.log('\n[7] Progres bertahan setelah halaman dimuat ulang');
  // Simpanan diambil apa adanya dari sesi pertama — tidak dirakit tangan.
  const KEY = 'chainrider.meta.v1';
  const carried = { [KEY]: win.localStorage.getItem(KEY) };
  check('ada simpanan yang dibawa ke sesi berikutnya', !!carried[KEY], carried[KEY]);
  const dom2 = openPage(carried);
  await waitForBoot(dom2);
  const win2 = dom2.window;
  const G2 = bind(win2);
  check('kartu terbaca lagi setelah reload',
    G2.META.cards.includes(pickedId), `cards=[${G2.META.cards.join(', ')}]`);
  check('stage terbuka terbaca lagi', G2.META.unlocked >= 1, `unlocked=${G2.META.unlocked}`);
  const rows3 = dom2.window.document.querySelectorAll('.stageRow');
  check('peta hasil reload menampilkan stage 2 terbuka', !rows3[1].disabled);

  // ---------------------------------------------------------------------
  console.log('\n[8] Meteran volume: balok, bukan slider');
  const doc2 = dom2.window.document;
  doc2.querySelector('.tab[data-tab="setup"]').click();
  check('tidak ada slider di layar setup',
    doc2.querySelectorAll('input[type="range"]').length === 0);
  const cells = doc2.querySelectorAll('.volCell');
  check('volume dikendalikan deret balok', cells.length === 6, `${cells.length} balok`);
  cells[0].click();
  check('balok OFF membuat volume benar-benar nol', G2.META.volume === 0,
    `volume=${G2.META.volume}`);
  check('balok OFF ditandai mute', cells[0].classList.contains('mute'));
  cells[5].click();
  check('balok teratas mengembalikan volume penuh', G2.META.volume === 1,
    `volume=${G2.META.volume}`);
  check('balok teratas menyala', cells[5].classList.contains('on'));

  // ---------------------------------------------------------------------
  console.log('\n[9] Kartu medan: terkunci sampai ada stage yang memakainya');
  doc2.querySelector('.tab[data-tab="arena"]').click();
  const arenaCards = doc2.querySelectorAll('.vbtn');
  check('satu kartu per arena', arenaCards.length === G2.CFG.variants.length,
    `${arenaCards.length} kartu`);
  const openArenas = [...arenaCards].filter((c) => !c.disabled);
  check('progres awal hanya membuka sebagian medan',
    openArenas.length >= 1 && openArenas.length < arenaCards.length,
    `${openArenas.length} dari ${arenaCards.length} terbuka`);
  const wanted = Math.max(...[...Array(G2.META.unlocked + 1).keys()]
    .filter((st) => G2.variantForStage(st) === +openArenas[0].dataset.i));
  check('kartu medan menunjuk stage terbaru yang memakainya',
    +openArenas[0].dataset.stage === wanted,
    `stage=${openArenas[0].dataset.stage}, terbaru=${wanted}`);

  // ---------------------------------------------------------------------
  console.log('\n[10] Hapus progres harus ditahan, bukan diklik');
  doc2.querySelector('.tab[data-tab="setup"]').click();
  const press = () => doc2.getElementById('mapReset')
    .dispatchEvent(new dom2.window.Event('pointerdown', { bubbles: true }));
  const release = () => doc2.getElementById('mapReset')
    .dispatchEvent(new dom2.window.Event('pointerup', { bubbles: true }));
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  press();
  await wait(250);
  release();
  await wait(1300);
  check('lepas cepat tidak menghapus apa pun', G2.META.cards.length === 1,
    `cards=[${G2.META.cards.join(', ')}]`);

  press();
  await wait(1500);
  check('tahan penuh mengosongkan kartu', G2.META.cards.length === 0);
  check('tahan penuh mengunci lagi stage 2',
    doc2.querySelectorAll('.stageRow')[1].disabled);
  check('hapus progres tidak ikut mereset volume', G2.META.volume === 1,
    `volume=${G2.META.volume}`);

  dom.window.close();
  dom2.window.close();

  console.log('\n' + '='.repeat(78));
  console.log(failures === 0
    ? `LULUS — ${checks} pemeriksaan, 0 gagal`
    : `GAGAL — ${failures} dari ${checks} pemeriksaan gagal`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('\nUji meta error:', err);
  process.exit(1);
});

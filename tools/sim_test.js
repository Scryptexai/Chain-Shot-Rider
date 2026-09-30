#!/usr/bin/env node
/**
 * sim_test.js — Harness simulasi headless untuk CHAIN RIDER.
 *
 * Memuat logika gameplay langsung dari prototype/index.html (satu sumber
 * kebenaran — tidak ada duplikasi aturan), menstub DOM/Canvas/WebAudio, lalu
 * menjalankan run penuh dengan BOT agar balance bisa diukur, bukan ditebak.
 *
 * Dipakai untuk:
 *   - balance pass   : berapa lama satu run, berapa musuh bocor, winnable?
 *   - regression     : tunneling peluru, speed cap, bounce overflow
 *   - determinisme   : seed + input sama -> hasil identik (docs/09 §B)
 *
 * Pemakaian:
 *   node tools/sim_test.js                 # semua varian, bot standar
 *   node tools/sim_test.js --bot=skilled   # bot mahir (steer ke crowd terpadat)
 *   node tools/sim_test.js --determinism   # hanya uji determinisme
 *   node tools/sim_test.js --variant=2
 */

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FIXED_DT = 1 / 60;

// ---------------------------------------------------------------------------
// STUB LINGKUNGAN BROWSER
// ---------------------------------------------------------------------------
function makeEnv() {
  const noop = () => {};
  const mkEl = () => new Proxy(
    { style: {}, classList: { toggle: noop, add: noop, remove: noop },
      textContent: '', innerHTML: '', dataset: {},
      getBoundingClientRect: () => ({ width: 450, height: 800 }) },
    { get(t, k) { return k in t ? t[k] : noop; }, set(t, k, v) { t[k] = v; return true; } });

  const ctx = new Proxy({}, {
    get: (t, k) => (k === 'createLinearGradient' || k === 'createRadialGradient')
      ? () => ({ addColorStop: noop })
      : noop,
    set: () => true,
  });
  const canvas = mkEl();
  canvas.getContext = () => ctx;

  function FakeAudioCtx() {
    this.currentTime = 0;
    this.destination = {};
    this.createGain = () => ({
      gain: { value: 0, setValueAtTime: noop, exponentialRampToValueAtTime: noop },
      connect: noop });
    this.createOscillator = () => ({
      type: '', frequency: { setValueAtTime: noop, exponentialRampToValueAtTime: noop },
      connect: noop, start: noop, stop: noop });
  }

  // documentElement carries the CSS custom properties the theme writes to.
  // Recorded rather than discarded so a test can assert on the palette.
  const cssVars = {};
  global.document = { getElementById: id => (id === 'c' ? canvas : mkEl()),
                      querySelectorAll: () => [], body: mkEl(),
                      documentElement: { style: {
                        setProperty: (k, v) => { cssVars[k] = v; },
                        getPropertyValue: k => cssVars[k] ?? '' } } };
  global.__cssVars = cssVars;
  global.window = { addEventListener: noop, devicePixelRatio: 1, AudioContext: FakeAudioCtx };
  global.requestAnimationFrame = noop;
  global.performance = { now: () => Date.now() };
  // Chain explosion dijalankan langsung supaya deterministik di harness.
  global.setTimeout = fn => fn();
}

// ---------------------------------------------------------------------------
// MEMUAT LOGIKA DARI PROTOTIPE
// ---------------------------------------------------------------------------
function loadGame() {
  const html = fs.readFileSync(path.join(ROOT, 'prototype/index.html'), 'utf8');
  let code = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  code = code.replace(/fetch\('\.\.\/Config[\s\S]*$/, '');   // buang boot browser
  code += `
    CFG = JSON.parse(require('fs').readFileSync(${JSON.stringify(path.join(ROOT, 'Config/arena_config.json'))}, 'utf8'));
    module.exports = { get S(){return S;}, CFG, loadVariant, resetRun, simulate,
                       fire, queueSteer, queueAim, draw, predictAimPath };
  `;
  makeEnv();
  const mod = { exports: {} };
  // eslint-disable-next-line no-new-func
  new Function('module', 'require', code)(mod, require);
  return mod.exports;
}

// ---------------------------------------------------------------------------
// BOT
// ---------------------------------------------------------------------------

/** Bot acak — baseline pesimis. */
function botRandom(G, t) {
  if (t % 40 === 0) G.fire();
  if (t % 7 === 0) G.queueSteer(Math.sin(t) * 0.8);
}

/**
 * Bot mahir — meniru pemain kompeten:
 *   - menembak saat ada musuh di depan dan amunisi tersedia
 *   - saat bullet-riding, membelokkan peluru menuju kolom crowd terpadat
 *   - memprioritaskan musuh yang paling dekat garis pertahanan
 */
function botSkilled(G, t) {
  const S = G.S, CFG = G.CFG;

  // Mode manual: sudut dikuasai pemain, jadi bot menggeser bidikan sendiri.
  // Tanpa cabang ini bot tidak pernah membidik dan seluruh angka regresi palsu.
  if (CFG.aim.mode === 'manual') return botSkilledManual(G, t);

  // --- menembak: tunggu sampai turret mengarah ke pusat massa crowd ---
  const riding = S.bullets.find(b => b.riding && b.alive);
  if (!riding && S.ammo > 0 && S.enemies.length > 0) {
    let cx = 0, cz = 0, w = 0;
    for (const e of S.enemies) {
      const urgency = 1 + Math.max(0, (25 - e.z) / 25);   // yang dekat garis lebih penting
      cx += e.x * urgency; cz += e.z * urgency; w += urgency;
    }
    cx /= w; cz /= w;
    const px = CFG.arena.playerSpawn.x, pz = CFG.arena.playerSpawn.z;
    const desired = Math.atan2(cx - px, Math.max(1, cz - pz)) * 180 / Math.PI;
    if (Math.abs(S.aimAngle - desired) < 5) G.fire();
  }

  if (!riding || riding.steer <= 0) return;

  // --- steering: cari pusat massa crowd di depan peluru ---
  let sx = 0, w = 0;
  for (const e of S.enemies) {
    const dz = e.z - riding.z;
    if (dz < -1 || dz > 14) continue;                 // hanya yang di depan
    const urgency = 1 + Math.max(0, (20 - e.z) / 20); // makin dekat garis, makin penting
    sx += e.x * urgency; w += urgency;
  }
  if (w === 0) return;

  const targetX = sx / w;
  const err = targetX - riding.x;
  // Arah peluru saat ini dalam derajat terhadap +Z
  const want = Math.atan2(err, Math.max(2, 8)) * 180 / Math.PI;
  const cur = Math.atan2(riding.dx, riding.dz) * 180 / Math.PI;
  const delta = Math.max(-1, Math.min(1, (want - cur) / CFG.bullet.steerAnglePerSwipe));
  G.queueSteer(delta);
}

/**
 * Bot untuk mode bidik manual: menggeser ke pusat massa crowd dengan laju jempol
 * terbatas (300 deg/s) lalu menembak setiap amunisi siap. Perbandingan penuh
 * antar kebijakan ada di tools/aim_ab.js + docs/12.
 */
const MANUAL_DRAG_DEG_PER_SEC = 300;
const MANUAL_PRESS_OVERHEAD = 0.12;
let _manualCooldown = 0;
/**
 * Bot menyimpan state antar tick (cooldown jempol). State itu HARUS direset di
 * awal tiap run, kalau tidak run kedua mulai dengan sisa state run pertama dan
 * uji determinisme gagal karena harness-nya, bukan karena simulasinya.
 */
function resetBots() { _manualCooldown = 0; _laneCd = 0; _laneTarget = 0; _laneRepick = 0; }
function botSkilledManual(G, t) {
  const S = G.S, CFG = G.CFG;

  const riding = S.bullets.find(b => b.riding && b.alive);
  if (riding) { botSteerOnly(G); return; }
  if (S.enemies.length === 0) return;

  let cx = 0, cz = 0, w = 0;
  for (const e of S.enemies) {
    const urgency = 1 + Math.max(0, (25 - e.z) / 25);
    cx += e.x * urgency; cz += e.z * urgency; w += urgency;
  }
  cx /= w; cz /= w;
  const px = CFG.arena.playerSpawn.x, pz = CFG.arena.playerSpawn.z;
  const want = Math.atan2(cx - px, Math.max(1, cz - pz)) * 180 / Math.PI;

  const err = want - S.aimAngle;
  const maxStep = MANUAL_DRAG_DEG_PER_SEC * FIXED_DT;
  if (Math.abs(err) > 0.01) G.queueAim(Math.sign(err) * Math.min(maxStep, Math.abs(err)));

  if (_manualCooldown > 0) { _manualCooldown -= FIXED_DT; return; }
  if (S.ammo <= 0) return;
  G.fire();
  _manualCooldown = MANUAL_PRESS_OVERHEAD;
}

/** Bagian steering saja (dipakai saat riding di mode manual). */
function botSteerOnly(G) {
  const S = G.S, CFG = G.CFG;
  const riding = S.bullets.find(b => b.riding && b.alive);
  if (!riding || riding.steer <= 0) return;
  let sx = 0, w = 0;
  for (const e of S.enemies) {
    const dz = e.z - riding.z;
    if (dz < -1 || dz > 14) continue;
    const urgency = 1 + Math.max(0, (20 - e.z) / 20);
    sx += e.x * urgency; w += urgency;
  }
  if (w === 0) return;
  const err = sx / w - riding.x;
  const want = Math.atan2(err, 8) * 180 / Math.PI;
  const cur = Math.atan2(riding.dx, riding.dz) * 180 / Math.PI;
  G.queueSteer(Math.max(-1, Math.min(1, (want - cur) / CFG.bullet.steerAnglePerSwipe)));
}

// ---------------------------------------------------------------------------
// BOT UNTUK LOOP LANE (Last War ATM)
// Kontrolnya sekarang posisi, bukan sudut, jadi bot lama tidak lagi mengukur
// apa pun yang relevan. Dua pelajaran dari A/B sebelumnya dipertahankan:
// (1) beri latensi jempol supaya bukan refleks super-manusia, (2) "mahir"
// berarti menembak pada laju maksimum SAMBIL memposisikan diri, bukan menahan
// tembakan menunggu momen sempurna.
// ---------------------------------------------------------------------------
const THUMB_LATENCY = 0.20;
const GATE_COMMIT_Z = 20;
let _laneCd = 0, _laneTarget = 0, _laneRepick = 0;

/** Sisi gate yang menguntungkan, atau null kalau belum ada gate yang dekat. */
function gateTargetX(G) {
  const S = G.S;
  let best = null;
  for (const g of S.gates) {
    if (g.squadDone || g.z > GATE_COMMIT_Z || g.z < G.CFG.arena.playerSpawn.z) continue;
    if (!best || g.z < best.z) best = g;
  }
  if (!best) return null;
  return best.left.positive ? -5 : 5;
}

/** Pusat massa crowd, dibobot urgensi — target saat tidak ada gate. */
function crowdCenterX(G) {
  const S = G.S;
  let cx = 0, w = 0;
  for (const e of S.enemies) {
    if (e.hp <= 0) continue;
    const urgency = 1 + Math.max(0, (25 - e.z) / 25);
    cx += e.x * urgency; w += urgency;
  }
  return w === 0 ? null : cx / w;
}

function botLaneSkilled(G) {
  const S = G.S;
  const riding = S.bullets.find(b => b.riding && b.alive);
  if (riding) { botSteerOnly(G); return; }

  // Gate mengalahkan crowd: satu gate salah menghapus keunggulan yang
  // dikumpulkan sepanjang satu wave penuh.
  const gx = gateTargetX(G);
  const target = gx !== null ? gx : crowdCenterX(G);
  if (target !== null) S.squadInput = target;

  if (_laneCd > 0) { _laneCd -= FIXED_DT; return; }
  if (S.chainCharges <= 0) return;
  G.fire();
  _laneCd = THUMB_LATENCY;
}

function botLaneRandom(G) {
  const S = G.S;
  const riding = S.bullets.find(b => b.riding && b.alive);
  if (riding) { botSteerOnly(G); return; }
  _laneRepick -= FIXED_DT;
  if (_laneRepick <= 0) {
    _laneRepick = 0.5;
    _laneTarget = (S.rng.f() * 2 - 1) * (G.CFG.arena.width / 2 - 1);
  }
  S.squadInput = _laneTarget;
  if (_laneCd > 0) { _laneCd -= FIXED_DT; return; }
  if (S.chainCharges <= 0) return;
  if (S.rng.f() < 0.4) { G.fire(); _laneCd = THUMB_LATENCY; }
}

const BOTS = { random: botLaneRandom, skilled: botLaneSkilled };

// ---------------------------------------------------------------------------
// MENJALANKAN SATU RUN
// ---------------------------------------------------------------------------
function runOne(G, variantIndex, bot, maxSeconds = 300) {
  resetBots();
  G.loadVariant(variantIndex);
  const S = G.S;

  const stats = {
    variant: variantIndex,
    name: G.CFG.variants[variantIndex].name,
    waveClearTick: [],
    peakEnemies: 0,
    totalBounces: 0,
    shots: 0,
    troopsEnd: 0,
    troopsPeak: 0,
    gatesTaken: 0,
    gatesGood: 0,
    violations: [],
  };

  const maxTicks = Math.floor(maxSeconds * 60);
  let lastWave = -1;
  const fireOrig = G.fire;
  const countingFire = () => {
    const before = S.chainCharges; fireOrig();
    if (S.chainCharges < before) stats.shots++;
  };
  const Gw = Object.create(G);
  Object.defineProperty(Gw, 'fire', { value: countingFire });

  for (let t = 0; t < maxTicks; t++) {
    bot(Gw, t);
    G.simulate(FIXED_DT);

    if (S.enemies.length > stats.peakEnemies) stats.peakEnemies = S.enemies.length;
    if (S.troops > stats.troopsPeak) stats.troopsPeak = S.troops;
    if (S.waveIndex !== lastWave) { lastWave = S.waveIndex; stats.waveClearTick.push(S.tick); }

    // --- invariant checks ---
    for (const e of S.enemies) {
      if (e.x < G.CFG.arena.xMin - 0.01 || e.x > G.CFG.arena.xMax + 0.01)
        stats.violations.push(`musuh keluar dinding x=${e.x.toFixed(2)} @${t}`);
    }
    for (const b of S.bullets) {
      if (!b.alive) continue;
      if (b.x < G.CFG.arena.xMin - 0.5 || b.x > G.CFG.arena.xMax + 0.5)
        stats.violations.push(`PELURU TUNNELING x=${b.x.toFixed(3)} @${t}`);
      if (b.spdMul > G.CFG.bullet.speedMultiplierCap + 1e-6)
        stats.violations.push(`speed cap dilanggar ${b.spdMul.toFixed(3)}`);
      if (b.bounceCount > (b.maxBounceSeen = Math.max(b.maxBounceSeen || 0, b.bounceCount)) + 1)
        stats.violations.push('bounce overflow');
    }

    if (S.state !== 'playing') break;
  }

  stats.state = S.state;
  stats.durationSec = S.tick / 60;
  stats.troopsEnd = S.troops;
  stats.score = S.score;
  stats.kills = S.kills;
  stats.bestCombo = S.bestCombo;
  stats.lives = S.lives;
  stats.wavesReached = S.waveIndex + 1;
  if (stats.violations.length > 5) stats.violations = stats.violations.slice(0, 5).concat(['...']);
  return stats;
}

// ---------------------------------------------------------------------------
// DETERMINISME
// ---------------------------------------------------------------------------
function determinismCheck(G, variantIndex = 0, ticks = 7200) {   // 120 s: harus menutup SEMUA wave
  const trace = () => {
    resetBots();
    G.loadVariant(variantIndex);
    const S = G.S, log = [];
    for (let t = 0; t < ticks; t++) {
      BOTS.skilled(G, t);
      G.simulate(FIXED_DT);
      if (t % 60 === 0) log.push([S.tick, S.score, S.kills, S.enemies.length, S.lives].join(','));
    }
    return log;
  };
  const a = trace(), b = trace();
  const same = a.join('|') === b.join('|');
  let firstDiff = null;
  if (!same) for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) { firstDiff = `${a[i]}  vs  ${b[i]}`; break; }
  return { same, firstDiff };
}

// ---------------------------------------------------------------------------
// MAIN
// ---------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  const botName = (args.find(a => a.startsWith('--bot=')) || '--bot=skilled').split('=')[1];
  const onlyVariant = args.find(a => a.startsWith('--variant='));
  const bot = BOTS[botName] || botSkilled;

  const G = loadGame();

  if (args.includes('--determinism')) {
    const r = determinismCheck(G);
    console.log(`DETERMINISME: ${r.same ? 'IDENTIK' : 'BERBEDA'}`);
    if (!r.same) console.log('  divergensi pertama: ' + r.firstDiff);
    process.exit(r.same ? 0 : 1);
  }

  const variants = onlyVariant
    ? [parseInt(onlyVariant.split('=')[1], 10) - 1]
    : G.CFG.variants.map((_, i) => i);

  console.log(`\nCHAIN RIDER — simulasi headless  (bot: ${botName})`);
  console.log('='.repeat(96));
  console.log('arena              hasil     durasi   wave  kill  bocor  skor     combo  peak  tembakan');
  console.log('-'.repeat(96));

  let allViolations = [];
  const rows = [];
  for (const v of variants) {
    const s = runOne(G, v, bot);
    rows.push(s);
    allViolations = allViolations.concat(s.violations.map(x => `${s.name}: ${x}`));
    const leaked = 3 - s.lives;
    console.log(
      `${(s.variant + 1) + '. ' + s.name}`.padEnd(19) +
      `${s.state}`.padEnd(10) +
      `${s.durationSec.toFixed(1)}s`.padStart(6) + '  ' +
      `${s.wavesReached}/5`.padStart(5) + '  ' +
      `${s.kills}`.padStart(4) + '  ' +
      `${leaked}`.padStart(5) + '  ' +
      `${s.score}`.padStart(7) + '  ' +
      `${s.bestCombo}`.padStart(5) + '  ' +
      `${s.peakEnemies}`.padStart(4) + '  ' +
      `${s.shots}`.padStart(8));
  }
  console.log('-'.repeat(96));

  const wins = rows.filter(r => r.state === 'victory').length;
  const avgDur = rows.reduce((a, r) => a + r.durationSec, 0) / rows.length;
  console.log(`menang ${wins}/${rows.length}   durasi rata-rata ${avgDur.toFixed(1)}s ` +
              `(target sesi: 60–180 s)`);

  console.log(allViolations.length
    ? '\nPELANGGARAN INVARIANT:\n  ' + allViolations.join('\n  ')
    : '\nInvariant aman: tidak ada tunneling, speed cap terjaga, musuh dalam dinding.');
}

if (require.main === module) main();
module.exports = { loadGame, resetBots, runOne, determinismCheck, BOTS };

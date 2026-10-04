#!/usr/bin/env node
/**
 * juice_test.js — Penjaga lapisan "rasa" build web (docs/01 EVENT & JUICE).
 *
 * Pasangan web dari godot/tests/juice_suite.gd. Yang diuji bukan angka
 * balance, melainkan reaksi: milestone pantulan, ambang kill, near miss,
 * perfect clear, peluru terakhir — beserta denyut slow motion, zoom
 * sinematik, dan confetti yang menempel padanya.
 *
 * Semua perilaku di sini gampang "lulus" tanpa pernah terjadi: sebuah efek
 * yang tidak pernah menyala dan sebuah efek yang tidak pernah padam
 * sama-sama hijau kalau cuma dilihat sekali. Jadi setiap baris diuji dalam
 * DUA keadaan yang berlawanan.
 *
 * Pemakaian: node tools/juice_test.js
 */

'use strict';
const { loadGame } = require('./sim_test.js');

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

/** Mengganti satu fungsi SFX dengan pencacah, mengembalikan pembacanya. */
function spy(G, name) {
  const state = { calls: 0 };
  G.SFX[name] = () => { state.calls++; };
  return state;
}

function fakeEnemy(G, z) {
  return {
    x: 0, z, r: 0.35, hp: 10, score: 10, speed: 0.6, color: '#FF4D3D',
    hit: 0, phase: 0, near: false, vx: 0, vz: 0,
  };
}

// ---------------------------------------------------------------------------
// 1. Tangga pantulan: tiap kelipatan lima berbunyi dan mendenyutkan waktu.
// ---------------------------------------------------------------------------
function testBounceMilestone(G) {
  const S = G.S;
  const every = G.CFG.scoring.bounceMilestoneEvery;
  const sfx = spy(G, 'milestone');
  const bullet = {
    x: 0, z: 10, dx: 0, dz: 1, bounces: 20, bounceCount: every - 2,
    dmgMul: 1, spdMul: 1, speed: 20, alive: true, riding: false, trail: [],
  };
  const wall = { nx: 0, nz: -1, kind: 'wall', ref: null };

  S.pulse = 0;
  G.resolveBounce(bullet, wall);           // -> kelipatan ke-(n-1)
  check('pantulan di luar kelipatan tidak dirayakan',
    sfx.calls === 0 && S.pulse === 0, `bounce ${bullet.bounceCount}`);

  G.resolveBounce(bullet, wall);           // -> kelipatan pas
  check('pantulan kelipatan lima berbunyi + mendenyut',
    sfx.calls === 1 && S.pulse === G.CFG.slowMo.bouncePulseDuration,
    `bounce ${bullet.bounceCount}, pulse ${S.pulse}`);
}

// ---------------------------------------------------------------------------
// 2. Ambang kill: bonus skor dari config, plus confetti.
// ---------------------------------------------------------------------------
function testKillMilestone(G) {
  const S = G.S;
  G.loadVariant(0);
  const bonus = G.CFG.scoring.killMilestoneBonus;
  const target = G.CFG.scoring.killMilestones[0];

  S.kills = target - 3;
  S.enemies = [fakeEnemy(G, 20), fakeEnemy(G, 21)];
  S.confetti = [];
  let before = S.score;
  G.damageEnemy(S.enemies[0], 999);
  check('kill biasa tidak memberi bonus ambang',
    S.score - before < bonus && S.confetti.length === 0,
    `+${S.score - before}`);

  S.kills = target - 1;
  before = S.score;
  G.damageEnemy(S.enemies[1], 999);
  check(`kill ke-${target} memberi bonus config + confetti`,
    S.score - before >= bonus && S.confetti.length > 0,
    `+${S.score - before}, ${S.confetti.length} kepingan`);

  for (let i = 0; i < 40; i++) G.tickConfetti(0.05);
  check('confetti habis sendiri', S.confetti.length === 0);
}

// ---------------------------------------------------------------------------
// 3. Near miss: sekali per musuh, bukan sekali per tick.
// ---------------------------------------------------------------------------
function testNearMiss(G) {
  const S = G.S;
  G.loadVariant(0);
  const sfx = spy(G, 'heartbeat');
  const defZ = G.CFG.arena.defenseLineZ;
  const band = G.CFG.arena.nearMissBandZ;

  // Jauh di atas pita: diam.
  S.enemies = [fakeEnemy(G, defZ + band + 6)];
  S.enemies[0].speed = 0;
  S.waveActive = false;
  for (let i = 0; i < 30; i++) G.simulate(1 / 60);
  check('musuh di luar pita tidak memicu heartbeat', sfx.calls === 0);

  // Di dalam pita, dipaksa bertahan di sana belasan tick.
  const enemy = S.enemies[0];
  enemy.z = defZ + band * 0.5;
  for (let i = 0; i < 30; i++) {
    enemy.z = defZ + band * 0.5;
    G.simulate(1 / 60);
  }
  check('musuh di dalam pita berdetak tepat sekali', sfx.calls === 1,
    `${sfx.calls} detak dalam 30 tick`);
}

// ---------------------------------------------------------------------------
// 4. Peluru terakhir: hanya kalau chain shot yang menutup gelombang.
// ---------------------------------------------------------------------------
function lastBulletCase(G, bulletInAir) {
  const S = G.S;
  G.loadVariant(0);
  S.boss = null;
  S.waveActive = true;
  S.cine = 0;
  S.enemies = [fakeEnemy(G, 20)];
  S.bullets = bulletInAir
    ? [{ x: 0, z: 12, dx: 0, dz: 1, alive: true, bounces: 5, bounceCount: 0, trail: [] }]
    : [];
  G.damageEnemy(S.enemies[0], 999);
  return S.cine;
}

function testLastBullet(G) {
  check('gelombang habis tanpa peluru di udara: tidak ada zoom',
    lastBulletCase(G, false) === 0);
  check('peluru penutup gelombang memicu zoom sinematik',
    Math.abs(lastBulletCase(G, true) - G.CFG.scoring.lastBulletZoomDuration) < 1e-9,
    `${G.CFG.scoring.lastBulletZoomDuration}s`);
}

// ---------------------------------------------------------------------------
// 5. Slow motion: dua waktu pinjaman menyala, lalu benar-benar padam.
// ---------------------------------------------------------------------------
function testSlowMoStep(G) {
  const S = G.S;
  G.loadVariant(0);
  S.targetTimeScale = 1; S.targetFov = 1; S.pulse = 0;

  S.cine = G.CFG.scoring.lastBulletZoomDuration;
  let want = G.slowMoStep(1 / 60);
  const zoomFov = G.CFG.slowMo.fovLastBullet / G.CFG.slowMo.fovNormal;
  check('zoom sinematik menekan waktu dan menarik kamera',
    want.scale === G.CFG.slowMo.finalBounceTimeScale && Math.abs(want.fov - zoomFov) < 1e-9,
    `scale ${want.scale}, fov ${want.fov.toFixed(3)}`);

  for (let i = 0; i < 120; i++) want = G.slowMoStep(1 / 60);
  check('zoom sinematik dilepas setelah durasinya habis',
    want.scale === 1 && want.fov === 1, `scale ${want.scale}`);

  S.pulse = G.CFG.slowMo.bouncePulseDuration;
  want = G.slowMoStep(1 / 60);
  check('denyut pantulan menekan waktu', want.scale === G.CFG.slowMo.bouncePulseTimeScale);
  for (let i = 0; i < 30; i++) want = G.slowMoStep(1 / 60);
  check('denyut pantulan kembali ke kecepatan normal', want.scale === 1);

  // Yang dalam menang atas yang dangkal: denyut tidak boleh MEMPERCEPAT
  // dunia yang sudah melambat karena tiga pantulan terakhir.
  S.targetTimeScale = G.CFG.slowMo.finalBounceTimeScale;
  S.pulse = G.CFG.slowMo.bouncePulseDuration;
  want = G.slowMoStep(1 / 60);
  check('denyut tidak pernah mempercepat slow motion yang lebih dalam',
    want.scale === G.CFG.slowMo.finalBounceTimeScale);
}

// ---------------------------------------------------------------------------
// 6. Perfect clear: koin hanya untuk gelombang tanpa kebobolan.
// ---------------------------------------------------------------------------
function clearWave(G, leaked) {
  const S = G.S;
  G.loadVariant(0);
  S.boss = null;
  S.enemies = [];
  S.waveActive = true;
  S.leaked = leaked;
  S.waveIndex = 0;
  const before = S.coins;
  G.simulate(1 / 60);
  return S.coins - before;
}

function testPerfectClear(G) {
  check('gelombang bersih memberi koin perfect clear',
    clearWave(G, 0) === G.CFG.scoring.perfectClearBonusCoins,
    `+${G.CFG.scoring.perfectClearBonusCoins}`);
  check('gelombang yang kebobolan tidak memberi koin', clearWave(G, 2) === 0);
}

// ---------------------------------------------------------------------------
function main() {
  console.log('');
  console.log('JUICE TEST — lapisan rasa build web');
  console.log('='.repeat(72));
  const G = loadGame();
  G.loadVariant(0);

  testBounceMilestone(G);
  testKillMilestone(G);
  testNearMiss(G);
  testLastBullet(G);
  testSlowMoStep(G);
  testPerfectClear(G);

  console.log('-'.repeat(72));
  console.log(failures === 0
    ? `SEMUA LULUS — ${checks} pemeriksaan`
    : `${failures} GAGAL dari ${checks} pemeriksaan`);
  process.exit(failures === 0 ? 0 : 1);
}

main();

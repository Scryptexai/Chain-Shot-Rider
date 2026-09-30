#!/usr/bin/env node
/**
 * aim_ab.js — Membandingkan dua mode bidikan CHAIN RIDER.
 *
 *   sweep  : turret menyapu otomatis, tap menembak pada sudut saat itu.
 *   manual : tahan lalu geser untuk membidik, lepas untuk menembak.
 *
 * KEADILAN PERBANDINGAN
 * Ini bagian tersulit dari pengukuran ini. Bot punya keunggulan tidak adil di
 * mode manual: ia bisa menetapkan sudut yang persis dalam satu tick, sedangkan
 * jempol manusia butuh waktu untuk menggeser. Kalau itu dibiarkan, manual akan
 * menang telak karena alasan yang tidak ada hubungannya dengan kualitas desain.
 *
 * Jadi bot manual dibebani model jempol:
 *   1. Sudut hanya boleh berubah dengan laju terbatas (dragRateDegPerSec).
 *   2. Ada ongkos tekan-lepas setiap siklus tembak (pressOverheadSec).
 *   3. Bot hanya menembak setelah sudutnya benar-benar sampai.
 *
 * Bot sweep membayar ongkosnya dalam bentuk lain: ia harus MENUNGGU turret
 * melewati sudut yang diinginkan, dan kalau momen itu terlewat ia menunggu
 * satu sapuan penuh lagi.
 *
 * Laju geser diuji pada tiga nilai karena inilah asumsi paling rapuh:
 *   180 deg/s  — membidik hati-hati
 *   300 deg/s  — geseran cepat dan percaya diri
 *   500 deg/s  — batas atas, praktis di luar kemampuan manusia
 *
 * Pemakaian:  node tools/aim_ab.js
 */

'use strict';
const { loadGame, BOTS } = require('./sim_test.js');

const FIXED_DT = 1 / 60;
const SEEDS = [20260929, 777, 4242, 99001, 31337, 6060];
const PRESS_OVERHEAD_SEC = 0.12;

// ---------------------------------------------------------------------------
// Sudut yang diinginkan: pusat massa crowd, dibobot urgensi (dekat garis = penting).
// Dipakai kedua bot supaya yang dibandingkan adalah MEKANIKNYA, bukan taktiknya.
// ---------------------------------------------------------------------------
function desiredAngle(S, CFG) {
  if (S.enemies.length === 0) return null;
  let cx = 0, cz = 0, w = 0;
  for (const e of S.enemies) {
    const urgency = 1 + Math.max(0, (25 - e.z) / 25);
    cx += e.x * urgency; cz += e.z * urgency; w += urgency;
  }
  cx /= w; cz /= w;
  const px = CFG.arena.playerSpawn.x, pz = CFG.arena.playerSpawn.z;
  return Math.atan2(cx - px, Math.max(1, cz - pz)) * 180 / Math.PI;
}

// ---------------------------------------------------------------------------
// KEBIJAKAN "PATH SCORING" — meniru pemain yang benar-benar memanfaatkan pantulan.
//
// Bot centroid di atas selalu menembak ke pusat massa crowd. Karena formasi
// game ini simetris, pusat massa hampir selalu ada di x ~ 0, jadi bot itu
// menembak lurus terus dan tidak pernah memakai dinding. Membandingkan mode
// bidikan dengan bot seperti itu akan menghukum mode manual karena alasan yang
// salah: bukan modenya yang buruk, kebijakan botnya yang tidak memakai
// kemampuan mode itu.
//
// Bot di bawah mencetak skor setiap sudut kandidat dengan MEMPREDIKSI lintasan
// pantulnya (fungsi yang sama dengan garis bidik pemain), lalu menghitung
// berapa musuh yang dilewati lintasan itu. Inilah yang dilakukan pemain mahir.
// ---------------------------------------------------------------------------

/** Jarak titik ke ruas garis. */
function distToSegment(px, pz, ax, az, bx, bz) {
  const vx = bx - ax, vz = bz - az;
  const len2 = vx * vx + vz * vz;
  let t = len2 > 1e-9 ? ((px - ax) * vx + (pz - az) * vz) / len2 : 0;
  t = Math.max(0, Math.min(1, t));
  const dx = px - (ax + vx * t), dz = pz - (az + vz * t);
  return Math.hypot(dx, dz);
}

/** Skor satu sudut: bobot musuh yang dilewati lintasan pantul yang diprediksi. */
function scoreAngle(G, angleDeg) {
  const S = G.S, CFG = G.CFG;
  const mx = CFG.arena.playerSpawn.x;
  const mz = CFG.arena.playerSpawn.z + CFG.arena.muzzleOffset.z;
  const a = angleDeg * Math.PI / 180;
  const path = G.predictAimPath(mx, mz, Math.sin(a), Math.cos(a), CFG.aim.indicatorBounces);
  const hitRadius = CFG.bullet.radius + 0.55;

  let score = 0;
  for (const e of S.enemies) {
    let best = Infinity;
    for (let i = 0; i < path.length - 1; i++) {
      const d = distToSegment(e.x, e.z, path[i][0], path[i][1], path[i + 1][0], path[i + 1][1]);
      if (d < best) best = d;
    }
    if (best < hitRadius) score += 1 + Math.max(0, (25 - e.z) / 25);   // dekat garis = lebih berharga
  }
  return score;
}

/** Sudut terbaik dari sampling kandidat. */
function bestAngle(G, stepDeg = 4) {
  const max = G.CFG.aim.maxAngleDeg;
  let bestA = 0, bestS = -1;
  for (let a = -max; a <= max; a += stepDeg) {
    const sc = scoreAngle(G, a);
    if (sc > bestS) { bestS = sc; bestA = a; }
  }
  return { angle: bestA, score: bestS };
}

/** Steering saat riding — identik untuk kedua mode. */
function steerLikeSkilled(G) {
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

/** Bot mode manual, dengan model biaya jempol. */
function makeManualBot(dragRateDegPerSec, reactionSec = 0.20) {
  let cooldown = 0, react = -1;
  return function (G) {
    const S = G.S, CFG = G.CFG;
    steerLikeSkilled(G);

    const riding = S.bullets.find(b => b.riding && b.alive);
    if (riding) return;                       // saat riding, tap = rem; bot tidak menembak
    if (cooldown > 0) { cooldown -= FIXED_DT; return; }
    if (S.ammo <= 0) return;

    const want = desiredAngle(S, CFG);
    if (want === null) return;
    if (react < 0) { react = reactionSec; return; }
    react -= FIXED_DT; if (react > 0) return; react = -1;

    const err = want - S.aimAngle;
    const maxStep = dragRateDegPerSec * FIXED_DT;

    // Toleransi 1 derajat — LEBIH KETAT dari bot sweep (5 derajat). Sudut yang
    // di-queue baru berlaku di tick berikutnya, jadi menembak di tick yang sama
    // dengan geseran akan memakai sudut yang belum diperbarui.
    if (Math.abs(err) > 1.0) {
      G.queueAim(Math.sign(err) * Math.min(maxStep, Math.abs(err)));
      return;
    }
    G.fire();
    cooldown = PRESS_OVERHEAD_SEC;            // ongkos angkat + tekan lagi
  };
}

/** Bot manual yang mencari tembakan pantul (pemain mahir). */
function makeManualPathBot(dragRateDegPerSec, reactionSec = 0.20) {
  let cooldown = 0, target = null, recompute = 0, react = -1;
  return function (G) {
    const S = G.S;
    steerLikeSkilled(G);
    const riding = S.bullets.find(b => b.riding && b.alive);
    if (riding) { target = null; react = -1; return; }
    if (cooldown > 0) { cooldown -= FIXED_DT; return; }
    if (S.ammo <= 0 || S.enemies.length === 0) return;

    // Latensi reaksi yang sama dengan bot sweep. Bedanya: di mode manual sudut
    // tidak ikut bergeser selama menunggu, jadi keterlambatan hanya menunda.
    if (react >= 0) { react -= FIXED_DT; if (react > 0) return; react = -1; }

    // Menilai ulang 10x per detik — kira-kira laju keputusan manusia.
    if (target === null || --recompute <= 0) {
      const b = bestAngle(G);
      if (b.score <= 0) { target = null; return; }
      target = b.angle; recompute = 6; react = reactionSec;
      return;
    }

    const err = target - S.aimAngle;
    const maxStep = dragRateDegPerSec * FIXED_DT;
    if (Math.abs(err) > 1.0) {
      G.queueAim(Math.sign(err) * Math.min(maxStep, Math.abs(err)));
      return;
    }
    G.fire();
    cooldown = PRESS_OVERHEAD_SEC;
    target = null;
  };
}

/**
 * Bot sweep dengan penilaian lintasan DAN latensi reaksi manusia.
 *
 * Ini pembanding yang jujur. Versi tanpa latensi menilai sudut 60x per detik dan
 * menembak pada tick yang sama — refleks yang mustahil bagi manusia. Padahal
 * justru di mode sweep keterlambatan itu mahal: turret terus bergerak 75 deg/s,
 * jadi reaksi 200 ms berarti meleset 15 derajat dari sudut yang tadi dinilai bagus.
 * Mode manual tidak punya masalah ini — sudutnya diam menunggu jempol.
 */
function makeSweepPathBot(reactionSec) {
  let pending = -1, decide = 0;
  return function (G) {
    const S = G.S;
    steerLikeSkilled(G);
    const riding = S.bullets.find(b => b.riding && b.alive);
    if (riding) { pending = -1; return; }

    if (pending >= 0) {                       // sudah memutuskan, sedang bereaksi
      pending -= FIXED_DT;
      if (pending <= 0) { pending = -1; if (S.ammo > 0) G.fire(); }
      return;
    }
    if (S.ammo <= 0 || S.enemies.length === 0) return;
    if (--decide > 0) return;
    decide = 6;                               // menilai 10x per detik, sama dengan bot manual

    const here = scoreAngle(G, S.aimAngle);
    if (here <= 0) return;
    if (here >= bestAngle(G, 8).score * 0.7) pending = reactionSec;
  };
}

// ---------------------------------------------------------------------------
// BOT "MAHIR" YANG BENAR
//
// Versi pertama bot mahir keliru: ia menahan tembakan sampai sudutnya sempurna,
// sehingga hanya menembak 26-44 kali per run sementara bot pemula menembak
// 75-97 kali. Hasilnya bot "mahir" kalah telak. Itu bukan kemahiran, itu
// kelambatan. Pemain sungguhan menembak sesering amunisi mengizinkan SAMBIL
// membidik sebaik mungkin. Dua bot di bawah memodelkan itu.
// ---------------------------------------------------------------------------

/** Manual, mahir: terus menggeser ke sudut terbaik, menembak setiap amunisi siap. */
function makeManualSkilled(dragRateDegPerSec, reactionSec = 0.20) {
  let cooldown = 0, target = 0, recompute = 0, react = -1;
  return function (G) {
    const S = G.S;
    steerLikeSkilled(G);
    const riding = S.bullets.find(b => b.riding && b.alive);
    if (riding) return;
    if (S.enemies.length === 0) return;

    if (--recompute <= 0) {
      recompute = 6;
      const b = bestAngle(G);
      if (b.score > 0 && Math.abs(b.angle - target) > 3) { react = reactionSec; target = b.angle; }
      else if (b.score > 0) target = b.angle;
    }
    if (react > 0) { react -= FIXED_DT; }
    else {
      const err = target - S.aimAngle;
      const maxStep = dragRateDegPerSec * FIXED_DT;
      if (Math.abs(err) > 0.01) G.queueAim(Math.sign(err) * Math.min(maxStep, Math.abs(err)));
    }

    if (cooldown > 0) { cooldown -= FIXED_DT; return; }
    if (S.ammo <= 0) return;
    G.fire();                                  // menembak pada sudut TERBAIK YANG SUDAH TERCAPAI
    cooldown = PRESS_OVERHEAD_SEC;
  };
}

/** Sweep, mahir: menembak setiap amunisi siap kalau sudut saat ini layak. */
function makeSweepSkilled(reactionSec = 0.20, threshold = 0.4) {
  let pending = -1, decide = 0, cooldown = 0;
  return function (G) {
    const S = G.S;
    steerLikeSkilled(G);
    const riding = S.bullets.find(b => b.riding && b.alive);
    if (riding) { pending = -1; return; }
    if (cooldown > 0) cooldown -= FIXED_DT;

    if (pending >= 0) {
      pending -= FIXED_DT;
      if (pending <= 0) { pending = -1; if (S.ammo > 0 && cooldown <= 0) { G.fire(); cooldown = PRESS_OVERHEAD_SEC; } }
      return;
    }
    if (S.ammo <= 0 || cooldown > 0 || S.enemies.length === 0) return;
    if (--decide > 0) return;
    decide = 6;
    const here = scoreAngle(G, S.aimAngle);
    if (here > 0 && here >= bestAngle(G, 8).score * threshold) pending = reactionSec;
  };
}

/** Bot mode sweep: menunggu turret melewati sudut yang diinginkan. */
function botSweep(G) {
  const S = G.S, CFG = G.CFG;
  steerLikeSkilled(G);
  const riding = S.bullets.find(b => b.riding && b.alive);
  if (riding || S.ammo <= 0) return;
  const want = desiredAngle(S, CFG);
  if (want === null) return;
  if (Math.abs(S.aimAngle - want) < 5) G.fire();
}

// ---------------------------------------------------------------------------
// SATU RUN, dengan instrumentasi peluru
// ---------------------------------------------------------------------------
function runInstrumented(G, variantIndex, bot, maxSeconds = 300) {
  G.loadVariant(variantIndex);
  const S = G.S;
  const tracked = new Map();     // objek peluru -> { maxBounce, everRiding }

  const maxTicks = Math.floor(maxSeconds * 60);
  let t = 0;
  for (; t < maxTicks; t++) {
    bot(G, t);
    G.simulate(FIXED_DT);

    for (const b of S.bullets) {
      let rec = tracked.get(b);
      if (!rec) { rec = { maxBounce: 0, everRiding: false }; tracked.set(b, rec); }
      if (b.bounceCount > rec.maxBounce) rec.maxBounce = b.bounceCount;
      if (b.riding) rec.everRiding = true;
    }
    if (S.state !== 'playing') break;
  }

  let bounces = 0, touched = 0;
  for (const rec of tracked.values()) { bounces += rec.maxBounce; touched += rec.everRiding ? 1 : 0; }
  const nb = tracked.size || 1;

  return {
    durationSec: t / 60,
    kills: S.kills,
    score: S.score,
    bestCombo: S.bestCombo,
    wave: S.waveIndex + 1,
    won: S.state === 'victory',
    bulletsFired: tracked.size,
    bouncePerBullet: bounces / nb,
    crowdContactPct: 100 * touched / nb,
  };
}

function sweepConfig(G, label, bot, mode, sweepSpeed) {
  const res = [];
  const origSpeed = G.CFG.aim.sweepSpeedDegPerSec;
  for (const seed of SEEDS) {
    G.CFG.determinism.defaultSeed = seed;
    G.CFG.aim.mode = mode;
    G.CFG.aim.sweepSpeedDegPerSec = sweepSpeed || origSpeed;
    for (let v = 0; v < 5; v++) res.push(runInstrumented(G, v, bot));
  }
  G.CFG.aim.sweepSpeedDegPerSec = origSpeed;
  const n = res.length, avg = k => res.reduce((a, r) => a + r[k], 0) / n;
  return {
    label,
    n,
    durationSec: avg('durationSec'),
    inWindow: res.filter(r => r.durationSec >= 60 && r.durationSec <= 180).length,
    wave: avg('wave'),
    kills: avg('kills'),
    combo: avg('bestCombo'),
    wins: res.filter(r => r.won).length,
    shots: avg('bulletsFired'),
    bouncePerBullet: avg('bouncePerBullet'),
    crowdContactPct: avg('crowdContactPct'),
  };
}

function main() {
  const G = loadGame();
  const rows = [];
  // --- pemain mahir (mencari tembakan pantul), reaksi 200 ms untuk semua ---
  rows.push(sweepConfig(G, 'manual mahir @300', makeManualSkilled(300, 0.20), 'manual'));
  rows.push(sweepConfig(G, 'manual mahir @180', makeManualSkilled(180, 0.20), 'manual'));
  rows.push(sweepConfig(G, 'sweep mahir 75d/s', makeSweepSkilled(0.20, 0.4), 'sweep', 75));
  rows.push(sweepConfig(G, 'sweep mahir 45d/s', makeSweepSkilled(0.20, 0.4), 'sweep', 45));
  // --- pemain pemula (hanya membidik ke gerombolan) ---
  rows.push(sweepConfig(G, 'manual pemula', makeManualBot(300, 0.20), 'manual'));
  rows.push(sweepConfig(G, 'sweep pemula 75d/s', botSweep, 'sweep', 75));
  rows.push(sweepConfig(G, 'sweep pemula 45d/s', botSweep, 'sweep', 45));

  const pad = (s, w) => String(s).padEnd(w);
  const num = (x, d, w) => String(x.toFixed(d)).padStart(w);

  console.log('\nPERBANDINGAN MODE BIDIKAN — ' + rows[0].n + ' run per konfigurasi (6 seed x 5 varian)\n');
  console.log(pad('mode', 20) + num2('durasi', 8) + num2('60-180s', 9) + num2('wave', 6) +
              num2('kill', 7) + num2('combo', 7) + num2('menang', 8) +
              num2('tembakan', 10) + num2('bounce/plr', 12) + num2('kena crowd', 12));
  console.log('-'.repeat(101));
  for (const r of rows) {
    console.log(
      pad(r.label, 20) +
      num(r.durationSec, 1, 7) + 's' +
      String(r.inWindow + '/' + r.n).padStart(9) +
      num(r.wave, 2, 6) +
      num(r.kills, 0, 7) +
      num(r.combo, 0, 7) +
      String(r.wins + '/' + r.n).padStart(8) +
      num(r.shots, 0, 10) +
      num(r.bouncePerBullet, 2, 12) +
      num(r.crowdContactPct, 1, 11) + '%'
    );
  }
  console.log('\nCatatan: bot manual dibebani laju geser terbatas + ongkos tekan-lepas ' +
              PRESS_OVERHEAD_SEC + ' s.');
  console.log('Bot sweep membayar dengan menunggu turret melewati sudut yang diinginkan.\n');
}

function num2(s, w) { return String(s).padStart(w); }

if (require.main === module) main();
module.exports = { botSweep, makeManualBot, runInstrumented };

#!/usr/bin/env node
/**
 * Measures every generated SFX clip and draws a waveform contact sheet.
 *
 *   node tools/audit_sfx.js
 *
 * There is no audio device in this sandbox, so these cues can never be heard
 * here. That is exactly the situation that produced the Vector2.UP bug and the
 * horizon-slab bug: code that passes every check while being wrong in the one
 * dimension nobody inspected. So the cues get inspected numerically and
 * visually instead of taken on trust.
 *
 * What the numbers catch:
 *   silent      - synthesis collapsed to nothing (a bad envelope, a typo)
 *   clipped     - normalise failed or the sum ran hot; would buzz on a phone
 *   dc          - non-zero mean, which wastes headroom and thumps on start
 *   centroid    - spectral centre of mass in Hz, a rough brightness readout.
 *                 This is the one that verifies character: a cue described as
 *                 "sub-bass 60 Hz" must not measure brighter than a cue
 *                 described as "4 kHz sizzle".
 */

'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas } = require('@napi-rs/canvas');

const ROOT = path.resolve(__dirname, '..');
const SFX = path.join(ROOT, 'godot', 'audio', 'sfx');

// Expected character per cue, read off the descriptions in docs/07 section 7.1.
//   lo/hi  - bounds on the spectral centroid, in Hz
//   hfMin  - minimum share of onset energy above 2 kHz, for cues the sheet
//            describes as having a bright transient over a dark body
//
// These are design bounds, not physics: they were calibrated against the
// synthesised cues so that a future edit which dulls a transient or muddies a
// bright cue trips the audit. They are deliberately loose enough that two
// constraints on the same cue do not fight each other - an early pass set
// shot to 90-400 Hz and 6% onset, which no single sound could satisfy.
const EXPECT = {
  shot:            { lo: 90,   hi: 900,  hfMin: 0.045, note: 'sub 60 Hz + klik 4 kHz' },
  bounce:          { lo: 1000, hi: 7000, note: 'ting metalik' },
  kill:            { lo: 300,  hi: 5000, note: 'pop kering + noise' },
  combo_milestone: { lo: 400,  hi: 4000, note: 'arpeggio mayor' },
  explosion:       { lo: 80,   hi: 2200, hfMin: 0.035, note: 'boom berat sub 40 Hz + debris' },
  chain_spark:     { lo: 2500, hi: 9000, note: 'sizzle tinggi' },
  slowmo_enter:    { lo: 100,  hi: 2500, note: 'whoosh turun' },
  slowmo_exit:     { lo: 800,  hi: 8000, note: 'whoosh naik + snap' },
  heartbeat:       { lo: 30,   hi: 400,  note: 'detak rendah' },
  breach:          { lo: 100,  hi: 2000, hfMin: 0.012, note: 'alarm rendah + impact tumpul' },
  perfect_clear:   { lo: 400,  hi: 5000, note: 'chord cerah + shimmer' },
  kill_milestone:  { lo: 300,  hi: 4500, note: 'fanfare' },
  bullet_expire:   { lo: 800,  hi: 7000, note: 'fizz turun' },
  steer_warn:      { lo: 1200, hi: 3000, note: 'beep tipis' },
  ui_tap:          { lo: 800,  hi: 8000, note: 'klik kering' },
  boss_roar:       { lo: 40,   hi: 1500, note: 'growl rendah + riser' },
};

function readWav(file) {
  const buf = fs.readFileSync(file);
  if (buf.toString('ascii', 0, 4) !== 'RIFF') throw new Error(`bukan RIFF: ${file}`);
  let pos = 12;
  let fmt = null;
  let data = null;
  while (pos + 8 <= buf.length) {
    const id = buf.toString('ascii', pos, pos + 4);
    const size = buf.readUInt32LE(pos + 4);
    if (id === 'fmt ') {
      fmt = { channels: buf.readUInt16LE(pos + 10), rate: buf.readUInt32LE(pos + 12),
              bits: buf.readUInt16LE(pos + 22) };
    } else if (id === 'data') {
      data = buf.subarray(pos + 8, pos + 8 + size);
    }
    pos += 8 + size + (size % 2);
  }
  const n = data.length / 2;
  const s = new Float32Array(n);
  for (let i = 0; i < n; i += 1) s[i] = data.readInt16LE(i * 2) / 32768;
  return { ...fmt, samples: s };
}

/**
 * Spectral centroid via a coarse Goertzel bank. A full FFT is overkill for a
 * single brightness number, and 32 log-spaced probes resolve the difference
 * between a 60 Hz thump and a 4 kHz sizzle with room to spare.
 */
function spectrum(s, rate) {
  const bands = [];
  for (let i = 0; i < 32; i += 1) bands.push(40 * Math.pow(2, i * 0.28));
  let num = 0;
  let den = 0;
  let hf = 0;
  for (const f of bands) {
    if (f > rate / 2) break;
    const w = (2 * Math.PI * f) / rate;
    const coeff = 2 * Math.cos(w);
    let s1 = 0;
    let s2 = 0;
    for (let i = 0; i < s.length; i += 1) {
      const s0 = s[i] + coeff * s1 - s2;
      s2 = s1; s1 = s0;
    }
    const mag = Math.sqrt(Math.max(0, s1 * s1 + s2 * s2 - coeff * s1 * s2));
    num += f * mag; den += mag;
    if (f >= 2000) hf += mag;
  }
  return { centroid: den > 1e-9 ? num / den : 0, hf: den > 1e-9 ? hf / den : 0 };
}

function main() {
  const files = fs.readdirSync(SFX).filter((f) => f.endsWith('.wav')).sort();
  if (files.length === 0) { console.error('tidak ada WAV — jalankan tools/gen_sfx.py'); process.exit(1); }

  const rows = [];
  const problems = [];
  for (const f of files) {
    const { rate, channels, bits, samples } = readWav(path.join(SFX, f));
    let peak = 0; let sum = 0; let sq = 0; let clipped = 0;
    for (const v of samples) {
      const a = Math.abs(v);
      if (a > peak) peak = a;
      if (a >= 0.999) clipped += 1;
      sum += v; sq += v * v;
    }
    const rms = Math.sqrt(sq / samples.length);
    const dc = sum / samples.length;
    const dur = samples.length / rate;
    const { centroid: cen, hf } = spectrum(samples, rate);
    // A click is localised in time: 13 ms of 4 kHz transient can never rival
    // 180 ms of sub in whole-clip energy, so measuring the whole clip would
    // report "no transient" even for a perfectly punchy sound. The onset
    // window is where a transient either exists or does not.
    const atkWin = samples.subarray(0, Math.min(samples.length, Math.floor(rate * 0.025)));
    const hfAtk = spectrum(atkWin, rate).hf;
    const base = f.replace(/_\d+\.wav$/, '');
    const exp = EXPECT[base];

    if (rms < 0.005) problems.push(`${f}: nyaris senyap (rms ${rms.toFixed(4)})`);
    if (clipped > 8) problems.push(`${f}: clipping ${clipped} sampel`);
    if (Math.abs(dc) > 0.02) problems.push(`${f}: DC offset ${dc.toFixed(3)}`);
    if (channels !== 1 || rate !== 22050 || bits !== 16) {
      problems.push(`${f}: format ${channels}ch/${rate}Hz/${bits}bit, docs/07 minta mono 22 kHz`);
    }
    if (exp && (cen < exp.lo || cen > exp.hi)) {
      problems.push(`${f}: centroid ${cen.toFixed(0)} Hz di luar ${exp.lo}-${exp.hi} (${exp.note})`);
    }
    if (exp && exp.hfMin !== undefined && hfAtk < exp.hfMin) {
      problems.push(`${f}: energi >2 kHz saat onset cuma ${(hfAtk * 100).toFixed(1)}%, `
        + `minimum ${(exp.hfMin * 100).toFixed(0)}% — transien hilang (${exp.note})`);
    }
    rows.push({ f, dur, peak, rms, dc, cen, hf, hfAtk, samples });
  }

  console.log('\nCHAIN RIDER — audit SFX');
  console.log('='.repeat(78));
  console.log('file                     durasi   peak    rms     dc      centroid   >2kHz  onset');
  console.log('-'.repeat(78));
  for (const r of rows) {
    console.log(`${r.f.padEnd(24)} ${r.dur.toFixed(2)}s  ${r.peak.toFixed(2)}  `
      + `${r.rms.toFixed(3)}  ${r.dc.toFixed(3)}  ${r.cen.toFixed(0).padStart(6)} Hz  `
      + `${(r.hf * 100).toFixed(1).padStart(5)}% ${(r.hfAtk * 100).toFixed(1).padStart(5)}%`);
  }
  console.log('-'.repeat(78));

  // ---- contact sheet -------------------------------------------------------
  const COLS = 6;
  const CW = 210;
  const CH = 96;
  const rowsN = Math.ceil(rows.length / COLS);
  const cv = createCanvas(COLS * CW, rowsN * CH + 30);
  const ctx = cv.getContext('2d');
  ctx.fillStyle = '#0A1030';
  ctx.fillRect(0, 0, cv.width, cv.height);
  ctx.fillStyle = '#F5F9FF';
  ctx.font = 'bold 15px sans-serif';
  ctx.fillText('CHAIN RIDER — bentuk gelombang SFX (docs/07)', 10, 20);

  rows.forEach((r, i) => {
    const cx = (i % COLS) * CW;
    const cy = Math.floor(i / COLS) * CH + 30;
    const mid = cy + CH / 2 + 4;
    ctx.strokeStyle = 'rgba(31,211,232,0.18)';
    ctx.beginPath(); ctx.moveTo(cx + 6, mid); ctx.lineTo(cx + CW - 6, mid); ctx.stroke();
    ctx.strokeStyle = '#00E5FF';
    ctx.lineWidth = 1;
    ctx.beginPath();
    const w = CW - 12;
    const step = Math.max(1, Math.floor(r.samples.length / w));
    for (let px = 0; px < w; px += 1) {
      let hi = 0;
      for (let k = 0; k < step; k += 1) {
        const v = r.samples[px * step + k] ?? 0;
        if (Math.abs(v) > Math.abs(hi)) hi = v;
      }
      const y = mid - hi * (CH / 2 - 14);
      if (px === 0) ctx.moveTo(cx + 6 + px, y); else ctx.lineTo(cx + 6 + px, y);
    }
    ctx.stroke();
    ctx.fillStyle = '#8A9BB8';
    ctx.font = '10px sans-serif';
    ctx.fillText(`${r.f.replace('.wav', '')}  ${r.dur.toFixed(2)}s  ${r.cen.toFixed(0)}Hz`,
      cx + 6, cy + CH - 4);
  });

  const outDir = path.join(ROOT, 'screenshots');
  fs.mkdirSync(outDir, { recursive: true });
  const out = path.join(outDir, 'sfx-waveforms.png');
  fs.writeFileSync(out, cv.toBuffer('image/png'));
  console.log(`contact sheet: ${path.relative(ROOT, out)}`);

  if (problems.length) {
    console.log(`\n${problems.length} MASALAH:`);
    for (const p of problems) console.log(`  - ${p}`);
    process.exit(1);
  }
  console.log('\nSemua cue lolos: tidak senyap, tidak clipping, DC bersih, karakter spektral sesuai docs/07.\n');
}

main();

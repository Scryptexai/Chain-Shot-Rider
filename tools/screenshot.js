#!/usr/bin/env node
/**
 * Renders the real prototype to PNG files, headlessly.
 *
 *   node tools/screenshot.js                  # all five variants
 *   node tools/screenshot.js --variant=2 --at=45
 *   node tools/screenshot.js --state=menu
 *
 * Why this exists: the sandbox has no GPU, no X server and no libGL, and
 * `apt-get` cannot reach the Debian mirrors, so neither Godot nor a browser
 * can put pixels on screen here. Every visual claim up to this point was
 * inferred from code rather than seen.
 *
 * npm is reachable, though, and @napi-rs/canvas is a self-contained Skia
 * build. The prototype draws through the ordinary Canvas2D API, so pointing
 * its context at Skia renders exactly what a browser would — the real draw()
 * on real game state, not a mock-up or a diagram.
 *
 * The output is a genuine frame of the game. The Godot renderer still cannot
 * be captured; the two share a palette and layout spec, not a renderer.
 */

'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas } = require('@napi-rs/canvas');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'screenshots');
const WIDTH = 450;
const HEIGHT = 800;
const FIXED_DT = 1 / 60;

// ---------------------------------------------------------------------------
// BROWSER STUBS
// ---------------------------------------------------------------------------
// Same shape as the ones in sim_test.js, except the canvas is real. Anything
// the game reads for layout has to return believable numbers, because the
// game derives its HUD geometry from them.
function makeEnv(canvas) {
  const noop = () => {};
  const styles = new Map();

  const mkEl = (id) => {
    const el = {
      id,
      style: new Proxy({}, { set: (t, k, v) => { t[k] = v; return true; },
                             get: (t, k) => t[k] ?? '' }),
      classList: {
        _set: new Set(),
        add(c) { this._set.add(c); },
        remove(c) { this._set.delete(c); },
        toggle(c, on) { if (on === undefined) { this._set.has(c) ? this._set.delete(c) : this._set.add(c); }
                        else if (on) { this._set.add(c); } else { this._set.delete(c); } },
        contains(c) { return this._set.has(c); },
      },
      textContent: '',
      innerHTML: '',
      dataset: {},
      children: [],
      appendChild: noop,
      addEventListener: noop,
      getBoundingClientRect: () => ({ width: WIDTH, height: HEIGHT, top: 0, left: 0 }),
    };
    styles.set(id, el);
    return el;
  };

  canvas.getBoundingClientRect = () => ({ width: WIDTH, height: HEIGHT, top: 0, left: 0 });
  canvas.addEventListener = noop;
  canvas.style = {};

  const elements = new Map();
  const getById = (id) => {
    if (id === 'c') return canvas;
    if (!elements.has(id)) elements.set(id, mkEl(id));
    return elements.get(id);
  };

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

  const cssVars = {};
  global.document = {
    getElementById: getById,
    querySelectorAll: () => [],
    body: mkEl('body'),
    documentElement: { style: {
      setProperty: (k, v) => { cssVars[k] = v; },
      getPropertyValue: (k) => cssVars[k] ?? '' } },
  };
  global.window = { addEventListener: noop, devicePixelRatio: 1, AudioContext: FakeAudioCtx };
  global.requestAnimationFrame = noop;
  global.performance = { now: () => Date.now() };
  global.setTimeout = (fn) => fn();
  return { elements: getById, cssVars };
}

// ---------------------------------------------------------------------------
// LOAD THE GAME
// ---------------------------------------------------------------------------
function loadGame(canvas) {
  const env = makeEnv(canvas);
  const html = fs.readFileSync(path.join(ROOT, 'prototype', 'index.html'), 'utf8');
  // Same loading contract as tools/sim_test.js: take the script block, drop
  // the browser boot that fetches config over HTTP, then inject the config
  // from disk. Keeping the two loaders identical means a change that breaks
  // one breaks the other, loudly, instead of silently drifting apart.
  let source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  source = source.replace(/fetch\('\.\.\/Config[\s\S]*$/, '');
  const cfgPath = JSON.stringify(path.join(ROOT, 'Config', 'arena_config.json'));
  source += `
    CFG = JSON.parse(require('fs').readFileSync(${cfgPath}, 'utf8'));
    module.exports = { get S(){return S;}, get CFG(){return CFG;},
                       loadVariant, resetRun, simulate, draw, fire, resize };
  `;

  const module = { exports: {} };
  new Function('module', 'require', source)(module, require);
  return { game: module.exports, env };
}

// ---------------------------------------------------------------------------
// CAPTURE
// ---------------------------------------------------------------------------
function capture(variant, seconds, label) {
  const canvas = createCanvas(WIDTH, HEIGHT);
  const { game } = loadGame(canvas);
  game.resize();
  game.loadVariant(variant);

  // Play forward with a simple bot so the frame has a crowd, gates, a chain
  // shot in flight — an empty arena proves nothing about the visuals.
  const S = game.S;
  const ticks = Math.round(seconds / FIXED_DT);
  for (let i = 0; i < ticks; i += 1) {
    const enemies = S.enemies ?? [];
    if (enemies.length > 0) {
      let sum = 0;
      let weight = 0;
      for (const e of enemies) { const w = 1 / Math.max(e.z, 1); sum += e.x * w; weight += w; }
      S.squadTargetX = sum / Math.max(weight, 0.001);
    }
    // fire() is the prototype's chain shot. Firing on a cadence keeps a
    // bullet in flight for most frames, so the captured frame actually shows
    // the signature mechanic rather than just auto-fire chip damage.
    if (i % 24 === 0) game.fire();
    game.simulate(FIXED_DT);
  }
  game.draw();

  fs.mkdirSync(OUT, { recursive: true });
  const file = path.join(OUT, `${label}.png`);
  fs.writeFileSync(file, canvas.toBuffer('image/png'));
  const size = (fs.statSync(file).size / 1024).toFixed(0);
  console.log(`  ${path.relative(ROOT, file)}  ${WIDTH}x${HEIGHT}  ${size} KB  t=${seconds}s`);
  return file;
}

function main() {
  const args = process.argv.slice(2);
  const arg = (name, fallback) => {
    const hit = args.find((a) => a.startsWith(`--${name}=`));
    return hit ? hit.split('=')[1] : fallback;
  };

  const names = ['classic-pit', 'twin-towers', 'gravity-chamber', 'explosive-yard', 'moving-maze'];
  const at = Number(arg('at', 40));

  console.log('\nCHAIN RIDER — tangkapan layar prototipe (Skia, tanpa GPU)');
  if (args.some((a) => a.startsWith('--variant='))) {
    const v = Number(arg('variant', 0));
    capture(v, at, `${String(v + 1).padStart(2, '0')}-${names[v]}`);
  } else {
    for (let v = 0; v < names.length; v += 1) {
      capture(v, at, `${String(v + 1).padStart(2, '0')}-${names[v]}`);
    }
  }
  console.log('');
}

main();

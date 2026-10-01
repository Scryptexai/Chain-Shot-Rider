#!/usr/bin/env node
/**
 * render3d_test.js — Bukti geometri untuk kamera WebGL CHAIN RIDER.
 *
 * Sandbox ini tidak punya GPU, jadi hasil render tidak bisa dilihat. Yang BISA
 * dibuktikan tanpa GPU adalah matematikanya: Three.js menghitung matriks
 * proyeksi di CPU. Tes ini memproyeksikan titik-titik penting arena lewat
 * kamera yang SAMA PERSIS dengan yang dipakai game (R3D.makeCamera, bukan
 * salinan), lalu memastikan semuanya jatuh di dalam layar portrait.
 *
 * Yang dibuktikan: arena 20x40 muat di 9:16, squad ada di bawah, zona spawn ada
 * di atas, dan tidak ada yang terpotong.
 * Yang TIDAK dibuktikan: warna, cahaya, dan rasa. Itu hanya bisa dinilai mata
 * di browser sungguhan.
 *
 * Pemakaian: node tools/render3d_test.js
 */

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const THREE = require(path.join(ROOT, 'js/vendor/three.min.js'));

// Kanvas palsu: Three.js hanya menyimpan elemennya untuk CanvasTexture, tidak
// menggambar apa pun di sisi CPU, jadi context no-op sudah cukup.
function fakeCanvas() {
  const ctx = new Proxy({}, { get: () => () => {}, set: () => true });
  return { width: 0, height: 0, getContext: () => ctx, style: {},
           classList: { add() {}, remove() {} } };
}
const fakeDocument = { createElement: () => fakeCanvas() };

// Memuat renderer apa adanya, lalu menyuntikkan THREE seperti browser.
const sandbox = { devicePixelRatio: 1 };
new Function('globalThis', 'window', 'document',
  fs.readFileSync(path.join(ROOT, 'js/render3d.js'), 'utf8')
)(sandbox, sandbox, fakeDocument);
const R3D = sandbox.R3D;
R3D._setThree(THREE);

let failures = 0;
function check(label, cond, detail) {
  if (cond) console.log(`  OK   ${label}${detail ? '  — ' + detail : ''}`);
  else { failures++; console.log(`  GAGAL ${label}${detail ? '  — ' + detail : ''}`); }
}

const ASPECT = 9 / 16;                     // portrait, sama dengan #stage
const camera = R3D.makeCamera(ASPECT);

/** Simulasi (x, z) -> NDC. x kanan, y atas, keduanya harus di [-1, 1]. */
function project(x, z, y = 0) {
  const v = new THREE.Vector3(x, y, -z);
  v.project(camera);
  return { x: v.x, y: v.y };
}
const inside = (p, m = 1) => Math.abs(p.x) <= m && Math.abs(p.y) <= m;
const fmt = (p) => `(${p.x.toFixed(2)}, ${p.y.toFixed(2)})`;

console.log('\nCHAIN RIDER — bukti geometri kamera WebGL');
console.log('='.repeat(72));
console.log(`kamera: fov ${R3D.CAM.fov}  posisi [${R3D.CAM.pos}]  lihat [${R3D.CAM.look}]`);
console.log(`arena : lebar ${R3D.ARENA.halfWidth * 2}  dalam ${R3D.ARENA.depth}  aspect ${ASPECT.toFixed(4)}\n`);

const HW = R3D.ARENA.halfWidth;
const D = R3D.ARENA.depth;

console.log('[1] Seluruh lantai arena masuk layar');
const corners = {
  'sudut dekat kiri': project(-HW, 0),
  'sudut dekat kanan': project(HW, 0),
  'sudut jauh kiri': project(-HW, D),
  'sudut jauh kanan': project(HW, D),
};
for (const [name, p] of Object.entries(corners)) {
  check(name + ' terlihat', inside(p), fmt(p));
}

console.log('\n[2] Elemen gameplay berada di tempat yang benar');
const squad = project(0, 2);
const defense = project(0, 5);
const spawn = project(0, D - 2);
const gate = project(0, 38);
check('squad terlihat', inside(squad), fmt(squad));
check('squad ada di paruh bawah layar', squad.y < 0, `y=${squad.y.toFixed(2)}`);
check('garis pertahanan terlihat', inside(defense), fmt(defense));
check('garis pertahanan di atas squad', defense.y > squad.y,
  `${defense.y.toFixed(2)} > ${squad.y.toFixed(2)}`);
check('zona spawn terlihat', inside(spawn), fmt(spawn));
check('zona spawn ada di paruh atas layar', spawn.y > 0, `y=${spawn.y.toFixed(2)}`);
check('gate muncul di dalam layar (z=38)', inside(gate), fmt(gate));

console.log('\n[3] Lebar arena terpakai, tidak kesempitan dan tidak terpotong');
const nearW = Math.abs(corners['sudut dekat kanan'].x - corners['sudut dekat kiri'].x) / 2;
const farW = Math.abs(corners['sudut jauh kanan'].x - corners['sudut jauh kiri'].x) / 2;
check('baris dekat mengisi >=70% lebar layar', nearW >= 0.7,
  `${(nearW * 100).toFixed(0)}%`);
check('baris dekat tidak terpotong', nearW <= 1.0, `${(nearW * 100).toFixed(0)}%`);
check('perspektif terasa: baris jauh lebih sempit', farW < nearW,
  `jauh ${(farW * 100).toFixed(0)}% < dekat ${(nearW * 100).toFixed(0)}%`);

console.log('\n[4] Kedalaman terpakai sepanjang layar');
const depthSpan = project(0, D).y - project(0, 0).y;
check('arena membentang >=70% tinggi layar', depthSpan >= 1.4,
  `${(depthSpan / 2 * 100).toFixed(0)}% tinggi`);

console.log('\n[5] Squad bergerak kiri-kanan tetap di dalam layar');
for (const x of [-HW + 0.5, 0, HW - 0.5]) {
  const p = project(x, 2);
  check(`squad di x=${x} terlihat`, inside(p), fmt(p));
}

// ---------------------------------------------------------------------------
// Bagian 6-8: logika renderer. Three.js membangun scene graph di CPU; hanya
// WebGLRenderer yang butuh GL, jadi itu saja yang distub.
// ---------------------------------------------------------------------------
console.log('\n[6] Renderer membangun scene dan menempatkan mesh');
let renderCalls = 0;
THREE.WebGLRenderer = function () {
  return {
    setPixelRatio() {}, setSize() {},
    render() { renderCalls++; },
  };
};
sandbox.THREE = THREE;
const ok = R3D.init(fakeCanvas());
check('init berhasil tanpa GPU', ok === true && R3D.ready === true);

const CFG = JSON.parse(fs.readFileSync(path.join(ROOT, 'Config/arena_config.json'), 'utf8'));
let rngCalls = 0;
const S = {
  troops: 7, squadX: 3.5, fov: 1, shake: 0, elapsed: 4,
  enemies: [
    { x: -2, z: 18, r: 0.38, color: '#ff4d3d', hit: 0 },
    { x: 4.5, z: 25, r: 0.55, color: '#b14dff', hit: 1 },
  ],
  autoBullets: [{ x: 0, z: 6 }, { x: 1, z: 9 }],
  bullets: [{ x: -1, z: 12, alive: true }],
  gates: [{ z: 30, left: { op: 'mul', value: 2, positive: true },
            right: { op: 'sub', value: 5, positive: false } }],
  obstacles: [{ kind: 'bumper', x: 0, z: 20, r: 0.9, alive: true }],
  boss: null,
  rng: { f: () => { rngCalls++; return 0.5; } },
};
R3D.sync(S, CFG);
check('render dipanggil sekali per sync', renderCalls === 1);

// Mesh dicari lewat scene graph sungguhan, bukan lewat variabel internal.
const scene = R3D._scene();
const grp = (name) => scene.getObjectByName(name);
const visible = (name) => grp(name).children.filter((c) => c.visible);
check('jumlah prajurit = S.troops', visible('troops').length === 7,
  `terlihat ${visible('troops').length}`);
check('jumlah musuh = S.enemies', visible('enemies').length === 2);
check('peluru = auto + chain', visible('bullets').length === 3);
check('gate menghasilkan 2 panel', visible('gates').length === 2);

console.log('\n[7] Pemetaan dunia simulasi -> three.js benar (x, y, -z)');
const en = visible('enemies')[0];
check('musuh x dipetakan apa adanya', Math.abs(en.position.x - (-2)) < 1e-6,
  `x=${en.position.x}`);
check('musuh z dibalik tandanya', Math.abs(en.position.z - (-18)) < 1e-6,
  `z=${en.position.z} (sim z=18)`);
check('musuh diangkat di atas lantai', en.position.y > 0, `y=${en.position.y.toFixed(2)}`);
const gp = visible('gates');
check('panel gate kiri dan kanan terpisah',
  Math.sign(gp[0].position.x) !== Math.sign(gp[1].position.x),
  `${gp[0].position.x.toFixed(2)} vs ${gp[1].position.x.toFixed(2)}`);
check('panel gate berada di z gate', Math.abs(gp[0].position.z - (-30)) < 1e-6);
const tr = visible('troops');
const avgX = tr.reduce((a, t) => a + t.position.x, 0) / tr.length;
check('formasi squad terpusat di squadX', Math.abs(avgX - 3.5) < 0.6,
  `rata-rata x=${avgX.toFixed(2)}`);

console.log('\n[8] Renderer tidak boleh menyentuh simulasi');
check('tidak memakai RNG simulasi', rngCalls === 0, `${rngCalls} panggilan`);
const before = JSON.stringify(S, (k, v) => (k === 'rng' ? undefined : v));
R3D.sync(S, CFG);
const after = JSON.stringify(S, (k, v) => (k === 'rng' ? undefined : v));
check('state simulasi tidak berubah setelah render', before === after);

const poolAfterBig = (() => {
  S.enemies = Array.from({ length: 180 }, (_, i) => (
    { x: (i % 19) - 9, z: 5 + (i % 30), r: 0.38, color: '#ff4d3d', hit: 0 }));
  R3D.sync(S, CFG);
  const peak = grp('enemies').children.length;
  S.enemies = S.enemies.slice(0, 3);
  R3D.sync(S, CFG);
  return { peak, after: grp('enemies').children.length,
           shown: visible('enemies').length };
})();
check('mesh dipakai ulang, bukan dibuat terus', poolAfterBig.after === poolAfterBig.peak,
  `kolam tetap ${poolAfterBig.peak} mesh`);
check('mesh berlebih disembunyikan, bukan dihapus', poolAfterBig.shown === 3,
  `terlihat ${poolAfterBig.shown} dari ${poolAfterBig.after}`);

console.log('\n' + '='.repeat(72));
console.log(failures === 0
  ? 'LULUS — framing kamera dan logika renderer terbukti'
  : `GAGAL — ${failures} pemeriksaan gagal`);
process.exit(failures === 0 ? 0 : 1);

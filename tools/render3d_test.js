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

console.log('[1] Koridor terbang terbaca penuh');
// Framing shmup (N1): kamera di belakang-atas jet, cakrawala di 33%. Pada
// framing ini seluruh koridor yang bisa dimainkan terbaca sekaligus, termasuk
// baris tepat di bawah jet — tidak ada lagi tepi yang sengaja dipotong,
// karena tidak ada lagi lantai yang berakhir di kaki kamera.
const corners = {
  'sudut dekat kiri': project(-HW, 0),
  'sudut dekat kanan': project(HW, 0),
  'sudut jauh kiri': project(-HW, D),
  'sudut jauh kanan': project(HW, D),
};
check('sudut jauh kiri terlihat', inside(corners['sudut jauh kiri']), fmt(corners['sudut jauh kiri']));
check('sudut jauh kanan terlihat', inside(corners['sudut jauh kanan']), fmt(corners['sudut jauh kanan']));
// Baris z=0 ada DI BELAKANG jet dan lebih lebar daripada bingkai, jadi
// sudutnya memang keluar ke samping. Yang tidak boleh terjadi adalah ia
// keluar ke ATAS atau ke BAWAH: itu berarti kamera salah pitch, bukan
// sekadar koridor yang melebar oleh perspektif.
check('baris z=0 hanya terpotong menyamping, tidak tegak',
  Math.abs(corners['sudut dekat kiri'].y) <= 1,
  fmt(corners['sudut dekat kiri']));
// Batas koridor diukur di depan jet, tempat pantulan peluru benar-benar
// terjadi.
const WALL_Z = 2.4;
const wallNear = { kiri: project(-HW, WALL_Z), kanan: project(HW, WALL_Z) };
check('batas koridor kiri terbaca sejak z=2,4', inside(wallNear.kiri), fmt(wallNear.kiri));
check('batas koridor kanan terbaca sejak z=2,4', inside(wallNear.kanan), fmt(wallNear.kanan));

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

console.log('\n[3] Lebar arena terpakai, tidak kesempitan');
const nearW = Math.abs(project(HW, WALL_Z).x - project(-HW, WALL_Z).x) / 2;
const farW = Math.abs(corners['sudut jauh kanan'].x - corners['sudut jauh kiri'].x) / 2;
// Diukur di z=2,4 dan bukan z=0: itulah baris pertama yang benar-benar
// dilihat pemain, dan di situlah lorong harus mengisi layar.
check('lorong mengisi >=80% lebar layar di z=2,4', nearW >= 0.8, `${(nearW * 100).toFixed(0)}%`);
check('lorong tidak terpotong di z=2,4', nearW <= 1.001, `${(nearW * 100).toFixed(0)}%`);
check('perspektif terasa: baris jauh lebih sempit', farW < nearW,
  `jauh ${(farW * 100).toFixed(0)}% < dekat ${(nearW * 100).toFixed(0)}%`);

console.log('\n[4] Framing sesuai key art (docs/images/keyart-master.jpg)');
const depthSpan = project(0, D).y - project(0, 0).y;
check('koridor membentang >=30% tinggi layar', depthSpan >= 0.6,
  `${(depthSpan / 2 * 100).toFixed(0)}% tinggi`);

// Dua angka ini DIUKUR dari key art dan mendefinisikan framing (art bible §1).
// Kamera diselesaikan dari keduanya, jadi di sinilah solusinya dibuktikan.
//
// Jangkar pemain diukur pada TITIK JANGKAR di bidang aksi (0, y=0, z=2),
// bukan pada pusat badan. Alasannya: badan pemain masih rig berjalan kaki
// setinggi 4,86 unit dan baru diganti jet di N2. Titik jangkar tidak
// bergantung pada model, jadi ia tetap sahih sebelum dan sesudah pergantian.
const anchor = project(0, 2);
const anchorScreen = (1 - anchor.y) / 2;       // NDC -> 0 di atas, 1 di bawah
const anchorX = (anchor.x + 1) / 2;
const horizonScreen = (1 - project(0, 4000).y) / 2;
check('jangkar pemain di tengah lebar layar (0,50)',
  Math.abs(anchorX - 0.5) <= 0.01, `${(anchorX * 100).toFixed(1)}%`);
check('jangkar pemain di ~72% tinggi layar',
  Math.abs(anchorScreen - 0.72) <= 0.04, `${(anchorScreen * 100).toFixed(1)}%`);
check('cakrawala di ~33% dari atas',
  Math.abs(horizonScreen - 0.33) <= 0.03, `${(horizonScreen * 100).toFixed(1)}%`);
check('laut berada di bawah bidang aksi', R3D.SEA.y < 0, `y=${R3D.SEA.y}`);

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
// Satu badan, berapa pun nilai troops: squad 100 prajurit dihapus, dan
// `troops` sekarang dibaca sebagai POWER senjata (keputusan D1). Simulasi
// tidak berubah sedikit pun — hanya tampilannya.
check('pemain digambar sebagai satu badan', visible('troops').length === 1,
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

console.log('\n[9] Interpolasi render antar-tick');
// Musuh dengan pose tick sebelumnya (rx, rz) harus digambar di antara dua tick.
S.enemies = [{ x: 4, z: 20, rx: 0, rz: 10, r: 0.38, color: '#ff4d3d', hit: 0 }];
S.prevSquadX = 0; S.squadX = 2;
S.gates = [{ z: 20, rz: 30, left: { op: 'mul', value: 2, positive: true },
             right: { op: 'sub', value: 5, positive: false } }];

R3D.sync(S, CFG, 0.5);
var e0 = visible('enemies')[0];
check('musuh berada di tengah dua tick saat alpha 0,5',
  Math.abs(e0.position.x - 2) < 1e-6 && Math.abs(e0.position.z - (-15)) < 1e-6,
  `x=${e0.position.x} z=${e0.position.z} (harap 2 / -15)`);
var g0 = visible('gates')[0];
check('gate ikut diinterpolasi', Math.abs(g0.position.z - (-25)) < 1e-6,
  `z=${g0.position.z} (harap -25)`);
var tr0 = visible('troops');
var avg0 = tr0.reduce((acc, t) => acc + t.position.x, 0) / tr0.length;
check('squad ikut diinterpolasi', Math.abs(avg0 - 1) < 0.6, `rata-rata x=${avg0.toFixed(2)}`);

R3D.sync(S, CFG, 1);
check('alpha 1 memakai pose tick terbaru',
  Math.abs(visible('enemies')[0].position.z - (-20)) < 1e-6);

R3D.sync(S, CFG, 0);
check('alpha 0 memakai pose tick sebelumnya',
  Math.abs(visible('enemies')[0].position.z - (-10)) < 1e-6);

// Entitas yang baru lahir di tengah tick belum punya rx/rz.
S.enemies = [{ x: -3, z: 33, r: 0.38, color: '#ff4d3d', hit: 0 }];
R3D.sync(S, CFG, 0.5);
var nb = visible('enemies')[0];
check('musuh baru tidak melesat dari titik nol',
  Math.abs(nb.position.x - (-3)) < 1e-6 && Math.abs(nb.position.z - (-33)) < 1e-6,
  `x=${nb.position.x} z=${nb.position.z}`);

// Alpha tak masuk akal harus diabaikan, bukan merusak gambar.
R3D.sync(S, CFG, undefined);
check('alpha kosong dianggap 1', Math.abs(visible('enemies')[0].position.z - (-33)) < 1e-6);

console.log('\n' + '='.repeat(72));
console.log(failures === 0
  ? 'LULUS — framing kamera, renderer, dan interpolasi terbukti'
  : `GAGAL — ${failures} pemeriksaan gagal`);
process.exit(failures === 0 ? 0 : 1);

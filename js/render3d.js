/**
 * render3d.js — WebGL renderer for CHAIN RIDER.
 *
 * Same approach Last Harbor uses to show a game in the browser without
 * installing an engine: vendored Three.js (r128, UMD, classic script tag),
 * a real perspective camera, real lights, real meshes. No build step, no CDN,
 * no npm at runtime.
 *
 * This file only DRAWS. It never touches simulation state, never consumes the
 * simulation RNG, and never decides gameplay — it reads `S` once per frame and
 * moves meshes to match. Keeping it read-only is what lets the browser build
 * and the Godot build stay in step.
 *
 * World mapping: simulation (x, z) -> three.js (x, y, -z), matching the Godot
 * convention. Simulation z grows away from the player; three.js -z does too.
 *
 * Exposed as window.R3D (classic script, no modules, so file:// and any static
 * host work the same).
 */

(function (global) {
  'use strict';

  // --- Framing ---------------------------------------------------------------
  // Arena is 20 wide x 40 deep; portrait is 9:16. Those ratios (1:2 vs 1:1.78)
  // are close, so a high, steeply tilted camera frames the lane almost exactly.
  // Verified numerically by tools/render3d_test.js, not by eyeballing.
  var CAM = {
    fov: 41,          // vertical FOV in degrees
    pos: [0, 51, 14], // three.js position: high, tilted 33.7 degrees
    look: [0, 0, -20],
    near: 0.5,
    far: 160,
  };

  var ARENA = { halfWidth: 10, depth: 40, defenseLineZ: 5 };

  var PAL = {
    bg: 0x060b1e,
    floor: 0x0d1736,
    floorFar: 0x070c22,
    grid: 0x1fd3e8,
    wall: 0x123a5c,
    danger: 0xff1744,
    gatePos: 0x3ddc97,
    gateNeg: 0xff4d3d,
    bullet: 0xfff3c4,
    chain: 0x00e5ff,
  };

  var THREE = null;
  var renderer = null, scene = null, camera = null, canvas = null;
  var groups = {};
  var pools = {};
  var labelCache = {};
  var baseFov = CAM.fov;
  var accentColor = 0x00e5ff;

  // ---------------------------------------------------------------------------
  // Small object pool: meshes are reused across frames so a wave of 200 enemies
  // never allocates mid-frame.
  // ---------------------------------------------------------------------------
  function makePool(parent, factory) {
    return {
      items: [], used: 0,
      begin: function () { this.used = 0; },
      take: function () {
        var it = this.items[this.used];
        if (!it) { it = factory(); this.items.push(it); parent.add(it); }
        this.used++; it.visible = true; return it;
      },
      end: function () {
        for (var i = this.used; i < this.items.length; i++) this.items[i].visible = false;
      },
    };
  }

  /** Builds the perspective camera. Shared with the test so framing is proven. */
  function makeCamera(aspect) {
    var cam = new THREE.PerspectiveCamera(CAM.fov, aspect, CAM.near, CAM.far);
    cam.position.set(CAM.pos[0], CAM.pos[1], CAM.pos[2]);
    cam.lookAt(CAM.look[0], CAM.look[1], CAM.look[2]);
    cam.updateMatrixWorld(true);
    cam.updateProjectionMatrix();
    return cam;
  }

  /** Grid texture drawn procedurally — no image files to ship or load. */
  function makeGridTexture() {
    var c = document.createElement('canvas');
    c.width = c.height = 256;
    var g = c.getContext('2d');
    g.fillStyle = '#0d1736'; g.fillRect(0, 0, 256, 256);
    g.strokeStyle = 'rgba(31,211,232,0.30)'; g.lineWidth = 2;
    g.beginPath(); g.moveTo(0, 0); g.lineTo(256, 0); g.moveTo(0, 0); g.lineTo(0, 256); g.stroke();
    var tex = new THREE.CanvasTexture(c);
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(ARENA.halfWidth, ARENA.depth / 2);
    return tex;
  }

  /** Gate labels ("x2", "+8", "-5") as cached canvas textures. */
  function labelTexture(text, positive) {
    var key = text + (positive ? '+' : '-');
    if (labelCache[key]) return labelCache[key];
    var c = document.createElement('canvas');
    c.width = 256; c.height = 128;
    var g = c.getContext('2d');
    g.fillStyle = positive ? 'rgba(14,52,40,0.92)' : 'rgba(58,14,14,0.92)';
    g.fillRect(0, 0, 256, 128);
    g.strokeStyle = positive ? '#3ddc97' : '#ff4d3d'; g.lineWidth = 8;
    g.strokeRect(4, 4, 248, 120);
    g.fillStyle = positive ? '#d6ffe9' : '#ffd9d4';
    g.font = 'bold 76px system-ui, sans-serif';
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(text, 128, 68);
    var tex = new THREE.CanvasTexture(c);
    labelCache[key] = tex;
    return tex;
  }

  function gateText(op) {
    if (!op) return '?';
    if (op.op === 'mul') return 'x' + op.value;
    if (op.op === 'add') return (op.value >= 0 ? '+' : '') + op.value;
    if (op.op === 'sub') return '-' + Math.abs(op.value);
    if (op.op === 'div') return '/' + op.value;
    return String(op.value);
  }

  /** One soldier: cylinder body + sphere head. Cheap, readable at this scale. */
  function makeTroop(color) {
    var grp = new THREE.Group();
    var mat = new THREE.MeshLambertMaterial({ color: color, emissive: color, emissiveIntensity: 0.22 });
    var body = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.2, 0.52, 7), mat);
    body.position.y = 0.26;
    var head = new THREE.Mesh(new THREE.SphereGeometry(0.15, 8, 6), mat);
    head.position.y = 0.62;
    grp.add(body); grp.add(head);
    return grp;
  }

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------
  function init(cv) {
    if (!global.THREE) return false;
    THREE = global.THREE;
    canvas = cv;

    renderer = new THREE.WebGLRenderer({
      canvas: canvas, antialias: false,
      powerPreference: 'high-performance', precision: 'mediump',
    });
    renderer.setPixelRatio(Math.min(global.devicePixelRatio || 1, 1.25));

    scene = new THREE.Scene();
    scene.background = new THREE.Color(PAL.bg);
    scene.fog = new THREE.FogExp2(PAL.bg, 0.016);

    camera = makeCamera(9 / 16);

    scene.add(new THREE.HemisphereLight(0x9fd8ff, 0x0a1030, 1.05));
    var sun = new THREE.DirectionalLight(0xfff0e0, 1.35);
    sun.position.set(16, 34, 18); scene.add(sun);
    var fill = new THREE.DirectionalLight(0x4da6ff, 0.55);
    fill.position.set(-18, 20, -16); scene.add(fill);

    // --- static world ---
    var floorMat = new THREE.MeshLambertMaterial({ map: makeGridTexture() });
    var floor = new THREE.Mesh(new THREE.PlaneGeometry(ARENA.halfWidth * 2, ARENA.depth), floorMat);
    floor.rotation.x = -Math.PI / 2;
    floor.position.set(0, 0, -ARENA.depth / 2);
    scene.add(floor);

    var wallMat = new THREE.MeshLambertMaterial({
      color: PAL.wall, emissive: PAL.grid, emissiveIntensity: 0.18,
    });
    [-1, 1].forEach(function (s) {
      var w = new THREE.Mesh(new THREE.BoxGeometry(0.5, 1.4, ARENA.depth), wallMat);
      w.position.set(s * (ARENA.halfWidth + 0.25), 0.7, -ARENA.depth / 2);
      scene.add(w);
    });

    var line = new THREE.Mesh(
      new THREE.BoxGeometry(ARENA.halfWidth * 2, 0.07, 0.3),
      new THREE.MeshBasicMaterial({ color: PAL.danger, transparent: true, opacity: 0.85 })
    );
    line.position.set(0, 0.04, -ARENA.defenseLineZ);
    scene.add(line);
    groups.defenseLine = line;

    // --- dynamic groups ---
    ['troops', 'enemies', 'bullets', 'gates', 'obstacles', 'boss', 'fx'].forEach(function (k) {
      groups[k] = new THREE.Group();
      groups[k].name = k;           // named so tests can walk the real scene graph
      scene.add(groups[k]);
    });

    pools.troops = makePool(groups.troops, function () { return makeTroop(accentColor); });
    pools.enemies = makePool(groups.enemies, function () {
      return new THREE.Mesh(new THREE.SphereGeometry(1, 10, 8),
        new THREE.MeshLambertMaterial({ color: 0xffffff }));
    });
    pools.bullets = makePool(groups.bullets, function () {
      return new THREE.Mesh(new THREE.SphereGeometry(1, 8, 6),
        new THREE.MeshBasicMaterial({ color: PAL.bullet }));
    });
    pools.gatePanels = makePool(groups.gates, function () {
      return new THREE.Mesh(new THREE.PlaneGeometry(1, 1),
        new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.93, side: THREE.DoubleSide }));
    });
    pools.obstacles = makePool(groups.obstacles, function () {
      return new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 1, 10),
        new THREE.MeshLambertMaterial({ color: 0xffffff }));
    });
    pools.bossParts = makePool(groups.boss, function () {
      return new THREE.Mesh(new THREE.SphereGeometry(1, 14, 10),
        new THREE.MeshLambertMaterial({ color: 0xff4d3d, emissive: 0x330000 }));
    });

    api.ready = true;
    return true;
  }

  function setAccent(hex) {
    accentColor = hex;
    pools.troops.items.forEach(function (grp) {
      grp.children.forEach(function (m) {
        m.material.color.setHex(hex); m.material.emissive.setHex(hex);
      });
    });
  }

  function resize(w, h) {
    if (!renderer) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }

  // ---------------------------------------------------------------------------
  // SYNC — read simulation state, move meshes. Read-only on S.
  // ---------------------------------------------------------------------------
  function sync(S, CFG) {
    if (!api.ready || !CFG) return;

    // Slow-mo pulls the camera in, mirroring the FOV 60->40 spec.
    camera.fov = baseFov * (0.82 + 0.18 * (S.fov === undefined ? 1 : S.fov));
    // Screen shake is cosmetic only: it must never feed back into the sim.
    var sh = S.shake || 0;
    camera.position.set(CAM.pos[0] + (sh ? (Math.random() - 0.5) * sh * 0.5 : 0),
      CAM.pos[1], CAM.pos[2]);
    camera.lookAt(CAM.look[0], CAM.look[1], CAM.look[2]);
    camera.updateProjectionMatrix();

    groups.defenseLine.material.opacity = 0.55 + 0.35 * Math.abs(Math.sin((S.elapsed || 0) * 2));

    // --- squad: a block formation centred on squadX ---
    pools.troops.begin();
    var shown = Math.min(S.troops || 0, 48);
    var perRow = 6, sx = S.squadX || 0;
    var sz = (CFG.arena && CFG.arena.playerSpawn ? CFG.arena.playerSpawn.z : 2);
    for (var i = 0; i < shown; i++) {
      var row = Math.floor(i / perRow), col = i % perRow;
      var t = pools.troops.take();
      t.position.set(sx + (col - (perRow - 1) / 2) * 0.42, 0, -(sz - row * 0.45));
    }
    pools.troops.end();

    // --- enemies ---
    pools.enemies.begin();
    var list = S.enemies || [];
    for (var e = 0; e < list.length; e++) {
      var en = list[e];
      var m = pools.enemies.take();
      var r = en.r || 0.4;
      m.scale.set(r, r * 1.15, r);
      m.position.set(en.x, r * 1.1, -en.z);
      m.material.color.set(en.color || '#ff4d3d');
      m.material.emissive.set(en.hit > 0 ? 0xffffff : 0x000000);
    }
    pools.enemies.end();

    // --- bullets: auto fire + the single chain bullet ---
    pools.bullets.begin();
    var ab = S.autoBullets || [];
    for (var a = 0; a < ab.length; a++) {
      var bm = pools.bullets.take();
      bm.scale.setScalar(0.13);
      bm.position.set(ab[a].x, 0.45, -ab[a].z);
      bm.material.color.setHex(PAL.bullet);
    }
    var cb = S.bullets || [];
    for (var b = 0; b < cb.length; b++) {
      if (!cb[b].alive) continue;
      var cm = pools.bullets.take();
      cm.scale.setScalar(0.3);
      cm.position.set(cb[b].x, 0.5, -cb[b].z);
      cm.material.color.setHex(PAL.chain);
    }
    pools.bullets.end();

    // --- gates: two panels with their operation printed on them ---
    pools.gatePanels.begin();
    var G = CFG.gates, gl = S.gates || [];
    if (G) {
      var gap = G.centerGapX || 0.6, hw = G.halfWidth || 4.7;
      var panelW = hw - gap;
      for (var g = 0; g < gl.length; g++) {
        var gt = gl[g];
        [['left', gt.left, -1], ['right', gt.right, 1]].forEach(function (side) {
          var op = side[1], dir = side[2];
          var p = pools.gatePanels.take();
          p.scale.set(panelW, 1.7, 1);
          p.position.set(dir * (gap + panelW / 2), 0.9, -gt.z);
          p.material.map = labelTexture(gateText(op), !!(op && op.positive));
          p.material.color.setHex(0xffffff);
          p.material.needsUpdate = true;
        });
      }
    }
    pools.gatePanels.end();

    // --- obstacles ---
    pools.obstacles.begin();
    var ob = S.obstacles || [];
    for (var o = 0; o < ob.length; o++) {
      var os = ob[o];
      if (!os.alive) continue;
      var om = pools.obstacles.take();
      if (os.kind === 'shieldWall') {
        om.scale.set((os.w || 4) / 2, 1.1, 0.25);
        om.material.color.setHex(0xb14dff);
      } else if (os.kind === 'barrel') {
        om.scale.set(os.r || 0.6, 0.9, os.r || 0.6);
        om.material.color.setHex(0xff8a2b);
      } else {
        om.scale.set(os.r || 0.9, 0.7, os.r || 0.9);
        om.material.color.setHex(0x1fd3e8);
      }
      om.position.set(os.x, 0.5, -os.z);
    }
    pools.obstacles.end();

    // --- boss ---
    pools.bossParts.begin();
    if (S.boss && S.boss.parts) {
      for (var p2 = 0; p2 < S.boss.parts.length; p2++) {
        var part = S.boss.parts[p2];
        if (!part.alive) continue;
        var pm = pools.bossParts.take();
        var pr = part.r || 1.8;
        pm.scale.setScalar(pr);
        pm.position.set(part.x, pr, -part.z);
        pm.material.emissive.setHex(part.hit > 0 ? 0xaa2222 : 0x330000);
      }
    }
    pools.bossParts.end();

    renderer.render(scene, camera);
  }

  var api = {
    ready: false,
    init: init, sync: sync, resize: resize, setAccent: setAccent,
    makeCamera: makeCamera, CAM: CAM, ARENA: ARENA,
    _setThree: function (t) { THREE = t; },   // for the headless geometry test
    _scene: function () { return scene; },    // ditto
  };
  global.R3D = api;
})(typeof window !== 'undefined' ? window : globalThis);

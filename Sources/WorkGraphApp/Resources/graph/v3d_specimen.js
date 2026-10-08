/* 측정 (three.js): 흐름 바탕 위에 놓인 식물 표본 한 송이(튤립)와 그 위에 얹은 측정값 덮개. 꽃은 분위기용이고 정보는 덮개의 선과 표식이 맡는다.
   층마다 표식이 다르다. 나 = 겹 고리(꽃 가운데), 분야 = 속 빈 원과 굵은 이름과 합계, 업무 = 쓴 시간만큼 긴 치수선과 가운데 숫자,
   세션 = 치수선 둘레 안쪽 궤도의 작은 속 빈 원, 자료 = 바깥 궤도의 짧은 눈금(종류마다 색). 실선 = 소속(나 > 분야 > 업무), 점선 = 관계(같은 자료를 쓴 업무 쌍).
   상자와 바탕 판은 쓰지 않는다. 글자와 선은 꽃 위에서는 먹색, 어두운 바탕 위에서는 크림색으로 그려 어디서나 읽힌다(꽃 실루엣 지도로 고른다).
   범례는 왼쪽 아래 작은 글자와 표식. 꽃은 천천히 돌고 숨 쉬며, 덮개는 꽃 가운데를 따라 움직인다. 꽃 뒤로 아주 큰 가는 호가 천천히 돈다 */
window.V3D = window.V3D || {};
window.V3D.specimen = function (main, data, ui) {
  let dead = false, cleanup = () => {};
  const start = () => { if (!dead) cleanup = build(window.THREE); };
  if (window.THREE) start(); else window.addEventListener('three-ready', start, { once: true });
  return () => { dead = true; window.removeEventListener('three-ready', start); cleanup(); };

  function build(THREE) {
    const INK = '#24150F', INK3 = '36,21,15', CRM = '246,243,238', CR = '#F6F3EE', FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
    const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
    const mix = (a, b, t) => a + (b - a) * t;
    const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
    const hash = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
    const rng = seed => () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    const V = (x, y, z) => new THREE.Vector3(x, y, z);
    const RM = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches), SPEED = RM ? 0.05 : 1;
    const fmt = n => Math.round(n).toLocaleString('en-US');

    const tasks = data.tasks.filter(t => data.themes.some(h => h.id === t.theme));
    const themes = data.themes.filter(th => tasks.some(t => t.theme === th.id));
    const NK = tasks.length, NT = themes.length;
    const itemsOf = t => Object.entries(t.items || {}).flatMap(([k, a]) => (a || []).map(n => ({ k, n: typeof n === 'string' ? n : (n && (n.name || n.title)) || '자료' })));
    const kindOf = k => (data.kinds && data.kinds[k]) || { name: k, color: '#8a837e' };
    const kcol = {}, kcol2 = {}, kc = k => kcol[k] || (kcol[k] = rgbOf(kindOf(k).color).join(',')), kcl = k => kcol2[k] || (kcol2[k] = rgbOf(kindOf(k).color, 1).join(','));
    const rgbOf = (c, f = 0.82) => { const m = /^#?([0-9a-f]{6})$/i.exec(c || ''); if (!m) return [138, 131, 126]; const n = parseInt(m[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => Math.round(v * f)); };

    // ---- 렌더러, 장면, 층 쌓기: 흐름 바탕 < 큰 호 < 3D 꽃 < 흐린 유리 < 덮개 그림 < 설명 ----
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, premultipliedAlpha: true, powerPreference: 'high-performance' }); }
    catch (e) { const p = document.createElement('p'); p.className = 'empty-note'; p.textContent = '이 환경에서는 WebGL 을 쓸 수 없습니다'; main.appendChild(p); return () => p.remove(); }
    renderer.setClearColor(0x000000, 0); renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05;
    renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    main.style.position = 'relative';
    const mesh = window.G3D && window.G3D.mesh ? window.G3D.mesh(main, 0.8) : null;   // 바탕: 다른 입체 보기와 같은 갈색 흐름
    const bg = document.createElement('div'); bg.style.cssText = `position:absolute;inset:0;z-index:0;pointer-events:none;background:radial-gradient(ellipse at 50% 46%,rgba(${INK3},0) 42%,rgba(${INK3},.13) 100%)${mesh ? '' : ',#d9d3cc'}`;
    const arcCv = document.createElement('canvas'); arcCv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;z-index:1;pointer-events:none';
    const cv = renderer.domElement; cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;z-index:2;touch-action:none';
    const ov = document.createElement('canvas'); ov.className = 'spov'; ov.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;z-index:3;pointer-events:none';
    main.append(bg, arcCv, cv, ov);
    const ctx = ov.getContext('2d'), actx = arcCv.getContext('2d');
    const disp = []; const own = o => { disp.push(o); return o; };
    const mkCanvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
    // 아주 옅은 먼지와 긁힌 자국(종이 결): 호 층 바탕으로 한 번만 깐다
    { const N = 1024, c = mkCanvas(N, N), x = c.getContext('2d'), r = rng(88123); x.lineCap = 'round';
      for (let i = 0; i < 2600; i++) { x.fillStyle = `rgba(${CRM},${(0.02 + 0.06 * r() * r()).toFixed(3)})`; const s = 0.5 + r() * r() * 1.3; x.fillRect(r() * N, r() * N, s, s); }
      for (let i = 0; i < 120; i++) { const px = r() * N, py = r() * N, L = 14 + r() * r() * 150, a = r() * 6.28, bend = (r() - 0.5) * 0.9; x.strokeStyle = `rgba(${CRM},${(0.02 + 0.04 * r()).toFixed(3)})`; x.lineWidth = 0.5 + r() * 0.7;
        x.beginPath(); x.moveTo(px, py); x.quadraticCurveTo(px + Math.cos(a + bend) * L * 0.5, py + Math.sin(a + bend) * L * 0.5, px + Math.cos(a) * L, py + Math.sin(a) * L); x.stroke(); }
      arcCv.style.backgroundImage = `url(${c.toDataURL('image/png')})`; arcCv.style.backgroundSize = '512px 512px'; }

    const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(30, 1, 0.1, 80);
    // ---- 빛: 소프트박스 환경(PMREM) + 왼쪽 위 따뜻한 주광 + 뒤쪽 서늘한 테두리 빛 ----
    const rig = new THREE.Group(), head = new THREE.Group(); rig.add(head); scene.add(rig);
    { const es = new THREE.Scene(), sky = new THREE.Mesh(new THREE.SphereGeometry(10, 32, 20), new THREE.MeshBasicMaterial({ side: THREE.BackSide, vertexColors: true }));
      { const g = sky.geometry, n = g.attributes.position.count, cc = new Float32Array(n * 3); for (let q = 0; q < n; q++) { const t = clamp(g.attributes.position.getY(q) / 10 * 0.5 + 0.5, 0, 1), s = t * t; cc.set([mix(0.5, 1.0, s), mix(0.44, 0.97, s), mix(0.4, 0.92, s)], q * 3); } g.setAttribute('color', new THREE.BufferAttribute(cc, 3)); }
      es.add(sky);
      const box = (w, h, col, x, y, z) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: col, side: THREE.DoubleSide })); m.position.set(x, y, z); m.lookAt(0, 0, 0); es.add(m); };
      box(8, 6, new THREE.Color(10, 9.3, 8.4), -5.5, 6, 4.5); box(3, 7, new THREE.Color(1.8, 2.0, 2.5), 7, 1.5, -3); box(9, 2.4, new THREE.Color(1.5, 1.28, 1.05), 0, -4.2, 5);
      const pm = new THREE.PMREMGenerator(renderer), rt = pm.fromScene(es, 0.04); pm.dispose(); own(rt); scene.environment = rt.texture; scene.environmentIntensity = 0.7;
      es.traverse(o => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); }); }
    const key = new THREE.DirectionalLight(0xFFF8F0, 3.0); key.position.set(-4, 5.5, 3); key.castShadow = true;
    key.shadow.mapSize.set(768, 768); Object.assign(key.shadow.camera, { left: -3.1, right: 3.1, top: 3.1, bottom: -3.1, near: 1, far: 22 }); key.shadow.bias = -0.0005; key.shadow.normalBias = 0.03;
    scene.add(key);
    const rimL = new THREE.DirectionalLight(0xDCE8FA, 1.5); rimL.position.set(4.6, 2.4, -3.8); scene.add(rimL);
    const fillL = new THREE.DirectionalLight(0xFFE8D4, 0.4); fillL.position.set(3.4, -1.6, 4.6); scene.add(fillL);
    const KEY = { dir: { value: new THREE.Vector3(0, 0, 1) }, col: { value: new THREE.Color(0xFFE9CC).multiplyScalar(1.0) } };   // 뒤에서 비치는 빛 계산용(보는 방향 기준), 크기 맞춤 때 채운다

    // ---- 꽃잎 무늬(캔버스): 크림색 바탕, 밑동의 분홍 보라 번짐과 가는 보라 결, 밑동에서 퍼지는 가는 결, 비단 같은 물결 ----
    const toNormal = (hc, st) => { const W = hc.width, H = hc.height, d = hc.getContext('2d').getImageData(0, 0, W, H).data, oc = mkCanvas(W, H), ox = oc.getContext('2d'), im = ox.createImageData(W, H), o = im.data;
      const h = (a, b) => d[(((b + H) % H) * W + ((a + W) % W)) * 4] / 255;
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const dx = (h(x + 1, y) - h(x - 1, y)) * st, dy = (h(x, y + 1) - h(x, y - 1)) * st, l = Math.hypot(dx, dy, 1), k = (y * W + x) * 4; o[k] = (-dx / l * 0.5 + 0.5) * 255; o[k + 1] = (dy / l * 0.5 + 0.5) * 255; o[k + 2] = (1 / l * 0.5 + 0.5) * 255; o[k + 3] = 255; }
      ox.putImageData(im, 0, 0); return oc; };
    const petalMaps = (seed, pal) => {
      const r = rng(seed), W = 512, H = 1024, c = mkCanvas(W, H), x = c.getContext('2d'), b = mkCanvas(W, H), y = b.getContext('2d');
      const g = x.createLinearGradient(0, 0, 0, H); pal.grad.forEach(([t, col]) => g.addColorStop(t, col)); x.fillStyle = g; x.fillRect(0, 0, W, H);
      for (let i = 0; i < 120; i++) { const px = r() * W, py = r() * H, rad = 40 + r() * 150, dark = r() < 0.5, a = 0.03 + 0.05 * r(), gr = x.createRadialGradient(px, py, 0, px, py, rad); gr.addColorStop(0, dark ? `rgba(${pal.shade},${a})` : `rgba(255,252,240,${a})`); gr.addColorStop(1, 'rgba(0,0,0,0)'); x.fillStyle = gr; x.fillRect(px - rad, py - rad, rad * 2, rad * 2); }
      if (pal.blush) { const [br, bg, bb] = pal.blush; for (let k = 0; k < 3; k++) { const gx = W * (0.2 + 0.6 * r()), gr = x.createRadialGradient(gx, H * 1.02, 6, gx, H * 0.88, H * (0.34 + 0.12 * r())); gr.addColorStop(0, `rgba(${br - 36},${bg - 44},${bb - 24},.72)`); gr.addColorStop(0.5, `rgba(${br},${bg},${bb},.4)`); gr.addColorStop(1, `rgba(${br},${bg},${bb},0)`); x.fillStyle = gr; x.fillRect(0, 0, W, H); } }
      y.fillStyle = '#808080'; y.fillRect(0, 0, W, H);
      const NV = 170; x.lineCap = y.lineCap = 'round';
      for (let i = 0; i < NV; i++) { const x0 = (i + r()) / NV * W, ph = r() * 6.28, am = 0.8 + 2.8 * r(), ws = 0.006 + 0.012 * r(), ys = r() < 0.4 ? H * (0.06 + 0.5 * r()) : 0, lw = 0.7 + 1.2 * r(), dark = r() < 0.6, al = 0.016 + 0.04 * r();
        const path = cx => { cx.beginPath(); for (let t = ys; t <= H; t += 20) { const xx = x0 + Math.sin(t * ws + ph) * am; t === ys ? cx.moveTo(xx, t) : cx.lineTo(xx, t); } cx.stroke(); };
        x.lineWidth = lw; x.strokeStyle = dark ? `rgba(${pal.shade},${al})` : `rgba(255,253,244,${al * 1.2})`; path(x);
        y.lineWidth = lw * 1.1; y.strokeStyle = dark ? `rgba(40,40,40,${0.08 + al * 3})` : `rgba(235,235,235,${0.07 + al * 3})`; path(y);
        if (pal.blush && r() < 0.55) { x.lineWidth = lw * 0.9; x.strokeStyle = `rgba(${pal.blush[0] - 60},${pal.blush[1] - 70},${pal.blush[2] - 40},${0.1 + 0.14 * r()})`; const ys2 = H * (0.52 + 0.2 * r()); x.beginPath(); for (let t = ys2; t <= H; t += 20) { const xx = x0 + Math.sin(t * ws + ph) * am; t === ys2 ? x.moveTo(xx, t) : x.lineTo(xx, t); } x.stroke(); } }
      // 비단 같은 가로 물결: 넓은 꽃잎 가운데에 얕게
      for (let k = 0; k < 3; k++) { const cx = W * (0.3 + 0.4 * r()), cy = H * (0.3 + 0.3 * r()), hw = W * (0.2 + 0.12 * r()), n = 12 + Math.floor(r() * 8), sp = 11 + r() * 8, ph = r() * 6.28, la = 0.25 + 0.3 * r();
        for (let j = 0; j < n; j++) { const yy = cy + (j - n / 2) * sp, fade = Math.sin(Math.PI * (j + 0.5) / n), light = j % 2 === 0; y.lineWidth = 3.5 + 2 * fade; y.strokeStyle = light ? `rgba(240,240,240,${0.1 * fade * la})` : `rgba(30,30,30,${0.12 * fade * la})`; y.beginPath();
          for (let t = -hw; t <= hw; t += 12) { const xx = cx + t, yo = yy + Math.sin(t * 0.03 + ph + j * 0.3) * 7 + (t * t) / (hw * hw) * 14; t === -hw ? y.moveTo(xx, yo) : y.lineTo(xx, yo); } y.stroke(); } }
      const nm = toNormal(b, 2.4), mk = (cc, srgb) => { const t = own(new THREE.CanvasTexture(cc)); t.anisotropy = 8; if (srgb) t.colorSpace = THREE.SRGBColorSpace; return t; };
      return { map: mk(c, true), nrm: mk(nm, false) };
    };
    const PAL = [
      { grad: [[0, '#F6F0E2'], [0.4, '#F0E8D4'], [0.75, '#E7DBBE'], [1, '#D5CAA2']], shade: '118,90,58', blush: [176, 124, 152] },
      { grad: [[0, '#F7F1E4'], [0.45, '#F1E9D6'], [0.8, '#E8DDC1'], [1, '#D9CDA6']], shade: '124,96,62', blush: [194, 146, 164] },
      { grad: [[0, '#F8F3E7'], [0.5, '#F2EBD9'], [0.85, '#EADFC5'], [1, '#DCD0AA']], shade: '130,102,68', blush: null }];
    const PM = PAL.map((p, i) => petalMaps(11 + i * 12, p));

    // ---- 꽃잎 설계: 중심선은 (바깥 거리, 높이) 평면의 3차 곡선, 폭은 둥근 껍질 위의 호, 가장자리에 주름 ----
    const R0 = rng(20261008), jit = a => (R0() - 0.5) * a, PET = [];
    const addP = (lay, o) => PET.push(Object.assign({ lay, r0: 0.12 - 0.012 * lay, y0: 0.015 * lay, k: [1, 0.3], roll: 0, amp: 0.045, f1: 3, f2: 6.8, tw: 0, vm: 0.5, tp: 2, tq: 2, fold: 0.014, nf: 2.5, off: 0, lf: 0.05, keel: 0.025 }, o));
    { const O = [   // 바깥 네 장: 위로 솟은 것, 바깥으로 말려 내려가는 것, 앞에서 둥글게 부푼 것, 아래로 벌어지는 것
        { c: [[1.2, 0.4], [1.65, 1.25], [2.0, 2.1]], W: 1.05, k: [0.9, 0.15], roll: 0.25, tw: 0.25, tp: 1.9, tq: 1.8, f1: 2.6 },
        { c: [[1.25, 0.35], [1.8, 1.05], [2.6, 1.25]], W: 1.05, k: [0.9, -0.6], roll: 0.6, tw: 0.55, tp: 1.5, tq: 1.6, f1: 2.2 },
        { c: [[1.2, 0.4], [1.7, 1.2], [2.1, 1.9]], W: 1.15, k: [0.9, 0], roll: 0.3, tw: -0.3, tp: 2.2, tq: 2.0, f1: 3.0 },
        { c: [[1.2, 0.4], [1.75, 0.95], [2.35, 1.3]], W: 1.1, k: [0.9, -0.4], roll: 0.5, tw: -0.5, tp: 2.0, tq: 1.8, f1: 2.4 }];
      O.forEach((o, k) => addP(0, Object.assign({ al: k * 1.571 + 0.3 + jit(0.2), vm: 0.55, off: k * 0.035, amp: 0.05, fold: 0.02, tex: 0 }, o))); }
    for (let k = 0; k < 4; k++) addP(1, { al: k * 1.571 + 1.1 + jit(0.25), c: [[1.05, 0.4], [1.4, 1.4], [1.5 + jit(0.2), 2.3 + jit(0.2)]], W: 1.0, k: [1, 0.25 + jit(0.3)], roll: 0.15, tw: jit(0.6), vm: 0.55, tp: 2.1, tq: 1.9, f1: 3 + jit(0.6), off: k * 0.035, amp: 0.05, fold: 0.022, tex: 0 });
    for (let k = 0; k < 5; k++) addP(2, { al: k * 1.2566 + 0.2 + jit(0.25), c: [[0.82, 0.45], [1.02, 1.5], [1.05 + jit(0.15), 2.45 + jit(0.15)]], th: 1.0, k: [1.05, 0.3], roll: 0.1, tw: jit(0.6), vm: 0.55, tp: 2.6, tq: 2.2, f1: 3.4, f2: 7.4, off: (k % 3) * 0.03, amp: 0.04, fold: 0.024, lf: 0.04, tex: 1 });
    for (let k = 0; k < 6; k++) addP(3, { al: k * 1.047 + 0.5 + jit(0.25), c: [[0.6, 0.5], [0.8, 1.55], [0.75 + jit(0.1), 2.55 + jit(0.12)]], th: 0.95, k: [1.05, 0.2], roll: 0.08, tw: jit(0.7), vm: 0.55, tp: 2.6, tq: 2.2, f1: 3.8, f2: 8, off: (k % 3) * 0.025, amp: 0.035, fold: 0.022, lf: 0.035, tex: 1 });
    for (let k = 0; k < 7; k++) addP(4, { al: k * 0.8976 + 0.9 + jit(0.25), c: [[0.42, 0.55], [0.55, 1.5], [0.45 + jit(0.08), 2.55 + jit(0.12)]], th: 0.9, k: [1.05, 0.15], roll: 0.06, tw: jit(0.8), vm: 0.55, tp: 2.6, tq: 2.2, f1: 4.2, f2: 8.6, off: (k % 3) * 0.02, amp: 0.03, fold: 0.02, lf: 0.03, tex: 2 });
    for (let k = 0; k < 4; k++) addP(5, { al: k * 1.571 + 0.4, c: [[0.2, 0.5], [0.3, 1.2], [0.22, 2.1 + jit(0.1)]], th: 0.9, k: [1.1, 0.15], roll: 0.05, tw: jit(1.0), vm: 0.55, tp: 2.4, tq: 2, f1: 4.6, f2: 9, amp: 0.025, fold: 0.016, lf: 0.025, tex: 2 });

    const NU = 34, NV = 64, wprof = (v, P) => { const a = 0.18 + 0.82 * sstep(0, 0.34, v), rise = v < P.vm ? Math.pow(Math.sin(Math.PI / 2 * v / P.vm), 0.6) : 1, t = Math.max(0, (v - P.vm) / (1 - P.vm)), tip = v < P.vm ? 1 : Math.pow(Math.max(0, 1 - Math.pow(t, P.tp)), 1 / P.tq); return Math.max(1e-4, a * rise * tip); };
    PET.forEach((P, pi) => {
      const r = rng(700 + pi * 13), ph1 = r() * 6.28, ph2 = r() * 6.28, ph3 = r() * 6.28, flip = r() < 0.5, n = (NU + 1) * (NV + 1), pos = new Float32Array(n * 3), uv = new Float32Array(n * 2), nrm = new Float32Array(n * 3), loc = new Float32Array(n * 3);
      const ca = Math.cos(P.al), sa = Math.sin(P.al), [c1, c2, c3] = P.c;
      if (P.W === undefined) { const o = 0.4492, b1 = 3 * 0.55 * o * o, b2 = 3 * 0.55 * 0.55 * o, b3 = 0.55 * 0.55 * 0.55; P.W = P.th * (o * o * o * P.r0 + b1 * c1[0] + b2 * c2[0] + b3 * c3[0]) * (0.92 + 0.16 * r()); }
      for (let iv = 0; iv <= NV; iv++) { const v = iv / NV, o = 1 - v, b0 = o * o * o, b1 = 3 * v * o * o, b2 = 3 * v * v * o, b3 = v * v * v;
        const R = b0 * P.r0 + b1 * c1[0] + b2 * c2[0] + b3 * c3[0] + P.off, Y = b0 * P.y0 + b1 * c1[1] + b2 * c2[1] + b3 * c3[1];
        const dR = 3 * o * o * (c1[0] - P.r0) + 6 * o * v * (c2[0] - c1[0]) + 3 * v * v * (c3[0] - c2[0]), dY = 3 * o * o * (c1[1] - P.y0) + 6 * o * v * (c2[1] - c1[1]) + 3 * v * v * (c3[1] - c2[1]), l = Math.hypot(dR, dY) || 1, nr = dY / l, ny = -dR / l;
        const w = P.W * wprof(v, P), kk = mix(P.k[0], P.k[1], sstep(0.25, 1, v)), kap = kk / Math.max(R, 0.3), tw = P.tw * Math.pow(v, 1.4), ct = Math.cos(tw), st = Math.sin(tw);
        const fade = 0.2 + 1.1 * sstep(0.3, 1, v), rl = P.roll * sstep(0.5, 1, v);
        for (let iu = 0; iu <= NU; iu++) { const u = iu / NU * 2 - 1, a = u * w, e = Math.abs(u), ph = clamp(kap * a, -2.1, 2.1);
          let lx, sg; if (Math.abs(kap) < 1e-3) { lx = a; sg = -kap * a * a / 2; } else { lx = Math.sin(ph) / kap; sg = -(1 - Math.cos(ph)) / kap; }
          const rf = (Math.sin(6.2832 * (P.f1 * v + 0.3 * u) + ph1) * 0.6 + Math.sin(6.2832 * (P.f2 * v - 0.45 * u) + ph2) * 0.4) * P.amp * Math.pow(e, 2.2) * fade;
          const fold = P.fold * Math.sin(Math.PI * P.nf * u + ph3) * sstep(0.04, 0.5, v) * (1 - e * e), roll = rl * Math.pow(e, 2.6) * w;
          const lfv = P.lf * Math.min(1, P.W) * (Math.sin(6.2832 * (0.9 * u + 1.3 * v) + ph1) * 0.5 + Math.sin(6.2832 * (-1.6 * u + 0.8 * v) + ph2) * 0.35 + Math.sin(6.2832 * (0.5 * u + 2.1 * v) + ph3) * 0.25) * (0.3 + 0.7 * sstep(0.05, 0.6, v)), keel = P.keel * Math.min(1, P.W) * Math.exp(-u * u / 0.05) * sstep(0.02, 0.35, v) * (1 - sstep(0.6, 1, v));
          const ex = lx + rf * 0.1 * Math.sign(u), es = sg + rf + fold + roll + lfv + keel, bx = ex * ct - es * st, nz = ex * st + es * ct, X = bx, Zr = R + nr * nz, Yy = Y + ny * nz;
          const k3 = (iv * (NU + 1) + iu) * 3; loc[k3] = X; loc[k3 + 1] = Yy; loc[k3 + 2] = Zr;
          pos[k3] = X * ca + Zr * sa; pos[k3 + 1] = Yy; pos[k3 + 2] = -X * sa + Zr * ca;
          const k2 = (iv * (NU + 1) + iu) * 2; uv[k2] = flip ? 0.5 - u * 0.5 : u * 0.5 + 0.5; uv[k2 + 1] = v; } }
      // 법선: 격자 이웃의 가운데 차분 (바깥쪽 면이 앞)
      for (let iv = 0; iv <= NV; iv++) for (let iu = 0; iu <= NU; iu++) { const i0 = Math.max(0, iu - 1), i1 = Math.min(NU, iu + 1), j0 = Math.max(0, iv - 1), j1 = Math.min(NV, iv + 1), a = (iv * (NU + 1) + i0) * 3, b = (iv * (NU + 1) + i1) * 3, c = (j0 * (NU + 1) + iu) * 3, d = (j1 * (NU + 1) + iu) * 3;
        const ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1], uz = pos[b + 2] - pos[a + 2], vx = pos[d] - pos[c], vy = pos[d + 1] - pos[c + 1], vz = pos[d + 2] - pos[c + 2];
        let nx = uy * vz - uz * vy, ny2 = uz * vx - ux * vz, nz2 = ux * vy - uy * vx; const l = Math.hypot(nx, ny2, nz2) || 1; const k3 = (iv * (NU + 1) + iu) * 3; nrm[k3] = nx / l; nrm[k3 + 1] = ny2 / l; nrm[k3 + 2] = nz2 / l; }
      P.d = { pos, uv, nrm, n, tint: [0.97 + 0.05 * r(), 0.97 + 0.04 * r(), 0.95 + 0.05 * r()] };
    });

    // ---- 꽃잎 사이 그늘 굽기: 점 밀도 격자에서 반구 방향으로 걸어 가려진 정도를 센다 (안쪽, 바깥쪽 면 따로) ----
    { let tot = 0; PET.forEach(P => { P.d.o = tot; tot += P.d.n; });
      const PP = new Float32Array(tot * 3), NN = new Float32Array(tot * 3); PET.forEach(P => { PP.set(P.d.pos, P.d.o * 3); NN.set(P.d.nrm, P.d.o * 3); });
      const cs = 0.08; let x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9;
      for (let i = 0; i < tot; i++) { const x = PP[i * 3], y = PP[i * 3 + 1], z = PP[i * 3 + 2]; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; if (z < z0) z0 = z; if (z > z1) z1 = z; }
      x0 -= 1; y0 -= 1; z0 -= 1; const nx = Math.ceil((x1 - x0 + 1) / cs) + 1, ny = Math.ceil((y1 - y0 + 1) / cs) + 1, nz = Math.ceil((z1 - z0 + 1) / cs) + 1; let G = new Float32Array(nx * ny * nz), T = new Float32Array(G.length);
      const ci = (x, y, z) => { const a = Math.floor((x - x0) / cs), b = Math.floor((y - y0) / cs), c = Math.floor((z - z0) / cs); return a < 0 || b < 0 || c < 0 || a >= nx || b >= ny || c >= nz ? -1 : a + nx * (b + ny * c); };
      for (let i = 0; i < tot; i++) { const k = ci(PP[i * 3], PP[i * 3 + 1], PP[i * 3 + 2]); if (k >= 0) G[k] += 1; }
      for (let it = 0; it < 2; it++) for (let ax = 0; ax < 3; ax++) { const st = ax === 0 ? 1 : ax === 1 ? nx : nx * ny; T.fill(0);
        for (let c = 0; c < nz; c++) for (let b = 0; b < ny; b++) for (let a = 0; a < nx; a++) { const k = a + nx * (b + ny * c), p = ax === 0 ? a : ax === 1 ? b : c, m = ax === 0 ? nx : ax === 1 ? ny : nz; T[k] = (G[k] * 2 + (p > 0 ? G[k - st] : 0) + (p < m - 1 ? G[k + st] : 0)) / 4; } const sw = G; G = T; T = sw; }
      const dirs = [[0, 0, 1, 1]]; for (let a = 0; a < 5; a++) dirs.push([Math.cos(a * 1.2566) * 0.6, Math.sin(a * 1.2566) * 0.6, 0.8, 0.85]); for (let a = 0; a < 7; a++) dirs.push([Math.cos(a * 0.8976 + 0.3) * 0.92, Math.sin(a * 0.8976 + 0.3) * 0.92, 0.39, 0.5]);
      const dsum = dirs.reduce((s, d) => s + d[3], 0), steps = [0.2, 0.3, 0.42, 0.56, 0.72, 0.9, 1.1], SC = 1 / 2.4;
      const AOf = new Float32Array(tot), AOb = new Float32Array(tot);
      for (let i = 0; i < tot; i++) { const px = PP[i * 3], py = PP[i * 3 + 1], pz = PP[i * 3 + 2], mx = NN[i * 3], my = NN[i * 3 + 1], mz = NN[i * 3 + 2];
        for (let sd = 1; sd >= -1; sd -= 2) { const nx_ = mx * sd, ny_ = my * sd, nz_ = mz * sd; let tx, ty, tz; if (Math.abs(ny_) < 0.9) { tx = nz_; ty = 0; tz = -nx_; } else { tx = 0; ty = -nz_; tz = ny_; } const tl = Math.hypot(tx, ty, tz) || 1; tx /= tl; ty /= tl; tz /= tl;
          const bx = ny_ * tz - nz_ * ty, by = nz_ * tx - nx_ * tz, bz = nx_ * ty - ny_ * tx; let acc = 0;
          for (const d of dirs) { const dx = tx * d[0] + bx * d[1] + nx_ * d[2], dy = ty * d[0] + by * d[1] + ny_ * d[2], dz = tz * d[0] + bz * d[1] + nz_ * d[2]; let tau = 0;
            for (const s of steps) { const k = ci(px + dx * s + nx_ * 0.04, py + dy * s + ny_ * 0.04, pz + dz * s + nz_ * 0.04); if (k >= 0) tau += G[k] * SC * (s < 0.5 ? 0.8 : 1.1); }
            acc += Math.exp(-1.15 * tau) * d[3]; }
          const ao = 0.6 + 0.4 * Math.pow(acc / dsum, 0.85); (sd > 0 ? AOf : AOb)[i] = ao; } }
      PET.forEach(P => { P.d.aof = AOf.subarray(P.d.o, P.d.o + P.d.n); P.d.aob = AOb.subarray(P.d.o, P.d.o + P.d.n); }); }

    // ---- 꽃잎 묶음 하나(층) = 메시 하나, 층마다 숨 쉬듯 벌어졌다 모인다 ----
    const patchPetal = m => { m.onBeforeCompile = sh => {
      sh.uniforms.uKeyDir = KEY.dir; sh.uniforms.uKeyCol = KEY.col;
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nattribute float aAOf;attribute float aAOb;varying float vAOf;varying float vAOb;varying vec2 vPU;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvAOf=aAOf;vAOb=aAOb;vPU=uv;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <opaque_fragment>', 'float lum = dot(outgoingLight, vec3(0.299, 0.587, 0.114)); outgoingLight *= mix(vec3(1.0, 0.8, 0.56), vec3(1.0), smoothstep(0.03, 0.5, lum));\n#include <opaque_fragment>').replace('#include <common>', '#include <common>\nvarying float vAOf;varying float vAOb;varying vec2 vPU;uniform vec3 uKeyDir;uniform vec3 uKeyCol;').replace('#include <aomap_fragment>', `
        float ao = gl_FrontFacing ? vAOf : vAOb;
        float nv = saturate(dot(normal, geometryViewDir)), rim = pow(1.0 - nv, 2.2), edge = abs(vPU.x * 2.0 - 1.0);
        float thin = 0.25 * smoothstep(0.3, 1.0, vPU.y) + 0.4 * pow(edge, 4.0) + 0.15 * pow(max(vPU.y, 0.0), 6.0);
        reflectedLight.indirectDiffuse *= ao; reflectedLight.indirectSpecular *= mix(1.0, ao, 0.8);
        reflectedLight.directDiffuse *= mix(1.0, ao, 0.35) * mix(1.0, 0.8, rim); reflectedLight.indirectDiffuse *= mix(1.0, 0.82, rim);
        float back = max(0.0, -dot(normal, uKeyDir));
        totalEmissiveRadiance += diffuseColor.rgb * vec3(1.0, 0.82, 0.55) * uKeyCol * (back * (0.10 + 0.5 * thin) + 0.04 * thin) * ao;`); }; return m; };
    const petalMat = M => patchPetal(own(new THREE.MeshPhysicalMaterial({ map: M.map, normalMap: M.nrm, normalScale: new THREE.Vector2(0.9, 0.9), vertexColors: true, roughness: 0.56, metalness: 0, sheen: 1, sheenRoughness: 0.4, sheenColor: new THREE.Color(0xFFF8EE), side: THREE.DoubleSide, shadowSide: THREE.DoubleSide })));
    const PMAT = PM.map(petalMat), layG = [];
    for (let L = 0; L < 6; L++) { const ps = PET.filter(P => P.lay === L); let nv = 0; ps.forEach(P => { nv += P.d.n; });
      const pos = new Float32Array(nv * 3), nrm = new Float32Array(nv * 3), uv = new Float32Array(nv * 2), col = new Float32Array(nv * 3), af = new Float32Array(nv), ab = new Float32Array(nv), idx = []; let o = 0;
      ps.forEach(P => { const d = P.d; pos.set(d.pos, o * 3); nrm.set(d.nrm, o * 3); uv.set(d.uv, o * 2); af.set(d.aof, o); ab.set(d.aob, o); for (let i = 0; i < d.n; i++) col.set(d.tint, (o + i) * 3);
        for (let iv = 0; iv < NV; iv++) for (let iu = 0; iu < NU; iu++) { const a = o + iv * (NU + 1) + iu, b = a + 1, c = a + NU + 1, e = c + 1; idx.push(a, b, c, b, e, c); } o += d.n; });
      const geo = own(new THREE.BufferGeometry()); geo.setAttribute('position', new THREE.BufferAttribute(pos, 3)); geo.setAttribute('normal', new THREE.BufferAttribute(nrm, 3)); geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2)); geo.setAttribute('color', new THREE.BufferAttribute(col, 3)); geo.setAttribute('aAOf', new THREE.BufferAttribute(af, 1)); geo.setAttribute('aAOb', new THREE.BufferAttribute(ab, 1)); geo.setIndex(idx);
      const mesh = new THREE.Mesh(geo, PMAT[ps[0].tex]); mesh.castShadow = mesh.receiveShadow = true; mesh.layers.enable(1); const g = new THREE.Group(); g.add(mesh); g.userData = { ph: L * 1.7 }; head.add(g); layG.push(g); }
    // 받침(꽃받침 덩어리): 꽃잎 밑동과 줄기를 잇는다
    const stemMat = (() => { const c = mkCanvas(256, 64), x = c.getContext('2d'), r = rng(515), g = x.createLinearGradient(0, 0, 256, 0); g.addColorStop(0, '#B4BD94'); g.addColorStop(0.2, '#A3B087'); g.addColorStop(0.6, '#8DA07C'); g.addColorStop(1, '#7B8E6E'); x.fillStyle = g; x.fillRect(0, 0, 256, 64);
      for (let i = 0; i < 64; i++) { const yy = i + 0.5, a = 0.03 + 0.07 * r(); x.fillStyle = r() < 0.5 ? `rgba(70,95,60,${a})` : `rgba(235,240,215,${a})`; x.fillRect(0, yy, 256, 0.6 + r() * 1.4); }
      for (let i = 0; i < 700; i++) { x.fillStyle = `rgba(240,244,225,${0.03 + 0.05 * r()})`; x.fillRect(r() * 256, r() * 64, 1 + r() * 6, 0.7); }
      const t = own(new THREE.CanvasTexture(c)); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; t.wrapT = THREE.RepeatWrapping;
      return own(new THREE.MeshPhysicalMaterial({ map: t, roughness: 0.42, vertexColors: true, sheen: 0.6, sheenRoughness: 0.5, sheenColor: new THREE.Color(0xE6F0D6), clearcoat: 0.18, clearcoatRoughness: 0.5 })); })();
    { const s = new THREE.Mesh(own(new THREE.SphereGeometry(1, 28, 18)), own(new THREE.MeshPhysicalMaterial({ color: 0xA9B88F, roughness: 0.5, sheen: 0.5, sheenColor: new THREE.Color(0xE6F0D6) }))); s.scale.set(0.13, 0.1, 0.13); s.position.y = -0.03; s.castShadow = s.receiveShadow = true; s.layers.enable(1); head.add(s); }
    const HEART = V(0.1, 0.95, 0.15);   // 덮개의 "나"가 얹히는 꽃 가운데 점(머리 기준)

    // ---- 줄기, 잎 ----
    const stemC = new THREE.CatmullRomCurve3([[0, 0, 0], [-0.3, -0.5, 0.02], [-0.66, -1.05, 0.05], [-0.88, -1.7, 0.03], [-0.9, -2.4, 0], [-0.76, -3.1, -0.04], [-0.55, -3.8, -0.05], [-0.4, -4.6, -0.03]].map(p => V(...p)), false, 'centripetal');
    { const TS = 130, RS = 22, geo = own(new THREE.TubeGeometry(stemC, TS, 1, RS, false)), p = geo.attributes.position, cols = [];
      for (let i = 0; i <= TS; i++) { const t = i / TS, c0 = stemC.getPointAt(t), rr = 0.082 + 0.03 * (1 - sstep(0, 0.12, t)) - 0.012 * t, sh = mix(0.62, 1.0, sstep(0, 0.16, t)) * mix(1.08, 0.82, sstep(0.1, 1, t));
        for (let j = 0; j <= RS; j++) { const k = i * (RS + 1) + j; p.setXYZ(k, c0.x + (p.getX(k) - c0.x) * rr, c0.y + (p.getY(k) - c0.y) * rr, c0.z + (p.getZ(k) - c0.z) * rr); cols.push(sh, sh, sh); } }
      geo.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
      const m = new THREE.Mesh(geo, stemMat); m.castShadow = m.receiveShadow = true; m.layers.enable(1); rig.add(m); }
    { const c = mkCanvas(128, 512), x = c.getContext('2d'), r = rng(616), g = x.createLinearGradient(0, 0, 0, 512); g.addColorStop(0, '#A7B58B'); g.addColorStop(0.5, '#93A583'); g.addColorStop(1, '#7E9272'); x.fillStyle = g; x.fillRect(0, 0, 128, 512);
      for (let i = 0; i < 70; i++) { const xx = (i + r()) / 70 * 128, a = 0.04 + 0.07 * r(); x.strokeStyle = r() < 0.5 ? `rgba(60,86,52,${a})` : `rgba(235,242,215,${a})`; x.lineWidth = 0.6 + r(); x.beginPath(); x.moveTo(xx, 0); x.lineTo(xx + (r() - 0.5) * 3, 512); x.stroke(); }
      x.fillStyle = 'rgba(236,244,214,.34)'; x.fillRect(62, 0, 4, 512); const t = own(new THREE.CanvasTexture(c)); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
      const TS = 90, US = 12, pos = [], col = [], uv = [], idx = [], t0 = 0.1, t1 = 0.98;   // 줄기를 따라 내려가는 긴 잎, 가운데 줄기를 따라 접힌다
      for (let i = 0; i <= TS; i++) { const tt = mix(t0, t1, i / TS), c0 = stemC.getPointAt(tt), tg = stemC.getTangentAt(tt), nx = -tg.y, ny = tg.x, nl = Math.hypot(nx, ny) || 1, s = i / TS;
        const w = 0.15 * Math.pow(Math.sin(Math.PI * Math.pow(s, 0.65)), 0.75), off = 0.1 + 0.05 * Math.sin(s * 3.1), shd = mix(1.05, 0.72, s);
        for (let j = 0; j <= US; j++) { const u = j / US * 2 - 1, xx = u * w, fold = 0.6 * xx * xx - 0.1 * Math.abs(xx); pos.push(c0.x - nx / nl * (off + xx), c0.y - ny / nl * (off + xx), c0.z + 0.07 - fold - 0.03 * s); uv.push(j / US, s); const q = shd * (0.88 + 0.12 * (1 - Math.abs(u))); col.push(q, q, q); } }
      for (let i = 0; i < TS; i++) for (let j = 0; j < US; j++) { const a = i * (US + 1) + j, b = a + 1, c2 = a + US + 1, d = c2 + 1; idx.push(a, c2, b, b, c2, d); }
      const geo = own(new THREE.BufferGeometry()); geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3)); geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); geo.setIndex(idx); geo.computeVertexNormals();
      const m = new THREE.Mesh(geo, own(new THREE.MeshPhysicalMaterial({ map: t, roughness: 0.4, vertexColors: true, side: THREE.DoubleSide, sheen: 0.5, sheenRoughness: 0.5, sheenColor: new THREE.Color(0xE6F0D6), clearcoat: 0.15 })));
      m.castShadow = m.receiveShadow = true; m.layers.enable(1); rig.add(m); }

    // ---- 자세: 시간 T 에서 꽃이 서 있는 모양 ----
    const HEAD_TILT = -0.72;
    const pose = (T, yawO) => {
      rig.rotation.set(0.04 * Math.sin(T * 0.31), 0.26 * Math.sin(T * 0.23) + 0.08 * Math.sin(T * 0.57 + 1) + yawO, 0.02 * Math.sin(T * 0.4 + 0.5), 'YXZ');
      head.rotation.set(0.5 + 0.02 * Math.sin(T * 0.53 + 1), -0.5 + 0.04 * Math.sin(T * 0.41), HEAD_TILT + 0.025 * Math.sin(T * 0.7));
      layG.forEach((g, i) => { const s = 1 + 0.016 * Math.sin(T * (0.55 + 0.06 * i) + g.userData.ph); g.scale.set(s, 1 + 0.008 * Math.sin(T * 0.43 + i), s); g.rotation.y = 0.03 * Math.sin(T * 0.27 + g.userData.ph); });
    };
    rig.position.set(0, 0, 0); head.scale.setScalar(1.02);

    // ---- 종이 위 그림자: 꽃의 실루엣을 작은 그림으로 그려 흐린 뒤, 빛 반대쪽으로 비껴 깐다 ----
    const SHK = 0.34, shA = own(new THREE.WebGLRenderTarget(2, 2, { minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter })), shB = own(new THREE.WebGLRenderTarget(2, 2, { minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter }));
    const silM = own(new THREE.MeshBasicMaterial({ color: 0x000000, side: THREE.DoubleSide })), qGeo = own(new THREE.PlaneGeometry(2, 2)), qCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1), qScene = new THREE.Scene();
    const QV = 'varying vec2 u;void main(){u=uv;gl_Position=vec4(position.xy,0.,1.);}';
    const blurM = own(new THREE.ShaderMaterial({ uniforms: { t: { value: null }, d: { value: new THREE.Vector2() } }, depthTest: false, depthWrite: false, vertexShader: QV,
      fragmentShader: 'uniform sampler2D t;uniform vec2 d;varying vec2 u;void main(){vec4 c=texture2D(t,u)*.227027;c+=(texture2D(t,u+d)+texture2D(t,u-d))*.1945946;c+=(texture2D(t,u+d*2.)+texture2D(t,u-d*2.))*.1216216;c+=(texture2D(t,u+d*3.)+texture2D(t,u-d*3.))*.054054;c+=(texture2D(t,u+d*4.)+texture2D(t,u-d*4.))*.0162162;gl_FragColor=c;}' }));
    qScene.add(new THREE.Mesh(qGeo, blurM));
    const SU = { t: { value: shA.texture }, o1: { value: new THREE.Vector2() }, o2: { value: new THREE.Vector2() }, a1: { value: 0.34 }, a2: { value: 0.28 } };
    const shQ = new THREE.Mesh(qGeo, own(new THREE.ShaderMaterial({ uniforms: SU, depthTest: false, depthWrite: false, transparent: false, blending: THREE.CustomBlending, blendSrc: THREE.SrcAlphaFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor, vertexShader: QV,
      fragmentShader: `uniform sampler2D t;uniform vec2 o1,o2;uniform float a1,a2;varying vec2 u;void main(){float s=texture2D(t,u-o1).a*a1+texture2D(t,u-o2).a*a2;gl_FragColor=vec4(${(36 / 255).toFixed(3)},${(21 / 255).toFixed(3)},${(15 / 255).toFixed(3)},clamp(s,0.,1.));}` })));
    shQ.frustumCulled = false; shQ.renderOrder = -10; scene.add(shQ);
    let shW = 2, shH = 2;
    const castShadow = () => {
      const ac = renderer.shadowMap.autoUpdate; renderer.shadowMap.autoUpdate = false;
      camera.layers.set(1); scene.overrideMaterial = silM; renderer.setRenderTarget(shA); renderer.render(scene, camera); scene.overrideMaterial = null; camera.layers.set(0);
      blurM.uniforms.t.value = shA.texture; blurM.uniforms.d.value.set(2.2 / shW, 0); renderer.setRenderTarget(shB); renderer.render(qScene, qCam);
      blurM.uniforms.t.value = shB.texture; blurM.uniforms.d.value.set(0, 2.2 / shH); renderer.setRenderTarget(shA); renderer.render(qScene, qCam);
      renderer.setRenderTarget(null); renderer.shadowMap.autoUpdate = ac;
    };

    // ---- 떠다니는 먼지: 빛 속의 작은 알갱이 ----
    const PU = { uT: { value: 0 }, uPx: { value: 1 } };
    { const N = 170, r = rng(9051), pp = new Float32Array(N * 3), sd = new Float32Array(N);
      for (let i = 0; i < N; i++) { pp[i * 3] = (r() - 0.5) * 7.5; pp[i * 3 + 1] = (r() - 0.5) * 5; pp[i * 3 + 2] = -1.2 + r() * 3.2; sd[i] = r(); }
      const g = own(new THREE.BufferGeometry()); g.setAttribute('position', new THREE.BufferAttribute(pp, 3)); g.setAttribute('aS', new THREE.BufferAttribute(sd, 1));
      const m = own(new THREE.ShaderMaterial({ uniforms: PU, transparent: true, depthWrite: false,
        vertexShader: 'uniform float uT,uPx;attribute float aS;varying float vA;void main(){vec3 p=position;p.y=mod(p.y+uT*(0.015+0.03*aS)+2.5,5.)-2.5;p.x+=sin(uT*0.2+aS*40.)*0.18;vec4 mv=modelViewMatrix*vec4(p,1.);gl_Position=projectionMatrix*mv;gl_PointSize=(1.4+2.8*fract(aS*7.))*uPx;vA=0.2+0.45*fract(aS*13.)*(0.6+0.4*sin(uT*0.7+aS*30.));}',
        fragmentShader: 'varying float vA;void main(){float d=length(gl_PointCoord-.5);if(d>.5)discard;gl_FragColor=vec4(1.,.97,.9,vA*(1.-d*2.));}' }));
      const pts = new THREE.Points(g, m); pts.frustumCulled = false; scene.add(pts); }

    // ---- 아주 큰 가는 호: 꽃 뒤에서 천천히 도는 먹색 가는 선 ----
    const arcList = [[0.9, 2.2, 1.35], [-1.7, -1.1, 2.1], [1.2, -1.6, 3.0], [-0.4, 0.2, 4.6]].map(([px, py, rad], i) => { const r = rng(4417 + i * 31), be = r() * 6.28, span = Math.min(5.6, 3.4 / rad + 1.0);
      return { px, py, rad, a0: be - span / 2, a1: be + span / 2, w: (0.05 + 0.06 * r()) * (r() < 0.5 ? -1 : 1), ph: r() * 6.28, am: 0.1 + 0.08 * r(), al: 0.2 + 0.1 * r(), d: 3 + 4 * r() }; });

    // ---- 자료 -> 분야, 업무, 세션, 자료 ----
    const mmax = Math.max(1, ...tasks.map(t => t.mins || 0));
    const hubs = themes.map((th, i) => { const ts = tasks.filter(t => t.theme === th.id);
      return { th, i, ts, n: ts.length, mins: ts.reduce((a, t) => a + (t.mins || 0), 0), ses: ts.reduce((a, t) => a + (t.sessions || []).length, 0), its: ts.reduce((a, t) => a + itemsOf(t).length, 0), x: 0, y: 0, bx: 0, by: 0, ph: (hash('h' + th.id) % 628) / 100 }; });
    const hubOf = new Map(hubs.map(h => [h.th.id, h]));
    const boxes = tasks.map((t, i) => { const ss = t.sessions || [], its = itemsOf(t), m = t.mins || 0;
      return { t, i, h: hubOf.get(t.theme), m, ss, its, nS: ss.length, nI: its.length, rel: [], x: 0, y: 0, bx: 0, by: 0, w: 40, h2: 17, ph: (hash('f' + t.id) % 628) / 100, o1: (hash('s' + t.id) % 628) / 100, o2: (hash('i' + t.id) % 628) / 100, dir: hash('d' + t.id) % 2 ? 1 : -1,
        k: Math.sqrt(m / mmax), sp: new Float32Array(ss.length * 2), ip: new Float32Array(its.length * 4), on: 1, fs: 10, font: '', tw: 0, txt: fmt(m) + '분' }; });
    const idMap = new Map(boxes.map(b => [b.t.id, b]));
    const rels = (data.rel || []).filter(r => idMap.has(r[0]) && idMap.has(r[1])).sort((p, q) => q[2] - p[2]).slice(0, Math.max(10, NK)).map(r => ({ p: idMap.get(r[0]), q: idMap.get(r[1]), n: r[2] }));
    rels.forEach(r => { r.p.rel.push(r); r.q.rel.push(r); });
    const tot = { mins: hubs.reduce((a, h) => a + h.mins, 0), ses: hubs.reduce((a, h) => a + h.ses, 0), its: hubs.reduce((a, h) => a + h.its, 0) };
    const kindsUsed = [...new Set(boxes.flatMap(b => b.its.map(o => o.k)))];
    const root = { x: 0, y: 0, bx: 0, by: 0 };

    // ---- 크기, 배치 ----
    let W = 1, H = 1, S = 1, base = 7, dpr = 1, cs = 1, legend = null, legRect = { x: 0, y: 0, w: 0, h: 0 }, heart0 = { x: 0, y: 0 };
    const proj = (v, o) => { const q = v.clone().project(camera); o.x = (q.x * 0.5 + 0.5) * W; o.y = (-q.y * 0.5 + 0.5) * H; return o; };
    const heartNow = o => { head.updateWorldMatrix(true, false); return proj(HEART.clone().applyMatrix4(head.matrixWorld), o); };
    const fonts = () => ({ n: `500 ${(10.5 * S).toFixed(1)}px ${FONT}`, b: `700 ${(13.5 * S).toFixed(1)}px ${FONT}`, c: `500 ${(9 * S).toFixed(1)}px ${FONT}`, r: `700 ${(16 * S).toFixed(1)}px ${FONT}` });
    // 궤도 반지름: 안쪽(세션), 바깥쪽(자료)
    const orbit = b => { const q = Math.sqrt(b.nS), u = Math.sqrt(b.nI);
      b.rx1 = b.w / 2 + 9 + 2.1 * q * cs; b.ry1 = b.h2 / 2 + 9 + 1.3 * q * cs;
      b.rx2 = b.rx1 + 6 + 1.6 * u * cs; b.ry2 = b.ry1 + 6 + 1.1 * u * cs; b.rc = b.rx2 + 7; };
    // 분야 이름표: 선과 다른 업무와 겹침이 가장 적은 자리(오른쪽, 왼쪽, 위, 아래)를 고른다
    const placeLabels = () => {
      const hit = (r, x1, y1, x2, y2) => { for (let k = 0; k <= 12; k++) { const x = x1 + (x2 - x1) * k / 12, y = y1 + (y2 - y1) * k / 12; if (x > r.x0 && x < r.x1 && y > r.y0 && y < r.y1) return 1; } return 0; }, placed = [];
      hubs.forEach(h => { const g = 9 * S, hw = h.lw, hh = h.lh, cands = [{ al: 'left', tox: g, cx: g + hw / 2, cy: h.dy * 5 * S }, { al: 'right', tox: -g, cx: -g - hw / 2, cy: h.dy * 5 * S }, { al: 'center', tox: 0, cx: 0, cy: -(hh / 2 + 8 * S) }, { al: 'center', tox: 0, cx: 0, cy: hh / 2 + 8 * S }, { al: 'left', tox: g, cx: g + hw / 2, cy: -(hh / 2 + 2 * S) }, { al: 'left', tox: g, cx: g + hw / 2, cy: hh / 2 + 2 * S }, { al: 'right', tox: -g, cx: -g - hw / 2, cy: -(hh / 2 + 2 * S) }, { al: 'right', tox: -g, cx: -g - hw / 2, cy: hh / 2 + 2 * S }];
        let best = cands[0], bs = 1e9;
        cands.forEach((c, ci) => { const r = { x0: h.bx + c.cx - hw / 2 - 3, x1: h.bx + c.cx + hw / 2 + 3, y0: h.by + c.cy - hh / 2 - 2, y1: h.by + c.cy + hh / 2 + 2 }; let sc = ci * 0.3;
          sc += 6 * hit(r, h.bx, h.by, root.bx, root.by); h.ts.forEach(t => { const b = idMap.get(t.id); sc += 6 * hit(r, h.bx, h.by, b.bx, b.by); });
          boxes.forEach(b => { const dx = Math.max(r.x0 - b.bx, 0, b.bx - r.x1), dy = Math.max(r.y0 - b.by, 0, b.by - r.y1); if (Math.hypot(dx / b.rx1, dy / b.ry1) < 1) sc += 10; else if (Math.hypot(dx / b.rx2, dy / b.ry2) < 1) sc += 3; });
          hubs.forEach(o => { if (o !== h && o.bx > r.x0 - 6 && o.bx < r.x1 + 6 && o.by > r.y0 - 6 && o.by < r.y1 + 6) sc += 6; }); if (Math.hypot(root.bx - clamp(root.bx, r.x0, r.x1), root.by - clamp(root.by, r.y0, r.y1)) < 24 * S) sc += 6;
          placed.forEach(q => { if (r.x0 < q.x1 && q.x0 < r.x1 && r.y0 < q.y1 && q.y0 < r.y1) sc += 8; }); if (r.x0 < 4 || r.x1 > W - 4 || r.y0 < 4 || r.y1 > H - 4) sc += 20;
          if (sc < bs) { bs = sc; best = c; best.r = r; } });
        h.al = best.al; h.tox = best.tox; h.lox = best.cx; h.loy = best.cy; placed.push(best.r); });
    };
    const layout = () => {
      S = clamp(Math.min(W / 1.3, H) / 880, 0.74, 1.25); const F = fonts();
      pose(0, 0); scene.updateMatrixWorld(true); heartNow(heart0);
      root.bx = heart0.x; root.by = heart0.y;
      // 업무 상자 크기
      boxes.forEach(b => { b.fs = (10 + 2.4 * b.k) * S; b.font = `600 ${b.fs.toFixed(1)}px ${FONT}`; ctx.font = b.font; b.tw = ctx.measureText(b.txt).width; b.w = b.tw + (18 + 34 * b.k) * S; b.h2 = (14 + 5 * b.k) * S; });
      // 층 크기 비율: 업무가 많으면 궤도를 줄인다
      cs = 1; boxes.forEach(b => orbit(b)); const need = boxes.reduce((a, b) => a + Math.PI * b.rc * b.rc * 0.8, 0), have = W * H * 0.5; cs = clamp(Math.sqrt(have / Math.max(1, need)), 0.45, 1); boxes.forEach(b => orbit(b));
      const mg = 10 * S, rc0 = Math.max(0, ...boxes.map(b => b.rc));
      // 분야 허브: 나를 둘러싼 타원 위에 업무 수에 비례한 부채꼴로 놓는다
      const Rx = Math.max(120, Math.min(root.bx, W - root.bx) - rc0 - mg), Ry = Math.max(100, Math.min(root.by, H - root.by) - rc0 - mg), fillK = clamp(0.62 + NK / 38, 0.66, 1);
      const ringK0 = clamp(0.5 + NK / 24, 0.62, 1), R1x = clamp(Rx * 0.3 * fillK + 70 * S, 125 * S, Rx * 0.5) * mix(0.8, 1, ringK0), R1y = clamp(Ry * 0.3 * fillK + 55 * S, 95 * S, Ry * 0.52) * mix(0.8, 1, ringK0);
      const ringK = clamp(0.5 + NK / 24, 0.62, 1), wts = hubs.map(h => h.n + 2.4), wsum = wts.reduce((a, b) => a + b, 0); let acc = -Math.PI / 2 - Math.PI * 0.22;
      hubs.forEach((h, i) => { const span = wts[i] / wsum * Math.PI * 2; h.a0 = acc; h.a1 = acc + span; h.a = acc + span / 2; acc += span; h.dx = Math.cos(h.a); h.dy = Math.sin(h.a);
        h.bx = root.bx + h.dx * R1x; h.by = root.by + h.dy * R1y; h.side = h.dx >= -0.12 ? 1 : -1; });
      ctx.font = F.b; hubs.forEach(h => { const l1 = ctx.measureText(h.th.name).width; ctx.font = F.c; const l2 = ctx.measureText(`${fmt(h.mins)}분  업무 ${h.n}  세션 ${h.ses}  자료 ${h.its}`).width; ctx.font = F.b; h.lw = Math.max(l1 + 4, l2) + 8; h.lh = 38 * S; h.lcx = h.bx + h.side * (9 * S + h.lw / 2); h.lcy = h.by + h.dy * 6 * S; });
      // 업무: 분야 부채꼴 안, 두세 줄로 엇갈려 놓은 뒤 겹침을 푼다
      hubs.forEach(h => { const n = h.n, span = h.a1 - h.a0, rows = clamp(Math.ceil(n * 2 * rc0 / (Math.max(0.3, span) * (Rx + Ry) / 2 * 0.9)), 1, 4);
        h.ts.forEach((t, k) => { const b = idMap.get(t.id), ang = h.a0 + span * (0.1 + 0.8 * (k + 0.5) / n), rr = 1 - (rows - 1 - (k % rows)) * 0.25 * (rows > 1 ? 1 : 0);
          b.tx = root.bx + Math.cos(ang) * Rx * rr * 0.88 * ringK; b.ty = root.by + Math.sin(ang) * Ry * rr * 0.88 * ringK; b.x = b.tx; b.y = b.ty; }); });
      legendBuild(F);
      const fixed = [{ x: root.bx, y: root.by, r: 30 * S }], fixedL = []; hubs.forEach(h => { fixed.push({ x: h.bx, y: h.by, r: 12 * S }); fixedL.push({ x: h.lcx, y: h.lcy, r: Math.max(h.lw / 2, 20) * 0.8 }); }); const fixedAll = fixed.concat(fixedL);
      const relax = (iters, lab) => { for (let it = 0; it < iters; it++) {
        for (let i = 0; i < NK; i++) { const p = boxes[i];
          for (let j = i + 1; j < NK; j++) { const q = boxes[j], dx = q.x - p.x, dy = q.y - p.y, d = Math.hypot(dx, dy) || 0.01, ov2 = (p.rc + q.rc) * 0.9 - d; if (ov2 > 0) { const f = ov2 / d * 0.5; p.x -= dx * f; p.y -= dy * f; q.x += dx * f; q.y += dy * f; } }
          (lab ? fixed : fixedAll).forEach(f => { const dx = p.x - f.x, dy = p.y - f.y, d = Math.hypot(dx, dy) || 0.01, ov2 = p.rc * 0.8 + f.r - d; if (ov2 > 0) { p.x += dx / d * ov2; p.y += dy / d * ov2; } });
          { const L = legRect, nx = clamp(p.x, L.x, L.x + L.w), ny = clamp(p.y, L.y, L.y + L.h), dx = p.x - nx, dy = p.y - ny, d = Math.hypot(dx, dy); if (d < p.rc * 0.8) { if (d > 0.01) { p.x += dx / d * (p.rc * 0.8 - d); p.y += dy / d * (p.rc * 0.8 - d); } else p.y = L.y - p.rc; } }
          if (lab) hubs.forEach(h => { const x0 = h.bx + h.lox - h.lw / 2 - 4 * S, x1 = h.bx + h.lox + h.lw / 2 + 4 * S, y0 = h.by + h.loy - h.lh / 2 - 2 * S, y1 = h.by + h.loy + h.lh / 2 + 2 * S, nx = clamp(p.x, x0, x1), ny = clamp(p.y, y0, y1), dx = (p.x - nx) / p.rx1, dy = (p.y - ny) / p.ry1, d = Math.hypot(dx, dy);
            if (d < 1) { if (d > 0.001) { p.x = nx + (p.x - nx) / d; p.y = ny + (p.y - ny) / d; } else { const l = p.x - x0, r = x1 - p.x, t = p.y - y0, b = y1 - p.y, m = Math.min(l, r, t, b); if (m === l) p.x = x0 - p.rx1; else if (m === r) p.x = x1 + p.rx1; else if (m === t) p.y = y0 - p.ry1; else p.y = y1 + p.ry1; } } });
          p.x += (p.tx - p.x) * 0.012; p.y += (p.ty - p.y) * 0.012;
          p.x = clamp(p.x, p.rx2 + 10, W - p.rx2 - 10); p.y = clamp(p.y, p.ry2 + 14, H - p.ry2 - 14); } } };
      const settle = () => boxes.forEach(b => { b.bx = b.x; b.by = b.y; });
      relax(140, false); settle(); placeLabels(); relax(80, true); settle(); placeLabels(); relax(60, true); settle();
    };
    // 범례(왼쪽 아래): 상자 없이 작은 글자와 표식만. 층마다 표식과 이름과 개수
    const legendBuild = F => {
      if (W < 560 || H < 420) { legend = null; legRect = { x: -9, y: -9, w: 0, h: 0 }; return; }
      const rows = [['root', '나', `총 ${fmt(tot.mins)}분`], ['hub', '분야', String(NT)], ['box', '업무', String(NK)], ['ses', '세션', String(tot.ses)], ['its', '자료', String(tot.its)], ['sol', '소속', ''], ['dash', '관계', String(rels.length)]];
      const lw = 150 * S, rh = 18 * S, kr = Math.ceil(kindsUsed.length / 2), hh = 14 * S + rows.length * rh + (kindsUsed.length ? kr * 14 * S + 6 * S : 0) + 4 * S;
      const c = mkCanvas(Math.ceil(lw * 2), Math.ceil(hh * 2)), x = c.getContext('2d'); x.scale(2, 2); x.textBaseline = 'middle'; x.lineCap = 'round'; x.shadowColor = 'rgba(36,21,15,.6)'; x.shadowBlur = 5 * S;
      x.font = `500 ${9 * S}px ${FONT}`; x.fillStyle = `rgba(${CRM},.6)`; x.fillText('층과 선 읽는 법', 0, 5 * S);
      rows.forEach((r, i) => { const y = 14 * S + i * rh + rh / 2, sx = 12 * S; x.strokeStyle = CR; x.fillStyle = CR; x.lineWidth = 1.1;
        if (r[0] === 'root') { x.beginPath(); x.arc(sx, y, 3 * S, 0, 6.2832); x.fill(); x.beginPath(); x.arc(sx, y, 7.5 * S, 0, 6.2832); x.stroke(); }
        else if (r[0] === 'hub') { x.lineWidth = 1.4; x.beginPath(); x.arc(sx, y, 4.5 * S, 0, 6.2832); x.stroke(); }
        else if (r[0] === 'box') { x.beginPath(); x.moveTo(sx - 10 * S, y - 4.5 * S); x.lineTo(sx - 10 * S, y + 4.5 * S); x.moveTo(sx + 10 * S, y - 4.5 * S); x.lineTo(sx + 10 * S, y + 4.5 * S); x.moveTo(sx - 10 * S, y); x.lineTo(sx - 3.5 * S, y); x.moveTo(sx + 3.5 * S, y); x.lineTo(sx + 10 * S, y); x.stroke(); }
        else if (r[0] === 'ses') { x.beginPath(); x.arc(sx - 4 * S, y, 2.2 * S, 0, 6.2832); x.stroke(); x.beginPath(); x.arc(sx + 4 * S, y, 2.2 * S, 0, 6.2832); x.stroke(); }
        else if (r[0] === 'its') { x.lineWidth = 1.4; for (let k = -1; k <= 1; k++) { x.beginPath(); x.moveTo(sx + k * 5 * S, y - 4 * S); x.lineTo(sx + k * 5 * S, y + 4 * S); x.stroke(); } }
        else if (r[0] === 'sol') { x.beginPath(); x.moveTo(sx - 10 * S, y); x.lineTo(sx + 10 * S, y); x.stroke(); }
        else { x.setLineDash([2.5 * S, 3.5 * S]); x.beginPath(); x.moveTo(sx - 10 * S, y); x.lineTo(sx + 10 * S, y); x.stroke(); x.setLineDash([]); }
        x.fillStyle = CR; x.font = `600 ${10.5 * S}px ${FONT}`; x.textAlign = 'left'; x.fillText(r[1], 36 * S, y); x.font = `500 ${10 * S}px ${FONT}`; x.fillStyle = `rgba(${CRM},.75)`; x.textAlign = 'right'; x.fillText(r[2], lw, y); });
      kindsUsed.forEach((k, i) => { const cx = 36 * S + (i % 2) * 58 * S, y = 14 * S + rows.length * rh + 6 * S + Math.floor(i / 2) * 14 * S + 7 * S; x.strokeStyle = `rgb(${kcl(k)})`; x.lineWidth = 1.6; x.beginPath(); x.moveTo(cx, y - 4 * S); x.lineTo(cx, y + 4 * S); x.stroke();
        x.fillStyle = `rgba(${CRM},.72)`; x.font = `500 ${9 * S}px ${FONT}`; x.textAlign = 'left'; x.fillText(kindOf(k).name, cx + 6 * S, y); });
      x.textAlign = 'left';
      const m = 24 * S; legend = { c, x: m, y: H - hh - m, w: lw, h: hh }; legRect = { x: m - 10 * S, y: H - hh - m - 8 * S, w: lw + 20 * S, h: hh + 16 * S };
    };
    // 꽃 실루엣 지도: 글자와 선 색을 고르는 데만 쓴다(처음 자세 기준, 크기가 바뀔 때 한 번 읽는다)
    let fmask = null, fmw = 2, fmh = 2;
    const readMask = () => { try { castShadow(); fmw = shW; fmh = shH; if (!fmask || fmask.length !== fmw * fmh * 4) fmask = new Uint8Array(fmw * fmh * 4); renderer.readRenderTargetPixels(shA, 0, 0, fmw, fmh, fmask); } catch (e) { fmask = null; } };
    const size = () => {
      const r = main.getBoundingClientRect(); W = Math.max(1, r.width); H = Math.max(1, r.height); dpr = Math.min(window.devicePixelRatio || 1, 2);
      renderer.setSize(W, H, false); camera.aspect = W / H; camera.updateProjectionMatrix(); mesh?.size(W, H);
      const visH = Math.max(6.4, 4.5 / (W / H)), FY = 0.47; base = visH / 2 / Math.tan(THREE.MathUtils.degToRad(15));
      pose(0, 0); scene.updateMatrixWorld(true); const hw = head.localToWorld(HEART.clone()), cy = hw.y - (0.5 - FY) * visH;
      camera.position.set(hw.x, cy, base); camera.lookAt(hw.x, cy, 0); camera.updateMatrixWorld();
      KEY.dir.value.copy(key.position).normalize().transformDirection(camera.matrixWorldInverse);
      ov.width = arcCv.width = Math.round(W * dpr); ov.height = arcCv.height = Math.round(H * dpr); PU.uPx.value = renderer.getPixelRatio() * clamp(Math.min(W, H) / 800, 0.7, 1.4);
      shW = Math.max(2, Math.round(W * dpr * SHK)); shH = Math.max(2, Math.round(H * dpr * SHK)); shA.setSize(shW, shH); shB.setSize(shW, shH); readMask();
      const sc = clamp(Math.min(W / 1400, H / 900), 0.6, 1.4); SU.o1.value.set(7 * sc / W, -9 * sc / H); SU.o2.value.set(26 * sc / W, -34 * sc / H);
      layout();
    };
    const ro = new ResizeObserver(size); ro.observe(main); size();

    // ---- 입력 ----
    let mouse = null, hover = null, drag = null, moved = 0, yawO = 0, raf = 0, last = 0, T = 0;
    const pp = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const onDown = e => { drag = pp(e); moved = 0; try { cv.setPointerCapture(e.pointerId); } catch (_) {} };
    const onMove = e => { const p = pp(e); mouse = p; if (!drag) return; moved += Math.abs(p.x - drag.x) + Math.abs(p.y - drag.y); yawO = clamp(yawO + (p.x - drag.x) * 0.004, -0.7, 0.7); drag = p; };
    const onUp = () => { if (drag && moved < 4 && hover && hover.b) ui.open(hover.b.t.id); drag = null; };
    const onLeave = () => { if (!drag) mouse = null; };
    cv.addEventListener('pointerdown', onDown); cv.addEventListener('pointermove', onMove); cv.addEventListener('pointerup', onUp); cv.addEventListener('pointercancel', onUp); cv.addEventListener('pointerleave', onLeave);

    // ---- 매 프레임 ----
    const hn = { x: 0, y: 0 }, TW = 6.2832;
    const clipTo = (cx, cy, hw, hh, tx, ty, o) => { const dx = tx - cx, dy = ty - cy, k = Math.max(Math.abs(dx) / hw, Math.abs(dy) / hh); if (k < 1) return false; o.x = cx + dx / k; o.y = cy + dy / k; return true; };
    const cA = { x: 0, y: 0 }, cB = { x: 0, y: 0 };
    let offX = 0, offY = 0;
    // 이 자리가 꽃 위인가(1) 바탕 위인가(0): 꽃 위는 먹색, 바탕 위는 크림색으로 그려 어디서나 읽힌다
    const onF = (x, y) => { if (!fmask) return 1; const u = clamp(Math.floor((x - offX) / W * fmw), 0, fmw - 1), v = clamp(Math.floor((1 - (y - offY) / H) * fmh), 0, fmh - 1); return fmask[(v * fmw + u) * 4 + 3] > 110 ? 1 : 0; };
    const WW = new Map(), wid = s => { const k = ctx.font + '|' + s; let w = WW.get(k); if (w === undefined) { w = ctx.measureText(s).width; WW.set(k, w); } return w; };
    const inkText = (s, x, y, on, hw) => { ctx.lineWidth = 4.4 * hw; ctx.strokeStyle = on ? 'rgba(246,243,238,.3)' : 'rgba(36,21,15,.3)'; ctx.strokeText(s, x, y);
      ctx.lineWidth = 2 * hw; ctx.strokeStyle = on ? 'rgba(246,243,238,.82)' : 'rgba(36,21,15,.5)'; ctx.strokeText(s, x, y); ctx.fillStyle = on ? INK : CR; ctx.fillText(s, x, y); };
    const text = (s, x, y, al, on, hw = 1) => {   // on 을 안 주면 낱말마다 그 자리가 꽃 위인지 보고 색을 고른다
      if (on !== undefined || s.indexOf(' ') < 0) { ctx.textAlign = al; if (on === undefined) { const w = wid(s); on = onF(al === 'left' ? x + w / 2 : al === 'right' ? x - w / 2 : x, y); } inkText(s, x, y, on, hw); return; }
      const sp = wid(' '), total = wid(s); let cx = al === 'left' ? x : al === 'right' ? x - total : x - total / 2; ctx.textAlign = 'left';
      s.split(' ').forEach(p => { if (p) { const w = wid(p); inkText(p, cx, y, onF(cx + w / 2, y), hw); cx += w; } cx += sp; }); };
    const ring = (x, y, r) => { ctx.moveTo(x + r, y); ctx.arc(x, y, r, 0, TW); };
    // 소속선: 짧게 쪼개 꽃 위 조각은 먹색, 바탕 위 조각은 크림색으로 긋고, 밑에 반대색 테두리를 깐다
    const SEG = [new Float32Array(3200), new Float32Array(3200)], sn = [0, 0];
    const solid = (arr, w, a) => { sn[0] = sn[1] = 0;
      for (let i = 0; i < arr.length; i += 4) { const x1 = arr[i], y1 = arr[i + 1], x2 = arr[i + 2], y2 = arr[i + 3], n = Math.max(1, Math.ceil(Math.hypot(x2 - x1, y2 - y1) / 26));
        for (let k = 0; k < n; k++) { const ax = mix(x1, x2, k / n), ay = mix(y1, y2, k / n), bx = mix(x1, x2, (k + 1) / n), by = mix(y1, y2, (k + 1) / n), c = onF((ax + bx) / 2, (ay + by) / 2), s = SEG[c], j = sn[c]; if (j + 4 > s.length) continue; s[j] = ax; s[j + 1] = ay; s[j + 2] = bx; s[j + 3] = by; sn[c] = j + 4; } }
      for (let c = 0; c < 2; c++) { const s = SEG[c], m = sn[c]; if (!m) continue; ctx.beginPath(); for (let j = 0; j < m; j += 4) { ctx.moveTo(s[j], s[j + 1]); ctx.lineTo(s[j + 2], s[j + 3]); }
        ctx.lineWidth = w + 2.4; ctx.strokeStyle = c ? `rgba(${CRM},${0.45 * a})` : `rgba(${INK3},${0.3 * a})`; ctx.stroke(); ctx.lineWidth = w; ctx.strokeStyle = c ? `rgba(${INK3},${a})` : `rgba(${CRM},${a})`; ctx.stroke(); } };
    const frame = ts => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (ts - (last || ts)) / 1000); last = ts; T += dt * SPEED; PU.uT.value = T;
      yawO *= drag ? 1 : 0.985;
      pose(T, yawO);
      mesh?.draw(ts); castShadow(); renderer.render(scene, camera);
      // ---- 큰 호 (꽃 뒤) ----
      actx.setTransform(dpr, 0, 0, dpr, 0, 0); actx.clearRect(0, 0, W, H); actx.lineWidth = 1; actx.lineCap = 'round';
      { const U = H / 5.2, ox = W / 2, oy = H * 0.47; arcList.forEach(a => { const rot = a.am * Math.sin(T * a.w + a.ph); actx.strokeStyle = `rgba(${CRM},${(a.al * 0.75).toFixed(3)})`; actx.beginPath(); actx.arc(ox + a.px * U + Math.sin(T * 0.07 + a.ph) * a.d, oy - a.py * U + Math.cos(T * 0.06 + a.ph) * a.d, a.rad * U, a.a0 + rot, a.a1 + rot); actx.stroke(); }); }
      // ---- 위치 갱신: 덮개 전체가 꽃 가운데를 따라 움직이고, 각자 조금씩 떠다닌다 ----
      heartNow(hn); const ox = hn.x - heart0.x, oy = hn.y - heart0.y; offX = ox; offY = oy;
      root.x = hn.x; root.y = hn.y;
      hubs.forEach(h => { h.x = h.bx + ox + 2.2 * S * Math.sin(T * 0.45 + h.ph); h.y = h.by + oy + 2.2 * S * Math.cos(T * 0.38 + h.ph); h.lx = h.x + h.lox; h.ly = h.y + h.loy; });
      boxes.forEach(b => { b.x = b.bx + ox + 3 * S * Math.sin(T * 0.5 + b.ph); b.y = b.by + oy + 3 * S * Math.cos(T * 0.43 + b.ph); b.on = onF(b.x, b.y);
        const a1 = b.o1 + T * 0.16 * b.dir, a2 = b.o2 - T * 0.1 * b.dir, n1 = b.nS, n2 = b.nI;
        for (let i = 0; i < n1; i++) { const a = a1 + i * TW / n1; b.sp[i * 2] = b.x + Math.cos(a) * b.rx1; b.sp[i * 2 + 1] = b.y + Math.sin(a) * b.ry1; }
        for (let i = 0; i < n2; i++) { const a = a2 + i * TW / n2, c = Math.cos(a), s = Math.sin(a), nx = c / b.rx2, ny = s / b.ry2, nl = Math.hypot(nx, ny) || 1; b.ip[i * 4] = b.x + c * b.rx2; b.ip[i * 4 + 1] = b.y + s * b.ry2; b.ip[i * 4 + 2] = nx / nl; b.ip[i * 4 + 3] = ny / nl; } });
      // ---- 마우스 아래 요소 ----
      hover = null;
      if (mouse) { let bd = 1e9; const mx = mouse.x, my = mouse.y;
        boxes.forEach(b => { const d = Math.max(Math.abs(mx - b.x) - b.w / 2, Math.abs(my - b.y) - b.h2 / 2); if (d < 5 && d < bd) { bd = d; hover = { b, kind: 'box' }; } });
        if (!hover) { bd = 5; boxes.forEach(b => { for (let i = 0; i < b.nS; i++) { const d = Math.hypot(mx - b.sp[i * 2], my - b.sp[i * 2 + 1]); if (d < bd) { bd = d; hover = { b, kind: 'ses', i }; } } for (let i = 0; i < b.nI; i++) { const d = Math.hypot(mx - b.ip[i * 4], my - b.ip[i * 4 + 1]); if (d < bd) { bd = d; hover = { b, kind: 'its', i }; } } }); }
        if (!hover) hubs.forEach(h => { if (Math.hypot(mx - h.x, my - h.y) < 12 * S || (Math.abs(mx - h.lx) < h.lw / 2 && Math.abs(my - h.ly) < h.lh / 2)) hover = { h, kind: 'hub' }; });
        if (!hover && Math.hypot(mx - root.x, my - root.y) < 16 * S) hover = { kind: 'root' }; }
      cv.style.cursor = hover && hover.b ? 'pointer' : drag ? 'grabbing' : 'grab';
      const hb = hover && hover.b, hh = hover && (hover.h || (hb && hb.h)), hRoot = hover && hover.kind === 'root', dim = hover ? 0.5 : 1;
      const isHot = b => !hover ? true : hb ? b === hb || (b.rel.some(r => r.p === hb || r.q === hb)) : hh ? b.h === hh : true;
      // ---- 그리기 ----
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
      const F = fonts(); ctx.textBaseline = 'middle'; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
      const hubHot = h => !hover || hRoot || h === hh;
      const L1 = [], L1h = [], L2 = [], L2h = [], pul = [];
      hubs.forEach(h => { const hot = hubHot(h); if (Math.hypot(root.x - h.x, root.y - h.y) > 24 * S) { const dx = root.x - h.x, dy = root.y - h.y, d = Math.hypot(dx, dy), s = 6 * S / d, e = 1 - 11 * S / d; (hot ? L1h : L1).push(h.x + dx * s, h.y + dy * s, h.x + dx * e, h.y + dy * e); pul.push(h.x + dx * e, h.y + dy * e, h.x + dx * s, h.y + dy * s, hot ? 1 : dim, h.ph); } });
      boxes.forEach(b => { const hot = hubHot(b.h) && isHot(b) && (!hb || b === hb); const h = b.h, dx = b.x - h.x, dy = b.y - h.y, d = Math.hypot(dx, dy) || 1;
        if (clipTo(b.x, b.y, b.w / 2, b.h2 / 2, h.x, h.y, cA)) { const s = 6 * S / d; (hot ? L2h : L2).push(h.x + dx * s, h.y + dy * s, cA.x, cA.y); pul.push(h.x + dx * s, h.y + dy * s, cA.x, cA.y, hot ? 1 : dim, b.ph); } });
      solid(L1, 1.5 * S, 0.85 * dim); solid(L2, 1, 0.72 * dim); solid(L1h, 2 * S, 1); solid(L2h, 1.3, 1);
      // 관계선: 점선, 흐르듯 움직인다. 꽃 위를 더 지나면 먹색, 아니면 크림색
      ctx.setLineDash([2.5, 4]); ctx.lineDashOffset = -T * 9;
      rels.forEach(r => { const hot = !hover || (hb ? r.p === hb || r.q === hb : hh ? r.p.h === hh && r.q.h === hh : true); if (!clipTo(r.p.x, r.p.y, r.p.w / 2, r.p.h2 / 2, r.q.x, r.q.y, cA) || !clipTo(r.q.x, r.q.y, r.q.w / 2, r.q.h2 / 2, r.p.x, r.p.y, cB)) return;
        let n = 0; for (let q = 1; q < 6; q++) n += onF(mix(cA.x, cB.x, q / 6), mix(cA.y, cB.y, q / 6)); const a = hot ? 0.9 : 0.28 * dim;
        ctx.strokeStyle = n >= 3 ? `rgba(${INK3},${a})` : `rgba(${CRM},${a})`; ctx.lineWidth = hot && hb ? 1.5 : 1; ctx.beginPath(); ctx.moveTo(cA.x, cA.y); ctx.lineTo(cB.x, cB.y); ctx.stroke(); });
      ctx.setLineDash([]);
      // 소속선 위를 흐르는 작은 점
      for (let i = 0; i < pul.length; i += 6) { const p = (T * 0.14 + pul[i + 5]) % 1, a = Math.sin(Math.PI * p) * pul[i + 4]; if (a < 0.05) continue; const px = mix(pul[i], pul[i + 2], p), py = mix(pul[i + 1], pul[i + 3], p); ctx.fillStyle = onF(px, py) ? INK : CR; ctx.globalAlpha = a * 0.9; ctx.beginPath(); ctx.arc(px, py, 1.6 * S, 0, TW); ctx.fill(); } ctx.globalAlpha = 1;
      // 궤도, 세션, 자료 (업무마다). 가는 궤도선은 가리킨 업무에만
      boxes.forEach(b => { const hot = hubHot(b.h) && isHot(b), A = hot ? 1 : dim * 0.9, act = hb === b, on = b.on; ctx.globalAlpha = A;
        if (act) { ctx.lineWidth = 0.8; ctx.strokeStyle = on ? `rgba(${INK3},.4)` : `rgba(${CRM},.45)`; ctx.beginPath(); if (b.nS) { ctx.moveTo(b.x + b.rx1, b.y); ctx.ellipse(b.x, b.y, b.rx1, b.ry1, 0, 0, TW); } if (b.nI) { ctx.moveTo(b.x + b.rx2, b.y); ctx.ellipse(b.x, b.y, b.rx2, b.ry2, 0, 0, TW); } ctx.stroke(); }
        // 세션: 속 빈 작은 원
        const rs = clamp((TW * Math.sqrt((b.rx1 * b.rx1 + b.ry1 * b.ry1) / 2)) / (Math.max(1, b.nS) * 4.4), 0.9, 1.9) * S; ctx.lineWidth = act ? 1.3 : 1; ctx.strokeStyle = on ? INK : CR; ctx.fillStyle = on ? 'rgba(255,255,255,.6)' : 'rgba(36,21,15,.4)'; ctx.beginPath(); for (let i = 0; i < b.nS; i++) ring(b.sp[i * 2], b.sp[i * 2 + 1], rs); ctx.fill(); ctx.stroke();
        // 자료: 짧은 눈금, 종류마다 색
        ctx.lineWidth = act ? 2 : 1.5; const tl = (4.5 + 1.2 * b.k) * S; let kk = '';
        for (let i = 0; i < b.nI; i++) { const k = b.its[i].k; if (k !== kk) { if (kk) ctx.stroke(); kk = k; ctx.strokeStyle = `rgb(${on ? kc(k) : kcl(k)})`; ctx.beginPath(); } const x = b.ip[i * 4], y = b.ip[i * 4 + 1]; ctx.moveTo(x, y); ctx.lineTo(x + b.ip[i * 4 + 2] * tl, y + b.ip[i * 4 + 3] * tl); } if (kk) ctx.stroke();
        ctx.globalAlpha = 1; });
      // 업무: 쓴 시간만큼 긴 치수선, 가운데 숫자
      boxes.forEach(b => { const hot = hubHot(b.h) && isHot(b), act = hb === b, on = b.on, x0 = b.x - b.w / 2, x1 = b.x + b.w / 2, gp = b.tw / 2 + 5 * S, th = (4.4 + 1.6 * b.k) * S, lw = act ? 1.9 : 1.1 + 0.7 * b.k;
        ctx.globalAlpha = hot ? 1 : Math.max(dim, 0.4);
        ctx.beginPath(); ctx.moveTo(x0, b.y - th); ctx.lineTo(x0, b.y + th); ctx.moveTo(x1, b.y - th); ctx.lineTo(x1, b.y + th); ctx.moveTo(x0, b.y); ctx.lineTo(b.x - gp, b.y); ctx.moveTo(b.x + gp, b.y); ctx.lineTo(x1, b.y);
        ctx.lineWidth = lw + 2.2; ctx.strokeStyle = on ? 'rgba(246,243,238,.45)' : 'rgba(36,21,15,.32)'; ctx.stroke(); ctx.lineWidth = lw; ctx.strokeStyle = on ? INK : CR; ctx.stroke();
        ctx.font = b.font; text(b.txt, b.x, b.y + 0.5, 'center', on); ctx.globalAlpha = 1; });
      // 풀이선: 가리킨 업무에서 업무, 세션, 자료 층을 짚는다
      if (hb) { const b = hb, sd = b.x >= root.x ? 1 : -1, ic = b.on ? INK : CR; ctx.font = F.c; ctx.lineWidth = 0.9; ctx.strokeStyle = ic; ctx.fillStyle = ic; ctx.globalAlpha = 1;
        const lead = (a, rx, ry, ext, txt) => { const ex = b.x + Math.cos(a) * rx, ey = b.y + Math.sin(a) * ry, fx = ex + sd * ext, fy = ey + Math.sin(a) * ext * 0.8; ctx.strokeStyle = ic; ctx.beginPath(); ctx.moveTo(ex, ey); ctx.lineTo(fx, fy); ctx.lineTo(fx + sd * 9 * S, fy); ctx.stroke(); ctx.fillStyle = ic; ctx.beginPath(); ring(ex, ey, 1.6 * S); ctx.fill(); text(txt, fx + sd * 12 * S, fy, sd > 0 ? 'left' : 'right'); };
        if (b.nS) lead(sd > 0 ? -0.62 : Math.PI + 0.62, b.rx1, b.ry1, (b.rx2 - b.rx1) + 22 * S, `세션 ${b.nS}`);
        if (b.nI) lead(sd > 0 ? 0.62 : Math.PI - 0.62, b.rx2, b.ry2, 24 * S, `자료 ${b.nI}`);
        { const ey = b.y - b.h2 / 2, fy = b.y - b.ry2 - 18 * S; ctx.strokeStyle = ic; ctx.beginPath(); ctx.moveTo(b.x, ey); ctx.lineTo(b.x, fy); ctx.stroke(); ctx.fillStyle = ic; ctx.beginPath(); ring(b.x, ey, 1.6 * S); ctx.fill(); text('업무', b.x, fy - 7 * S, 'center'); }
        ctx.globalAlpha = 1; }
      // 분야: 속 빈 원 + 굵은 이름 + 합계와 개수
      hubs.forEach(h => { const hot = hubHot(h); ctx.globalAlpha = hot ? 1 : Math.max(dim, 0.45); ctx.lineWidth = 1.5; ctx.strokeStyle = INK; ctx.fillStyle = 'rgba(255,255,255,.8)'; ctx.beginPath(); ring(h.x, h.y, 5.2 * S); ctx.fill(); ctx.stroke();
        const lx = h.x + h.tox, al = h.al, ty = h.ly;
        ctx.font = F.c; ctx.globalAlpha *= 0.78; text('분야', lx, ty - 13.5 * S, al); ctx.globalAlpha = hot ? 1 : Math.max(dim, 0.45); ctx.font = F.b; text(h.th.name, lx, ty, al);
        ctx.font = F.c; ctx.globalAlpha *= 0.85; text(`${fmt(h.mins)}분  업무 ${h.n}  세션 ${h.ses}  자료 ${h.its}`, lx, ty + 13 * S, al); ctx.globalAlpha = 1; });
      // 나: 겹 고리와 이름, 천천히 도는 점선 고리
      { ctx.globalAlpha = 1; ctx.strokeStyle = INK; ctx.lineWidth = 1.5; ctx.fillStyle = INK; ctx.beginPath(); ring(root.x, root.y, 3 * S); ctx.fill(); ctx.beginPath(); ring(root.x, root.y, 8 * S); ctx.stroke();
        ctx.lineWidth = 1; ctx.setLineDash([2 * S, 3.2 * S]); ctx.lineDashOffset = -T * 5; ctx.beginPath(); ring(root.x, root.y, 14 * S); ctx.stroke(); ctx.setLineDash([]);
        ctx.font = F.r; text('나', root.x + 19 * S, root.y - 1, 'left'); ctx.font = F.c; ctx.globalAlpha = 0.85; text(`총 ${fmt(tot.mins)}분`, root.x + 19 * S, root.y + 13 * S, 'left'); ctx.globalAlpha = 1; }
      // 범례
      if (legend) ctx.drawImage(legend.c, legend.x, legend.y, legend.w, legend.h);
      // 설명 글자: 상자 없이 글자만
      if (hover) { let t1 = '', t2 = '';
        if (hover.kind === 'box') { t1 = hover.b.t.title; t2 = `업무, ${hover.b.h.th.name} 분야, ${fmt(hover.b.m)}분, 세션 ${hover.b.nS}, 자료 ${hover.b.nI}`; }
        else if (hover.kind === 'ses') { const s = hover.b.ss[hover.i]; t1 = `세션 ${s.when || ''}`.trim(); t2 = `${hover.b.t.title}, ${Math.max(1, Math.round(((s.end || 0) - (s.start || 0)) || (s.active || 0) / 60))}분`; }
        else if (hover.kind === 'its') { const o = hover.b.its[hover.i]; t1 = `${kindOf(o.k).name} ${o.n}`; t2 = `자료, ${hover.b.t.title}`; }
        else if (hover.kind === 'hub') { t1 = `${hover.h.th.name}`; t2 = `분야, 업무 ${hover.h.n}, 세션 ${hover.h.ses}, 자료 ${hover.h.its}, ${fmt(hover.h.mins)}분`; }
        else { t1 = '나'; t2 = `분야 ${NT}, 업무 ${NK}, 세션 ${tot.ses}, 자료 ${tot.its}, 총 ${fmt(tot.mins)}분`; }
        t1 = t1.length > 36 ? t1.slice(0, 36) + '…' : t1; t2 = t2.length > 60 ? t2.slice(0, 60) + '…' : t2;
        ctx.globalAlpha = 1; const lf = hb && hb.x >= root.x; ctx.font = F.b; const w1 = ctx.measureText(t1).width; ctx.font = F.c; const tw = Math.max(w1, ctx.measureText(t2).width);
        const tx = clamp(lf ? mouse.x - tw - 16 : mouse.x + 16, 8, W - tw - 8), ty = clamp(mouse.y + 22, 16, H - 30);
        ctx.font = F.b; text(t1, tx, ty, 'left', undefined, 2.2); ctx.font = F.c; text(t2, tx, ty + 15 * S, 'left', undefined, 2.2); }
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf); ro.disconnect();
      ['pointerdown', 'pointermove', 'pointerup', 'pointercancel', 'pointerleave'].forEach((n, i) => cv.removeEventListener(n, [onDown, onMove, onUp, onUp, onLeave][i]));
      disp.forEach(o => o.dispose && o.dispose());
      renderer.dispose(); renderer.forceContextLoss(); mesh?.destroy();
      [bg, arcCv, cv, ov].forEach(e => e.remove());
    };
  }
};

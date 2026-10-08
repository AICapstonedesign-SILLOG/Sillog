/* 온톨로지 (three.js): 클래스 층(나 > 분야 > 업무 종류 > 업무 > 세션, 자료)을 반투명 유리판으로 쌓고, 각 층 위에 실제 데이터를 빛나는 점으로 놓는다.
   빛의 세기 = 최근에 일한 정도. 층 사이 가는 선 = 소속(is-a, has), 업무 층의 점선 호 = 같은 자료를 쓴 업무 관계(rel).
   점을 가리키면 그 점의 위쪽 길(나까지)과 아래쪽(세션, 자료)만 남고 나머지는 흐려진다. 업무를 누르면 업무 상세 */
window.V3D = window.V3D || {};
window.V3D.ontology = function (main, data, ui) {
  let dead = false, cleanup = () => {};
  const start = () => { if (!dead) cleanup = build(window.THREE); };
  if (window.THREE) start(); else window.addEventListener('three-ready', start, { once: true });
  return () => { dead = true; window.removeEventListener('three-ready', start); cleanup(); };

  function build(THREE) {
    const BROWN = '#24150F';
    const FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
    const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
    const mulberry = a => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
    const rnd = mulberry(77);
    const trunc = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);

    // ---- 층(클래스) 정의: 위에서 아래로 ----
    const LAYERS = [
      { key: 'me', y: 2.55, s: 0.3 }, { key: 'theme', y: 1.6, s: 0.5, label: '분야' }, { key: 'type', y: 0.65, s: 0.74, label: '업무 종류' },
      { key: 'task', y: -0.4, s: 1, label: '업무' }, { key: 'ses', y: -1.45, s: 1, label: '세션' }, { key: 'item', y: -2.4, s: 1, label: '자료' }];
    const LX = 5.1, LZ = 3.5;

    // ---- 데이터 → 노드 ----
    const tasks = data.tasks || [], themeName = new Map((data.themes || []).map(t => [t.id, t.name]));
    const kindName = k => (data.kinds && data.kinds[k] && (data.kinds[k].name || data.kinds[k].label)) || k;
    const days = tasks.flatMap(t => (t.sessions || []).map(s => s.d)).filter(d => typeof d === 'number');
    const maxD = days.length ? Math.max(...days) : 0, minD = days.length ? Math.min(...days) : 0, tau = Math.max(3, (maxD - minD) * 0.3);
    const rec = d => (typeof d === 'number' ? Math.exp(-(maxD - d) / tau) : 0);
    const N = [];   // 노드: {k, layer, name, par, x, y, z, r, glow, kids:[], ...}
    const add = o => { o.i = N.length; o.kids = []; o.sx = o.sy = 0; o.w = 1; N.push(o); if (o.par != null) N[o.par].kids.push(o.i); return o; };
    const lay = i => LAYERS[i].y;
    const root = add({ k: 0, name: '나', par: null, x: 0, y: lay(0), z: 0, r: 0.2, glow: 1 });

    // 분야 > 종류 > 업무 묶기
    const gmap = new Map();
    tasks.forEach(t => { const g = gmap.get(t.theme) || gmap.set(t.theme, { id: t.theme, name: themeName.get(t.theme) || '기타', types: new Map(), n: 0 }).get(t.theme); const ty = t.type || '기타'; (g.types.get(ty) || g.types.set(ty, []).get(ty)).push(t); g.n++; });
    const gs = [...gmap.values()].sort((a, b) => b.n - a.n), total = Math.max(1, tasks.length);
    const ell = (a, r, y) => ({ x: Math.cos(a) * r * 1.16, z: Math.sin(a) * r * 0.76, y });
    let a0 = -Math.PI / 2 - Math.PI * 0.12;
    const tmins = Math.max(1, ...tasks.map(t => t.mins || 0));
    gs.forEach(g => {
      const span = g.n / total * Math.PI * 2, ac = a0 + span / 2;
      const gn = add({ k: 1, name: g.name, par: root.i, ...ell(ac, 1.15, lay(1)), r: 0.11 + 0.025 * Math.sqrt(g.n), glow: 0 });
      let a = a0; const types = [...g.types.entries()].sort((p, q) => q[1].length - p[1].length);
      types.forEach(([ty, ts]) => {
        const ts_span = ts.length / g.n * span, tc = a + ts_span / 2;
        const tn = add({ k: 2, name: ty, par: gn.i, ...ell(tc, 2.2, lay(2)), r: 0.085 + 0.02 * Math.sqrt(ts.length), glow: 0 });
        ts.sort((p, q) => (q.mins || 0) - (p.mins || 0));
        ts.forEach((t, j) => {
          const aa = ts.length === 1 ? tc : a + ts_span * (0.12 + 0.76 * j / (ts.length - 1)), rr = 3.25 + (ts.length === 1 ? 0 : (j % 2 ? 0.55 : -0.2));
          const last = Math.max(-1e9, ...(t.sessions || []).map(s => s.d).filter(d => typeof d === 'number')), gl = last > -1e9 ? rec(last) : 0;
          const tk = add({ k: 3, name: t.title, id: t.id, par: tn.i, ...ell(aa, rr, lay(3)), r: 0.075 + 0.07 * Math.sqrt((t.mins || 0) / tmins), glow: gl, t });
          tn.glow = Math.max(tn.glow, gl); gn.glow = Math.max(gn.glow, gl); root.glow = 1;
          // 세션, 자료: 업무 바로 아래 층에 작은 구름
          const ses = t.sessions || [], its = Object.entries(t.items || {}).flatMap(([kk, arr]) => (arr || []).map(it => ({ kk, it })));
          const cloud = (n, ly, mk) => { const rad = Math.min(0.62, 0.14 + 0.055 * Math.sqrt(n)); for (let q = 0; q < n; q++) { const rho = rad * Math.sqrt((q + 0.5) / n), th = q * 2.39996 + tk.i; mk(q, tk.x + Math.cos(th) * rho * 1.15, tk.z + Math.sin(th) * rho * 0.85); } };
          cloud(ses.length, 4, (q, x, z) => { const s = ses[q]; add({ k: 4, name: s.when || '세션', par: tk.i, x, y: lay(4) + (rnd() - 0.5) * 0.12, z, r: 0.034 + 0.02 * Math.sqrt(clamp((s.active || 20) / 90, 0, 1.5)), glow: rec(s.d) }); });
          cloud(its.length, 5, (q, x, z) => { const o = its[q]; add({ k: 5, name: (o.it && o.it.name) || '자료', sub: kindName(o.kk), par: tk.i, x, y: lay(5) + (rnd() - 0.5) * 0.12, z, r: 0.03 + 0.008 * rnd(), glow: gl * 0.55 }); });
        });
        a += ts_span;
      });
      a0 += span;
    });
    // 분야, 종류의 빛은 일한 정도가 아니라 소속 합의 최대값으로 약하게
    N.forEach(n => { if (n.k === 1 || n.k === 2) n.glow = 0.25 + 0.5 * n.glow; });
    const taskNode = new Map(N.filter(n => n.k === 3).map(n => [n.id, n]));
    const NN = N.length;

    // ---- 렌더러, 장면 ----
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, premultipliedAlpha: true, powerPreference: 'high-performance' }); }
    catch (e) { const p = document.createElement('p'); p.className = 'empty-note'; p.textContent = '이 환경에서는 WebGL 을 쓸 수 없습니다'; main.appendChild(p); return () => p.remove(); }
    renderer.setClearColor(0x000000, 0); renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.15;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    const cv = renderer.domElement;
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;cursor:grab;touch-action:none';
    main.style.position = 'relative';
    const mesh = window.G3D && window.G3D.mesh ? window.G3D.mesh(main, 0.8) : null;
    main.appendChild(cv);
    const scene = new THREE.Scene(), FOV = 40, camera = new THREE.PerspectiveCamera(FOV, 1, 0.1, 80), group = new THREE.Group();
    scene.add(group);
    const disp = []; const own = o => { disp.push(o); return o; };

    // ---- 유리 층: 가장자리가 부드럽게 사라지는 둥근 사각형, 선 없음 ----
    const tex = (() => {
      const S = 192, c = document.createElement('canvas'); c.width = c.height = S; const g = c.getContext('2d'), im = g.createImageData(S, S), R = 0.22;
      for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
        const px = Math.abs(x / (S - 1) * 2 - 1), py = Math.abs(y / (S - 1) * 2 - 1), qx = Math.max(px - (1 - R), 0), qy = Math.max(py - (1 - R), 0), d = Math.hypot(qx, qy) - R;
        const e = clamp(1 - (d + 0.14) / 0.14, 0, 1), a = e * e * (3 - 2 * e), o = (y * S + x) * 4;
        im.data[o] = 255; im.data[o + 1] = 246; im.data[o + 2] = 232; im.data[o + 3] = Math.round(255 * a);
      }
      g.putImageData(im, 0, 0); const t = own(new THREE.CanvasTexture(c)); t.colorSpace = THREE.SRGBColorSpace; return t;
    })();
    const planeG = own(new THREE.PlaneGeometry(2 * LX, 2 * LZ)); planeG.rotateX(-Math.PI / 2);
    LAYERS.forEach((L, i) => {
      const m = new THREE.Mesh(planeG, own(new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: i < 3 ? 0.11 : 0.1, side: THREE.DoubleSide })));
      m.position.y = L.y; m.scale.set(L.s, 1, L.s); m.renderOrder = i; group.add(m);
    });

    // ---- 점 (핵 + 번짐) ----
    const hex = h => new THREE.Color(h);
    const cDim = hex('#76503C'), cMid = hex('#C9A98C'), cHot = hex('#FFF1DC'), cSky = hex('#C7DCEA');
    const nPos = new Float32Array(NN * 3), nCol = new Float32Array(NN * 3), nR = new Float32Array(NN), nG = new Float32Array(NN), nLit = new Float32Array(NN).fill(1), nPh = new Float32Array(NN);
    const tmp = new THREE.Color();
    N.forEach((n, i) => {
      nPos.set([n.x, n.y, n.z], i * 3); nR[i] = n.r; nG[i] = n.glow; nPh[i] = rnd() * 6.28;
      const g = Math.pow(n.glow, 0.8);
      tmp.copy(cDim).lerp(cMid, clamp(g * 2, 0, 1)).lerp(cHot, clamp(g * 2 - 1, 0, 1));
      if (n.k === 5) tmp.lerp(cSky, 0.55);
      if (n.k === 0) tmp.copy(cHot);
      nCol.set([tmp.r, tmp.g, tmp.b], i * 3);
    });
    const ptG = own(new THREE.BufferGeometry()), litA = new THREE.BufferAttribute(nLit, 1);
    ptG.setAttribute('position', new THREE.BufferAttribute(nPos, 3)); ptG.setAttribute('aCol', new THREE.BufferAttribute(nCol, 3)); ptG.setAttribute('aR', new THREE.BufferAttribute(nR, 1));
    ptG.setAttribute('aG', new THREE.BufferAttribute(nG, 1)); ptG.setAttribute('aPh', new THREE.BufferAttribute(nPh, 1)); ptG.setAttribute('aLit', litA);
    const U = { uPs: { value: 1 }, uT: { value: 0 } };
    const VS = (halo) => `attribute vec3 aCol; attribute float aR, aG, aPh, aLit; uniform float uPs, uT; varying vec3 vC; varying float vA, vG;
      void main() { vec4 mv = modelViewMatrix * vec4(position, 1.0); float k = ${halo ? '(2.0 + 3.2 * aG)' : '1.0'};
        gl_PointSize = max(${halo ? '2.0' : '2.2'}, 2.0 * aR * k * uPs / -mv.z); vC = aCol; vG = aG * (1.0 + 0.1 * sin(uT * 1.3 + aPh)); vA = mix(0.14, 1.0, aLit); gl_Position = projectionMatrix * mv; }`;
    const haloM = own(new THREE.ShaderMaterial({ transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, uniforms: U, vertexShader: VS(true),
      fragmentShader: `varying vec3 vC; varying float vA, vG; void main() { float d = length(gl_PointCoord * 2.0 - 1.0); if (d > 1.0) discard; float f = pow(1.0 - d, 2.4); gl_FragColor = vec4(1.0, 0.86, 0.64, f * pow(vG, 1.6) * 0.42 * vA); }` }));
    const coreM = own(new THREE.ShaderMaterial({ transparent: true, depthWrite: false, uniforms: U, vertexShader: VS(false),
      fragmentShader: `varying vec3 vC; varying float vA, vG; void main() { float d = length(gl_PointCoord * 2.0 - 1.0); if (d > 1.0) discard; float e = 1.0 - smoothstep(0.72, 1.0, d); vec3 c = vC * (1.0 + 0.25 * smoothstep(0.6, 0.0, d) * vG); gl_FragColor = vec4(c, e * vA); }` }));
    const halo = new THREE.Points(ptG, haloM), core = new THREE.Points(ptG, coreM);
    halo.frustumCulled = core.frustumCulled = false; halo.renderOrder = 10; core.renderOrder = 11; group.add(halo, core);

    // ---- 가는 선: 소속(수직 실)과 업무 사이 점선 호 ----
    const lineVS = `attribute float aA; varying float vA; void main() { vA = aA; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;
    const lineFS = `uniform vec3 uC; varying float vA; void main() { gl_FragColor = vec4(uC, vA); }`;
    const lineM = c => own(new THREE.ShaderMaterial({ transparent: true, depthWrite: false, uniforms: { uC: { value: new THREE.Color(c) } }, vertexShader: lineVS, fragmentShader: lineFS }));
    const mkLines = (segs, mat, order) => {   // segs: [[ax,ay,az,bx,by,bz], ...]
      const P = new Float32Array(segs.length * 6); segs.forEach((s, i) => P.set(s, i * 6));
      const g = own(new THREE.BufferGeometry()), A = new Float32Array(segs.length * 2);
      g.setAttribute('position', new THREE.BufferAttribute(P, 3)); const aa = new THREE.BufferAttribute(A, 1); g.setAttribute('aA', aa);
      const l = new THREE.LineSegments(g, mat); l.frustumCulled = false; l.renderOrder = order; group.add(l); return { A, aa };
    };
    const thr = [];   // 자식 노드마다 부모와 잇는 실
    N.forEach(n => { if (n.par != null) { const p = N[n.par]; thr.push({ c: n.i, p: n.par, s: [p.x, p.y, p.z, n.x, n.y, n.z] }); } });
    const TL = mkLines(thr.map(t => t.s), lineM('#FFEBD2'), 8);
    const arcs = [];   // 업무 관계: 업무 층 위로 살짝 솟는 점선 호
    (data.rel || []).forEach(([a, b, c]) => {
      const A = taskNode.get(a), B = taskNode.get(b); if (!A || !B) return;
      const d = Math.hypot(A.x - B.x, A.z - B.z), lift = 0.35 + d * 0.16, M = (u, k) => (1 - u) * (1 - u) * A[k] + 2 * (1 - u) * u * ((A[k] + B[k]) / 2) + u * u * B[k];
      const my = (A.y + B.y) / 2 + lift, S = Math.max(10, Math.round(d * 7)), pts = [];
      for (let q = 0; q <= S; q++) { const u = q / S; pts.push([M(u, 'x'), (1 - u) * (1 - u) * A.y + 2 * (1 - u) * u * my + u * u * B.y, M(u, 'z')]); }
      arcs.push({ a: A.i, b: B.i, c: c || 1, pts });
    });
    const arcSegs = [], arcOwner = [];
    arcs.forEach((r, ri) => { for (let q = 0; q < r.pts.length - 1; q += 2) { arcSegs.push([...r.pts[q], ...r.pts[q + 1]]); arcOwner.push(ri); } });
    const AL = arcSegs.length ? mkLines(arcSegs, lineM('#FFF1DC'), 9) : null;

    // ---- 강조 상태: 가리킨 점의 길(위로 나까지, 아래로 세션과 자료)만 남긴다 ----
    let lit = null;   // Set 또는 null(전체)
    const setLit = hv => {
      lit = null;
      if (hv) { lit = new Set(); for (let n = hv; n; n = n.par == null ? null : N[n.par]) lit.add(n.i); const dn = n => { lit.add(n.i); n.kids.forEach(k => dn(N[k])); }; dn(hv); }
      for (let i = 0; i < NN; i++) nLit[i] = !lit || lit.has(i) ? 1 : 0;
      litA.needsUpdate = true;
      thr.forEach((t, i) => { const on = !lit || (lit.has(t.c) && lit.has(t.p)), base = 0.07 + 0.3 * Math.pow(N[t.c].glow, 0.9) + (N[t.c].k <= 3 ? 0.16 : 0); const a = on ? (lit ? 0.85 : base) : 0.012; TL.A[i * 2] = TL.A[i * 2 + 1] = a; });
      TL.aa.needsUpdate = true;
      if (AL) { arcSegs.forEach((_, i) => { const r = arcs[arcOwner[i]], on = !lit || (lit.has(r.a) && lit.has(r.b)) || (hv && hv.k === 3 && (r.a === hv.i || r.b === hv.i)), a = on ? (lit && hv.k === 3 ? 0.8 : 0.16 + 0.07 * Math.min(4, r.c)) : 0.015; AL.A[i * 2] = AL.A[i * 2 + 1] = a; }); AL.aa.needsUpdate = true; }
    };
    setLit(null);

    // ---- DOM: 라벨 ----
    const labs = [], mctx = document.createElement('canvas').getContext('2d'); let used = 0;
    const label = (txt, x, y, al, wt, sz, o = {}) => {
      let el = labs[used++];
      if (!el) { el = document.createElement('div'); el._t = ''; el._v = 0; main.appendChild(el); labs.push(el); el.style.cssText = `position:absolute;left:0;top:0;z-index:4;pointer-events:none;white-space:nowrap;font-family:${FONT};color:${BROWN};text-shadow:0 0 5px rgba(246,245,244,.95),0 0 2px rgba(246,245,244,.9);will-change:transform`; }
      if (el._w !== wt) { el._w = wt; el.style.fontWeight = wt; }
      if (el._sz !== sz) { el._sz = sz; el.style.fontSize = sz + 'px'; }
      if (el._t !== txt) { el._t = txt; el.textContent = txt; }
      el.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) translate(${o.mid ? '-50%' : '0'},-50%)`;
      el.style.opacity = al; if (!el._v) { el._v = 1; el.style.display = ''; }
    };

    // ---- 시점, 입력 ----
    let W = 1, H = 1, base = 14;
    const view = { yaw: 0.5, pitch: 0.3, zoom: 1 }, PAD_L = 90;
    let vy = 0.0016, vp = 0, drag = null, moved = 0, mouse = null, hover = null, raf = 0, last = 0;
    const size = () => {
      const r = main.getBoundingClientRect(); W = Math.max(1, r.width); H = Math.max(1, r.height); renderer.setSize(W, H, false); camera.aspect = W / H; camera.updateProjectionMatrix(); mesh?.size(W, H);
      const half = Math.min(FOV / 2 * Math.PI / 180, Math.atan(Math.tan(FOV / 2 * Math.PI / 180) * W / H)), Rb = 5.3;
      base = Rb / Math.tan(half) * 0.92; camera.setViewOffset(W, H, -PAD_L / 2, 0, W, H);
    };
    const ro = new ResizeObserver(size); ro.observe(main); size();
    const pos = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const pick = (x, y) => {
      let b = null, bs = 1e9;
      for (const n of N) { if (n.k === 0 && 0) continue; const d = Math.hypot(x - n.sx, y - n.sy), rr = Math.max(7, n.pr + 3); if (d < rr) { const s = d / rr + n.w * 0.004 - (n.k === 3 ? 0.15 : 0); if (s < bs) { bs = s; b = n; } } }
      return b;
    };
    cv.addEventListener('pointerdown', e => { drag = pos(e); moved = 0; cv.setPointerCapture(e.pointerId); cv.style.cursor = 'grabbing'; });
    cv.addEventListener('pointermove', e => { const p = pos(e); mouse = p; if (!drag) return; const dx = p.x - drag.x, dy = p.y - drag.y; moved += Math.abs(dx) + Math.abs(dy); vy = dx * 0.006; vp = dy * 0.004; view.yaw += vy; view.pitch = clamp(view.pitch + vp, 0.02, 1.1); drag = p; });
    const up = e => { if (drag && moved < 4) { const p = pos(e), n = pick(p.x, p.y); if (n && n.k === 3) ui.open(n.id); } drag = null; cv.style.cursor = 'grab'; };
    cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
    cv.addEventListener('pointerleave', () => { if (!drag) mouse = null; });
    cv.addEventListener('wheel', e => { e.preventDefault(); view.zoom = clamp(view.zoom * Math.exp(-e.deltaY * 0.0015), 1, 3); }, { passive: false });

    // ---- 매 프레임 ----
    const M4 = new THREE.Matrix4(), hovPrev = { n: null }, startT = performance.now();
    const taskOrder = N.filter(n => n.k === 3).sort((a, b) => (b.glow * 0.6 + b.r * 2) - (a.glow * 0.6 + a.r * 2));
    const showName = new Set(taskOrder.slice(0, 9).map(n => n.i));
    const frame = t => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (t - (last || t)) / 1000) * 60 || 1; last = t;
      if (!drag) { vy += ((mouse ? 0 : 0.0016) - vy) * 0.05 * dt; vp *= Math.pow(0.9, dt); view.yaw += vy * dt; view.pitch = clamp(view.pitch + vp * dt, 0.02, 1.1); }
      const D = base / view.zoom;
      camera.position.set(0, 0, D); group.rotation.set(view.pitch, view.yaw, 0, 'XYZ');
      group.updateMatrixWorld(true); camera.updateMatrixWorld(); camera.updateProjectionMatrix();
      const ps = renderer.getPixelRatio() * H / (2 * Math.tan(FOV / 2 * Math.PI / 180));
      U.uPs.value = ps; U.uT.value = (performance.now() - startT) / 1000;
      // 화면 좌표
      M4.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse).multiply(group.matrixWorld); const e = M4.elements, mv = new THREE.Matrix4().multiplyMatrices(camera.matrixWorldInverse, group.matrixWorld).elements;
      for (const n of N) {
        const w = e[3] * n.x + e[7] * n.y + e[11] * n.z + e[15];
        n.sx = ((e[0] * n.x + e[4] * n.y + e[8] * n.z + e[12]) / w * 0.5 + 0.5) * W; n.sy = (0.5 - (e[1] * n.x + e[5] * n.y + e[9] * n.z + e[13]) / w * 0.5) * H; n.w = w; n.pr = n.r * (ps / renderer.getPixelRatio()) / w;
      }
      const nh = mouse && !drag ? pick(mouse.x, mouse.y) : null;
      if (nh !== hovPrev.n) { hovPrev.n = nh; hover = nh; setLit(nh); }
      cv.style.cursor = hover ? (hover.k === 3 ? 'pointer' : 'default') : drag ? 'grabbing' : 'grab';
      mesh?.draw(t); renderer.render(scene, camera);

      // 라벨: 층 이름은 화면 왼쪽에 고정, 나머지는 겹치면 건너뛴다
      used = 0; const boxes = [], wOf = (txt, sz, w) => { mctx.font = `${w} ${sz}px ${FONT}`; return mctx.measureText(txt).width + 4; };
      const hit = (x, y, w, h) => boxes.some(b => x < b[0] + b[2] + 3 && x + w > b[0] - 3 && y < b[1] + b[3] + 1 && y + h > b[1] - 1);
      const put = (txt, x, y, wt, sz, al, o = {}, force) => {
        const w = wOf(txt, sz, wt), h = sz + 6, lx = o.mid ? x - w / 2 : x; if (!force && hit(lx, y - h / 2, w, h)) return false;
        if (lx < 4 || lx + w > W - 4 || y < 10 || y > H - 10) return false; boxes.push([lx, y - h / 2, w, h]); label(txt, x, y, al, wt, sz, o); return true;
      };
      const cp = new THREE.Vector3();
      LAYERS.forEach(L => { if (!L.label) return; cp.set(0, L.y, 0).applyMatrix4(group.matrixWorld).applyMatrix4(camera.matrixWorldInverse).applyMatrix4(camera.projectionMatrix); put(L.label, 22, (0.5 - cp.y * 0.5) * H, 600, 13, 1, {}, true); });
      const alOf = n => clamp(1.25 - (n.w - base * 0.75) / (base * 0.9), 0.5, 1);
      const nameOf = n => n.k === 5 ? n.name : n.name;
      if (hover) {
        const path = []; for (let n = hover; n; n = n.par == null ? null : N[n.par]) path.push(n);
        const hs = hover.k >= 4 ? trunc(hover.sub ? hover.sub + '  ' + nameOf(hover) : nameOf(hover), 34) : nameOf(hover);
        put(hs, hover.sx + hover.pr + 10, hover.sy - 2, 600, 13, 1, {}, true);
        path.slice(1).forEach(n => { put(nameOf(n), n.sx + n.pr + 8, n.sy, n.k === 1 ? 600 : 400, n.k === 1 ? 13 : 12, 1, {}, true); });
        if (hover.k === 3) hover.kids.length;
      } else {
        N.forEach(n => { if (n.k === 0) put('나', n.sx + 12, n.sy, 600, 13, 1, {}); });
        N.filter(n => n.k === 1).forEach(n => put(n.name, n.sx + n.pr + 8, n.sy, 600, 13, alOf(n)));
        taskOrder.forEach(n => { if (showName.has(n.i)) put(trunc(n.name, 14), n.sx + n.pr + 7, n.sy, 400, 12, alOf(n)); });
        N.filter(n => n.k === 2).forEach(n => put(trunc(n.name, 12), n.sx + n.pr + 7, n.sy, 400, 11.5, alOf(n) * 0.9));
      }
      for (let i = used; i < labs.length; i++) if (labs[i]._v) { labs[i]._v = 0; labs[i].style.display = 'none'; }
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf); ro.disconnect();
      disp.forEach(o => o.dispose());
      renderer.dispose(); renderer.forceContextLoss(); cv.remove(); mesh?.destroy(); labs.forEach(e => e.remove());
    };
  }
};

/* 꽃 (three.js): 꽃다발 모양의 둥근 꽃 공. 숨은 중심에서 휘어진 줄기가 바깥으로 뻗고, 분야 하나 = 같은 방향으로 모인 줄기 묶음, 업무 하나 = 줄기 끝의 꽃 한 송이.
   꽃잎 = 그 업무의 세션 하나씩과 자료 하나씩(실제 데이터만), 길이 = 세션 활동 분(자료는 같은 길이), 중심 원판 크기 = 업무 총 시간.
   열 때 꽃잎이 펼쳐지고, 줄기는 바람에 살랑인다. 꽃을 누르면 그 꽃 앞으로 날아가 꽃잎 이름이 보인다 */
window.V3D = window.V3D || {};
window.V3D.bloom = function (main, data, ui) {
  let dead = false, cleanup = () => {};
  const start = () => { if (!dead) cleanup = build(window.THREE); };
  if (window.THREE) start(); else window.addEventListener('three-ready', start, { once: true });
  return () => { dead = true; window.removeEventListener('three-ready', start); cleanup(); };

  function build(THREE) {
    const BROWN = '#24150F', FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
    const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
    const trunc = (s, n) => (s.length > n ? s.slice(0, n) + '…' : s);
    const mulberry = a => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
    const rnd = mulberry(20261008), GA = Math.PI * (3 - Math.sqrt(5));
    const V = (x, y, z) => new THREE.Vector3(x, y, z);
    const nrm = v => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
    const crs = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    const easeIO = x => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
    const easeOut = x => 1 - Math.pow(1 - clamp(x, 0, 1), 3);

    // ---- 렌더러, 장면 ----
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, premultipliedAlpha: true, powerPreference: 'high-performance' }); }
    catch (e) { const p = document.createElement('p'); p.className = 'empty-note'; p.textContent = '이 환경에서는 WebGL 을 쓸 수 없습니다'; main.appendChild(p); return () => p.remove(); }
    renderer.setClearColor(0x000000, 0); renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.1;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    const cv = renderer.domElement;
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;cursor:grab;touch-action:none';
    main.style.position = 'relative';
    const mesh = window.G3D && window.G3D.mesh ? window.G3D.mesh(main, 0.8) : null;
    main.appendChild(cv);
    const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(40, 1, 0.05, 40), group = new THREE.Group();
    scene.add(group);
    scene.add(new THREE.HemisphereLight(0xFFFFFF, 0x9A8878, 1.5));
    const key = new THREE.DirectionalLight(0xFFE6CC, 3.2); key.position.set(-3, 4, 4); scene.add(key);
    const fill = new THREE.DirectionalLight(0xCFE0EC, 0.8); fill.position.set(4, 0.5, 2.5); scene.add(fill);
    const front = new THREE.DirectionalLight(0xFFFFFF, 1.4); front.position.set(0.5, 1, 6); scene.add(front);
    const rim = new THREE.DirectionalLight(0xE8F0E8, 2.2); rim.position.set(1.5, 2.5, -4); scene.add(rim);
    const disp = []; const own = o => { disp.push(o); return o; };
    const U = { uD: { value: 3.4 }, uTime: { value: 0 } };
    // 공통 재질 손질: 개별 투명도(aDim), 멀리 있는 것 옅게, 줄기는 바람에 흔들림
    const patch = (mat, sway) => {
      mat.onBeforeCompile = sh => {
        sh.uniforms.uD = U.uD; sh.uniforms.uTime = U.uTime;
        sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nattribute float aDim;\nvarying float vDim;' + (sway ? '\nattribute float aT, aPh; uniform float uTime;' : ''))
          .replace('#include <begin_vertex>', '#include <begin_vertex>\nvDim = aDim;' + (sway ? '\ntransformed += vec3(sin(uTime*0.9+aPh), sin(uTime*0.7+aPh*1.7+1.0), sin(uTime*0.8+aPh*2.3+2.0)) * 0.018 * aT * aT;' : ''));
        sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vDim; uniform float uD;')
          .replace('#include <dithering_fragment>', '#include <dithering_fragment>\n gl_FragColor.a *= vDim * mix(1.0, 0.3, smoothstep(uD - 0.4, uD + 1.1, length(vViewPosition)));');
      };
      mat.transparent = true; return own(mat);
    };

    // ---- 데이터: 업무 하나 = 꽃 하나, 분야 = 같은 방향으로 모인 묶음 ----
    const themeIx = {}; data.themes.forEach((t, i) => { themeIx[t.id] = i; });
    const kindKeys = Object.keys(data.kinds || {});
    const tasks = data.tasks.slice().sort((a, b) => (themeIx[a.theme] ?? 99) - (themeIx[b.theme] ?? 99) || b.mins - a.mins);
    const N = tasks.length, maxMins = Math.max(1, ...tasks.map(t => t.mins || 0));
    const PAL = ['#FFFFFF', '#E6F3D2', '#CDE8A6'], CEN = ['#9BCB6A', '#86BB55', '#B2D985', '#A3C47A', '#8FC070'];
    const itemN = t => Object.keys(t.items || {}).reduce((s, k) => s + (t.items[k] || []).length, 0);
    const flowers = tasks.map((t, i) => {
      const y = 1 - 2 * (i + 0.5) / N, r = Math.sqrt(1 - y * y), a = i * GA, c = [r * Math.cos(a), y, r * Math.sin(a)];
      const pet = t.sessions.map(s => ({ cls: 0, wt: 0.8 + 0.4 * Math.min(1, Math.sqrt((s.active || 0) / 45)), label: `${s.when} ${s.active}분` }));
      for (const k of Object.keys(t.items || {})) (t.items[k] || []).forEach(nm => pet.push({ cls: 1, wt: 0.9, label: String(nm) }));
      const n = pet.length, L = Math.min(0.19, 0.07 + 0.0125 * Math.sqrt(n)), nR = Math.min(4, Math.max(1, Math.ceil(n / 18))), rc = L * (0.3 + 0.25 * Math.sqrt((t.mins || 0) / maxMins)), ti = themeIx[t.theme] ?? 0;
      pet.forEach((p, idx) => { p.ring = idx % nR; const j = Math.floor(idx / nR), cnt = Math.ceil((n - p.ring) / nR); p.th = p.ring * GA * 0.5 + j / cnt * 6.2832 + (rnd() - 0.5) * 0.12; p.len = L * p.wt * (1 - 0.2 * p.ring) * (0.88 + 0.24 * rnd()); p.j = j; p.tilt = (rnd() - 0.5) * 0.22; p.twist = (rnd() - 0.5) * 0.35; p.wd = 0.78 + 0.22 * rnd(); });
      return { t, c, pet, n, L, nR, rc, ti, ph: rnd() * 6.28, dim: 1, hs: 1, delay: 0.35 + 0.045 * i, cen: CEN[ti % CEN.length], sx: 0, sy: 0, rr: 10, hw: V(0, 0, 0), ax: null, e1: null, e2: null, p0: 0 };
    });
    // 분야 묶음 방향
    const hubs = data.themes.map(th => {
      const fs = flowers.filter(f => f.t.theme === th.id); if (!fs.length) return null;
      const m = fs.reduce((s, f) => [s[0] + f.c[0], s[1] + f.c[1], s[2] + f.c[2]], [0, 0, 0]);
      return { th, dir: nrm(m), fs };
    }).filter(Boolean);

    // ---- 줄기: 숨은 중심에서 묶음으로 나와 휘어지며 바깥으로, 끝에 꽃 ----
    const stemMat = patch(new THREE.MeshStandardMaterial({ color: '#8A7048', roughness: 0.85, vertexColors: true }), true), stems = [];
    hubs.forEach(hb => {
      const d = hb.dir;
      hb.fs.forEach(f => {
        const c = f.c, sw = nrm(crs(d, c)), sgn = 0.1 + 0.08 * rnd();
        const k1 = 0.34, pts = [V(d[0] * 0.03, d[1] * 0.03, d[2] * 0.03),
          V(c[0] * k1 + d[0] * 0.1 + sw[0] * sgn * 0.4, c[1] * k1 + d[1] * 0.1 + sw[1] * sgn * 0.4, c[2] * k1 + d[2] * 0.1 + sw[2] * sgn * 0.4),
          V(c[0] * 0.72 + d[0] * 0.05 + sw[0] * sgn, c[1] * 0.72 + d[1] * 0.05 + sw[1] * sgn, c[2] * 0.72 + d[2] * 0.05 + sw[2] * sgn),
          V(c[0] * 0.985, c[1] * 0.985, c[2] * 0.985)];
        const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal'), S = 44, RAD = 6, geo = new THREE.TubeGeometry(curve, S, 1, RAD, false), p = geo.attributes.position, nv = (S + 1) * (RAD + 1);
        const aT = new Float32Array(nv), aPh = new Float32Array(nv).fill(f.ph), aDim = new Float32Array(nv).fill(1), col = new Float32Array(nv * 3), cc = new THREE.Vector3(), vv = new THREE.Vector3();
        for (let i = 0; i <= S; i++) {
          const t = i / S, rad = 0.0032 + 0.0075 * Math.pow(1 - t, 1.1); curve.getPointAt(t, cc);
          for (let j = 0; j <= RAD; j++) { const k = i * (RAD + 1) + j; vv.fromBufferAttribute(p, k).sub(cc).normalize().multiplyScalar(rad).add(cc); p.setXYZ(k, vv.x, vv.y, vv.z); aT[k] = t; const g = 0.75 + 0.25 * t; col.set([0.5 * (1 - 0.25 * t) * g, 0.46 * g + 0.1 * t, 0.3 * g], k * 3); }
        }
        geo.setAttribute('aT', new THREE.BufferAttribute(aT, 1)); geo.setAttribute('aPh', new THREE.BufferAttribute(aPh, 1)); geo.setAttribute('aDim', new THREE.BufferAttribute(aDim, 1)); geo.setAttribute('color', new THREE.BufferAttribute(col, 3)); geo.computeVertexNormals();
        const m = new THREE.Mesh(own(geo), stemMat); m.frustumCulled = false; group.add(m); f.stem = m; f.stemDim = 1;
        const tg = curve.getTangentAt(1), ax = nrm([c[0] * 0.6 + tg.x * 0.4, c[1] * 0.6 + tg.y * 0.4, c[2] * 0.6 + tg.z * 0.4]);
        f.ax = ax; f.e1 = nrm(crs(ax, Math.abs(ax[1]) > 0.95 ? [1, 0, 0] : [0, 1, 0])); f.e2 = crs(ax, f.e1);
      });
    });

    // ---- 꽃잎: 깊이 휘어진 물방울 모양 하나를 공유하고, 꽃잎마다 위치, 방향, 길이, 색만 다르게(인스턴스) ----
    // 잎맥 무늬: 아래에서 부채처럼 퍼지는 가는 선(은은한 범프와 색)
    const vc = document.createElement('canvas'); vc.width = 128; vc.height = 256; { const g = vc.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, 128, 256);
      for (let k = -9; k <= 9; k++) { const a = k / 9; g.strokeStyle = `rgba(120,165,95,${0.2 - 0.1 * Math.abs(a)})`; g.lineWidth = k === 0 ? 1.6 : 0.9; g.beginPath(); g.moveTo(64, 256); g.bezierCurveTo(64 + a * 14, 190, 64 + a * 48, 90, 64 + a * 56 * (0.55 + 0.1 * Math.abs(a)), 14); g.stroke(); } }
    const vtex = own(new THREE.CanvasTexture(vc)); vtex.colorSpace = THREE.SRGBColorSpace; vtex.anisotropy = 4;
    const pg = own(new THREE.PlaneGeometry(1, 1, 12, 26)), pp = pg.attributes.position, pcol = new Float32Array(pp.count * 3);
    for (let i = 0; i < pp.count; i++) {
      const u = pp.getY(i) + 0.5, vx = pp.getX(i) * 2, half = 0.31 * Math.pow(Math.max(0, Math.sin(Math.PI * Math.pow(u, 0.7))), 0.62) * (1 - 0.12 * u * u), x = vx * half;
      const ruf = 0.022 * Math.pow(Math.abs(vx), 2.4) * Math.pow(u, 1.4) * Math.sin(u * 10 + vx * 2.4 + 1.3), tipUp = 0.12 * Math.pow(Math.abs(vx), 3) * u;
      pp.setXYZ(i, x, u + 0.04 * Math.abs(vx) * u, 0.3 * u * u + 1.35 * x * x + ruf + tipUp);
      pcol.set([0.9 + 0.1 * u, 0.96 + 0.04 * u, 0.82 + 0.18 * u], i * 3);   // 아래는 연한 초록, 끝은 흰색
    }
    pg.setAttribute('color', new THREE.BufferAttribute(pcol, 3)); pg.computeVertexNormals();
    let nPet = 0; flowers.forEach(f => { f.p0 = nPet; nPet += f.n; });
    const petMat = patch(new THREE.MeshPhysicalMaterial({ vertexColors: true, side: THREE.DoubleSide, roughness: 0.45, sheen: 0.6, sheenRoughness: 0.4, sheenColor: new THREE.Color('#FFFFFF'), map: vtex, bumpMap: vtex, bumpScale: 0.15, emissive: new THREE.Color('#BFE0A0'), emissiveIntensity: 0.16, clearcoat: 0.25, clearcoatRoughness: 0.5 }));
    const petM = new THREE.InstancedMesh(pg, petMat, Math.max(1, nPet)); petM.frustumCulled = false; petM.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    const petDim = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, nPet)).fill(1), 1); pg.setAttribute('aDim', petDim); petDim.setUsage(THREE.DynamicDrawUsage);
    petM.instanceMatrix.array.fill(0);
    const cc0 = new THREE.Color();
    flowers.forEach(f => f.pet.forEach((p, i) => {
      cc0.set(PAL[(p.ring + f.ti + p.cls) % 3]); if (p.j & 1) cc0.multiplyScalar(0.93); petM.setColorAt(f.p0 + i, cc0);
    }));
    petM.instanceColor.needsUpdate = true; group.add(petM);
    // 중심 원판(돔)과 수술 점
    const domeG = own(new THREE.SphereGeometry(1, 22, 10, 0, Math.PI * 2, 0, Math.PI / 2)); domeG.rotateX(Math.PI / 2);
    const nF = flowers.length, ctrMat = patch(new THREE.MeshStandardMaterial({ roughness: 0.6, emissive: new THREE.Color('#9BCB6A'), emissiveIntensity: 0.38 }));
    const domeM = new THREE.InstancedMesh(domeG, ctrMat, Math.max(1, nF)); domeM.frustumCulled = false; domeM.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    const domeDim = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, nF)).fill(1), 1); domeG.setAttribute('aDim', domeDim);
    domeM.instanceMatrix.array.fill(0); flowers.forEach((f, i) => domeM.setColorAt(i, cc0.set(f.cen))); domeM.instanceColor.needsUpdate = true; group.add(domeM);
    const NS = 14, stG = own(new THREE.IcosahedronGeometry(1, 1)), stMat = patch(new THREE.MeshStandardMaterial({ color: '#F6FBE8', roughness: 0.5, emissive: new THREE.Color('#F6FBE8'), emissiveIntensity: 0.25 }));
    const stM = new THREE.InstancedMesh(stG, stMat, Math.max(1, nF * NS)); stM.frustumCulled = false; stM.instanceMatrix.setUsage(THREE.DynamicDrawUsage); stM.instanceMatrix.array.fill(0);
    const stDim = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, nF * NS)).fill(1), 1); stG.setAttribute('aDim', stDim); group.add(stM);
    const stam = []; for (let k = 0; k < NS; k++) { const q = Math.sqrt((k + 0.5) / NS) * 0.82, th = k * GA; stam.push([q * Math.cos(th), q * Math.sin(th), Math.sqrt(Math.max(0, 1 - q * q)), 0.35 + 0.65 * rnd()]); }
    const stLine = new THREE.LineSegments(own(new THREE.BufferGeometry()), own(new THREE.LineBasicMaterial({ color: '#F6FBE8', transparent: true, opacity: 0.7, depthWrite: false })));
    const stLP = new Float32Array(Math.max(1, nF * NS) * 6); stLine.geometry.setAttribute('position', new THREE.BufferAttribute(stLP, 3)); stLine.frustumCulled = false; group.add(stLine);
    // 은은한 빛 번짐: 꽃마다 더하기 합성 스프라이트
    const gc = document.createElement('canvas'); gc.width = gc.height = 128; { const g = gc.getContext('2d'), gr = g.createRadialGradient(64, 64, 0, 64, 64, 64); gr.addColorStop(0, 'rgba(255,255,255,0.9)'); gr.addColorStop(0.35, 'rgba(230,243,210,0.35)'); gr.addColorStop(1, 'rgba(230,243,210,0)'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128); }
    const gtex = own(new THREE.CanvasTexture(gc));
    flowers.forEach(f => { f.halo = new THREE.Sprite(own(new THREE.SpriteMaterial({ map: gtex, color: '#E6F3D2', transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 }))); f.halo.renderOrder = 3; group.add(f.halo); });

    // ---- 화면 위 단추와 라벨 ----
    const glass = 'position:absolute;z-index:5;font:600 12px ' + FONT + ';color:#24150f;background:rgba(255,255,255,0.72);border:0;border-radius:999px;padding:6px 13px;cursor:pointer;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);box-shadow:0 4px 14px rgba(36,21,15,0.12);display:none;white-space:nowrap';
    const mkBtn = (txt, fn) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = txt; b.style.cssText = glass; b.addEventListener('click', e => { e.stopPropagation(); fn(); }); main.appendChild(b); return b; };
    const labs = [], mctx = document.createElement('canvas').getContext('2d'); let used = 0;
    const pill = (txt, x, y, al, o = {}) => {   // 갈색 반투명 알약 (테두리 없음). o.right: 오른쪽 끝 기준
      let el = labs[used++];
      if (!el) { el = document.createElement('div'); main.appendChild(el); labs.push(el); el._k = ''; }
      if (el._k !== (o.sz || 11)) { el._k = o.sz || 11; el.style.cssText = `position:absolute;left:0;top:0;z-index:4;pointer-events:none;white-space:nowrap;font:${o.w || 500} ${o.sz || 11}px ${FONT};color:#fff;background:rgba(36,21,15,0.78);border-radius:999px;padding:3px 6px;will-change:transform`; }
      if (el._t !== txt) { el._t = txt; el.textContent = txt; }
      el.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) translate(${o.right ? '-100%' : o.mid ? '-50%' : '0'},-50%)`; el.style.opacity = al; el.style.display = '';
    };
    const pw = (txt, sz, w) => { mctx.font = `${w} ${sz}px ${FONT}`; return mctx.measureText(txt).width + 12; };

    // ---- 시점, 입력 ----
    let W = 1, H = 1, base = 3.4;
    const view = { yaw: 0.5, pitch: -0.25, dist: 3.4, dragging: false, hold: false };
    let focus = null, anim = null, hover = null, drag = null, moved = 0, mouse = null, vy = 0.0012, vp = 0, raf = 0, last = 0;
    const size = () => { const r = main.getBoundingClientRect(); W = Math.max(1, r.width); H = Math.max(1, r.height); renderer.setSize(W, H, false); camera.aspect = W / H; camera.updateProjectionMatrix(); const nb = 3.4 * Math.max(1, 1.05 * H / W); if (!focus) { view.dist = nb * (view.dist / base); } base = nb; mesh?.size(W, H); };
    const ro = new ResizeObserver(size); ro.observe(main); base = 3.4; size();
    const pos = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const wrap = a => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };
    const go = to => { anim = { t0: -1, from: { yaw: view.yaw, pitch: view.pitch, dist: view.dist }, to }; };
    const btn = mkBtn('업무 상세 →', () => focus && ui.open(focus.t.id)), back = mkBtn('← 전체', () => leave());
    back.style.top = '18px'; back.style.left = '24px';
    function enter(f) {
      focus = f; view.hold = true;
      const c = f.c, hh = Math.hypot(c[0], c[2]), yaw = Math.atan2(-c[0], c[2]), pitch = clamp(Math.atan2(c[1], hh), -1.4, 1.4);
      go({ yaw: view.yaw + wrap(yaw - view.yaw), pitch, dist: clamp(1 + f.L * 7.3, 1.8, 3.2) }); btn.style.display = back.style.display = 'block';
    }
    function leave() { if (!focus) return; focus = null; view.hold = false; go({ yaw: view.yaw, pitch: view.pitch, dist: base }); btn.style.display = back.style.display = 'none'; }
    const onKey = e => { if (e.key === 'Escape') leave(); };
    window.addEventListener('keydown', onKey);
    const pick = (x, y) => { let b = null, bd = 1e9; for (const f of flowers) { if (!f.front) continue; const d = Math.hypot(x - f.sx, y - f.sy) / f.rr; if (d < 1 && d < bd) { bd = d; b = f; } } return b; };
    cv.addEventListener('pointerdown', e => { drag = pos(e); moved = 0; view.dragging = true; cv.setPointerCapture(e.pointerId); });
    cv.addEventListener('pointermove', e => { const p = pos(e); mouse = p; if (!drag) return; const dx = p.x - drag.x, dy = p.y - drag.y; moved += Math.abs(dx) + Math.abs(dy); vy = dx * 0.006; vp = dy * 0.006; view.yaw += vy; view.pitch = clamp(view.pitch + vp, -1.4, 1.4); drag = p; });
    const up = e => { if (drag && moved < 4) { const p = pos(e), f = pick(p.x, p.y); if (f) { if (f !== focus) enter(f); } else leave(); } drag = null; view.dragging = false; };
    cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
    cv.addEventListener('pointerleave', () => { if (!drag) mouse = null; });
    cv.addEventListener('wheel', e => { e.preventDefault(); view.dist = clamp(view.dist * Math.exp(e.deltaY * 0.0015), 1.6, 6); if (anim) anim.to.dist = view.dist; }, { passive: false });

    // ---- 매 프레임 ----
    const startT = performance.now(), tw = V(0, 0, 0), cam = V(0, 0, 0);
    const swayAt = (ph, t, o) => { o[0] = Math.sin(t * 0.9 + ph) * 0.018; o[1] = Math.sin(t * 0.7 + ph * 1.7 + 1) * 0.018; o[2] = Math.sin(t * 0.8 + ph * 2.3 + 2) * 0.018; };
    const sw3 = [0, 0, 0], pm = petM.instanceMatrix.array, dm = domeM.instanceMatrix.array, sm = stM.instanceMatrix.array, pDimA = petDim.array, dDimA = domeDim.array, sDimA = stDim.array;
    const proj = (x, y, z, o) => { tw.set(x, y, z).applyMatrix4(group.matrixWorld).project(camera); o.x = (tw.x * 0.5 + 0.5) * W; o.y = (-tw.y * 0.5 + 0.5) * H; o.z = tw.z; return o; };
    const sp = { x: 0, y: 0, z: 0 }, tipS = new Array(0);
    const frame = t => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (t - (last || t)) / 1000) * 60 || 1; last = t;
      const age = (performance.now() - startT) / 1000, ts = performance.now() / 1000; U.uTime.value = ts;
      if (anim) {
        if (anim.t0 < 0) anim.t0 = t; const k = clamp((t - anim.t0) / 600, 0, 1), e = easeIO(k);
        if (!view.dragging) { view.yaw = anim.from.yaw + (anim.to.yaw - anim.from.yaw) * e; view.pitch = anim.from.pitch + (anim.to.pitch - anim.from.pitch) * e; }
        view.dist = anim.from.dist + (anim.to.dist - anim.from.dist) * e; if (k >= 1) anim = null;
      } else if (!drag && !view.hold) { vy += (0.0012 - vy) * 0.04 * dt; vp *= Math.pow(0.92, dt); view.yaw += vy * dt; view.pitch = clamp(view.pitch + vp * dt, -1.4, 1.4); }
      camera.position.set(0, 0, view.dist); U.uD.value = view.dist; group.rotation.set(view.pitch, view.yaw, 0, 'XYZ'); group.updateMatrixWorld(true); camera.updateMatrixWorld();
      // 꽃마다: 줄기 끝 위치(바람), 꽃잎 펼침, 행렬
      for (let fi = 0; fi < flowers.length; fi++) {
        const f = flowers[fi], hot = hover === f; f.hs += ((hot ? 1.1 : 1) - f.hs) * 0.2 * dt;
        const tgt = focus && f !== focus ? 0.13 : 1; f.dim += (tgt - f.dim) * 0.15 * dt;
        swayAt(f.ph, ts, sw3); const c = f.c, ax = f.ax, e1 = f.e1, e2 = f.e2, L = f.L * f.hs;
        const hx = c[0] * 0.985 + sw3[0] + ax[0] * 0.012, hy = c[1] * 0.985 + sw3[1] + ax[1] * 0.012, hz = c[2] * 0.985 + sw3[2] + ax[2] * 0.012;
        f.hw.set(hx, hy, hz);
        const op = easeOut((age - f.delay) / 1.4), rcS = f.rc * f.hs * (0.25 + 0.75 * op);
        // 중심 원판(돔)
        let o = fi * 16;
        dm[o] = e1[0] * rcS; dm[o + 1] = e1[1] * rcS; dm[o + 2] = e1[2] * rcS; dm[o + 3] = 0; dm[o + 4] = e2[0] * rcS; dm[o + 5] = e2[1] * rcS; dm[o + 6] = e2[2] * rcS; dm[o + 7] = 0;
        dm[o + 8] = ax[0] * rcS * 0.6; dm[o + 9] = ax[1] * rcS * 0.6; dm[o + 10] = ax[2] * rcS * 0.6; dm[o + 11] = 0; dm[o + 12] = hx; dm[o + 13] = hy; dm[o + 14] = hz; dm[o + 15] = 1; dDimA[fi] = f.dim;
        for (let k = 0; k < NS; k++) {
          const q = stam[k], o2 = (fi * NS + k) * 16, s = rcS * 0.085, px = (e1[0] * q[0] + e2[0] * q[1] + ax[0] * q[2] * 0.6) * rcS, py = (e1[1] * q[0] + e2[1] * q[1] + ax[1] * q[2] * 0.6) * rcS, pz = (e1[2] * q[0] + e2[2] * q[1] + ax[2] * q[2] * 0.6) * rcS;
          sm[o2] = s; sm[o2 + 1] = 0; sm[o2 + 2] = 0; sm[o2 + 3] = 0; sm[o2 + 4] = 0; sm[o2 + 5] = s; sm[o2 + 6] = 0; sm[o2 + 7] = 0; sm[o2 + 8] = 0; sm[o2 + 9] = 0; sm[o2 + 10] = s; sm[o2 + 11] = 0;
          const lift = rcS * (0.1 + 0.9 * q[3] * 0.6), l6 = (fi * NS + k) * 6;
          sm[o2 + 12] = hx + px + ax[0] * lift; sm[o2 + 13] = hy + py + ax[1] * lift; sm[o2 + 14] = hz + pz + ax[2] * lift; sm[o2 + 15] = 1; sDimA[fi * NS + k] = f.dim;
          stLP[l6] = hx + px; stLP[l6 + 1] = hy + py; stLP[l6 + 2] = hz + pz; stLP[l6 + 3] = sm[o2 + 12]; stLP[l6 + 4] = sm[o2 + 13]; stLP[l6 + 5] = sm[o2 + 14];
        }
        // 꽃잎
        const r0 = f.rc * 0.78 * f.hs;
        for (let i = 0; i < f.pet.length; i++) {
          const p = f.pet[i], idx = f.p0 + i, po = easeOut((age - f.delay - 0.03 * (i % 7) - 0.04 * p.ring) / 1.1), alo = [0.3, 0.52, 0.78, 1.04][p.ring] ?? 0.9, alpha = 1.35 + (alo - 1.35) * po, ln = p.len * f.hs * (0.35 + 0.65 * po);
          const ct = Math.cos(p.th), st = Math.sin(p.th), ca = Math.cos(alpha + p.tilt), sa = Math.sin(alpha + p.tilt), tc = Math.cos(p.twist), ts2 = Math.sin(p.twist);
          // 꽃 좌표(x:e1, y:e2, z:ax)의 방향 벡터 -> 세계 좌표
          const W3 = (x, y, z, out, off) => { out[off] = e1[0] * x + e2[0] * y + ax[0] * z; out[off + 1] = e1[1] * x + e2[1] * y + ax[1] * z; out[off + 2] = e1[2] * x + e2[2] * y + ax[2] * z; };
          const m = pm, mo = idx * 16;
          W3((-st * tc + ct * sa * ts2) * ln * p.wd, (ct * tc + st * sa * ts2) * ln * p.wd, -ca * ts2 * ln * p.wd, m, mo); m[mo + 3] = 0;   // 폭 방향(살짝 비틀림)
          W3(ct * ca * ln, st * ca * ln, sa * ln, m, mo + 4); m[mo + 7] = 0;                // 길이 방향
          W3((-ct * sa * tc - st * ts2) * ln, (-st * sa * tc + ct * ts2) * ln, ca * tc * ln, m, mo + 8); m[mo + 11] = 0;   // 오목한 쪽
          W3(ct * r0, st * r0, 0.0, m, mo + 12); m[mo + 12] += hx; m[mo + 13] += hy; m[mo + 14] += hz; m[mo + 15] = 1;
          pDimA[idx] = f.dim;
        }
        { const hl = f.halo, fz = clamp(1 - (tw.set(hx, hy, hz).applyMatrix4(group.matrixWorld).z + 0.6) / 2.4, 0.15, 1); hl.position.set(hx + ax[0] * 0.01, hy + ax[1] * 0.01, hz + ax[2] * 0.01); const hsz = f.L * 6.2 * (0.4 + 0.6 * op); hl.scale.set(hsz, hsz, 1); hl.material.opacity = 0.5 * f.dim * fz * op; }
        // 줄기 투명도
        if (Math.abs(f.dim - f.stemDim) > 0.004) { const a = f.stem.geometry.attributes.aDim; a.array.fill(f.dim); a.needsUpdate = true; f.stemDim = f.dim; }
        // 화면 위치와 원판
        proj(hx, hy, hz, sp); f.sx = sp.x; f.sy = sp.y; f.wz = sp.z;
        const wz = tw.set(hx, hy, hz).applyMatrix4(group.matrixWorld).z; f.front = wz > -0.1 * 1 && f.ax != null;
        tw.set(hx, hy, hz).applyMatrix4(group.matrixWorld); tw.x += f.L * 1.15; tw.project(camera); f.rr = Math.abs((tw.x * 0.5 + 0.5) * W - f.sx) + 8;
      }
      stLine.geometry.attributes.position.needsUpdate = true;
      petM.instanceMatrix.needsUpdate = domeM.instanceMatrix.needsUpdate = stM.instanceMatrix.needsUpdate = true; petDim.needsUpdate = domeDim.needsUpdate = stDim.needsUpdate = true;
      hover = mouse && !drag ? pick(mouse.x, mouse.y) : null;
      cv.style.cursor = hover ? 'pointer' : drag ? 'grabbing' : 'grab';
      mesh?.draw(t); renderer.render(scene, camera);

      // 라벨
      used = 0;
      if (focus) {
        const f = focus, boxes = [];
        const bw = btn.offsetWidth || 90; btn.style.left = Math.max(8, Math.min(W - bw - 8, f.sx + f.rr + 14)) + 'px'; btn.style.top = Math.max(8, Math.min(H - 40, f.sy - 14)) + 'px';
        const tw2 = pw(trunc(f.t.title, 30), 12, 600), ty = Math.max(16, f.sy - f.rr - 18); pill(trunc(f.t.title, 30), clamp(f.sx, tw2 / 2 + 6, W - tw2 / 2 - 6), ty, 1, { mid: true, sz: 12, w: 600 }); boxes.push([f.sx - tw2 / 2, ty - 10, tw2, 20]);
        const items = [];
        for (let i = 0; i < f.pet.length; i++) {
          const mo = (f.p0 + i) * 16, tx = pm[mo + 12] + pm[mo + 4], ty2 = pm[mo + 13] + pm[mo + 5], tz = pm[mo + 14] + pm[mo + 6];
          proj(tx, ty2, tz, sp); items.push({ i, x: sp.x, y: sp.y, z: sp.z });
        }
        items.sort((a, b) => a.z - b.z);
        for (const it of items) {
          if (it.x < 6 || it.x > W - 6 || it.y < 6 || it.y > H - 6) continue;
          const dx = it.x - f.sx, dy = it.y - f.sy, l = Math.hypot(dx, dy) || 1, txt = trunc(f.pet[it.i].label, 20), w = pw(txt, 11, 500), right = dx < 0, x = it.x + dx / l * 8, y = it.y + dy / l * 5, x0 = right ? x - w : x;
          if (boxes.some(q => x0 < q[0] + q[2] + 2 && x0 + w > q[0] - 2 && y - 10 < q[1] + q[3] + 1 && y + 10 > q[1] - 1)) continue;
          boxes.push([x0, y - 10, w, 20]); pill(txt, x, y, 1, { right });
        }
      } else {
        for (const hb of hubs) {
          proj(hb.dir[0] * 1.2, hb.dir[1] * 1.2, hb.dir[2] * 1.2, sp); const wz = tw.set(hb.dir[0], hb.dir[1], hb.dir[2]).applyMatrix4(group.matrixWorld).z; if (wz < 0.05) continue;
          const w = pw(hb.th.name, 11, 600); pill(hb.th.name, clamp(sp.x, w / 2 + 6, W - w / 2 - 6), clamp(sp.y, 14, H - 14), 0.92, { mid: true, w: 600 });
        }
        if (hover) { const w = pw(trunc(hover.t.title, 30), 12, 600); pill(trunc(hover.t.title, 30), clamp(hover.sx + hover.rr + 6, 6, W - w - 6), Math.max(14, hover.sy - 14), 1, { sz: 12, w: 600 }); }
      }
      for (let i = used; i < labs.length; i++) labs[i].style.display = 'none';
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf); ro.disconnect(); window.removeEventListener('keydown', onKey);
      disp.forEach(o => o.dispose()); petM.dispose(); domeM.dispose(); stM.dispose();
      renderer.dispose(); renderer.forceContextLoss(); cv.remove(); mesh?.destroy(); labs.forEach(e => e.remove()); btn.remove(); back.remove();
    };
  }
};

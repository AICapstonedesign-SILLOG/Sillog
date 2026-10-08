/* 개미집 (three.js): 땅 위 풀밭과 화면 가득 흙 단면. 단면에 파인 굴이 완성된 채로 보인다.
   위쪽 땅의 작은 입구가 "나", 거기서 내려가는 굴 하나가 분야, 굴에서 갈라진 방 하나가 업무(방 크기 = 쓴 시간),
   방 바닥의 작은 알이 세션과 자료. 개미가 굴을 따라 방으로 오간다.
   굴은 스텐실로 단면에 구멍을 내고, 구멍 안쪽 뒷벽(BackSide)을 그려서 속이 빈 굴로 보이게 한다. */
window.V3D = window.V3D || {};
window.V3D.antnest = function (main, data, ui) {
  let dead = false, cleanup = () => {};
  const start = () => { if (!dead) cleanup = build(window.THREE); };
  if (window.THREE) start(); else window.addEventListener('three-ready', start, { once: true });
  return () => { dead = true; window.removeEventListener('three-ready', start); cleanup(); };

  function build(THREE) {
    const BROWN = '#24150F', FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
    const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
    const hash = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
    const rng = seed => () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    const V = (x, y, z) => new THREE.Vector3(x, y, z);
    const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

    const tasks = data.tasks.filter(t => data.themes.some(h => h.id === t.theme));
    const themes = data.themes.filter(th => tasks.some(t => t.theme === th.id)), NT = themes.length;
    const BX = 2.1, BY = 0.85, BZ = 0.3;      // 굴이 퍼지는 범위(반 크기)
    const SURF = BY, FZ = 0.52, WW = 44, DEP = 1.5;   // 땅 높이, 단면 앞 z, 폭, 땅 깊이

    // ---- 렌더러, 장면 ----
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, stencil: true, premultipliedAlpha: true, powerPreference: 'high-performance' }); }
    catch (e) { const p = document.createElement('p'); p.className = 'empty-note'; p.textContent = '이 환경에서는 WebGL 을 쓸 수 없습니다'; main.appendChild(p); return () => p.remove(); }
    renderer.setClearColor(0x000000, 0); renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.12;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    const cv = renderer.domElement;
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;cursor:grab;touch-action:none';
    main.style.position = 'relative';
    main.appendChild(cv);
    const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(46, 1, 0.05, 80), group = new THREE.Group(), nest = new THREE.Group();
    group.add(nest); scene.add(group);
    scene.add(new THREE.HemisphereLight(0xFFF1E0, 0x5A4234, 1.05));
    const key = new THREE.DirectionalLight(0xFFE1BE, 2.7); key.position.set(-3, 4.5, 4); scene.add(key);
    const fill = new THREE.DirectionalLight(0xD8E4EE, 0.5); fill.position.set(3.5, 0.5, 2.5); scene.add(fill);
    const rim = new THREE.DirectionalLight(0xFFEBD2, 1.0); rim.position.set(1.5, 2.5, -3.5); scene.add(rim);
    const disp = []; const own = o => { disp.push(o); return o; };
    const rnd = rng(7421);
    const hN = x => 0.016 * Math.sin(x * 7.3 + 1.2) + 0.011 * Math.sin(x * 19.1 + 0.4) + 0.006 * Math.sin(x * 47 + 2.1);   // 땅 앞 가장자리 높낮이
    const groundY = (x, z) => SURF + hN(x) * Math.pow(clamp((z - (FZ - DEP)) / DEP, 0, 1), 3) + 0.012 * Math.sin(x * 2.3 + z * 3.1) * (1 - clamp((z - (FZ - DEP)) / DEP, 0, 1));

    // ---- 무늬(캔버스) ----
    const mkCanvas = n => { const c = document.createElement('canvas'); c.width = c.height = n; return c; };
    const tileDots = (x, n, cnt, cols, rmax) => { for (let i = 0; i < cnt; i++) { const px = rnd() * n, py = rnd() * n, r = 0.4 + rnd() * rnd() * rmax; x.fillStyle = cols[Math.floor(rnd() * cols.length)] + (0.08 + 0.3 * rnd()).toFixed(2) + ')';
      for (const ox of [-n, 0, n]) for (const oy of [-n, 0, n]) { if (px + ox < -8 || px + ox > n + 8 || py + oy < -8 || py + oy > n + 8) continue; x.beginPath(); x.arc(px + ox, py + oy, r, 0, 6.2832); x.fill(); } } };
    const stone = (x, n, px, py, r, base) => {   // 박힌 작은 돌: 그림자, 몸통, 윗면 빛
      for (const ox of [-n, 0, n]) { const X = px + ox; if (X < -r * 2 || X > n + r * 2) continue;
        x.fillStyle = 'rgba(20,10,6,.32)'; x.beginPath(); x.ellipse(X + r * 0.18, py + r * 0.24, r * 1.12, r * 0.95, 0.3, 0, 6.2832); x.fill();
        const g = x.createRadialGradient(X - r * 0.35, py - r * 0.4, r * 0.1, X, py, r * 1.05); g.addColorStop(0, base[0]); g.addColorStop(0.6, base[1]); g.addColorStop(1, base[2]);
        x.fillStyle = g; x.beginPath(); x.ellipse(X, py, r * 1.1, r * 0.9, 0.3, 0, 6.2832); x.fill(); } };
    // 단면 흙: 층, 알갱이, 돌
    const SN = 1024, sc = mkCanvas(SN);
    { const x = sc.getContext('2d'), bands = [['#8D6C57', 0], ['#7C5C49', 0.12], ['#957560', 0.24], ['#6E4F3E', 0.4], ['#85654F', 0.55], ['#6A4B3B', 0.72], ['#7E5E4B', 0.88], ['#8D6C57', 1]];
      const gr = x.createLinearGradient(0, 0, 0, SN); bands.forEach(([c, p]) => gr.addColorStop(p, c)); x.fillStyle = gr; x.fillRect(0, 0, SN, SN);
      for (let i = 0; i < 160; i++) { const y = rnd() * SN, h = 1 + rnd() * 10, dark = rnd() < 0.55, ph = rnd() * 6, k = 1 + Math.floor(rnd() * 2); x.fillStyle = `rgba(${dark ? '36,21,15' : '236,210,180'},${0.03 + 0.07 * rnd()})`;
        x.beginPath(); x.moveTo(0, y); for (let q = 0; q <= 16; q++) x.lineTo(q * SN / 16, y + Math.sin(q / 16 * 6.2832 * k + ph) * 7); for (let q = 16; q >= 0; q--) x.lineTo(q * SN / 16, y + h + Math.sin(q / 16 * 6.2832 * k + ph) * 7); x.fill(); }
      tileDots(x, SN, 30000, ['rgba(30,18,12,', 'rgba(210,180,150,', 'rgba(150,115,90,'], 2.1);
      for (let i = 0; i < 70; i++) stone(x, SN, rnd() * SN, rnd() * SN, 2 + rnd() * rnd() * 7, rnd() < 0.5 ? ['#B8A590', '#8E7B68', '#5A4636'] : ['#9C8A78', '#6E5C4C', '#3E2F25']); }
    const mkTex = (c, rx, ry, srgb) => { const t = own(new THREE.CanvasTexture(c)); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(rx, ry); t.anisotropy = 8; if (srgb) t.colorSpace = THREE.SRGBColorSpace; return t; };
    const soilTex = mkTex(sc, 1, 1, true), soilBump = mkTex(sc, 1, 1, false);
    // 땅 위 표면: 부엽토, 이끼, 자갈
    const GN = 512, gc = mkCanvas(GN);
    { const x = gc.getContext('2d'); x.fillStyle = '#6B5240'; x.fillRect(0, 0, GN, GN);
      for (let i = 0; i < 30; i++) { const px = rnd() * GN, py = rnd() * GN, r = 20 + rnd() * 50; const g = x.createRadialGradient(px, py, 0, px, py, r); g.addColorStop(0, `rgba(${rnd() < 0.5 ? '98,102,60' : '48,30,22'},.28)`); g.addColorStop(1, 'rgba(0,0,0,0)'); x.fillStyle = g; x.fillRect(px - r, py - r, r * 2, r * 2); }
      tileDots(x, GN, 14000, ['rgba(36,21,15,', 'rgba(190,165,130,', 'rgba(104,112,64,', 'rgba(140,110,84,'], 2.2);
      for (let i = 0; i < 26; i++) stone(x, GN, rnd() * GN, rnd() * GN, 2 + rnd() * 4, ['#B3A28E', '#887665', '#4E3E32']); }
    const gTex = mkTex(gc, 1, 1, true), gBump = mkTex(gc, 1, 1, false);
    // 굴 안쪽 벽: 고운 알갱이와 결
    const tc = mkCanvas(256);
    { const x = tc.getContext('2d'); x.fillStyle = '#D6BC98'; x.fillRect(0, 0, 256, 256);
      for (let i = 0; i < 70; i++) { const px = rnd() * 256, w = 1 + rnd() * 5; x.fillStyle = `rgba(${rnd() < 0.6 ? '36,21,15' : '255,246,230'},${0.025 + 0.06 * rnd()})`; x.fillRect(px, 0, w, 256); x.fillRect(px - 256, 0, w, 256); }
      tileDots(x, 256, 4200, ['rgba(58,36,26,', 'rgba(255,244,224,'], 1.3); }
    const tex = mkTex(tc, 1, 1, true), bump = mkTex(tc, 1, 1, false);

    // ---- 단면과 땅 ----
    const stW = { colorWrite: false, depthWrite: false, depthTest: false, side: THREE.DoubleSide, stencilWrite: true, stencilRef: 1, stencilFunc: THREE.AlwaysStencilFunc, stencilFail: THREE.ReplaceStencilOp, stencilZFail: THREE.ReplaceStencilOp, stencilZPass: THREE.ReplaceStencilOp };
    const stR = { stencilWrite: true, stencilRef: 1, stencilFunc: THREE.NotEqualStencilFunc };
    const noise2 = (x, y) => Math.sin(x * 1.7 + Math.sin(y * 1.3) * 2) * 0.5 + Math.sin(x * 0.63 - y * 1.1 + 2) * 0.3 + Math.sin(y * 2.9 + x * 0.4) * 0.2;
    { // 앞 단면: 위쪽은 촘촘한 격자(표토 어둡게), 아래로 갈수록 성기게, 정점 색으로 큰 얼룩과 깊이 어둠
      const NX = 240, xs = [], ys = [0, 0.02, 0.045, 0.08, 0.12, 0.17, 0.23, 0.31, 0.42, 0.6, 0.9, 1.4, 2.2, 3.6, 6, 10, 16];
      for (let i = 0; i <= NX; i++) xs.push(-WW / 2 + WW * i / NX);
      const pos = [], uv = [], col = [], idx = [], TS = 3.6, c = new THREE.Color();
      ys.forEach((d, j) => xs.forEach(x => {
        pos.push(x, SURF - d + (j === 0 ? hN(x) : 0), FZ); uv.push(x / TS, -d / TS);
        const topsoil = 0.58 + 0.42 * sstep(0, 0.2, d), deepen = 1 - 0.42 * sstep(0.2, 7, d), mott = 1 + 0.13 * noise2(x * 0.9, d * 0.9) + 0.06 * noise2(x * 3.1, d * 3.7);
        c.setRGB(1, 1, 1).multiplyScalar(topsoil * deepen * mott); col.push(c.r, c.g * 0.98, c.b * 0.96);
      }));
      for (let j = 0; j < ys.length - 1; j++) for (let i = 0; i < NX; i++) { const a = j * (NX + 1) + i, b = a + NX + 1; idx.push(a, b, a + 1, b, b + 1, a + 1); }
      const g = own(new THREE.BufferGeometry()); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3)); g.setIndex(idx); g.computeVertexNormals();
      const face = new THREE.Mesh(g, own(new THREE.MeshStandardMaterial({ map: soilTex, bumpMap: soilBump, bumpScale: 2.4, vertexColors: true, roughness: 1, ...stR }))); face.renderOrder = 0; face.frustumCulled = false; nest.add(face); }
    { // 땅 윗면
      const NX = 240, NZ = 14, pos = [], uv = [], col = [], idx = [], TS = 2.4, c = new THREE.Color();
      for (let j = 0; j <= NZ; j++) for (let i = 0; i <= NX; i++) { const x = -WW / 2 + WW * i / NX, zz = FZ - DEP + DEP * j / NZ;
        pos.push(x, groundY(x, zz), zz); uv.push(x / TS, zz / TS); c.setRGB(1, 1, 1).multiplyScalar(0.8 + 0.2 * (j / NZ) + 0.1 * noise2(x * 1.3, zz * 1.7)); col.push(c.r, c.g, c.b); }
      for (let j = 0; j < NZ; j++) for (let i = 0; i < NX; i++) { const a = j * (NX + 1) + i, b = a + NX + 1; idx.push(a, a + 1, b, b, a + 1, b + 1); }
      const g = own(new THREE.BufferGeometry()); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3)); g.setIndex(idx); g.computeVertexNormals();
      const ground = new THREE.Mesh(g, own(new THREE.MeshStandardMaterial({ map: gTex, bumpMap: gBump, bumpScale: 2, vertexColors: true, roughness: 1, side: THREE.DoubleSide }))); ground.frustumCulled = false; nest.add(ground); }
    { // 풀잎, 자갈
      const gp = [], gcl = [], gi = [], pc = new THREE.Color(), cols = ['#7B8750', '#66723F', '#8E8A52', '#5A6638', '#8B7A48'];
      for (let i = 0; i < 1500; i++) {
        const x = (rnd() - 0.5) * 14 * (0.3 + rnd() * 0.7), zt = Math.pow(rnd(), 1.7), z = FZ - 0.02 - zt * (DEP - 0.15), y = groundY(x, z), h = 0.022 + 0.05 * rnd() * (0.5 + 0.5 * (1 - zt)), w = 0.003 + 0.0025 * rnd();
        const a = rnd() * 6.2832, lean = (rnd() - 0.2) * 0.05, lx = Math.cos(a) * lean, lz = Math.sin(a) * lean, px = -Math.sin(a) * w, pz = Math.cos(a) * w, o = gp.length / 3;
        gp.push(x - px, y - 0.004, z - pz, x + px, y - 0.004, z + pz, x + lx * 0.5 + px * 0.5, y + h * 0.55, z + lz * 0.5 + pz * 0.5, x + lx * 0.5 - px * 0.5, y + h * 0.55, z + lz * 0.5 - pz * 0.5, x + lx * 1.6, y + h, z + lz * 1.6);
        pc.set(cols[Math.floor(rnd() * cols.length)]).multiplyScalar(0.72 + 0.3 * rnd()); gcl.push(pc.r * 0.85, pc.g * 0.85, pc.b * 0.8, pc.r * 0.85, pc.g * 0.85, pc.b * 0.8, pc.r * 1.1, pc.g * 1.1, pc.b * 1.0, pc.r * 1.1, pc.g * 1.1, pc.b * 1.0, pc.r * 1.35, pc.g * 1.35, pc.b * 1.2);
        gi.push(o, o + 1, o + 3, o + 1, o + 2, o + 3, o + 3, o + 2, o + 4); }
      const g = own(new THREE.BufferGeometry()); g.setAttribute('position', new THREE.Float32BufferAttribute(gp, 3)); g.setAttribute('color', new THREE.Float32BufferAttribute(gcl, 3)); g.setIndex(gi); g.computeVertexNormals();
      const gm = new THREE.Mesh(g, own(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.9, side: THREE.DoubleSide }))); gm.frustumCulled = false; nest.add(gm);
      const sg = new THREE.SphereGeometry(1, 10, 7), sp = [], sci = [], si = [], pcol = ['#A99987', '#8B7A68', '#B8A894', '#6F5F50'];
      for (let i = 0; i < 70; i++) { const x = (rnd() - 0.5) * 9 * rnd(), z = FZ - 0.05 - rnd() * (DEP - 0.2), r = 0.008 + rnd() * rnd() * 0.03, y = groundY(x, z) + r * 0.2, o = sp.length / 3; pc.set(pcol[i % 4]).multiplyScalar(0.8 + 0.3 * rnd());
        const v = V(0, 0, 0); for (let k = 0; k < sg.attributes.position.count; k++) { v.fromBufferAttribute(sg.attributes.position, k); sp.push(x + v.x * r * 1.3, y + v.y * r * 0.7, z + v.z * r); sci.push(pc.r, pc.g, pc.b); }
        for (let k = 0; k < sg.index.count; k++) si.push(sg.index.array[k] + o); }
      const pg = own(new THREE.BufferGeometry()); pg.setAttribute('position', new THREE.Float32BufferAttribute(sp, 3)); pg.setAttribute('color', new THREE.Float32BufferAttribute(sci, 3)); pg.setIndex(si); pg.computeVertexNormals();
      const pm2 = new THREE.Mesh(pg, own(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.85 }))); pm2.frustumCulled = false; nest.add(pm2); }

    // ---- 굴 메시 병합 버퍼 ----
    const P = [], N = [], C = [], UV = [], IX = [];
    const sand = new THREE.Color('#A98258'), deep = new THREE.Color('#6E4E36'), tmpC = new THREE.Color();
    const pushV = (p, n, u, v, shade) => {
      P.push(p.x, p.y, p.z); N.push(n.x, n.y, n.z); UV.push(u, v);
      tmpC.copy(sand).lerp(deep, clamp((SURF - p.y) / 1.9, 0, 1)); tmpC.multiplyScalar(shade); C.push(tmpC.r, tmpC.g, tmpC.b);
    };
    const wob = (t, ph) => Math.sin(t * 17 + ph) * 0.5 + Math.sin(t * 41 + ph * 2.3) * 0.3 + Math.sin(t * 89 + ph * 0.7) * 0.2;
    const addTube = (pts, rf, ph, shadeBase = 1) => {
      const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal'), L = curve.getLength(), S = Math.max(14, Math.ceil(L / 0.01)), R = 20;
      const fr = curve.computeFrenetFrames(S, false), base = P.length / 3, pt = V(0, 0, 0), n = V(0, 0, 0), q = V(0, 0, 0);
      for (let i = 0; i <= S; i++) {
        const t = i / S; curve.getPointAt(t, pt); const r = rf(t, t * L);
        for (let j = 0; j <= R; j++) {
          const a = j / R * 6.2832, rr = r * (1 + 0.045 * Math.sin(3 * a + i * 0.21 + ph) + 0.03 * Math.sin(5 * a - i * 0.13 + ph * 2) + 0.03 * wob(t * 3, ph));
          n.copy(fr.normals[i]).multiplyScalar(Math.cos(a)).addScaledVector(fr.binormals[i], Math.sin(a));
          q.copy(pt).addScaledVector(n, rr);
          pushV(q, n, j / R, t * L / 0.28, shadeBase);
        }
      }
      for (let i = 0; i < S; i++) for (let j = 0; j < R; j++) { const a = base + i * (R + 1) + j, b = a + R + 1; IX.push(a, b, a + 1, b, b + 1, a + 1); }
      return curve;
    };
    const addBlob = (c, rx, ry, rz, ph, shade = 1.04, wseg = 36, hseg = 22) => {
      const g = new THREE.SphereGeometry(1, wseg, hseg), p = g.attributes.position, uv = g.attributes.uv, base = P.length / 3, v = V(0, 0, 0), n = V(0, 0, 0);
      for (let i = 0; i < p.count; i++) {
        v.fromBufferAttribute(p, i); n.copy(v);
        const k = 1 + 0.05 * Math.sin(v.x * 4.1 + ph) * Math.sin(v.z * 3.7 + ph * 1.3) + 0.03 * Math.sin(v.y * 7 + v.x * 5 + ph);
        v.multiplyScalar(k); if (v.y < 0) v.y *= 0.85;
        v.set(c.x + v.x * rx, c.y + v.y * ry, c.z + v.z * rz);
        n.set(n.x / rx, n.y / ry, n.z / rz).normalize();
        pushV(v, n, uv.getX(i) * 2, uv.getY(i) * 1.2, shade);
      }
      for (let i = 0; i < g.index.count; i++) IX.push(g.index.array[i] + base);
      g.dispose();
    };

    // ---- 굴 모양: 입구에서 분야마다 한 줄기 ----
    const ENT = V(0, SURF - 0.006, 0.26);
    const chambers = [], seedsA = { pos: [], size: [], col: [], task: [] }, subs = [], paths = [];
    const jit = (r, a) => (r() - 0.5) * a;
    themes.forEach((th, hi) => {
      const ts = tasks.filter(t => t.theme === th.id), r = rng(hash(th.id + hi)), ph = r() * 6.28;
      const phi = (hi + 0.5) / NT * 6.2832 + (r() - 0.5) * 0.4, depth = -0.45 - 0.4 * r(), reach = (0.7 + 0.45 * r()) * 1.5;
      const M = 16, pts = [];
      for (let j = 0; j <= M; j++) {
        const u = j / M, e = Math.pow(u, 1.15), w = Math.sin(u * 6 + hi * 1.7) * 0.05 + jit(r, 0.025) * (j > 1 ? 1 : 0);
        pts.push(V(clamp(Math.cos(phi) * reach * e + w, -BX + 0.12, BX - 0.12), SURF - 0.08 + (depth - SURF + 0.08) * (0.25 * u + 0.75 * Math.pow(u, 1.3)) + jit(r, 0.02) * (j > 1 ? 1 : 0), clamp(ENT.z - (ENT.z + 0.05) * Math.min(1, u * 2.4) + Math.sin(phi) * reach * 0.25 * e + w * 0.4, -BZ, BZ)));
      }
      pts[0] = ENT.clone(); pts[1] = V(ENT.x + (pts[1].x - ENT.x) * 0.4, ENT.y - 0.12, ENT.z + (pts[1].z - ENT.z) * 0.4);
      const n = ts.length, us = ts.map((_, k) => (n > 1 ? 0.3 + 0.7 * (k / (n - 1)) : 0.7));
      const r0 = 0.05, r1 = 0.034;
      const shaft = addTube(pts, (t) => {
        let r = r0 + (r1 - r0) * t; r *= 1 + 0.1 * wob(t, ph);
        r *= 1 + 0.55 * Math.pow(Math.max(0, 1 - t / 0.06), 2);
        us.forEach(u => { r *= 1 + 0.3 * Math.exp(-Math.pow((t - u) / 0.035, 2)); });
        return r;
      }, ph);
      addBlob(shaft.getPointAt(1), 0.052, 0.045, 0.052, ph, 1.0, 20, 12);
      subs.push({ name: th.name, shaft });
      ts.forEach((t, k) => {
        const u = us[k], S = shaft.getPointAt(clamp(u, 0, 1)), a = k * 2.39996 + hi, rad = 0.2 + 0.22 * ((k * 0.618) % 1);
        const mins = t.mins || 0, cr = clamp(0.05 + 0.011 * Math.sqrt(mins), 0.055, 0.13);
        const Cc = V(clamp(S.x + Math.cos(a) * rad, -BX + cr + 0.04, BX - cr - 0.04), clamp(S.y - 0.05 - 0.06 * ((k * 0.37) % 1), -BY + cr + 0.04, BY - 0.25), clamp(S.z + Math.sin(a) * rad * 0.35, -BZ + 0.02, BZ - 0.02));
        const sx = 1 + 0.25 * r(), sz = 0.7 + 0.15 * r(), ry = cr * 0.6;
        const d = Cc.clone().sub(S), m1 = S.clone().addScaledVector(d, 0.33), m2 = S.clone().addScaledVector(d, 0.68);
        m1.y += jit(r, 0.03); m2.y += jit(r, 0.03); m1.x += jit(r, 0.03); m2.z += jit(r, 0.02);
        const bph = r() * 6.28, rb = 0.022 + 0.0006 * Math.min(40, Math.sqrt(mins)), rEnd = Math.min(cr * 0.55, ry * 0.8);
        const bc = addTube([S.clone().addScaledVector(d, -0.04), S, m1, m2, Cc.clone().addScaledVector(d, 0.1)], (tt, l) => {
          let q = rb * (1 + 0.14 * wob(tt, bph));
          q *= 1 + 0.8 * Math.exp(-l / 0.045);
          return q + (rEnd - q) * sstep(0.62, 1, tt);
        }, bph, 0.97);
        addBlob(S, 0.046, 0.04, 0.046, bph, 0.97, 16, 10); addBlob(S.clone().addScaledVector(d, -0.04), 0.045, 0.045, 0.045, bph, 0.97, 12, 8);
        addBlob(Cc, cr * sx, ry, cr * sz, bph + 1, 1.05);
        const ci = chambers.length;
        chambers.push({ t, c: Cc, r: cr, sub: hi, sx, sz, ry });
        paths.push({ shaft, u, branch: bc, ci });
        const cnt = (t.sessions || []).length + Object.values(t.items || {}).reduce((s, x) => s + (x ? x.length : 0), 0), mm = Math.min(24, Math.max(3, cnt));
        for (let q = 0; q < mm; q++) {
          const ang = q * 2.39996, rr = cr * 0.62 * Math.sqrt((q + 0.5) / mm);
          seedsA.pos.push(Cc.x + Math.cos(ang) * rr * sx, Cc.y - ry * 0.55 + 0.004, Cc.z + Math.sin(ang) * rr * sz);
          seedsA.size.push(8 + (q % 3) * 2); const g = q % 3 === 1; seedsA.col.push(g ? 0.84 : 1, g ? 0.95 : 1, g ? 0.82 : 1); seedsA.task.push(ci);
        }
      });
    });

    // ---- 굴 한 덩어리: 구멍(스텐실)과 속 벽 ----
    const bg = own(new THREE.BufferGeometry());
    bg.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); bg.setAttribute('normal', new THREE.Float32BufferAttribute(N, 3));
    bg.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); bg.setAttribute('uv', new THREE.Float32BufferAttribute(UV, 2)); bg.setIndex(IX);
    bg.computeBoundingBox(); const bb = bg.boundingBox, sz3 = bb.getSize(V(0, 0, 0));
    const TOPM = SURF + 0.12, ctrY = (bb.min.y + TOPM) / 2, ctr = V((bb.min.x + bb.max.x) / 2, ctrY, (bb.min.z + bb.max.z) / 2), HALF = { x: sz3.x / 2, y: (TOPM - bb.min.y) / 2, z: sz3.z / 2 };
    nest.position.copy(ctr).multiplyScalar(-1);
    const writer = new THREE.Mesh(bg, own(new THREE.MeshBasicMaterial(stW))); writer.renderOrder = -10; writer.frustumCulled = false; nest.add(writer);
    const tunM = own(new THREE.MeshStandardMaterial({ map: tex, bumpMap: bump, bumpScale: 1.4, vertexColors: true, roughness: 0.9, side: THREE.BackSide, emissive: new THREE.Color('#7A4A28'), emissiveIntensity: 0.1 }));
    tunM.onBeforeCompile = sh => {   // 굴 속: 가장자리와 안쪽 깊이에 그늘, 중앙은 뒷벽이 밝게
      sh.fragmentShader = sh.fragmentShader.replace('#include <color_fragment>', `#include <color_fragment>
        float ndv = abs(dot(normalize(vNormal), normalize(vViewPosition)));
        diffuseColor.rgb *= mix(0.16, 0.8, smoothstep(0.02, 0.7, ndv));`);
    };
    const tunnels = new THREE.Mesh(bg, tunM); tunnels.renderOrder = 1; tunnels.frustumCulled = false; nest.add(tunnels);
    // 구멍 안 바닥: 뒷벽이 비는 틈이 없게 어두운 흙 면
    { const bw = new THREE.Mesh(own(new THREE.PlaneGeometry(60, 40)), own(new THREE.MeshBasicMaterial({ color: '#33200F', stencilWrite: true, stencilRef: 1, stencilFunc: THREE.EqualStencilFunc }))); bw.position.set(ctr.x, SURF - 4, -BZ - 0.25); bw.renderOrder = 0.2; nest.add(bw); }
    // 구멍 가장자리 그늘: 단면 위에서만, 화면 기준으로 넓힌 두 겹
    [[0.03, 0.2], [0.012, 0.22]].forEach(([w, a]) => {
      const m = own(new THREE.ShaderMaterial({ transparent: true, depthWrite: false, depthTest: false, stencilWrite: true, stencilRef: 1, stencilFunc: THREE.NotEqualStencilFunc,
        vertexShader: `void main() { vec4 c = projectionMatrix * modelViewMatrix * vec4(position, 1.); vec3 n = normalize(normalMatrix * normal); c.xy += normalize(n.xy + 1e-4) * ${w.toFixed(3)} * c.w; gl_Position = c; }`,
        fragmentShader: `void main() { gl_FragColor = vec4(.1, .05, .025, ${a}); }` }));
      const h = new THREE.Mesh(bg, m); h.renderOrder = 0.5; h.frustumCulled = false; nest.add(h); });
    // 입구: 땅 위의 어두운 구멍과 가장자리 흙
    { const hc = mkCanvas(128), x = hc.getContext('2d'), g = x.createRadialGradient(64, 64, 4, 64, 64, 62);
      g.addColorStop(0, 'rgba(24,12,7,1)'); g.addColorStop(0.45, 'rgba(24,12,7,.97)'); g.addColorStop(0.66, 'rgba(60,38,26,.55)'); g.addColorStop(1, 'rgba(60,38,26,0)'); x.fillStyle = g; x.fillRect(0, 0, 128, 128);
      const ht = own(new THREE.CanvasTexture(hc)), hole = new THREE.Mesh(own(new THREE.PlaneGeometry(0.3, 0.2)), own(new THREE.MeshBasicMaterial({ map: ht, transparent: true, depthWrite: false })));
      hole.rotation.x = -Math.PI / 2; hole.position.set(ENT.x, groundY(ENT.x, ENT.z) + 0.004, ENT.z); hole.renderOrder = 2; nest.add(hole); }
    // 가리킨 방 강조(구멍 안에서만)
    const hl = new THREE.Mesh(own(new THREE.SphereGeometry(1, 24, 14)), own(new THREE.MeshBasicMaterial({ color: 0xFFEBC8, transparent: true, opacity: 0.3, depthWrite: false, depthTest: false, stencilWrite: true, stencilRef: 1, stencilFunc: THREE.EqualStencilFunc })));
    hl.visible = false; hl.renderOrder = 6; nest.add(hl);

    // 빛 점: 알
    const PU = { uHover: { value: -1 }, uPx: { value: 1 }, uD: { value: 3 } };
    const pm = own(new THREE.ShaderMaterial({ uniforms: PU, transparent: true, depthWrite: false,
      vertexShader: 'attribute float aSize; attribute vec3 aCol; attribute float aTask; uniform float uHover, uPx, uD; varying vec3 vC; varying float vA;\n void main() { vec4 mv = modelViewMatrix * vec4(position, 1.); gl_Position = projectionMatrix * mv;\n gl_PointSize = aSize * uPx * (uD / -mv.z); vC = aCol; vA = ((uHover < 0. || aTask < 0. || abs(aTask - uHover) < .5) ? 1. : .45); }',
      fragmentShader: 'varying vec3 vC; varying float vA; void main() { float d = length(gl_PointCoord - .5) * 2.; if (d > 1.) discard; float core = smoothstep(.62, .2, d), glow = smoothstep(1., .2, d); vec3 c = mix(vC * .92, vec3(1., .97, .88), core * .6); gl_FragColor = vec4(c, (core * .95 + glow * glow * .3) * vA); }' }));
    { const A = seedsA, g = own(new THREE.BufferGeometry());
      g.setAttribute('position', new THREE.Float32BufferAttribute(A.pos, 3)); g.setAttribute('aSize', new THREE.Float32BufferAttribute(A.size, 1)); g.setAttribute('aCol', new THREE.Float32BufferAttribute(A.col, 3)); g.setAttribute('aTask', new THREE.Float32BufferAttribute(A.task, 1));
      const p = new THREE.Points(g, pm); p.frustumCulled = false; p.renderOrder = 4; nest.add(p); }

    // 개미: 머리, 가슴, 배 + 다리
    const NA = Math.min(16, paths.length), ants = [];
    for (let i = 0; i < NA; i++) { const p = paths[Math.floor(i * paths.length / NA)]; const a = { p, s: p.shaft.getSpacedPoints(60).slice(0, Math.round(60 * p.u) + 1), b: p.branch.getSpacedPoints(12), v: 0.1 + 0.05 * rnd() }; a.len = a.s.length + a.b.length - 2; a.prog = rnd() * a.len; ants.push(a); }
    const antM = own(new THREE.MeshStandardMaterial({ color: '#2A1710', roughness: 0.45, metalness: 0.1, emissive: '#3A2216', emissiveIntensity: 0.5 }));
    const antI = new THREE.InstancedMesh(own(new THREE.SphereGeometry(1, 12, 8)), antM, Math.max(1, NA * 3)); antI.frustumCulled = false; antI.renderOrder = 3; antI.instanceMatrix.setUsage(THREE.DynamicDrawUsage); nest.add(antI);
    const legG = own(new THREE.BufferGeometry()), legA = new THREE.BufferAttribute(new Float32Array(Math.max(1, NA) * 6 * 2 * 3), 3); legA.setUsage(THREE.DynamicDrawUsage); legG.setAttribute('position', legA);
    const legs = new THREE.LineSegments(legG, own(new THREE.LineBasicMaterial({ color: 0x2A1710 }))); legs.frustumCulled = false; legs.renderOrder = 3; nest.add(legs);
    const dum = new THREE.Object3D(), mm4 = new THREE.Matrix4(), pm4 = new THREE.Matrix4(), ZERO = new THREE.Matrix4().makeScale(0, 0, 0), lv = V(0, 0, 0), IQ = new THREE.Quaternion();
    for (let i = 0; i < NA * 3; i++) antI.setMatrixAt(i, ZERO);
    const PARTS = [[-0.0175, 0.0082, 0.0078, 0.0135], [0, 0.0058, 0.0058, 0.0085], [0.0155, 0.0066, 0.0062, 0.0075]];   // z 위치, 반지름 x, y, z
    const LEG = [[0.004, 0.011, 0.016], [0.0, 0.012, -0.004], [-0.004, 0.011, -0.016]];

    // ---- 라벨 ----
    const labs = []; let used = 0;
    const label = (txt, x, y, al, sz, o = {}) => {
      let el = labs[used++];
      if (!el) { el = document.createElement('div'); el._t = ''; el._v = 0; main.appendChild(el); labs.push(el); el.style.cssText = `position:absolute;left:0;top:0;z-index:4;pointer-events:none;white-space:nowrap;font-family:${FONT};font-weight:600;color:#FBF4EA;text-shadow:0 0 6px rgba(36,21,15,.95),0 0 2px rgba(36,21,15,.9),0 1px 1px rgba(36,21,15,.8);will-change:transform`; }
      if (el._sz !== sz) { el._sz = sz; el.style.fontSize = sz + 'px'; }
      if (el._t !== txt) { el._t = txt; el.textContent = txt; }
      el.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) translate(${o.mid ? '-50%' : '0'},-50%)`;
      el.style.opacity = al; if (!el._v) { el._v = 1; el.style.display = ''; }
    };

    // ---- 시점, 입력 ----
    let W = 1, H = 1, base = 4;
    const view = { yaw: 0.2, pitch: 0.33, zoom: 1, dragging: false, hold: false }, ZMIN = 0.55, ZMAX = 1.5, YL = 0.7;
    let drag = null, moved = 0, mouse = null, hover = -1, raf = 0, last = 0;
    const size = () => {
      const r = main.getBoundingClientRect(); W = Math.max(1, r.width); H = Math.max(1, r.height); renderer.setSize(W, H, false); camera.aspect = W / H; camera.updateProjectionMatrix();
      const tv = Math.tan(THREE.MathUtils.degToRad(23)), th = tv * (W / H);
      base = Math.max(HALF.y / tv, HALF.x / th) * 1.1 + HALF.z + 0.15;
    };
    const ro = new ResizeObserver(size); ro.observe(main); size();
    const pp = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    cv.addEventListener('pointerdown', e => { drag = pp(e); moved = 0; view.dragging = true; cv.setPointerCapture(e.pointerId); cv.style.cursor = 'grabbing'; });
    cv.addEventListener('pointermove', e => { const p = pp(e); mouse = p; if (!drag) return; const dx = p.x - drag.x, dy = p.y - drag.y; moved += Math.abs(dx) + Math.abs(dy); view.yaw = clamp(view.yaw + dx * 0.004, -YL, YL); view.pitch = clamp(view.pitch + dy * 0.004, 0.08, 0.7); drag = p; });
    const up = () => { if (drag && moved < 4 && hover >= 0) ui.open(chambers[hover].t.id); drag = null; view.dragging = false; cv.style.cursor = 'grab'; };
    cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
    cv.addEventListener('pointerleave', () => { if (!drag) mouse = null; });
    cv.addEventListener('wheel', e => { e.preventDefault(); view.zoom = clamp(view.zoom * Math.exp(e.deltaY * 0.0015), ZMIN, ZMAX); }, { passive: false });

    // ---- 매 프레임 ----
    const tmp = V(0, 0, 0), so = { x: 0, y: 0 }, wp = V(0, 0, 0), wp2 = V(0, 0, 0), sc3 = V(1, 1, 1), tv3 = V(0, 0, 0);
    const scr = (v, o) => { tmp.copy(v).applyMatrix4(nest.matrixWorld).project(camera); o.x = (tmp.x * 0.5 + 0.5) * W; o.y = (-tmp.y * 0.5 + 0.5) * H; };
    const CAND = [0.5, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74, 0.18, 0.82, 0.62, 0.38];
    const frame = t => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (t - (last || t)) / 1000) * 60 || 1, ds = dt / 60; last = t;
      if (!drag && !view.hold) { view.yaw += (0.3 * Math.sin(t / 4200) - view.yaw) * 0.012 * dt; view.pitch += (0.33 + 0.04 * Math.sin(t / 5300) - view.pitch) * 0.012 * dt; }
      const D = base * view.zoom;
      camera.position.set(0, 0, D); camera.lookAt(0, 0, 0); group.rotation.set(view.pitch, view.yaw, 0, 'XYZ'); group.updateMatrixWorld(true); camera.updateMatrixWorld();
      PU.uD.value = D; PU.uPx.value = renderer.getPixelRatio() * Math.min(1.4, Math.max(0.6, Math.min(W, H) / 800));
      hover = -1;
      if (mouse && !drag) { let best = 1e9; chambers.forEach((c, i) => { scr(c.c, so); const rr = Math.max(16, c.r * 900 / D * (H / 860)), d = Math.hypot(so.x - mouse.x, so.y - mouse.y); if (d < rr && d < best) { best = d; hover = i; } }); }
      view.hold = hover >= 0; PU.uHover.value = hover;
      if (hover >= 0) { const c = chambers[hover]; hl.visible = true; hl.position.copy(c.c); hl.scale.set(c.r * c.sx * 1.04, c.ry * 1.05, c.r * c.sz * 1.04); } else hl.visible = false;
      // 개미: 입구에서 굴을 따라 방까지
      const la = legA.array, sw = t / 90;
      ants.forEach((a, i) => {
        a.prog += a.v * ds * 3; if (a.prog > a.len + 2) a.prog = -2 - rnd() * 8; const ph = a.prog;
        const hide = () => { for (let k = 0; k < 3; k++) antI.setMatrixAt(i * 3 + k, ZERO); la.fill(0, i * 36, i * 36 + 36); };
        if (ph < 0) { hide(); return; }
        const f = Math.min(ph, a.len - 0.001), ix = Math.floor(f), fr = f - ix, seq = j => (j < a.s.length ? a.s[j] : a.b[Math.min(a.b.length - 1, j - a.s.length + 1)]);
        const p0 = seq(ix), p1 = seq(Math.min(a.len, ix + 1)); if (!p0 || !p1) { hide(); return; }
        wp.copy(p0).lerp(p1, fr); wp2.copy(p1).sub(p0); if (wp2.lengthSq() < 1e-10) return;
        dum.position.copy(wp); dum.lookAt(wp.x + wp2.x, wp.y + wp2.y, wp.z + wp2.z); dum.updateMatrix();
        PARTS.forEach((q, k) => { mm4.compose(tv3.set(0, 0.002, q[0]), IQ, sc3.set(q[1], q[2], q[3])); pm4.multiplyMatrices(dum.matrix, mm4); antI.setMatrixAt(i * 3 + k, pm4); });
        for (let s = 0; s < 6; s++) { const side = s < 3 ? 1 : -1, L = LEG[s % 3], w = Math.sin(sw + s * 2.1 + i) * 0.004, o = i * 36 + s * 6;
          lv.set(0, 0, L[0]).applyMatrix4(dum.matrix); la[o] = lv.x; la[o + 1] = lv.y; la[o + 2] = lv.z;
          lv.set(side * L[1], -0.006, L[0] + (L[2] > 0 ? 0.006 : L[2] < 0 ? -0.006 : 0) + w).applyMatrix4(dum.matrix); la[o + 3] = lv.x; la[o + 4] = lv.y; la[o + 5] = lv.z; }
      });
      antI.instanceMatrix.needsUpdate = true; legA.needsUpdate = true;
      cv.style.cursor = hover >= 0 ? 'pointer' : drag ? 'grabbing' : 'grab';
      renderer.render(scene, camera);
      used = 0;
      const boxes = [];
      const free = (x, y, w, h) => !boxes.some(b => x < b[0] + b[2] + 4 && b[0] < x + w + 4 && y - h / 2 < b[1] + b[3] / 2 + 2 && b[1] - b[3] / 2 < y + h / 2 + 2);
      scr(V(ENT.x + 0.1, groundY(0, ENT.z) + 0.02, ENT.z), so); label('나', so.x + 8, so.y - 4, 1, 15); boxes.push([so.x + 8, so.y - 4, 18, 18]);
      subs.forEach((s, i) => {
        const w = s.name.length * 14 + 6, h = 18;
        for (const u of CAND) { s.shaft.getPointAt(u, wp); scr(wp, so); const x = so.x + 10, y = so.y - 10;
          if (x > 4 && x + w < W - 4 && y > 10 && y < H - 10 && free(x, y, w, h)) { boxes.push([x, y, w, h]); label(s.name, x, y, hover < 0 || chambers[hover].sub === i ? 1 : 0.55, 14); break; } }
      });
      if (hover >= 0) { scr(chambers[hover].c, so); const s0 = chambers[hover].t.title; label(s0.length > 30 ? s0.slice(0, 30) + '…' : s0, Math.min(W - 90, so.x + 16), so.y - 8, 1, 13); }
      for (let i = used; i < labs.length; i++) if (labs[i]._v) { labs[i]._v = 0; labs[i].style.display = 'none'; }
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf); ro.disconnect();
      disp.forEach(o => o.dispose && o.dispose());
      antI.dispose(); renderer.dispose(); renderer.forceContextLoss(); cv.remove(); labs.forEach(e => e.remove());
    };
  }
};

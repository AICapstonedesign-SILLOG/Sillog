/* 분재 (three.js): 키우는 재미가 있는 귀여운 분재. 분야 하나 = 굵은 가지 하나 + 잎 뭉치(패드), 업무 하나 = 그 패드 위의 잎 다발 하나.
   잎 다발 크기 = 그 업무에 쓴 시간, 줄기 굵기와 키 = 전체 시간(성장 단계 1~5). 열 때 줄기가 자라고 잎 다발이 통통 튀며 나온다.
   실제 데이터만 쓴다. 부드러운 면 + 둥근 잎 덩어리, 연한 도자기 화분 */
window.V3D = window.V3D || {};
window.V3D.dandelion = function (main, data, ui) {
  let dead = false, cleanup = () => {};
  const start = () => { if (!dead) cleanup = build(window.THREE); };
  if (window.THREE) start(); else window.addEventListener('three-ready', start, { once: true });
  return () => { dead = true; window.removeEventListener('three-ready', start); cleanup(); };

  function build(THREE) {
    const BROWN = '#24150F';
    const FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
    const trunc = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
    const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
    const sm = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
    const mulberry = a => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
    const V = (x, y, z) => new THREE.Vector3(x, y, z);

    // ---- 데이터 → 분야별 업무 ----
    const cnt = t => (t.sessions || []).length + Object.values(t.items || {}).reduce((s, a) => s + (a ? a.length : 0), 0);
    const groups = new Map();
    (data.themes || []).forEach(th => groups.set(th.id, { id: th.id, name: th.name, tasks: [] }));
    (data.tasks || []).forEach(t => { if (!groups.has(t.theme)) groups.set(t.theme, { id: t.theme, name: '기타', tasks: [] }); groups.get(t.theme).tasks.push(t); });
    const gs = [...groups.values()].filter(g => g.tasks.length);
    gs.forEach(g => { g.n = g.tasks.reduce((s, t) => s + cnt(t), 0); g.tasks.sort((a, b) => cnt(b) - cnt(a)); });
    gs.sort((a, b) => b.tasks.length - a.tasks.length);
    const GA = Math.PI * (3 - Math.sqrt(5)), maxN = Math.max(1, ...gs.map(g => g.n));

    // ---- 렌더러, 장면 ----
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, premultipliedAlpha: true, powerPreference: 'high-performance' }); }
    catch (e) { const p = document.createElement('p'); p.className = 'empty-note'; p.textContent = '이 환경에서는 WebGL 을 쓸 수 없습니다'; main.appendChild(p); return () => p.remove(); }
    renderer.setClearColor(0x000000, 0); renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.15;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    const cv = renderer.domElement;
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;cursor:grab;touch-action:none';
    main.style.position = 'relative';
    const mesh = window.G3D && window.G3D.mesh ? window.G3D.mesh(main, 0.8) : null;   // 아래에 흐르는 갈색, 흰색 바탕
    main.appendChild(cv);
    const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(46, 1, 0.05, 40), group = new THREE.Group();
    scene.add(group);
    scene.add(new THREE.HemisphereLight(0xF6F5F4, 0x6A5748, 1.0));
    const key = new THREE.DirectionalLight(0xFFE6CC, 3.4); key.position.set(-3, 4.5, 3.5); scene.add(key);   // 왼쪽 위 부드러운 주광
    const fill = new THREE.DirectionalLight(0xCFE0EC, 0.9); fill.position.set(3.5, 0.5, 2.5); scene.add(fill);
    const rim = new THREE.DirectionalLight(0xE8F0E8, 2.2); rim.position.set(1.5, 2.5, -3.5); scene.add(rim);   // 뒤에서 비추는 가장자리 빛
    const disp = []; const own = o => { disp.push(o); return o; };
    const rnd = mulberry(5150);

    // ---- 껍질 질감 + 사리(흰 마른 줄) 셰이더 ----
    const loader = new THREE.TextureLoader(), maxA = renderer.capabilities.getMaxAnisotropy(), BT = window.BARK_TEX;
    const ldTex = (src, srgb) => { const t = own(loader.load(src)); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = maxA; if (srgb) t.colorSpace = THREE.SRGBColorSpace; return t; };
    const woodMat = own(new THREE.MeshStandardMaterial({ color: '#9C6B52', emissive: '#1E0F0A', emissiveIntensity: 0.25, roughness: 1, vertexColors: true, map: BT ? ldTex(BT.color, true) : null, normalMap: BT ? ldTex(BT.normal) : null, normalScale: new THREE.Vector2(1.7, 1.7), roughnessMap: BT ? ldTex(BT.rough) : null }));
    woodMat.onBeforeCompile = sh => {
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nattribute float aShari; varying float vSh;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvSh = aShari;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vSh;')
        .replace('#include <color_fragment>', '#include <color_fragment>\n diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.9, 0.84, 0.76), vSh);')
        .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n roughnessFactor = mix(roughnessFactor, 0.6, vSh);');
    };

    // ---- 관(비틀린 줄기, 가지): 반지름 함수 + 단면 요철 + 사리 + UV ----
    const sculpt = (curve, S, RAD, radFn, modFn, shFn, tintFn, forceSh = 0) => {
      const geo = new THREE.TubeGeometry(curve, S, 1, RAD, false), p = geo.attributes.position, uv = geo.attributes.uv, n = (S + 1) * (RAD + 1);
      const col = new Float32Array(n * 3), sh = new Float32Array(n), c = new THREE.Vector3(), c0 = new THREE.Vector3(), v = new THREE.Vector3();
      let mean = 0; for (let i = 0; i <= S; i++) mean += radFn(i / S); mean /= S + 1;
      const aN = Math.max(1, Math.round(2 * Math.PI * mean / 0.25)); let vv = 0;
      for (let i = 0; i <= S; i++) {
        const t = i / S, rad = radFn(t); curve.getPointAt(t, c); if (i) vv += c.distanceTo(c0) * aN / (2 * Math.PI * rad); c0.copy(c);
        for (let j = 0; j <= RAD; j++) {
          const k = i * (RAD + 1) + j, th = j / RAD * 6.2832, s = forceSh || (shFn ? shFn(t, th) : 0), r = rad * (modFn ? modFn(t, th) : 1) * (1 - 0.1 * s), tn = tintFn ? tintFn(t, th) : 1;
          v.fromBufferAttribute(p, k).sub(c).normalize().multiplyScalar(r).add(c); p.setXYZ(k, v.x, v.y, v.z); uv.setXY(k, j / RAD * aN, vv);
          col[k * 3] = tn; col[k * 3 + 1] = tn * 0.97; col[k * 3 + 2] = tn * 0.95; sh[k] = s;
        }
      }
      geo.setAttribute('color', new THREE.BufferAttribute(col, 3)); geo.setAttribute('aShari', new THREE.BufferAttribute(sh, 1)); geo.computeVertexNormals();
      const N = geo.attributes.normal; for (let i = 0; i <= S; i++) { const a = i * (RAD + 1), b = a + RAD; v.set((N.getX(a) + N.getX(b)) / 2, (N.getY(a) + N.getY(b)) / 2, (N.getZ(a) + N.getZ(b)) / 2).normalize(); N.setXYZ(a, v.x, v.y, v.z); N.setXYZ(b, v.x, v.y, v.z); }
      return geo;
    };
    const mergeGeos = list => {
      let nv = 0, ni = 0; list.forEach(g => { nv += g.attributes.position.count; ni += g.index.count; });
      const P = new Float32Array(nv * 3), N = new Float32Array(nv * 3), U = new Float32Array(nv * 2), C = new Float32Array(nv * 3), A = new Float32Array(nv), I = new Uint32Array(ni); let vo = 0, io = 0;
      list.forEach(g => { P.set(g.attributes.position.array, vo * 3); N.set(g.attributes.normal.array, vo * 3); U.set(g.attributes.uv.array, vo * 2); C.set(g.attributes.color.array, vo * 3); A.set(g.attributes.aShari.array, vo); for (let i = 0; i < g.index.count; i++) I[io + i] = g.index.array[i] + vo; vo += g.attributes.position.count; io += g.index.count; g.dispose(); });
      const m = own(new THREE.BufferGeometry()); m.setAttribute('position', new THREE.BufferAttribute(P, 3)); m.setAttribute('normal', new THREE.BufferAttribute(N, 3)); m.setAttribute('uv', new THREE.BufferAttribute(U, 2)); m.setAttribute('color', new THREE.BufferAttribute(C, 3)); m.setAttribute('aShari', new THREE.BufferAttribute(A, 1)); m.setIndex(new THREE.BufferAttribute(I, 1)); return m;
    };
    const wood = [];   // 줄기, 가지, 진, 드러난 뿌리: 전부 하나의 메시로 합친다

    // ---- 성장 단계: 전체 시간(분)이 늘수록 줄기가 굵어지고 키가 커진다 (1~5단계) ----
    const totalMin = data.tasks.reduce((s, t) => s + (t.mins || 0), 0), th = totalMin / 60;
    const stage = 1 + (th >= 5) + (th >= 15) + (th >= 40) + (th >= 100), gk = (stage - 1) / 4, HS = 0.68 + 0.32 * gk, RM = 0.7 + 0.45 * gk, BY = 0.5;
    const gy = y => BY + (y - BY) * HS;   // 높이 늘리기(화분 위 기준)
    const lastD = Math.max(-1, ...data.tasks.flatMap(t => (t.sessions || []).map(s => s.d)).filter(d => typeof d === 'number'));

    // ---- 줄기: 왼쪽으로 기울고 지그재그로 비틀린 부드러운 S 자 ----
    const TRUNK = [V(0.58, 0.56, 0.02), V(0.66, 0.8, 0.07), V(0.3, 0.98, 0.14), V(-0.08, 1.14, 0.0), V(0.36, 1.4, -0.04), V(0.08, 1.66, -0.1), V(0.34, 1.92, 0.0), V(0.2, 2.16, 0.04)].map(p => V(p.x, gy(p.y), p.z));
    const trunk = new THREE.CatmullRomCurve3(TRUNK, false, 'centripetal');
    const trad = t => RM * (0.034 + 0.15 * Math.pow(1 - t, 1.15) + 0.085 * Math.exp(-t * 20)) + 0.004 * Math.sin(t * 15);
    const tmod = (t, th) => 1 + 0.07 * Math.sin(2 * th + 6 * t) + 0.05 * Math.sin(3 * th - 9 * t + 1);
    const shari = (t, th) => { const w = sm(0.1, 0.16, t) * (1 - sm(0.36, 0.42, t)) + 0.9 * sm(0.6, 0.64, t) * (1 - sm(0.7, 0.74, t)); return w * sm(0.8, 0.93, Math.cos(th - (2.2 + t * 4.2))); };
    const ttint = (t, th) => 0.92 + 0.08 * Math.sin(th * 2 + t * 7) - 0.1 * t;
    wood.push(sculpt(trunk, 160, 24, trad, tmod, null, ttint));
    for (let r = 0; r < 5; r++) {   // 밑동에서 퍼지는 뿌리(뿌리 퍼짐)
      const a = r * 1.3 + 0.4, o = V(Math.cos(a), 0, Math.sin(a)), b = TRUNK[0], pts = [b.clone().add(V(0, 0.1, 0)), b.clone().addScaledVector(o, 0.15).add(V(0, 0.05, 0)), b.clone().addScaledVector(o, 0.3 + 0.1 * rnd()), b.clone().addScaledVector(o, 0.42 + 0.12 * rnd()).add(V(0, -0.01, 0))];
      const rr = 0.065 * RM; wood.push(sculpt(new THREE.CatmullRomCurve3(pts, false, 'centripetal'), 24, 9, t => 0.008 + rr * Math.pow(1 - t, 0.9), null, null, () => 0.95));
    }
    const jin = (P, D, r, L, depth) => {   // 진(마른 흰 가지): 짧고 통통하게
      const steps = 6, dir = D.clone().normalize(), p = P.clone(), pts = [P.clone()];
      for (let i = 1; i <= steps; i++) { dir.add(V(rnd() - 0.5, (rnd() - 0.5) * 0.6, rnd() - 0.5).multiplyScalar(0.35)).normalize(); p.addScaledVector(dir, L / steps); pts.push(p.clone()); }
      const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal'), rt = 0.004;
      wood.push(sculpt(curve, 24, 7, t => rt + (r - rt) * Math.pow(1 - t, 0.85), null, null, null, 1));
      if (depth < 1) { const t = 0.55, Q = curve.getPointAt(t), Tn = curve.getTangentAt(t), ax = new THREE.Vector3().crossVectors(Tn, V(rnd() - 0.5, rnd() - 0.5, rnd() - 0.5)).normalize(); jin(Q, Tn.clone().applyAxisAngle(ax, 0.7), (r + (rt - r) * t) * 0.8, L * 0.5, depth + 1); }
    };
    // ---- 분야 = 굵은 가지 하나 + 잎 뭉치 자리, 업무 = 그 위의 잎 다발 하나 (크기 = 쓴 시간) ----
    const SLOTS = [[V(0.28, 2.12, 0.0), 0.93], [V(-0.95, 1.55, 0.22), 0.7], [V(0.95, 1.5, -0.1), 0.62], [V(-0.8, 1.02, -0.28), 0.46], [V(-1.2, 0.74, 0.15), 0.32], [V(0.3, 1.7, 0.7), 0.76], [V(0.1, 1.75, -0.72), 0.84], [V(-0.5, 2.0, -0.45), 0.88]];
    const subs = []; let blobTotal = 0;
    gs.forEach((g, gi) => {
      const [C0, ta] = SLOTS[gi % SLOTS.length], m = g.tasks.length, rx = 0.3 + 0.09 * Math.sqrt(m), ry = 0.4 * rx, rz = 0.8 * rx, A = trunk.getPointAt(ta), pad = V(C0.x * (0.75 + 0.25 * gk), gy(C0.y), C0.z * (0.75 + 0.25 * gk));
      g.pad = pad; g.rx = rx; g.ry = ry;
      const E = pad.clone().add(V(0, -ry * 0.5, 0)), dd = E.clone().sub(A), L = dd.length(), side = new THREE.Vector3().crossVectors(dd, V(0, 1, 0.2)).normalize();
      const pts = [A.clone().addScaledVector(dd, -0.04), A.clone().addScaledVector(dd, 0.3).addScaledVector(side, 0.06 * L).add(V(0, 0.04, 0)), A.clone().addScaledVector(dd, 0.65).addScaledVector(side, -0.05 * L), E];
      const rb = (0.028 + 0.028 * Math.sqrt(g.n / maxN)) * (0.75 + 0.25 * RM), bcur = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
      wood.push(sculpt(bcur, 56, 12, t => 0.01 + (rb - 0.01) * Math.pow(1 - t, 0.7) * (1 + 0.2 * Math.exp(-t * 14)), (t, th) => 1 + 0.06 * Math.sin(2 * th + 5 * t), null, () => 0.95));
      g.tasks.forEach((t, k) => {
        const mins = t.mins || 0, rho = Math.sqrt((k + 0.5) / m), thv = k * GA + gi, rs = clamp(0.115 + 0.04 * Math.sqrt(mins / 60 + 0.4), 0.12, 0.27);
        const c = pad.clone().add(V(rho * Math.cos(thv) * rx * 0.8, ry * (0.7 * (1 - rho * rho) - 0.15), rho * Math.sin(thv) * rz * 0.8)), bud = rs < 0.15, nb = bud ? 3 : clamp(Math.round(4 + 16 * rs), 6, 9);
        const recent = (t.sessions || []).some(s => s.d === lastD);
        const blobs = Array.from({ length: nb }, (_, q) => { const u = V(rnd() - 0.5, (rnd() - 0.5) * 0.55, rnd() - 0.5).normalize().multiplyScalar(q ? rs * (0.45 + 0.4 * rnd()) : 0); return { off: u, r: rs * (q ? 0.42 + 0.28 * rnd() : 0.62), hl: clamp(0.3 + 0.5 * rnd() + 0.6 * u.y / rs, 0, 1) }; });
        subs.push({ t, g, c, rs, nb, blobs, b0: blobTotal, hs: 1, b: 1, tb: 1, bud, recent, ph: rnd() * 6.28, delay: 0.55 + 0.05 * subs.length, sx: 0, sy: 0, rr: 8 }); blobTotal += nb;
        const tw = new THREE.CatmullRomCurve3([E.clone(), E.clone().lerp(c, 0.5).add(V((rnd() - 0.5) * 0.05, 0.03, (rnd() - 0.5) * 0.05)), c.clone()], false, 'centripetal');
        wood.push(sculpt(tw, 12, 6, tt => 0.004 + 0.006 * Math.pow(1 - tt, 0.8), null, null, () => 0.9));
      });
    });
    const treeG = new THREE.Group(); treeG.position.y = BY; group.add(treeG);
    const woodMesh = new THREE.Mesh(mergeGeos(wood), woodMat); woodMesh.position.y = -BY; treeG.add(woodMesh);

    // ---- 잎 다발: 꽃 v2 의 꽃처럼 은은하게 빛나는 둥근 원판(화면을 향함) 수십 개가 모여 둥근 구름이 된다. 점 수 = 그 업무의 세션 + 자료 ----
    const cntOf = t => (t.sessions || []).length + Object.values(t.items || {}).reduce((q, a) => q + (a ? a.length : 0), 0);
    let ptTotal = 0; subs.forEach(sb => { sb.np = clamp(Math.round(cntOf(sb.t) * 0.9) + 8, 12, 90); sb.p0 = ptTotal; ptTotal += sb.np; });
    const hexRGB = h => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];
    const FOL = ['#CDE8A6', '#9BCB6A', '#E6F3D2', '#CDE8A6', '#FFFFFF', '#9BCB6A'];
    const dPos = new Float32Array(ptTotal * 3), dCol = new Float32Array(ptTotal * 3), dK = new Float32Array(ptTotal), dS = new Float32Array(ptTotal).fill(1), dDim = new Float32Array(ptTotal).fill(1), dIdx = new Uint32Array(ptTotal);
    subs.forEach(sb => { sb.off = []; for (let q = 0; q < sb.np; q++) {
      const u = V(rnd() - 0.5, (rnd() - 0.5) * 0.75, rnd() - 0.5).normalize().multiplyScalar(sb.rs * (0.35 + 0.65 * Math.cbrt(rnd()))), hl = clamp(0.5 + u.y / sb.rs * 0.6 + (rnd() - 0.5) * 0.5, 0, 1);
      sb.off.push(u); const k = sb.p0 + q, col = sb.bud ? '#E6F3D2' : hl > 0.82 ? '#FFFFFF' : hl > 0.55 ? FOL[Math.floor(rnd() * 4)] : rnd() < 0.5 ? '#9BCB6A' : '#CDE8A6';
      dCol.set(hexRGB(col), k * 3); dK[k] = q === 0 ? 2 : (rnd() < 0.18 ? 1 : 0); dS[k] = 1.15 + 0.5 * rnd(); } });
    const dotG = own(new THREE.BufferGeometry()), posA = new THREE.BufferAttribute(dPos, 3), sA = new THREE.BufferAttribute(dS, 1), dimA = new THREE.BufferAttribute(dDim, 1), idxA = new THREE.BufferAttribute(dIdx, 1);
    dotG.setAttribute('position', posA); dotG.setAttribute('aCol', new THREE.BufferAttribute(dCol, 3)); dotG.setAttribute('aK', new THREE.BufferAttribute(dK, 1)); dotG.setAttribute('aS', sA); dotG.setAttribute('aDim', dimA); dotG.setIndex(idxA);
    const dotU = { uPx: { value: 1 }, uSc: { value: 1 }, uD: { value: 5 }, uBase: { value: 5 } };
    const dotM = own(new THREE.ShaderMaterial({ transparent: true, depthWrite: false, uniforms: dotU,
      vertexShader: `attribute vec3 aCol; attribute float aK, aS, aDim; uniform float uPx, uSc, uD, uBase; varying vec3 vCol; varying float vA, vRc, vHalo;
        void main() {
          vec4 mv = modelViewMatrix * vec4(position, 1.0); mv.z += 0.03; float dist = length(mv.xyz), far = smoothstep(-0.4, 0.8, dist - uD), zf = pow(uBase / uD, 0.55);
          float r = (aK < 0.5 ? 3.3 : aK < 1.5 ? 3.8 : 5.2) * uSc * pow(uD / dist, 1.4) * zf * aS, ring = 2.0 * uSc * zf, tot = aK > 1.5 ? r * 2.1 : r + ring;
          vRc = r / tot; vCol = aCol; vA = mix(1.0, 0.35, far) * aDim; vHalo = aK > 1.5 ? 0.3 : 0.24 * (1.0 - far);
          gl_PointSize = max(2.0, 2.0 * tot * uPx); gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: `varying vec3 vCol; varying float vA, vRc, vHalo;
        void main() {
          float d = length(gl_PointCoord * 2.0 - 1.0); if (d > 1.0) discard;
          float core = 1.0 - smoothstep(vRc - 0.06, vRc + 0.03, d), edge = 1.0 - smoothstep(0.86, 1.0, d);
          float a = (core + (1.0 - core) * vHalo * edge) * vA; gl_FragColor = vec4(vCol, a);
        }` }));
    const foliage = new THREE.Points(dotG, dotM); foliage.frustumCulled = false; foliage.renderOrder = 5; group.add(foliage);
    const sorted = subs.slice();
    // 오늘(가장 최근 활동일) 일한 잎 다발에는 부드러운 반짝임
    const sparkSubs = subs.filter(s => s.recent).slice(0, 14), sparkN = sparkSubs.length * 3, sparkP = new Float32Array(Math.max(1, sparkN) * 3);
    const sg = own(new THREE.BufferGeometry()); sg.setAttribute('position', new THREE.BufferAttribute(sparkP, 3));
    const sc = document.createElement('canvas'); sc.width = sc.height = 64; { const g = sc.getContext('2d'), gr = g.createRadialGradient(32, 32, 0, 32, 32, 32); gr.addColorStop(0, 'rgba(255,252,220,1)'); gr.addColorStop(0.35, 'rgba(255,246,190,0.55)'); gr.addColorStop(1, 'rgba(255,246,190,0)'); g.fillStyle = gr; g.fillRect(0, 0, 64, 64); }
    const sparkM = own(new THREE.PointsMaterial({ map: own(new THREE.CanvasTexture(sc)), size: 16, sizeAttenuation: false, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0.8 }));
    const sparks = new THREE.Points(sg, sparkM); sparks.frustumCulled = false; sparks.renderOrder = 6; group.add(sparks);

    // ---- 화분: 낮고 긴 직사각형 유약 도자기(둥글게 접힌 가장자리, 말려 올라간 테두리와 벽 두께, 환경 반사), 점토 발 넷, 속은 구멍 많은 화산석을 줄기 쪽으로 높이 쌓는다 ----
    { const X = 1.42, Z = 0.5, potG = new THREE.Group(); group.add(potG);
      // 부드러운 반사용 환경: 왼쪽 위의 밝은 소프트박스 + 어두운 보조광을 작은 장면으로 만들어 PMREM 으로 굽는다
      const envS = new THREE.Scene(), envBg = new THREE.Mesh(new THREE.SphereGeometry(10, 24, 16), new THREE.MeshBasicMaterial({ side: THREE.BackSide, vertexColors: true }));
      { const g = envBg.geometry, c = new Float32Array(g.attributes.position.count * 3); for (let q = 0; q < g.attributes.position.count; q++) { const t = clamp(g.attributes.position.getY(q) / 10 * 0.5 + 0.5, 0, 1), v = 0.05 + 0.3 * t * t; c.set([v * 0.95, v * 0.95, v], q * 3); } g.setAttribute('color', new THREE.BufferAttribute(c, 3)); }
      envS.add(envBg);
      const box = (w, h, col, x, y, z) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: col, side: THREE.DoubleSide })); m.position.set(x, y, z); m.lookAt(0, 0, 0); envS.add(m); };
      box(7, 5, new THREE.Color(9, 8.6, 8), -5, 6, 4); box(3, 6, new THREE.Color(1.6, 1.7, 1.9), 7, 1, 2); box(8, 2, new THREE.Color(0.6, 0.55, 0.5), 0, -3, 6);
      const pmrem = new THREE.PMREMGenerator(renderer), envRT = pmrem.fromScene(envS, 0.04); pmrem.dispose(); disp.push(envRT); envS.traverse(o => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });
      // 단면 곡선(안쪽으로 들어간 거리 d, 높이 y): 바닥 모서리 둥글림, 살짝 벌어지는 벽, 말린 테두리, 안쪽 벽
      const prof = []; const addP = (d, y) => prof.push([d, y]);
      for (let k = 0; k <= 8; k++) { const a = k / 8 * Math.PI / 2; addP(0.112 + 0.05 * (1 - Math.sin(a)), 0.06 * (1 - Math.cos(a))); }   // 바닥 가장자리 둥글림
      for (let k = 1; k <= 14; k++) { const t = k / 14; addP(0.1 * Math.pow(1 - t, 1.3) + 0.012, 0.06 + t * 0.46); }                                                                             // 벽: 위로 갈수록 벌어진다
      for (let k = 0; k <= 12; k++) { const a = Math.PI - k / 12 * Math.PI; addP(0.057 + 0.047 * Math.cos(a), 0.554 + 0.047 * Math.sin(a)); }                                                         // 둥글게 말린 테두리
      for (let k = 1; k <= 4; k++) addP(0.104 + 0.01 * k, 0.554 - 0.01 * k * 1.4);                                                                                                                  // 안쪽 벽(두께가 보인다)
      addP(0.13, 0.5);
      const per = 44, ringPts = (sx, sz, r) => { const out = [], cs = [[sx - r, sz - r, 0], [-(sx - r), sz - r, 1], [-(sx - r), -(sz - r), 2], [sx - r, -(sz - r), 3]]; for (const [cx, cz, q] of cs) for (let k = 0; k < 11; k++) { const a = (q + k / 10) * Math.PI / 2; out.push([cx + Math.cos(a) * r, cz + Math.sin(a) * r]); } return out; };
      const P = [], Cc = [], I = [];
      prof.forEach(([d, y]) => { const r = clamp(0.17 - d * 0.7, 0.05, 0.17); ringPts(X - d, Z - d, r).forEach(([x, z]) => { P.push(x, y, z); const nz = 0.5 + 0.5 * Math.sin(x * 9 + z * 7) * Math.sin(z * 11 - x * 5), g = (0.78 + 0.42 * clamp(y / 0.5, 0, 1)) * (0.9 + 0.2 * nz); Cc.push(g, g, g * 1.04); }); });
      for (let a = 0; a < prof.length - 1; a++) for (let k = 0; k < per; k++) { const k2 = (k + 1) % per, a0 = a * per + k, a1 = a * per + k2, b0 = (a + 1) * per + k, b1 = (a + 1) * per + k2; I.push(a0, a1, b0, a1, b1, b0); }
      const cb = P.length / 3; P.push(0, 0, 0); Cc.push(0.8, 0.8, 0.8); for (let k = 0; k < per; k++) I.push(cb, k, (k + 1) % per);
      const ct = P.length / 3; P.push(0, 0.5, 0); Cc.push(0.8, 0.8, 0.8); const lr = (prof.length - 1) * per; for (let k = 0; k < per; k++) I.push(ct, lr + (k + 1) % per, lr + k);
      const pg = own(new THREE.BufferGeometry()); pg.setAttribute('position', new THREE.BufferAttribute(new Float32Array(P), 3)); pg.setAttribute('color', new THREE.BufferAttribute(new Float32Array(Cc), 3)); pg.setIndex(I); pg.computeVertexNormals();
      potG.add(new THREE.Mesh(pg, own(new THREE.MeshPhysicalMaterial({ color: '#121212', roughness: 0.18, clearcoat: 1, clearcoatRoughness: 0.1, envMap: envRT.texture, envMapIntensity: 1.5, vertexColors: true, side: THREE.DoubleSide }))));
      // 발: 통통하고 살짝 둥근 무광 점토(아주 작은 흠집)
      const footG = own(new THREE.SphereGeometry(1, 22, 14)); { const p3 = footG.attributes.position, v = new THREE.Vector3(); for (let q = 0; q < p3.count; q++) { v.fromBufferAttribute(p3, q); const f = a => Math.sign(a) * Math.pow(Math.abs(a), 0.42); p3.setXYZ(q, f(v.x) * 0.11, f(v.y) * 0.035, f(v.z) * 0.08); } footG.computeVertexNormals(); }
      const footM = own(new THREE.MeshStandardMaterial({ color: '#E8E0D2', roughness: 0.95, bumpMap: null }));
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) { const f = new THREE.Mesh(footG, footM); f.position.set(sx * (X - 0.32), -0.02, sz * (Z - 0.2)); potG.add(f); }
      // 화산석: 노이즈로 울퉁불퉁하게 일그러뜨린 매끈한 돌 4 종류(구멍 많은 질감), 아래쪽일수록 어둡게
      const hash = (x, y, z) => { const h = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453; return h - Math.floor(h); };
      const vn = (x, y, z) => { const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z), fx = x - ix, fy = y - iy, fz = z - iz, u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy), w = fz * fz * (3 - 2 * fz), L = (a, b, t) => a + (b - a) * t;
        return L(L(L(hash(ix, iy, iz), hash(ix + 1, iy, iz), u), L(hash(ix, iy + 1, iz), hash(ix + 1, iy + 1, iz), u), v), L(L(hash(ix, iy, iz + 1), hash(ix + 1, iy, iz + 1), u), L(hash(ix, iy + 1, iz + 1), hash(ix + 1, iy + 1, iz + 1), u), v), w); };
      const rockGeo = seed => { const g = new THREE.SphereGeometry(1, 10, 7), p3 = g.attributes.position, v = new THREE.Vector3(), flat = 0.55 + 0.4 * hash(seed, 1, 2), sx = 0.85 + 0.35 * hash(seed, 3, 4);
        for (let q = 0; q < p3.count; q++) { v.fromBufferAttribute(p3, q); const n = vn(v.x * 1.6 + seed * 7, v.y * 1.6, v.z * 1.6) * 0.6 + vn(v.x * 3.7 + seed, v.y * 3.7, v.z * 3.7) * 0.3 + vn(v.x * 8 + seed, v.y * 8, v.z * 8) * 0.1, r = 0.68 + 0.6 * n; p3.setXYZ(q, v.x * r * sx, v.y * r * flat, v.z * r); }
        g.computeVertexNormals(); const N = g.attributes.normal, map = new Map(); for (let q = 0; q < p3.count; q++) { const k = p3.getX(q).toFixed(4) + p3.getY(q).toFixed(4) + p3.getZ(q).toFixed(4); (map.get(k) || map.set(k, []).get(k)).push(q); }
        map.forEach(a => { if (a.length > 1) { v.set(0, 0, 0); a.forEach(q => v.add(new THREE.Vector3().fromBufferAttribute(N, q))); v.normalize(); a.forEach(q => N.setXYZ(q, v.x, v.y, v.z)); } }); own(g); return g; };
      const rc = document.createElement('canvas'); rc.width = rc.height = 128; { const g = rc.getContext('2d'); g.fillStyle = '#9a9a9a'; g.fillRect(0, 0, 128, 128); for (let q = 0; q < 2600; q++) { const x = rnd() * 128, y = rnd() * 128, r = 0.6 + rnd() * 2.2, v = rnd() < 0.7 ? 20 + rnd() * 40 : 170 + rnd() * 70; g.fillStyle = `rgba(${v},${v},${v},${0.35 + rnd() * 0.5})`; g.beginPath(); g.arc(x, y, r, 0, 6.2832); g.fill(); } }
      const rtex = own(new THREE.CanvasTexture(rc)); rtex.wrapS = rtex.wrapT = THREE.RepeatWrapping;
      const rockM = own(new THREE.MeshStandardMaterial({ color: '#FFFFFF', roughness: 1, metalness: 0, bumpMap: rtex, bumpScale: 0.5, envMapIntensity: 0 }));
      const slab = new THREE.Mesh(own(new THREE.BoxGeometry(2 * (X - 0.09), 0.06, 2 * (Z - 0.09))), own(new THREE.MeshStandardMaterial({ color: '#0E0E10', roughness: 1 }))); slab.position.y = 0.51; potG.add(slab);
      const TONE = ['#2B2B2D', '#333336', '#3E3D40', '#4A4948', '#5A5754'], KV = 4, NV = 450, d = new THREE.Object3D();
      for (let kv = 0; kv < KV; kv++) {
        const mm = new THREE.InstancedMesh(rockGeo(kv + 1), rockM, NV);
        for (let q = 0; q < NV; q++) {
          const x = (rnd() * 2 - 1) * (X - 0.14), z = (rnd() * 2 - 1) * (Z - 0.14), hh = 0.2 * Math.exp(-((x - 0.45) * (x - 0.45) / 0.55 + z * z / 0.1)) + 0.03, big = rnd() < 0.18, s = (big ? 0.055 + 0.045 * rnd() : 0.026 + 0.034 * rnd() * rnd() + 0.014);
          const layer = rnd(), y = 0.52 + hh * (0.25 + 0.75 * Math.sqrt(layer)) + s * 0.1, ao = clamp(0.5 + 0.7 * ((y - 0.52) / 0.24), 0.45, 1.05);
          d.position.set(x, y, z); d.rotation.set(rnd() * 6, rnd() * 6, rnd() * 6); d.scale.set(s * (0.85 + 0.5 * rnd()), s * (0.7 + 0.4 * rnd()), s * (0.85 + 0.5 * rnd())); d.updateMatrix(); mm.setMatrixAt(q, d.matrix);
          const c = new THREE.Color(rnd() < 0.05 ? '#5A3F32' : rnd() < 0.08 ? '#6A6866' : TONE[Math.floor(rnd() * 5)]); c.multiplyScalar(ao * (0.9 + 0.2 * rnd())); mm.setColorAt(q, c);
        }
        mm.instanceMatrix.needsUpdate = true; mm.instanceColor.needsUpdate = true; mm.frustumCulled = false; potG.add(mm); disp.push({ dispose: () => mm.dispose() });
      } }

    // ---- DOM: 라벨 ----
    const labs = [], mctx = document.createElement('canvas').getContext('2d'); let used = 0;
    const label = (txt, x, y, al, cls, sz, o = {}) => {
      let el = labs[used++];
      if (!el) { el = document.createElement('div'); el._t = ''; el._v = 0; main.appendChild(el); labs.push(el); }
      if (el._k !== cls) { el._k = cls; el.style.cssText = `position:absolute;left:0;top:0;z-index:4;pointer-events:none;white-space:nowrap;font-family:${FONT};font-weight:${cls === 'n' ? 400 : 600};color:${BROWN};text-shadow:0 0 5px rgba(246,245,244,.95),0 0 2px rgba(246,245,244,.9);will-change:transform`; el._sz = 0; }
      if (el._sz !== sz) { el._sz = sz; el.style.fontSize = sz + 'px'; }
      if (el._t !== txt) { el._t = txt; el.textContent = txt; }
      el.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) translate(${o.mid ? '-50%' : o.right ? '-100%' : '0'},-50%)`;
      el.style.opacity = al; if (!el._v) { el._v = 1; el.style.display = ''; }
    };

    // ---- 시점, 입력 ----
    let W = 1, H = 1, base = 3.9;
    const view = { yaw: 0.25, pitch: 0.1, zoom: 1, dragging: false, hold: false }, ZMIN = 0.35, ZMAX = 1.8;
    let vy = 0.0012, vp = 0, drag = null, moved = 0, mouse = null, hover = null, raf = 0, last = 0;
    const size = () => { const r = main.getBoundingClientRect(); W = Math.max(1, r.width); H = Math.max(1, r.height); renderer.setSize(W, H, false); camera.aspect = W / H; camera.updateProjectionMatrix(); base = 3.9 * Math.max(1, 1.05 * H / W); mesh?.size(W, H); };
    const ro = new ResizeObserver(size); ro.observe(main); size();
    const tv = new THREE.Vector3(), tw = new THREE.Vector3();
    const pos = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const scr = (v, o) => { tw.copy(v).project(camera); o.x = (tw.x * 0.5 + 0.5) * W; o.y = (-tw.y * 0.5 + 0.5) * H; return o; };
    const pick = (x, y) => { let b = null, bd = 1e9; for (const s of subs) { const d = Math.hypot(x - s.sx, y - s.sy); if (d < s.rr && d < bd) { bd = d; b = s; } } return b; };
    cv.addEventListener('pointerdown', e => { drag = pos(e); moved = 0; view.dragging = true; cv.setPointerCapture(e.pointerId); cv.style.cursor = 'grabbing'; });
    cv.addEventListener('pointermove', e => { const p = pos(e); mouse = p; if (!drag) return; const dx = p.x - drag.x, dy = p.y - drag.y; moved += Math.abs(dx) + Math.abs(dy); vy = dx * 0.006; vp = dy * 0.006; view.yaw += vy; view.pitch = clamp(view.pitch + vp, -1.0, 1.2); drag = p; });
    const up = e => { if (drag && moved < 4) { const p = pos(e), s = pick(p.x, p.y); if (s) ui.open(s.t.id); } drag = null; view.dragging = false; cv.style.cursor = 'grab'; };
    cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
    cv.addEventListener('pointerleave', () => { if (!drag) mouse = null; });
    cv.addEventListener('wheel', e => { e.preventDefault(); view.zoom = clamp(view.zoom * Math.exp(e.deltaY * 0.0015), ZMIN, ZMAX); }, { passive: false });

    // ---- 매 프레임 ----
    const sp = { x: 0, y: 0 }, c3 = new THREE.Vector3(), startT = performance.now(), cwork = new THREE.Color();
    const easeBack = x => { x = clamp(x, 0, 1); const c1 = 1.70158, c3_ = c1 + 1; return 1 + c3_ * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); };
    const frame = t => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (t - (last || t)) / 1000) * 60 || 1; last = t;
      const age = (performance.now() - startT) / 1000;   // 열린 뒤 지난 초
      if (!drag && !view.hold) { vy += (0.0012 - vy) * 0.04 * dt; vp *= Math.pow(0.92, dt); view.yaw += vy * dt; view.pitch = clamp(view.pitch + vp * dt, -1.0, 1.2); }
      const D = base * view.zoom;
      camera.position.set(0, 1.22, D); group.rotation.set(view.pitch, view.yaw, 0, 'XYZ');
      // 자라나는 연출: 줄기가 위로 자라고(통통 튀며), 가지와 잎 다발은 차례로 터져 나온다
      const eg = easeBack(age / 1.1), sy = 0.04 + 0.96 * eg, sxz = 0.8 + 0.2 * clamp(eg, 0, 1.05);
      treeG.scale.set(sxz, sy, sxz);
      group.updateMatrixWorld(true); camera.updateMatrixWorld();
      for (const s of subs) {
        const hot = hover === s; s.tb = hover ? (hot ? 1.2 : 0.62) : 1; const k = 0.2 * dt; s.b += (s.tb - s.b) * k; s.hs += ((hot ? 1.22 : 1) - s.hs) * k;
        const pop = easeBack((age - s.delay) / 0.55), pc = V(s.c.x * sxz, BY + (s.c.y - BY) * sy, s.c.z * sxz), br = 1 + 0.05 * Math.sin(t / 900 + s.ph), dm = clamp((s.b - 0.4) / 0.6, 0.3, 1);   // 숨 쉬듯 부풀었다 줄어든다
        s.pc = pc; s.pop = clamp(pop, 0, 1); const pp = Math.max(0.0001, pop), sw = s.hs * br * pp;
        for (let q = 0; q < s.np; q++) { const o = s.off[q], kk = s.p0 + q, ph = s.ph + q; dPos[kk * 3] = pc.x + o.x * sw + Math.sin(t / 1300 + ph) * 0.006; dPos[kk * 3 + 1] = pc.y + o.y * sw + Math.sin(t / 1100 + ph * 1.3) * 0.005; dPos[kk * 3 + 2] = pc.z + o.z * sw; dDim[kk] = dm * clamp(pop * 1.6, 0, 1); }
        c3.copy(pc).applyMatrix4(group.matrixWorld); scr(c3, sp); s.sx = sp.x; s.sy = sp.y; c3.x += s.rs * 1.1; scr(c3, sp); s.rr = Math.hypot(sp.x - s.sx, sp.y - s.sy) + 4;
      }
      for (const s of subs) s.dz = camera.position.distanceTo(s.pc); sorted.sort((a, b) => b.dz - a.dz); { let k = 0; for (const s of sorted) for (let q = 0; q < s.np; q++) dIdx[k++] = s.p0 + q; }
      posA.needsUpdate = dimA.needsUpdate = idxA.needsUpdate = true;
      dotU.uPx.value = renderer.getPixelRatio(); dotU.uSc.value = Math.min(W, H) / 700; dotU.uD.value = D; dotU.uBase.value = base;
      sparkSubs.forEach((s, i) => { for (let q = 0; q < 3; q++) { const a = t / 1600 + q * 2.1 + s.ph, o = (i * 3 + q) * 3; sparkP[o] = s.pc.x + Math.cos(a) * s.rs * 0.8 * s.pop; sparkP[o + 1] = s.pc.y + s.rs * (0.55 + 0.25 * Math.sin(a * 1.7)) * s.pop - (1 - s.pop) * 3; sparkP[o + 2] = s.pc.z + Math.sin(a) * s.rs * 0.8 * s.pop; } });
      sg.attributes.position.needsUpdate = true; sparkM.opacity = 0.55 + 0.4 * Math.sin(t / 500);
      hover = mouse && !drag ? pick(mouse.x, mouse.y) : null; view.hold = !!hover;
      cv.style.cursor = hover ? 'pointer' : drag ? 'grabbing' : 'grab';
      mesh?.draw(t); renderer.render(scene, camera);

      // 라벨: "나" 는 줄기 밑동, 분야 이름은 그 패드 위(겹치면 위로 올린다), 성장 단계는 화분 앞, 업무 이름은 가리킬 때만
      used = 0; const boxes = [], wOf = (txt, sz, w) => { mctx.font = `${w} ${sz}px ${FONT}`; return mctx.measureText(txt).width + 6; };
      const hit = (x, y, w, h) => boxes.some(b => x < b[0] + b[2] + 2 && x + w > b[0] - 2 && y < b[1] + b[3] + 1 && y + h > b[1] - 1);
      c3.copy(TRUNK[0]).applyMatrix4(group.matrixWorld); scr(c3, sp); label('나', sp.x + 44, sp.y - 6, 1, 'g', 15, { mid: true }); boxes.push([sp.x + 44 - 14, sp.y - 16, 28, 20]);

      for (const g of gs) {
        c3.set(g.pad.x * sxz, BY + (g.pad.y + g.ry * 1.1 + 0.1 - BY) * sy, g.pad.z * sxz).applyMatrix4(group.matrixWorld); scr(c3, sp);
        const w = wOf(g.name, 14, 600), h = 22; let y = sp.y - 8; for (let tries = 0; tries < 5 && hit(sp.x - w / 2, y - h / 2, w, h); tries++) y -= 24;
        y = clamp(y, 14, H - 14); boxes.push([sp.x - w / 2, y - h / 2, w, h]); label(g.name, clamp(sp.x, w / 2 + 6, W - w / 2 - 6), y, (!hover || hover.g === g ? 1 : 0.5) * clamp((age - 0.8) / 0.4, 0, 1), 'g', 14, { mid: true });
      }
      if (hover) label(hover.t.title, Math.min(W - 60, hover.sx + hover.rr + 6), hover.sy - 4, 1, 'h', 12.5);
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

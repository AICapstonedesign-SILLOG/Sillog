/* 입체 군집: 가운데 "나" → 분야(상위) → 업무(하위) → 세션과 자료(그 아래) 로 퍼지는 방사형 위계.
   층 사이는 허리가 잘록한 묶음 곡선으로 잇고, 분야 가지는 하나의 덩어리로 자기 기울어진 궤도를 따로 돌아 서로 앞뒤로 교차한다 */
window.V3D = window.V3D || {};
window.V3D.cluster = function (main, data, ui) {
  const FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
  // 실록 브랜드 색만: 흰색, 고동색, 연한 파랑, 회색 (분야 구분은 밝기 단계와 이름표)
  const PAL = [[255, 255, 255], [246, 245, 244], [226, 225, 223], [206, 204, 201], [184, 181, 177], [160, 155, 149]];
  const WARM = [246, 245, 244], BROWN = [36, 21, 15], GRAY = [115, 109, 104], GRAY2 = [156, 150, 144], SKY = [180, 208, 228];
  const hash = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rng = seed => () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const gauss = r => Math.sqrt(-2 * Math.log(r() + 1e-9)) * Math.cos(6.2832 * r());
  const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
  const lerpC = (a, b, u) => a.map((v, i) => Math.round(v + (b[i] - v) * u));
  const norm = v => { const l = Math.hypot(...v) || 1; return v.map(x => x / l); };
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

  const tasks = data.tasks.filter(t => data.themes.some(h => h.id === t.theme));
  const themes = data.themes.filter(th => tasks.some(t => t.theme === th.id));

  // 점 (가지 안 좌표). 0번 = 가운데 "나"
  const PX = [], PY = [], PZ = [], PR = [], PK = [], PT = [], PS = [];   // PK: 3 나, 4 분야, 2 업무, 1 자료/세션, 0 장식, -1 공 중심(안 그림)
  const addPt = (x, y, z, rad, k, t, s) => { PX.push(x); PY.push(y); PZ.push(z); PR.push(rad); PK.push(k); PT.push(t); PS.push(s); return PX.length - 1; };
  addPt(0, 0, 0, 12, 3, null, -1);
  const subs = [], balls = [], taskPts = [], hubPts = [];
  const NT = themes.length;
  themes.forEach((th, hi) => {
    const ts = tasks.filter(t => t.theme === th.id), r = rng(hash(th.id + hi)), col = PAL[hi % PAL.length];
    let ax = norm([gauss(r), gauss(r), gauss(r)]);
    const sub = { col, name: th.name, ax, th0: r() * 6.2832, om: (r() < 0.5 ? -1 : 1) * 6.2832 / (40000 + r() * 50000), bph: r() * 6.2832, bom: 6.2832 / (18000 + r() * 22000), p0: PX.length, hub: 0, tasks: [], M: [1, 0, 0, 0, 1, 0, 0, 0, 1], sc: 1 };
    const yy = NT > 1 ? 1 - 2 * (hi + 0.5) / NT : 0, rr = Math.sqrt(1 - yy * yy), aa = hi * 2.39996;
    const d = [rr * Math.cos(aa), yy, rr * Math.sin(aa)];
    const hp = Math.abs(d[1]) > 0.9 ? [1, 0, 0] : [0, 1, 0], u = norm(cross(d, hp)), w = cross(d, u);
    sub.hub = addPt(d[0] * 0.32, d[1] * 0.32, d[2] * 0.32, 12, 4, null, subs.length); hubPts.push(sub.hub);
    const n = ts.length, cone = Math.min(0.95, 0.3 + 0.12 * Math.sqrt(n));
    ts.forEach((t, k) => {
      const ph = cone * Math.sqrt((k + 0.5) / n), az = k * 2.39996 + r() * 0.3;
      const dir = norm([0, 1, 2].map(a => d[a] * Math.cos(ph) + (u[a] * Math.cos(az) + w[a] * Math.sin(az)) * Math.sin(ph)));
      const rt = 0.62 + (r() - 0.5) * 0.05;
      const tp = addPt(dir[0] * rt, dir[1] * rt, dir[2] * rt, 4 + Math.min(2.6, Math.sqrt(t.mins || 0) * 0.1), 2, t, subs.length);
      taskPts.push(tp); sub.tasks.push(tp);
      const kids = (t.sessions || []).length + Object.values(t.items || {}).reduce((a, b) => a + (b || []).length, 0);
      const nd = Math.min(28, Math.max(12, Math.min(kids, 16) + 8)), R3 = 0.045 + 0.011 * Math.sqrt(nd);
      const bc = addPt(dir[0] * 0.93, dir[1] * 0.93, dir[2] * 0.93, 0, -1, t, subs.length);
      const b = { i0: bc + 1, ci: bc, col, tp, task: t, e: null };
      for (let m = 0; m < nd; m++) {
        let q; do { q = [gauss(r), gauss(r), gauss(r)]; } while (Math.hypot(...q) > 2);
        addPt(PX[bc] + q[0] * R3 / 1.4, PY[bc] + q[1] * R3 / 1.4, PZ[bc] + q[2] * R3 / 1.4, m < Math.min(kids, 16) ? 1.3 + r() : 1 + r() * 1.2, m < Math.min(kids, 16) ? 1 : 0, t, subs.length);
      }
      b.i1 = PX.length;
      balls.push(b);
    });
    sub.p1 = PX.length; subs.push(sub);
  });
  const NN = PX.length;
  const WX = new Float32Array(NN), WY = new Float32Array(NN), WZ = new Float32Array(NN);
  const SX = new Float32Array(NN), SY = new Float32Array(NN), SD = new Float32Array(NN), SS = new Float32Array(NN);
  const taskBall = {}; balls.forEach(b => { taskBall[b.tp] = b; });

  // 가지마다 자기 축으로 돌고 반지름이 숨 쉰다 (가지 전체가 한 덩어리)
  const setWorld = t => {
    subs.forEach(s => {
      const th = s.th0 + s.om * t, co = Math.cos(th), si = Math.sin(th), k = s.ax, c1 = 1 - co, sc = 1 + 0.06 * Math.sin(s.bph + s.bom * t);
      const M = s.M;
      M[0] = co + k[0] * k[0] * c1; M[1] = k[0] * k[1] * c1 - k[2] * si; M[2] = k[0] * k[2] * c1 + k[1] * si;
      M[3] = k[1] * k[0] * c1 + k[2] * si; M[4] = co + k[1] * k[1] * c1; M[5] = k[1] * k[2] * c1 - k[0] * si;
      M[6] = k[2] * k[0] * c1 - k[1] * si; M[7] = k[2] * k[1] * c1 + k[0] * si; M[8] = co + k[2] * k[2] * c1;
      for (let i = s.p0; i < s.p1; i++) {
        const x = PX[i] * sc, y = PY[i] * sc, z = PZ[i] * sc;
        WX[i] = M[0] * x + M[1] * y + M[2] * z; WY[i] = M[3] * x + M[4] * y + M[5] * z; WZ[i] = M[6] * x + M[7] * y + M[8] * z;
      }
    });
  };

  // 묶음: 한쪽 후보 점들 → 허리 → 반대쪽 후보 점들
  const H = 5, bundles = [];
  const mkB = (ra, rb, candA, candB, K, jA, jB, ca, cb, al, lw, tk, seedKey, off) => {
    const r = rng(hash(seedKey)), ea = new Uint16Array(K), eb = new Uint16Array(K), ja = new Float32Array(K * 3), jb = new Float32Array(K * 3), jw = new Float32Array(K * 3);
    for (let s = 0; s < K; s++) {
      ea[s] = candA[Math.floor(r() * candA.length)]; eb[s] = candB[Math.floor(r() * candB.length)];
      for (let m = 0; m < 3; m++) { ja[s * 3 + m] = gauss(r) * jA; jb[s * 3 + m] = gauss(r) * jB; jw[s * 3 + m] = (r() - 0.5) * 0.022; }
    }
    bundles.push({ ra, rb, K, ea, eb, ja, jb, jw, ca, cb, al, lw, tk, t0: 0.5, off: off || 0, sw: (hash('w' + seedKey) % 100 - 50) / 700, d: 0 });
  };
    subs.forEach((s, si) => {
    mkB(0, s.hub, [0], [s.hub], 12, 0.01, 0.025, WARM, s.col, 0.3, 3.0, null, 'c' + si, (hash('q' + si) % 100 - 50) / 450);
    s.tasks.forEach(tp => {
      const b = taskBall[tp];
      mkB(s.hub, tp, [s.hub], [tp], 5, 0.012, 0.01, s.col, s.col, 0.3, 1.8, tp, 'h' + tp, (hash('o' + tp) % 100 - 50) / 380);
      const cand = []; for (let i = b.i0; i < b.i1; i++) cand.push(i);
      mkB(tp, b.ci, [tp], cand, 5, 0.006, 0.01, s.col, s.col, 0.3, 1.0, tp, 'b' + tp, (hash('p' + tp) % 100 - 50) / 500);
    });
  });
  const bigTitles = new Set(taskPts.slice().sort((a, b) => (PT[b].mins || 0) - (PT[a].mins || 0)).slice(0, 6));

  const pc = document.createElement('canvas'); pc.width = pc.height = 22;
  const pcx = pc.getContext('2d'); pcx.fillStyle = 'rgba(255,255,255,0.05)'; pcx.fillRect(10, 10, 2, 2);

  // 그리는 차례 목록: 공, 묶음, 점(나, 분야, 업무)
  const items = [];
  balls.forEach(b => items.push({ b, d: 0 }));
  bundles.forEach(b => items.push({ w: b, d: 0 }));
  items.push({ n: 0, d: 0 }); hubPts.forEach(h => items.push({ n: h, d: 0 })); taskPts.forEach(h => items.push({ n: h, d: 0 }));

  const TX = new Float32Array(32 * (2 * H + 1)), TY = new Float32Array(32 * (2 * H + 1));
  let pat = null, hover = null, inited = false, cursorEl = null;
  const g = window.G3D(main, (ctx, v, t) => {
    if (!inited) { inited = true; v.zoom = 0.95; cursorEl = main.querySelector('canvas'); }
    setWorld(t);
    const cyw = Math.cos(v.yaw), syw = Math.sin(v.yaw), cp = Math.cos(v.pitch), sp = Math.sin(v.pitch);
    const R = Math.min(v.w, v.h) * 0.4 * v.zoom, W2 = v.w / 2, H2 = v.h / 2;
    let ox = 0, oy = 0, od = 0, os = 0;
    const pr = (px, py, pz) => {
      const x = px * cyw - pz * syw, z1 = px * syw + pz * cyw, y = py * cp - z1 * sp, z = py * sp + z1 * cp;
      os = v.dist / (v.dist + z); ox = W2 + x * os * R; oy = H2 + y * os * R; od = (1 - z) / 2;
    };
    ctx.globalCompositeOperation = 'source-over';
    window.G3D.glass(ctx, v);
    ctx.fillStyle = pat || (pat = ctx.createPattern(pc, 'repeat')); ctx.fillRect(0, 0, v.w, v.h);
    for (let i = 0; i < NN; i++) { pr(WX[i], WY[i], WZ[i]); SX[i] = ox; SY[i] = oy; SD[i] = od; SS[i] = Math.pow(os, 1.5); }
    const fadeOf = d => 0.12 + 0.88 * Math.max(0, Math.min(1, (d - 0.05) / 0.6));
    hover = null;
    if (v.mouse && !v.dragging) {
      let best = 14;
      taskPts.forEach(i => { const d = Math.hypot(SX[i] - v.mouse.x, SY[i] - v.mouse.y); if (d < best) { best = d; hover = i; } });
    }
    const dim = hover != null ? 0.4 : 1;
    ctx.lineCap = 'round';
    const drawBundle = b => {
      const hot = hover != null && b.tk === hover, f = fadeOf((SD[b.ra] + SD[b.rb]) / 2) * (hover == null ? 1 : hot ? 2.2 : dim);
      const ax0 = WX[b.ra], ay0 = WY[b.ra], az0 = WZ[b.ra];
      const dx = WX[b.rb] - ax0, dy = WY[b.rb] - ay0, dz = WZ[b.rb] - az0;
      const dl = Math.hypot(dx, dy, dz) || 1e-3, ux = dx / dl, uy = dy / dl, uz = dz / dl;
      const Wx = ax0 + dx * b.t0 - uy * b.off, Wy = ay0 + dy * b.t0 + ux * b.off, Wz = az0 + dz * b.t0;
      ctx.lineCap = 'butt'; ctx.lineJoin = 'round';
      const NP = 2 * H + 1, K = b.K;
      for (let s = 0; s < K; s++) {
        const a = b.ea[s], e = b.eb[s];
        const wx = Wx + b.jw[s * 3], wy = Wy + b.jw[s * 3 + 1], wz = Wz + b.jw[s * 3 + 2];
        const p0x = WX[a] + b.ja[s * 3], p0y = WY[a] + b.ja[s * 3 + 1], p0z = WZ[a] + b.ja[s * 3 + 2], p3x = WX[e] + b.jb[s * 3], p3y = WY[e] + b.jb[s * 3 + 1], p3z = WZ[e] + b.jb[s * 3 + 2];
        const la = Math.hypot(p0x - wx, p0y - wy, p0z - wz) * 0.5, lb = Math.hypot(p3x - wx, p3y - wy, p3z - wz) * 0.5;
        for (let half = 0; half < 2; half++) {
          const sg = half ? -b.sw : b.sw, cx1 = (half ? wx + ux * lb : wx - ux * la) - uy * sg, cy1 = (half ? wy + uy * lb : wy - uy * la) + ux * sg, cz1 = half ? wz + uz * lb : wz - uz * la;
          const sx = half ? wx : p0x, sy = half ? wy : p0y, sz = half ? wz : p0z, ex = half ? p3x : wx, ey = half ? p3y : wy, ez = half ? p3z : wz;
          for (let m = half; m <= H; m++) {
            const u = m / H, w = 1 - u, f0 = w * w, f1 = 2 * w * u, f2 = u * u;
            pr(f0 * sx + f1 * cx1 + f2 * ex, f0 * sy + f1 * cy1 + f2 * ey, f0 * sz + f1 * cz1 + f2 * ez);
            TX[s * NP + half * H + m] = ox; TY[s * NP + half * H + m] = oy;
          }
        }
      }
      const dp = 0.35 + 0.9 * (SS[b.ra] + SS[b.rb]) / 2, Gn = b.lw > 1.5 ? 10 : 5, sg2 = 10 / Gn;
      ctx.beginPath();      // 번진 가장자리: 한 줄 한 번에 그려 이음새가 겹쳐 짙어지지 않는다
      for (let s = 0; s < K; s++) { ctx.moveTo(TX[s * NP], TY[s * NP]); for (let q = 1; q < NP; q++) ctx.lineTo(TX[s * NP + q], TY[s * NP + q]); }
      ctx.strokeStyle = rgba(lerpC(GRAY, GRAY2, Math.max(0, Math.min(1, 1 - f))), 0.16 * (0.35 + 0.65 * f)); ctx.lineWidth = b.lw * dp * 1.3 + 1.2; ctx.stroke();
      for (let gi = 0; gi < Gn; gi++) {      // 굵고 짙은 쪽에서 가늘고 옅은 쪽으로 이어서 줄어든다
        const tt = (gi + 0.5) / Gn;
        ctx.beginPath();
        for (let s = 0; s < K; s++) { const o = s * NP + sg2 * gi; ctx.moveTo(TX[o], TY[o]); for (let q = 1; q <= sg2; q++) ctx.lineTo(TX[o + q], TY[o + q]); }
        const cc = lerpC(lerpC(BROWN, GRAY, tt), GRAY2, Math.max(0, Math.min(1, 1 - f))), al = (0.5 - 0.22 * tt) * (0.35 + 0.65 * f), lw = b.lw * dp * (1 - 0.65 * tt);
        ctx.strokeStyle = rgba(cc, al); ctx.lineWidth = lw; ctx.stroke();
      }
    };
    const drawBall = b => {
      const f = fadeOf(SD[b.ci]), hot = hover != null && b.tp === hover, k = hover == null ? 1 : hot ? 1 : dim;
      ctx.beginPath();      // 실제 세션과 자료: 흰 점
      for (let i = b.i0; i < b.i1; i++) if (PK[i] === 1) { const r = PR[i] * SS[i]; ctx.moveTo(SX[i] + r, SY[i]); ctx.arc(SX[i], SY[i], r, 0, 6.2832); }
      ctx.fillStyle = hot ? '#fff' : rgba([255, 255, 255], 0.95 * f * k); ctx.fill();
      ctx.beginPath();      // 장식: 회색 잔뿌리
      for (let i = b.i0; i < b.i1; i++) if (PK[i] === 0) { const r = PR[i] * SS[i]; ctx.moveTo(SX[i] + r, SY[i]); ctx.arc(SX[i], SY[i], r, 0, 6.2832); }
      ctx.fillStyle = rgba(hot ? WARM : [226, 222, 217], 0.85 * f * k); ctx.fill();
    };
    const drawNode = i => {
      const k = PK[i], f = fadeOf(SD[i]), r = PR[i] * SS[i] * Math.min(1.5, Math.max(0.8, v.zoom)), x = SX[i], y = SY[i];
      if (k === 3) {
        const gr = ctx.createRadialGradient(x, y, 0, x, y, r * 3.2);
        gr.addColorStop(0, rgba(WARM, 0.6)); gr.addColorStop(1, rgba(WARM, 0));
        ctx.fillStyle = gr; ctx.beginPath(); ctx.arc(x, y, r * 3.2, 0, 6.2832); ctx.fill();
        ctx.fillStyle = rgba(WARM, 1); ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832); ctx.fill();
      } else {
        const hot = i === hover, a = Math.min(1, f + (hover == null ? 0 : hot ? 1 : -0.1));
        ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832); ctx.fillStyle = hot ? '#fff' : rgba(k === 4 ? [255, 255, 255] : lerpC([255, 255, 255], SKY, 0.6), 0.97 * a); ctx.fill();
      }
    };
    items.forEach(it => { it.d = it.b ? SD[it.b.ci] : it.w ? Math.min(SD[it.w.ra], SD[it.w.rb]) - 0.002 : SD[it.n] + 0.001; });
    items.sort((a, b) => a.d - b.d);
    items.forEach(it => {
      if (it.w) { ctx.globalCompositeOperation = 'source-over'; drawBundle(it.w); return; }
      ctx.globalCompositeOperation = 'source-over';
      it.b ? drawBall(it.b) : drawNode(it.n);
    });
    ctx.globalCompositeOperation = 'source-over';
    // 이름표: 나, {분야}, 큰 업무 몇 개, 가리킨 업무
    ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    const placed = [];
    const tag = (s, x, y, fnt, a, sc, force) => {
      ctx.font = fnt.replace(/(\d+)px/, (m, n) => Math.max(9, Math.round(n * Math.min(1.25, sc))) + 'px');
      const w = ctx.measureText(s).width + 8, rc = [x - 4, y - 9, x - 4 + w, y + 9];
      if (!force && placed.some(q => rc[0] < q[2] && rc[2] > q[0] && rc[1] < q[3] && rc[3] > q[1])) return;
      placed.push(rc);
      ctx.fillStyle = 'rgba(36,21,15,0.62)'; ctx.fillRect(rc[0], rc[1], w, 18);
      ctx.fillStyle = `rgba(246,245,244,${a})`; ctx.fillText(s, x, y);
    };
    tag('나', SX[0] + PR[0] * SS[0] * 1.3 + 4, SY[0], `600 13px ${FONT}`, 1, SS[0], true);
    hubPts.forEach(h => tag(`{${subs[PS[h]].name}}`, SX[h] + PR[h] * SS[h] + 6, SY[h], '12px ui-monospace, Menlo, monospace', 0.4 + 0.6 * fadeOf(SD[h]), SS[h], true));
    const tl = i => { const s0 = PT[i].title, s = s0.length > 30 ? s0.slice(0, 30) + '…' : s0; tag(s, SX[i] + PR[i] * SS[i] + 6, SY[i], `${i === hover ? 600 : 500} 12px ${FONT}`, i === hover ? 1 : 0.8, SS[i], i === hover); };
    if (hover != null) tl(hover);
    let shown = 0;
    taskPts.slice().sort((a, b) => (PT[b].mins || 0) - (PT[a].mins || 0)).forEach(i => { if (i !== hover && shown < 3 && SD[i] > 0.4) { const n = placed.length; tl(i); if (placed.length > n) shown++; } });
    if (cursorEl && !v.dragging) cursorEl.style.cursor = hover != null ? 'pointer' : 'grab';
  });
  g.view.onClick(() => { if (hover != null) ui.open(PT[hover].id); });
  return () => g.destroy();
};

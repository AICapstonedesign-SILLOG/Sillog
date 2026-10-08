/* 뿌리: 위쪽 가운데 "나"(뿌리 머리)에서 분야(굵은 원뿌리)가 아래로 퍼지고, 업무(곁뿌리)가 원뿌리에서 갈라지며,
   곁뿌리 끝에 세션과 자료(가는 뿌리털)가 달린다. 위쪽 굵고 끝은 가늘며, 중력으로 휘어 내려간다. 원은 그리지 않는다 */
window.V3D = window.V3D || {};
window.V3D.cluster = function (main, data, ui) {
  const FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
  const INK = [36, 21, 15], PALE = [158, 132, 116];
  const hash = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rng = seed => () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const gauss = r => Math.sqrt(-2 * Math.log(r() + 1e-9)) * Math.cos(6.2832 * r());
  const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
  const lerpC = (a, b, u) => a.map((v, i) => Math.round(v + (b[i] - v) * u));
  const norm = v => { const l = Math.hypot(...v) || 1; return v.map(x => x / l); };
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

  const tasks = data.tasks.filter(t => data.themes.some(h => h.id === t.theme));
  const themes = data.themes.filter(th => tasks.some(t => t.theme === th.id));
  const NT = themes.length;

  // 뿌리 한 가닥: 처음 점과 방향에서 시작해 조금씩 흔들리며 중력 쪽(아래, +y)으로 휜다
  const grow = (p0, d0, n, len, wan, grav, r) => {
    const P = new Float32Array(n * 3), ph = [r() * 6.28, r() * 6.28, r() * 6.28], fr = 0.35 + r() * 0.3;
    let p = p0.slice(), d = norm(d0); P.set(p, 0);
    for (let j = 1; j < n; j++) {
      d[0] += Math.sin(j * fr + ph[0]) * wan; d[2] += Math.sin(j * fr * 1.3 + ph[1]) * wan; d[1] += Math.sin(j * fr * 0.8 + ph[2]) * wan * 0.5 + grav; d = norm(d);
      p = [p[0] + d[0] * len / (n - 1), p[1] + d[1] * len / (n - 1), p[2] + d[2] * len / (n - 1)]; P.set(p, j * 3);
    }
    return { P, dir: d };
  };

  const PX = [], PY = [], PZ = [], PT = [], PS = [];   // 점: 0 나, 허브(분야), 업무 끝
  const addPt = (x, y, z, t, s) => { PX.push(x); PY.push(y); PZ.push(z); PT.push(t); PS.push(s); return PX.length - 1; };
  const roots = [], balls = [], subs = [], hubPts = [], taskPts = [];
  const CROWN = [0, -0.6, 0];
  addPt(CROWN[0], CROWN[1], CROWN[2], null, -1);

  themes.forEach((th, hi) => {
    const ts = tasks.filter(t => t.theme === th.id), r = rng(hash(th.id + hi));
    const phi = (hi + 0.5) / NT * 6.2832 + (r() - 0.5) * 0.3, al = 0.95 + 0.3 * r();
    const d0 = [Math.sin(al) * Math.cos(phi), Math.cos(al), Math.sin(al) * Math.sin(phi)];
    const N = 26, g = grow(CROWN, d0, N, 0.95 + 0.15 * r(), 0.05, 0.03, r);
    const sub = { name: th.name, hub: 0 }; subs.push(sub);
    roots.push({ P: g.P, n: N, lw0: 10, lw1: 1.2, sub: hi });
    const hi0 = 12; sub.hub = addPt(g.P[hi0 * 3], g.P[hi0 * 3 + 1], g.P[hi0 * 3 + 2], null, hi); hubPts.push(sub.hub);
    for (let m = 0; m < 8; m++) {      // 가는 곁뿌리: 뿌리 모양을 채운다
      const ix = 8 + Math.floor(r() * 16), b0 = [g.P[ix * 3], g.P[ix * 3 + 1], g.P[ix * 3 + 2]], a0 = r() * 6.2832;
      const dd = norm([Math.cos(a0) * 0.8 + d0[0] * 0.3, 0.45, Math.sin(a0) * 0.8 + d0[2] * 0.3]), fg = grow(b0, dd, 7, 0.2 + 0.12 * r(), 0.08, 0.04, r);
      roots.push({ P: fg.P, n: 7, lw0: 1.7, lw1: 0.3, sub: hi });
    }
    const n = ts.length;
    ts.forEach((t, k) => {
      const idx = Math.min(N - 2, Math.max(13, Math.round(13 + (n > 1 ? k * (N - 15) / (n - 1) : (N - 15) / 2) + (r() - 0.5))));
      const base = [g.P[idx * 3], g.P[idx * 3 + 1], g.P[idx * 3 + 2]];
      const T = norm([g.P[(idx + 1) * 3] - g.P[(idx - 1) * 3], g.P[(idx + 1) * 3 + 1] - g.P[(idx - 1) * 3 + 1], g.P[(idx + 1) * 3 + 2] - g.P[(idx - 1) * 3 + 2]]);
      let s1 = cross(T, [0, 1, 0]); if (Math.hypot(...s1) < 0.1) s1 = [1, 0, 0]; s1 = norm(s1); const s2 = cross(T, s1);
      const th2 = (k % 2 ? 0 : 3.1416) + (r() - 0.5) * 1.2;
      const dl = norm([0, 1, 2].map(a => T[a] * 0.3 + (s1[a] * Math.cos(th2) + s2[a] * Math.sin(th2)) * 0.9 + (a === 1 ? 0.35 : 0)));
      const LN = 10, lg = grow(base, dl, LN, 0.34 + 0.18 * r(), 0.07, 0.04, r);
      roots.push({ P: lg.P, n: LN, lw0: 2.8, lw1: 0.6, sub: hi });
      const tip = [lg.P[(LN - 1) * 3], lg.P[(LN - 1) * 3 + 1], lg.P[(LN - 1) * 3 + 2]];
      const tp = addPt(tip[0], tip[1], tip[2], t, hi); taskPts.push(tp);
      const kids = (t.sessions || []).length + Object.values(t.items || {}).reduce((a, b) => a + (b || []).length, 0);
      const nd = Math.min(22, Math.max(9, Math.min(kids, 16) + 5));
      const hairs = [];
      for (let m = 0; m < nd; m++) {      // 뿌리털: 곁뿌리 끝에서 부채꼴로 가늘게 퍼지는 곡선
        let q; do { q = [gauss(r), gauss(r), gauss(r)]; } while (Math.hypot(...q) > 2);
        const L = 0.1 + 0.15 * r(), end = [0, 1, 2].map(a => tip[a] + lg.dir[a] * L + q[a] * 0.075 + (a === 1 ? 0.06 : 0));
        const mid = [0, 1, 2].map(a => tip[a] + (end[a] - tip[a]) * 0.5 + (r() - 0.5) * 0.06 + (a === 1 ? -0.015 : 0));
        const Q = new Float32Array(15);
        for (let j = 0; j < 5; j++) { const u = j / 4, w = 1 - u; [0, 1, 2].forEach(a => { Q[j * 3 + a] = w * w * tip[a] + 2 * w * u * mid[a] + u * u * end[a]; }); }
        hairs.push(Q);
      }
      balls.push({ tp, hairs, sub: hi });
    });
  });
  const NN = PX.length, SX = new Float32Array(NN), SY = new Float32Array(NN), SD = new Float32Array(NN);
  roots.forEach(rt => { rt.sx = new Float32Array(rt.n); rt.sy = new Float32Array(rt.n); rt.sw = new Float32Array(rt.n); rt.sd = 0; rt.sm = 1; });

  // 화면 점들을 부드럽게 이어(Catmull-Rom) 끝으로 갈수록 가는 띠 모양의 닫힌 경로로 만든다
  const SUB = 3;
  const ribbon = (ctx, rt, j0, j1) => {
    const n = rt.n, X = rt.sx, Y = rt.sy, W = rt.sw, px = [], py = [], pw = [];
    for (let j = j0; j < j1; j++) {
      const a = Math.max(0, j - 1), b = j, c = j + 1, d = Math.min(n - 1, j + 2);
      for (let s = 0; s < SUB; s++) {
        const u = s / SUB, u2 = u * u, u3 = u2 * u;
        const cr = (p0, p1, p2, p3) => 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3);
        px.push(cr(X[a], X[b], X[c], X[d])); py.push(cr(Y[a], Y[b], Y[c], Y[d])); pw.push(W[b] + (W[c] - W[b]) * u);
      }
    }
    px.push(X[j1]); py.push(Y[j1]); pw.push(W[j1]);
    const m = px.length, L = [], Rr = [];
    for (let i = 0; i < m; i++) {
      const i0 = Math.max(0, i - 1), i1 = Math.min(m - 1, i + 1);
      let tx = px[i1] - px[i0], ty = py[i1] - py[i0]; const l = Math.hypot(tx, ty) || 1; tx /= l; ty /= l;
      const h = pw[i] / 2; L.push(px[i] - ty * h, py[i] + tx * h); Rr.push(px[i] + ty * h, py[i] - tx * h);
    }
    ctx.moveTo(L[0], L[1]);
    for (let i = 1; i < m; i++) ctx.lineTo(L[i * 2], L[i * 2 + 1]);
    for (let i = m - 1; i >= 0; i--) ctx.lineTo(Rr[i * 2], Rr[i * 2 + 1]);
    ctx.closePath();
  };

  let hover = null, inited = false, cursorEl = null;
  const NB = 5, NL = 3;
  const g = window.G3D(main, (ctx, v, t) => {
    if (!inited) { inited = true; v.zoom = 1.12; v.pitch = -0.12; cursorEl = main.querySelector('canvas'); }
    const cyw = Math.cos(v.yaw), syw = Math.sin(v.yaw), cp = Math.cos(v.pitch), sp = Math.sin(v.pitch);
    const R = Math.min(v.w, v.h) * 0.4 * v.zoom, W2 = v.w / 2, H2 = v.h / 2 + R * 0.08;
    let ox = 0, oy = 0, od = 0, os = 0;
    const pr = (px, py, pz) => {
      const x = px * cyw - pz * syw, z1 = px * syw + pz * cyw, y = py * cp - z1 * sp, z = py * sp + z1 * cp;
      os = v.dist / (v.dist + z); ox = W2 + x * os * R; oy = H2 + y * os * R; od = (1 - z) / 2;
    };
    for (let i = 0; i < NN; i++) { pr(PX[i], PY[i], PZ[i]); SX[i] = ox; SY[i] = oy; SD[i] = od; }
    const zk = Math.min(1.4, Math.max(0.8, v.zoom));
    roots.forEach(rt => {
      let ds = 0, ss = 0; const n = rt.n;
      for (let j = 0; j < n; j++) { pr(rt.P[j * 3], rt.P[j * 3 + 1], rt.P[j * 3 + 2]); rt.sx[j] = ox; rt.sy[j] = oy; rt.sw[j] = os; ds += od; ss += Math.pow(os, 1.5); }
      rt.sd = ds / n; rt.sm = ss / n;
      const dp = (0.35 + 0.9 * rt.sm) * zk;
      for (let j = 0; j < n; j++) { const u = j / (n - 1); rt.sw[j] = Math.max(0.35, (rt.lw1 + (rt.lw0 - rt.lw1) * Math.pow(1 - u, 1.35)) * dp * (j === n - 1 ? 0.4 : 1)); }
    });
    const fadeOf = d => 0.15 + 0.85 * Math.max(0, Math.min(1, (d - 0.05) / 0.6));
    const binOf = d => Math.max(0, Math.min(NB - 1, Math.floor(d * NB)));
    hover = null;
    if (v.mouse && !v.dragging) {
      let best = 16;
      taskPts.forEach(i => { const d = Math.hypot(SX[i] - v.mouse.x, SY[i] - v.mouse.y); if (d < best) { best = d; hover = i; } });
    }
    const hsub = hover != null ? PS[hover] : -1;
    const inkOf = (f, lighten) => rgba(lerpC(INK, PALE, Math.min(1, (1 - f) * 0.9 + lighten)), Math.min(0.96, 0.3 + 0.7 * f) * (1 - lighten * 0.5));
    ctx.lineJoin = 'round'; ctx.lineCap = 'round';
    // 깊이 칸(먼 곳부터) × 길이 칸(굵은 쪽부터) × 흐림 여부로 묶어, 칸마다 한 번에 칠한다
    const rbin = []; roots.forEach(rt => { const k = binOf(rt.sd); (rbin[k] = rbin[k] || []).push(rt); });
    const bbin = []; balls.forEach(b => { const k = binOf(SD[b.tp]); (bbin[k] = bbin[k] || []).push(b); });
    for (let bi = 0; bi < NB; bi++) {
      const f = fadeOf((bi + 0.5) / NB), list = rbin[bi] || [];
      for (let dm = 0; dm < 2; dm++) for (let lb = 0; lb < NL; lb++) {
        ctx.beginPath(); let any = false;
        list.forEach(rt => {
          if ((hsub >= 0 && rt.sub !== hsub) !== (dm === 1)) return;
          const j0 = Math.floor((rt.n - 1) * lb / NL), j1 = lb === NL - 1 ? rt.n - 1 : Math.min(rt.n - 1, Math.floor((rt.n - 1) * (lb + 1) / NL) + 1);
          if (j1 > j0) { ribbon(ctx, rt, j0, j1); any = true; }
        });
        if (!any) continue;
        ctx.fillStyle = inkOf(f * (dm ? 0.55 : 1), lb * 0.1); ctx.fill();
      }
      (bbin[bi] || []).forEach(b => {
        const hot = hover === b.tp, k = hsub < 0 ? 1 : hot ? 1.3 : b.sub === hsub ? 1 : 0.4;
        for (let seg = 0; seg < 2; seg++) {
          ctx.beginPath();
          b.hairs.forEach(Q => { for (let j = seg * 2; j <= seg * 2 + 2; j++) { pr(Q[j * 3], Q[j * 3 + 1], Q[j * 3 + 2]); j > seg * 2 ? ctx.lineTo(ox, oy) : ctx.moveTo(ox, oy); } });
          ctx.strokeStyle = rgba(lerpC(INK, PALE, (1 - f) * 0.8 + seg * 0.15), Math.min(0.9, (0.62 - seg * 0.25) * f * k));
          ctx.lineWidth = Math.max(0.4, (seg ? 0.45 : 0.8) * Math.pow(os, 1.5) * zk); ctx.stroke();
        }
      });
    }
    ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    const placed = [];
    const tag = (s, x, y, fnt, a, sc, force, ax) => {
      ctx.font = fnt.replace(/(\d+(?:\.\d+)?)px/, (m, n) => Math.max(10, Math.round(n * Math.min(1.2, Math.max(0.9, sc)) * 2) / 2) + 'px');
      const w = ctx.measureText(s).width, x0 = ax === 'c' ? x - w / 2 : ax === 'r' ? x - w : x;
      for (const dy of [0, 16, -16, 32, -32]) {
        const rc = [x0 - 3, y + dy - 9, x0 + w + 3, y + dy + 9];
        if (placed.some(q => rc[0] < q[2] && rc[2] > q[0] && rc[1] < q[3] && rc[3] > q[1]) && !(force && dy === 32)) continue;
        placed.push(rc);
        ctx.lineWidth = 3.5; ctx.lineJoin = 'round'; ctx.strokeStyle = `rgba(250,246,242,${0.7 * a})`; ctx.strokeText(s, x0, y + dy);
        ctx.fillStyle = `rgba(36,21,15,${a})`; ctx.fillText(s, x0, y + dy); return;
      }
    };
    tag('나', SX[0], SY[0] - 16, `600 13px ${FONT}`, 1, 1, true, 'c');
    hubPts.forEach(h => tag(subs[PS[h]].name, SX[h] + (SX[h] < SX[0] ? -14 : 14), SY[h] - 4, `600 12.5px ${FONT}`, 0.55 + 0.45 * fadeOf(SD[h]), 1, true, SX[h] < SX[0] ? 'r' : 'l'));
    if (hover != null) { const s0 = PT[hover].title, s = s0.length > 30 ? s0.slice(0, 30) + '…' : s0; tag(s, SX[hover] + 10, SY[hover] + 6, `500 12px ${FONT}`, 1, 1, true); }
    if (cursorEl && !v.dragging) cursorEl.style.cursor = hover != null ? 'pointer' : 'grab';
  });
  g.view.onClick(() => { if (hover != null) ui.open(PT[hover].id); });
  return () => g.destroy();
};

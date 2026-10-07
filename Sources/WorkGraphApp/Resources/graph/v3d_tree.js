/* 입체 나무: Walrus(쌍곡 나무) 풍. 검은 바탕, 큰 원 와이어, 업무 = 성게 모양 부채 허브(살 + 작은 사각 점) */
window.V3D = window.V3D || {};
window.V3D.tree = function (main, data, ui) {
  const hash = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rng = seed => () => ((seed = Math.imul(seed ^ (seed >>> 15), 2246822507) + 0x9e3779b9 | 0) >>> 0) / 4294967296;
  const norm = v => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const basis = u => { const a = norm(cross(u, Math.abs(u[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0])); return [a, norm(cross(u, a))]; };
  const fib = (i, n) => { const y = 1 - 2 * (i + 0.5) / n, r = Math.sqrt(1 - y * y), p = i * 2.399963; return [Math.cos(p) * r, y, Math.sin(p) * r]; };
  const PAL = ['#A9D18E', '#C9E4B1', '#FFFFFF', '#8CC26E', '#E4F2D6', '#A9D18E']; // 잎: 밝은 연두 계열 초록과 흰색 (브랜드 팔레트 밖 예외는 잎만, 가지는 고동색)
  const W = [5, 3, 3, 2, 1, 0.6];

  const themes = data.themes.filter(t => data.tasks.some(k => k.theme === t.id));
  const tdir = {}, tcnt = {}, tot = {};
  themes.forEach((t, i) => { tdir[t.id] = fib(i, themes.length); tcnt[t.id] = 0; });
  data.tasks.forEach(t => { tot[t.theme] = (tot[t.theme] || 0) + 1; });
  const sz = t => (t.sessions || []).length + Object.values(t.items || {}).reduce((a, x) => a + (x || []).length, 0);
  const big = data.tasks.reduce((a, t) => (sz(t) > sz(a) ? t : a), data.tasks[0] || {});

  const mk = (r, c, nrm, rho, cnt, flat, main, isBig, task, parent) => {
    const [e1, e2] = basis(nrm), col = [], pts = new Float32Array(cnt * 3), nr = isBig ? 0.8 : 0.4;
    for (let i = 0; i < cnt; i++) {
      const rim = i % 9 !== 0 || isBig ? r() < nr : false, q = rim ? 1 : Math.sqrt(r()) * 0.95, th = (i / cnt) * 6.283 * (flat ? 1 : 0.55) + (isBig ? r() * 0.05 : 0);
      const h = flat ? 0 : Math.sqrt(Math.max(0, 1 - q * q)) * 0.55;
      for (let j = 0; j < 3; j++) pts[i * 3 + j] = c[j] + rho * (e1[j] * Math.cos(th) * q + e2[j] * Math.sin(th) * q + nrm[j] * h);
      if (isBig) col.push(rim ? [0, 0, 0, 1, 1, 4, 2][Math.floor(r() * 7)] : -1);
      else { let x = r() * 14.6, ci = 0; while (x > W[ci] && ci < 5) x -= W[ci++]; col.push(r() < 0.7 ? [main, (main + 1) % 3][r() < 0.15 ? 1 : 0] : ci); }
    }
    const rim = Array.from({ length: 32 }, (_, i) => [0, 1, 2].map(j => c[j] + rho * (e1[j] * Math.cos(i / 32 * 6.283) + e2[j] * Math.sin(i / 32 * 6.283))));
    return { task, c, pts, col, cnt, rho, flat, rim, isBig, parent };
  };
  const order0 = data.tasks.slice().sort((a, b) => themes.findIndex(t => t.id === a.theme) - themes.findIndex(t => t.id === b.theme));
  const fdir = new Map(order0.map((t, i) => [t, fib(i, order0.length)]));
  themes.forEach(t => { const m = [0, 0, 0]; data.tasks.filter(k => k.theme === t.id).forEach(k => fdir.get(k).forEach((x, i) => { m[i] += x; })); tdir[t.id] = norm(m); });
  const hubs = [];
  data.tasks.forEach(task => {
    const td = tdir[task.theme] || [0, 1, 0], k = tcnt[task.theme]++, r = rng(hash(task.id)), isBig = task === big;
    const [a, b] = basis(td), ph = k * 2.399963 + r(), cone = 0.2 + (tot[task.theme] > 8 ? 1.5 : 0.8) * Math.sqrt((k + 0.5) / tot[task.theme]);
    const u = fdir.get(task);
    const rad = isBig ? 0 : 0.5 + 0.35 * r(), c = isBig ? [-0.3, -0.38, 0.1] : u.map(x => x * rad);
    const nrm = isBig ? norm([0.75, 0.15, 0.65]) : norm([0, 1, 2].map(i => u[i] + (r() - 0.5) * 1.4)), n = sz(task);
    const rho = isBig ? 0.42 : 0.09 + 0.08 * Math.min(1, Math.sqrt(n / 30)) + 0.02 * r();
    const h = mk(r, c, nrm, rho, isBig ? 600 : Math.min(150, 50 + n * 6), isBig || r() < 0.4, Math.floor(r() * 3), isBig, task, null);
    hubs.push(h);
    const m = isBig ? 5 : 1 + (r() < 0.35 ? 1 : 0);
    for (let j = 0; j < m; j++) {
      const d = (isBig ? 0.3 : 0.18) + 0.2 * r(), sp = 0.45;
      const cc = norm([0, 1, 2].map(i => u[i] + (r() - 0.5) * sp + [-0.35, -0.5, 0][i])).map((x, i) => c[i] + x * d);
      const l = Math.hypot(cc[0], cc[1], cc[2]), sc = l > 0.93 ? 0.93 / l : 1;
      hubs.push(mk(r, cc.map(x => x * sc), norm([r() - 0.5, r() - 0.5, r() - 0.5]), 0.05 + 0.04 * r(), 20 + Math.floor(r() * 20), r() < 0.55, Math.floor(r() * 3), false, null, h));
    }
  });
  hubs.push(mk(rng(7), [-0.53, 0.05, 0.29], norm([0.88, 0, -0.48]), 0.26, 280, true, 0, true, null, null));
  const sessN = data.tasks.reduce((a, t) => a + (t.sessions || []).length, 0), itemN = data.tasks.reduce((a, t) => a + sz(t) - (t.sessions || []).length, 0);


  const TREE = 'rgba(36,21,15,0.6)';
  let hover = null;
  const g = window.G3D(main, (ctx, v) => {
    G3D.glass(ctx, v);
    const P = p => v.project(p), R = Math.min(v.w, v.h) * 0.4 * v.zoom, cx = v.w / 2, cy = v.h / 2;
    const o = P([0, 0, 0]), ps = hubs.map(h => P(h.c)), tp = {};
    themes.forEach(t => { tp[t.id] = P(tdir[t.id].map(x => x * 0.3)); });
    let best = null, bd = 14;
    // 나무 선: 중심 → 분야 → 허브
    ctx.strokeStyle = TREE; ctx.lineWidth = 0.7; ctx.beginPath();
    themes.forEach(t => { const a = tp[t.id]; ctx.moveTo(o.x, o.y); ctx.lineTo(a.x, a.y); });
    hubs.forEach((h, i) => { const a = h.parent ? ps[hubs.indexOf(h.parent)] : (h.task ? tp[h.task.theme] || o : o); ctx.moveTo(a.x, a.y); ctx.lineTo(ps[i].x, ps[i].y); }); ctx.stroke();
    ctx.fillStyle = '#24150f'; ctx.beginPath(); ctx.arc(o.x, o.y, 3, 0, 6.283); ctx.fill();
    const used = [];
    themes.slice().sort((x, y) => tp[y.id].z - tp[x.id].z).reverse().forEach(t => { const a = tp[t.id]; ctx.fillStyle = '#24150f'; ctx.fillRect(a.x - 2, a.y - 2, 4, 4);
      let ly = a.y - 8; for (let n = 0; n < 4; n++) { if (!used.some(u => Math.abs(u[0] - a.x) < 64 && Math.abs(u[1] - ly) < 14)) break; ly -= 14; }
      used.push([a.x, ly]); ctx.font = '600 12px "SUIT",-apple-system,sans-serif'; ctx.textAlign = 'center'; ctx.globalAlpha = 0.5 + 0.5 * a.d; ctx.fillStyle = '#24150f'; ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(255,255,255,0.85)'; ctx.lineJoin = 'round'; ctx.strokeText(t.name, a.x, ly); ctx.fillText(t.name, a.x, ly); ctx.globalAlpha = 1; });

    // 허브: 먼 것부터
    const XY = new Float32Array(1600); const order = hubs.map((h, i) => i).sort((a, b) => ps[b].z - ps[a].z);
    const cvs = v.dist, cp = Math.cos(v.pitch), sp = Math.sin(v.pitch), cyw = Math.cos(v.yaw), syw = Math.sin(v.yaw), mx = v.w / 2, my = v.h / 2;
    order.forEach(i => {
      const h = hubs[i], c = ps[i], hv = hover === h;
      if (v.mouse && h.task) { const dd = Math.hypot(c.x - v.mouse.x, c.y - v.mouse.y); if (dd < bd) { bd = dd; best = h; } }
      const f = 0.08 + 0.92 * Math.pow(Math.max(0, c.d), 1.6), ws = Math.pow(c.s, 1.5), pts = h.pts, xy = XY;
      for (let k = 0; k < h.cnt; k++) {
        const x0 = pts[k * 3], y0 = pts[k * 3 + 1], z0 = pts[k * 3 + 2];
        const x = x0 * cyw - z0 * syw, z1 = x0 * syw + z0 * cyw, y = y0 * cp - z1 * sp, z = y0 * sp + z1 * cp, s = cvs / (cvs + z);
        xy[k * 2] = mx + x * s * R; xy[k * 2 + 1] = my + y * s * R;
      }
      if (h.flat) { // 반투명 원반
        ctx.beginPath(); h.rim.forEach((p, j) => { const a = P(p); ctx[j ? 'lineTo' : 'moveTo'](a.x, a.y); }); ctx.closePath();
        ctx.fillStyle = 'rgba(246,245,244,' + (h.isBig ? 0.12 : 0.22) * f + ')'; ctx.fill();   // 테두리 없음
      }
      ctx.strokeStyle = hv ? 'rgba(36,21,15,0.9)' : 'rgba(' + [36 + 79 * (1 - c.d), 21 + 88 * (1 - c.d), 15 + 89 * (1 - c.d)].map(Math.round) + ',' + (h.isBig ? 0.55 : 0.85) * f + ')'; ctx.lineWidth = (hv ? 1 : 0.6) * ws; ctx.beginPath();
      for (let k = 0; k < h.cnt; k++) { ctx.moveTo(c.x, c.y); ctx.lineTo(xy[k * 2], xy[k * 2 + 1]); } ctx.stroke();
      const sq = Math.max(1.2, (h.task ? 4.4 : 3.6) * Math.pow(c.s, 1.7));
      ctx.globalAlpha = f;
      for (let ci = 0; ci < PAL.length; ci++) {
        ctx.fillStyle = PAL[ci]; ctx.beginPath();
        for (let k = 0; k < h.cnt; k++) if (h.col[k] === ci) ctx.rect(xy[k * 2] - sq / 2, xy[k * 2 + 1] - sq / 2, sq, sq);
        ctx.fill();
      }
      ctx.globalAlpha = 1; ctx.fillStyle = hv ? '#fff' : 'rgba(246,245,244,' + f + ')'; ctx.beginPath(); ctx.arc(c.x, c.y, (hv ? 4 : h.task ? 2.6 : 1.4) * c.s, 0, 6.283); ctx.fill();
    });
    hover = v.dragging ? null : best;
    const lab = h => { const i = hubs.indexOf(h), c = ps[i], t = h.task.title || ''; ctx.font = '600 12px "SUIT",-apple-system,sans-serif'; ctx.textAlign = 'left'; ctx.fillStyle = '#24150f'; ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.lineJoin = 'round'; ctx.strokeText(t.length > 30 ? t.slice(0, 30) + '…' : t, c.x + 8, c.y - 8); ctx.fillText(t.length > 30 ? t.slice(0, 30) + '…' : t, c.x + 8, c.y - 8); };
    if (hover) lab(hover);
  });
  g.view.onClick((x, y) => {
    let b = null, bd = 16;
    hubs.forEach(h => { if (!h.task) return; const q = g.view.project(h.c), d = Math.hypot(q.x - x, q.y - y); if (d < bd) { bd = d; b = h; } });
    if (b) ui.open(b.task.id);
  });
  return () => g.destroy();
};

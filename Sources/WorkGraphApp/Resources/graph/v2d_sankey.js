/* 흐름 보기: 분야(왼쪽 막대) -> 업무 종류(가운데 마디) -> 업무(오른쪽, 시작일 순)로 흐르는 3단 산키 그림. 가운데 마디와 오른쪽 막대는 위아래로 끌 수 있음. 윗줄(주 칸)은 화면 맨 위에 고정. */
window.V3D = window.V3D || {};
window.V3D.sankey = function (main, data, ui) {
  const vivid = hex => {   // 분야 색을 유리 위에서 맑게: 채도 ×1.4, 밝기 조금 올림
    const n = parseInt(String(hex).replace('#', ''), 16); if (isNaN(n)) return hex;
    let r = (n >> 16 & 255) / 255, g = (n >> 8 & 255) / 255, b = (n & 255) / 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b); let h = 0, s = 0, l = (mx + mn) / 2;
    if (mx !== mn) { const d = mx - mn; s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6; }
    s = Math.min(1, s * 1.55); l = Math.min(0.52, Math.max(0.44, l * 1.05));   // 맑은 보석색: 채도 높게, 밝기는 중간
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q, f = t => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
    return '#' + [f(h + 1 / 3), f(h), f(h - 1 / 3)].map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('');
  };
  const NS = 'http://www.w3.org/2000/svg', STRIP = 30, GAP = 16, DAY = 864e5;
  let MX = 40, MR = 40;
  const el = (n, a, p) => { const e = document.createElementNS(NS, n); for (const k in a || {}) e.setAttribute(k, a[k]); if (p) p.appendChild(e); return e; };
  const now = new Date();
  const toDay = w => { const [m, d] = w.split(' ')[0].split('/').map(Number); let y = now.getFullYear(); if (m > now.getMonth() + 2) y--; return Math.floor(Date.UTC(y, m - 1, d) / DAY); };
  const fmt = n => { const t = new Date(n * DAY); return (t.getUTCMonth() + 1) + '/' + t.getUTCDate(); };
  const hm = m => m >= 60 ? Math.floor(m / 60) + '시간' + (m % 60 ? ' ' + (m % 60) + '분' : '') : m + '분';

  const ts = data.tasks.filter(t => t.sessions.length).map(t => {
    const ds = t.sessions.map(s => toDay(s.when)), ss = t.sessions.slice().sort((a, b) => a.d - b.d);
    return { t, first: Math.min(...ds), mins: Math.max(t.mins || 0, 1), fw: ss[0].when, lw: ss[ss.length - 1].when };
  });
  main.innerHTML = '';
  if (!ts.length) return () => {};
  const lo = Math.min(...ts.map(x => x.first)), hi = Math.max(...data.tasks.flatMap(t => t.sessions.map(s => toDay(s.when))));
  const mon = d => d - ((d + 3) % 7);
  const nW = (mon(hi) - mon(lo)) / 7 + 1, byDay = nW < 6;
  const colOf = d => byDay ? d - lo : (mon(d) - mon(lo)) / 7, nCol = byDay ? hi - lo + 1 : nW;
  const colLabel = c => fmt(byDay ? lo + c : mon(lo) + c * 7);
  ts.forEach(x => x.col = colOf(x.first));

  const wrap = document.createElement('div');
  wrap.style.cssText = 'position:absolute;inset:0;background:transparent;overflow:hidden;font-family:"SUIT",-apple-system,"Apple SD Gothic Neo",sans-serif';
  const stripSvg = el('svg', { style: 'position:absolute;left:0;top:0;width:100%;height:' + STRIP + 'px;z-index:2' });
  const body = document.createElement('div');
  body.style.cssText = 'position:absolute;left:0;right:0;bottom:0;top:' + STRIP + 'px;overflow:hidden';
  const svg = el('svg', { style: 'display:block;user-select:none' }); body.appendChild(svg);
  const tip = document.createElement('div');
  tip.style.cssText = 'position:absolute;z-index:5;pointer-events:none;display:none;background:#24150F;color:#fff;font-size:12px;line-height:1.5;padding:7px 10px;border-radius:8px;max-width:260px';
  wrap.append(body, stripSvg, tip); main.appendChild(wrap);

  const NK = (th, ty) => th + '\u0001' + ty;
  ts.forEach(x => { x.type = x.t.type || '기타'; x.nk = NK(x.t.theme, x.type); });

  let hoverId = null, hoverTheme = null, hoverNode = null, ribs = [];
  const apply = () => ribs.forEach(r => {
    const any = hoverId || hoverTheme || hoverNode;
    const on = hoverId ? r.t.id === hoverId : hoverNode ? r.nk === hoverNode : hoverTheme ? r.t.theme === hoverTheme : true;
    r.p.setAttribute('fill-opacity', any ? (on ? 0.97 : 0.15) : 0.95);
    if (r.lab.style) r.lab.style.fontWeight = hoverId && on ? 700 : 400, r.lab.style.fill = hoverId && on ? '#24150F' : '';
    r.lab.setAttribute('opacity', any ? (on ? 1 : 0.2) : 1);
  });

  let vg = null, WW = 0, dragged = false;
  // 끌 수 있는 한 줄(분야 막대, 업무 종류 마디): 순서, 위치, 폭, 스프링 상태를 줄마다 따로 가짐
  const BG = 8, mkRow = () => ({ order: null, pos: null, w: {}, tgt: {}, disp: {}, vel: {} });
  const R1 = mkRow(), R2 = mkRow(); let drag = null, raf = 0, lastT = 0;
  const step = now => {
    const dt = Math.min(.033, (now - lastT) / 1000 || .016); lastT = now; let moving = false;
    [R1, R2].forEach(R => { for (const id in R.tgt) {
      if (R.disp[id] == null) { R.disp[id] = R.tgt[id]; R.vel[id] = 0; continue; }
      if (drag && drag.R === R && drag.id === id) { R.disp[id] += (R.tgt[id] - R.disp[id]) * (1 - Math.exp(-dt * 16)); R.vel[id] = 0; moving = true; continue; }
      const a = 380 * (R.tgt[id] - R.disp[id]) - 22 * R.vel[id]; R.vel[id] += a * dt; R.disp[id] += R.vel[id] * dt;
      if (Math.abs(R.tgt[id] - R.disp[id]) > .3 || Math.abs(R.vel[id]) > .3) moving = true; else { R.disp[id] = R.tgt[id]; R.vel[id] = 0; }
    } });
    raf = 0; draw(true); if (moving || drag) raf = requestAnimationFrame(step);
  };
  const kick = () => { if (!raf) { lastT = performance.now(); raf = requestAnimationFrame(step); } };
  // 끈 항목(id)을 기준으로 좌우 이웃을 밀어내며 겹침 제거
  const resolve = (R, id) => {
    const d = R.order.indexOf(id), W = WW, L = R.order.slice(0, d), Rt = R.order.slice(d + 1), pos = R.pos, bw = R.w;
    const lo = 4 + L.reduce((q, i) => q + bw[i] + BG, 0), hi = W - 4 - bw[id] - Rt.reduce((q, i) => q + bw[i] + BG, 0);
    pos[id] = Math.max(lo, Math.min(hi, pos[id]));
    let e = pos[id] + bw[id] + BG; Rt.forEach(i => { pos[i] = Math.max(pos[i], e); e = pos[i] + bw[i] + BG; });
    let st = pos[id] - BG; for (let j = L.length - 1; j >= 0; j--) { const i = L[j]; pos[i] = Math.min(pos[i], st - bw[i]); st = pos[i] - BG; }
  };
  const grab = (hit, R, id, items) => hit.addEventListener('mousedown', e => {
    if (e.button) return; e.preventDefault();
    const sx = e.clientY; dragged = true; drag = { R, id }; tip.style.display = 'none'; body.style.cursor = 'grabbing';
    if (!R.pos) { R.pos = {}; items.forEach(q => { R.pos[q] = R.tgt[q]; }); }
    const p0 = R.pos[id];
    const mv = ev => {
      R.pos[id] = p0 + ev.clientY - sx;
      let d = R.order.indexOf(id);
      for (;;) {   // 이웃의 가운데를 넘으면 순서 교환
        const c = R.pos[id] + R.w[id] / 2, rn = R.order[d + 1], ln = R.order[d - 1];
        if (rn != null && c > R.pos[rn] + R.w[rn] / 2) { R.order[d] = rn; R.order[d + 1] = id; d++; }
        else if (ln != null && c < R.pos[ln] + R.w[ln] / 2) { R.order[d] = ln; R.order[d - 1] = id; d--; }
        else break;
      }
      resolve(R, id); R.tgt = { ...R.pos }; kick();
    };
    const up = () => { removeEventListener('mousemove', mv); removeEventListener('mouseup', up); dragged = false; drag = null; hoverTheme = hoverNode = null; body.style.cursor = ''; kick(); };
    addEventListener('mousemove', mv); addEventListener('mouseup', up);
  });

  function draw(fromAnim) {
    const W = wrap.clientWidth, H = wrap.clientHeight;
    if (!W || !H) return;
    const BH = H - STRIP, V0 = 14, VH = BH - V0 - 18;
    const xB = 24 + 90, xT = W - Math.min(300, W * .27), xM = xB + (xT - xB) * .5;
    WW = BH; svg.setAttribute('width', W); svg.setAttribute('height', BH); svg.innerHTML = ''; vg = el('g', {}, svg);
    // 열 이름(맨 위 고정)
    stripSvg.innerHTML = '';
    const hdr = (x, a, t) => { const e = el('text', { x, y: STRIP / 2 + 4, 'text-anchor': a, 'font-size': 11, fill: '#a39a92' }, stripSvg); e.textContent = t; };
    hdr(xT + 12, 'start', '업무 ' + ts.length + '개'); hdr(xM, 'middle', '업무 종류');
    // 분야 순서: 가장 이른 시작 기준
    const themes = data.themes.filter(th => ts.some(x => x.t.theme === th.id));
    ts.forEach(x => { if (!themes.find(th => th.id === x.t.theme)) themes.push({ id: x.t.theme, name: x.t.theme, color: x.t.color }); });
    const ord = th => Math.min(...ts.filter(x => x.t.theme === th.id).map(x => x.first));
    themes.sort((a, b) => ord(a) - ord(b));
    hdr(xB - 14, 'end', '분야 ' + themes.length + '개');
    // 왼쪽 열: 시작일 순으로 한 줄씩, 날짜가 바뀌면 약간 띄움
    const L = ts.slice().sort((a, b) => a.first - b.first || b.mins - a.mins), n = L.length;
    const sq = x => Math.sqrt(x.mins), maxSq = Math.max(...ts.map(sq));
    let sc = 60 / maxSq; const wOf = x => Math.max(2.5, sq(x) * sc), slot = x => Math.max(wOf(x), 13);
    const gapAt = i => i ? (L[i].col !== L[i - 1].col ? 9 : 3) : 0;
    const tot = () => L.reduce((q, x, i) => q + slot(x) + gapAt(i), 0);
    while (tot() > VH * .98 && sc > .01) sc *= .94;
    const extra = n > 1 ? Math.max(0, (VH - tot()) / (n - 1)) : 0;
    let yy = V0;
    L.forEach((x, i) => { yy += i ? gapAt(i) + extra : 0; x.slotTop = yy; x.y0 = yy + (slot(x) - wOf(x)) / 2; yy += slot(x); });
    if (!R1.order) R1.order = themes.map(th => th.id);
    themes.sort((a, b) => R1.order.indexOf(a.id) - R1.order.indexOf(b.id)); R1.order = themes.map(th => th.id);
    // 업무 종류 마디
    const nmap = {};
    ts.forEach(x => { (nmap[x.nk] = nmap[x.nk] || { id: x.nk, theme: x.t.theme, type: x.type, list: [], color: x.t.color }).list.push(x); });
    const nodes = Object.values(nmap);
    nodes.forEach(q => { q.list.sort((a, b) => a.y0 - b.y0); q.first = q.list[0].first; R2.w[q.id] = q.list.reduce((t, x) => t + wOf(x), 0); });
    themes.forEach(th => { R1.w[th.id] = nodes.filter(q => q.theme === th.id).reduce((t, q) => t + R2.w[q.id], 0); });
    R1.tgt = {};
    if (!R1.pos) {
      const sb = themes.reduce((q, th) => q + R1.w[th.id], 0), span = Math.max(sb + 8 * (themes.length - 1), VH * .88);
      const gp = themes.length > 1 ? (span - sb) / (themes.length - 1) : 0; let bx = V0 + (VH - span) / 2;
      themes.forEach(th => { R1.tgt[th.id] = bx; bx += R1.w[th.id] + gp; });
    } else { themes.forEach(th => { if (R1.pos[th.id] == null) R1.pos[th.id] = 4; }); resolve(R1, R1.order[0]); themes.forEach(th => { R1.tgt[th.id] = R1.pos[th.id]; }); }
    themes.forEach(th => { if (R1.disp[th.id] == null) { R1.disp[th.id] = R1.tgt[th.id]; R1.vel[th.id] = 0; } });
    const keep = R2.order ? R2.order.filter(i => nmap[i]) : [];
    if (!R2.pos || !R2.order) R2.order = nodes.slice().sort((a, b) => R1.order.indexOf(a.theme) - R1.order.indexOf(b.theme) || a.first - b.first).map(q => q.id);
    else { nodes.forEach(q => { if (!keep.includes(q.id)) keep.push(q.id); }); R2.order = keep; }
    R2.tgt = {};
    if (!R2.pos) {
      let end = -1e9;
      themes.forEach(th => {
        const ns = R2.order.filter(i => nmap[i].theme === th.id), nw = ns.reduce((q, i) => q + R2.w[i], 0) + BG * (ns.length - 1);
        let ny = Math.max(R1.tgt[th.id] + (R1.w[th.id] - nw) / 2, end + BG, 4);
        ns.forEach(i => { R2.tgt[i] = ny; ny += R2.w[i] + BG; end = ny - BG; });
      });
    } else { nodes.forEach(q => { if (R2.pos[q.id] == null) R2.pos[q.id] = 4; }); resolve(R2, R2.order[0]); nodes.forEach(q => { R2.tgt[q.id] = R2.pos[q.id]; }); }
    nodes.forEach(q => { if (R2.disp[q.id] == null) { R2.disp[q.id] = R2.tgt[q.id]; R2.vel[q.id] = 0; } });
    nodes.forEach(q => { let m = R2.disp[q.id]; q.y = m; q.list.forEach(x => { x.my = m; m += wOf(x); }); });
    const bars = themes.map(th => {
      const b = { th, y0: R1.disp[th.id] }; let by = b.y0;
      nodes.filter(q => q.theme === th.id).sort((a, c) => a.y - c.y).forEach(q => q.list.forEach(x => { x.by = by; by += wOf(x); }));
      b.y1 = by; return b;
    });
    const g = el('g', {}, vg), lg = el('g', {}, vg); ribs = [];
    const h1 = (xB + xM) / 2, h2 = (xM + xT) / 2;
    const over = x => { if (dragged) return; hoverId = x.t.id; apply(); tip.style.display = 'block'; tip.innerHTML = `<b>${x.t.title}</b><br>${x.type}, ${hm(x.mins)}, 세션 ${x.t.sessions.length}회<br>${x.fw} ~ ${x.lw}`; };
    const mvT = e => { const q = wrap.getBoundingClientRect(); tip.style.left = Math.min(e.clientX - q.left + 14, W - 270) + 'px'; tip.style.top = (e.clientY - q.top + 14) + 'px'; };
    const out = () => { hoverId = null; apply(); tip.style.display = 'none'; };
    [...ts].sort((a, b) => b.mins - a.mins).forEach(x => {
      const w = wOf(x), a = x.y0, m = x.my, b = x.by;
      const d = `M${xB},${b}C${h1},${b} ${h1},${m} ${xM},${m}C${h2},${m} ${h2},${a} ${xT},${a}L${xT},${a + w}C${h2},${a + w} ${h2},${m + w} ${xM},${m + w}C${h1},${m + w} ${h1},${b + w} ${xB},${b + w}Z`;
      const p = el('path', { d, fill: vivid(x.t.color), 'fill-opacity': .95, style: 'cursor:pointer' }, g);
      ribs.push({ t: x.t, p, lab: null, x, nk: x.nk });
      p.addEventListener('mouseenter', () => over(x)); p.addEventListener('mousemove', mvT); p.addEventListener('mouseleave', out);
      p.addEventListener('click', () => { if (!dragged) ui.open(x.t.id); });
    });
    // 왼쪽: 시작 막대, 제목, 날짜
    L.forEach((x, i) => {
      const w = wOf(x), cy = x.y0 + w / 2, rb = ribs.find(q => q.x === x);
      el('rect', { x: xT, y: x.y0, width: 3, height: w, fill: '#24150F', 'fill-opacity': 0.45, 'pointer-events': 'none' }, vg);
      const txt = x.t.title.length > 18 ? x.t.title.slice(0, 17) + '…' : x.t.title;
      const t = el('text', { x: xT + 12, y: cy + 4, 'font-size': 11, fill: '#8a817a', style: 'cursor:pointer' }, lg);
      t.textContent = txt; rb.lab = t;
      t.addEventListener('mouseenter', () => over(x)); t.addEventListener('mousemove', mvT); t.addEventListener('mouseleave', out); t.addEventListener('click', () => { if (!dragged) ui.open(x.t.id); });
      if (!i || x.col !== L[i - 1].col) { const d = el('text', { x: W - 10, y: cy + 4, 'text-anchor': 'end', 'font-size': 10, fill: '#a39a92', 'pointer-events': 'none' }, vg); d.textContent = colLabel(x.col); }
    });
    // 가운데 마디: 검은 얇은 막대 + 이름표, 위아래로 끎
    const chips = [];
    R2.order.forEach(id => {
      const q = nmap[id]; if (!q) return; const h = Math.max(R2.w[id], 2), y = q.y;
      el('rect', { x: xM - 2, y, width: 4, height: h, rx: 1, fill: '#24150F', 'fill-opacity': 0.28 }, vg);   // 가운데는 옅게
      const label = `${q.type} ${q.list.length}`, cwid = label.length * 10.5 + 14, cy = y + h / 2;
      let row = 0; while (chips.some(c => c.row === row && Math.abs(c.cy - cy) < 19)) row++;
      chips.push({ row, cy });
      const cx = xM + (row ? (row % 2 ? 1 : -1) * (cwid * .6 + 6) * Math.ceil(row / 2) : 0);
      const hit = el('rect', { x: Math.min(xM - 6, cx - cwid / 2), y: Math.min(y - 3, cy - 10), width: Math.max(12, cx + cwid / 2 - Math.min(xM - 6, cx - cwid / 2)), height: Math.max(h + 6, 20), fill: 'transparent', style: 'cursor:grab' }, vg);
      el('rect', { x: cx - cwid / 2, y: cy - 8.5, width: cwid, height: 17, rx: 8.5, fill: '#FFFFFF', 'fill-opacity': 0.82, 'pointer-events': 'none' }, vg);
      const t = el('text', { x: cx, y: cy + 4, 'text-anchor': 'middle', 'font-size': 11, 'font-weight': 600, fill: '#4A4541', 'pointer-events': 'none' }, vg); t.textContent = label;
      hit.addEventListener('mouseenter', () => { hoverNode = id; apply(); });
      hit.addEventListener('mouseleave', () => { if (!dragged) { hoverNode = null; apply(); } });
      grab(hit, R2, id, R2.order.slice());
    });
    // 오른쪽 분야 막대
    bars.forEach(b => {
      const h = Math.max(b.y1 - b.y0, 2), cy = b.y0 + h / 2;
      el('rect', { x: xB - 4, y: b.y0, width: 4, height: h, rx: 1, fill: '#24150F', 'fill-opacity': 0.55 }, vg);
      const hit = el('rect', { x: xB - 110, y: Math.min(b.y0 - 4, cy - 12), width: 114, height: Math.max(h + 8, 24), fill: 'transparent', style: 'cursor:grab' }, vg);
      const t = el('text', { x: xB - 14, y: cy + 5, 'text-anchor': 'end', 'font-size': 13, fill: '#24150F', 'pointer-events': 'none' }, vg); t.textContent = b.th.name;
      hit.addEventListener('mouseenter', () => { hoverTheme = b.th.id; apply(); });
      hit.addEventListener('mouseleave', () => { if (!dragged) { hoverTheme = null; apply(); } });
      grab(hit, R1, b.th.id, R1.order.slice());
    });
    ribs.forEach(r => { if (!r.lab) r.lab = el('g', {}); });
    apply();
    if (!fromAnim && !raf && ([R1, R2].some(R => Object.keys(R.tgt).some(i => Math.abs(R.disp[i] - R.tgt[i]) > .3)))) kick();
  }
  const ro = new ResizeObserver(draw); ro.observe(wrap); draw();
  return () => { cancelAnimationFrame(raf); ro.disconnect(); wrap.remove(); };
};

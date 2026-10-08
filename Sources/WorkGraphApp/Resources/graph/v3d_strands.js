/* 거미줄 (Canvas 2D): 나를 가운데 둔 둥근 거미줄 한 장. 화면 끝까지 퍼지고, 바깥 틀은 화면 밖에 묶여 있다.
   살 = 분야(굵은 살, 바깥 끝에 이름과 몫 d)와 업무(가는 살). 나선 한 바퀴 = 하루(안쪽 = 오래된 날, 바깥 = 최근, 맨 위 살에 날짜).
   이슬 = 업무(크기 = 시간, 그 업무 살과 마지막으로 일한 날 나선이 만나는 곳), 작은 물방울 = 세션(그날 나선 위, 업무 살 옆),
   이슬 아래 매달린 실 = 자료(종류마다 한 가닥, 길이 = 개수, 끝 방울 색 = 종류), 늘어진 실 = 관계(같은 자료를 쓴 업무).
   실은 용수철 그물(제자리에서 벗어난 만큼만 푼다): 커서가 지나가면 실이 튕겨 물결이 번지고 이슬이 출렁인다. 바람에 늘 흔들리고 숨쉰다.
   빛 한 점(커서를 따라온다)에 직각인 실 조각이 무지갯빛으로 반짝인다. 가끔 이슬 위로 반짝임이 지나간다.
   바탕은 칠하지 않는다: G3D.mesh 갈색 흐름이 비친다 */
window.V3D = window.V3D || {};
window.V3D.strands = function (main, data, ui) {
  const FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif', SERIF = '"Times New Roman", "AppleMyungjo", serif';
  const TAU = Math.PI * 2, clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const hash = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rng = seed => () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const hexRGB = h => { const n = parseInt(String(h || '9b9490').replace('#', '').slice(0, 6).padEnd(6, '0'), 16) || 0; return [n >> 16 & 255, n >> 8 & 255, n & 255]; };
  const fmtT = m => { m = Math.round(m); const h = Math.floor(m / 60), r = m % 60; return h ? (r ? `${h}시간 ${r}분` : `${h}시간`) : `${r}분`; };
  const trunc = (s, n) => (s.length > n ? s.slice(0, n) + '…' : s);
  if (getComputedStyle(main).position === 'static') main.style.position = 'relative';
  const note = msg => { const p = document.createElement('p'); p.className = 'empty-note'; p.textContent = msg; main.appendChild(p); return () => p.remove(); };

  // ---- 자료: 분야, 업무, 세션(날짜 고리), 자료(종류), 관계 ----
  const rawT = (data && data.tasks) || [], rawH = (data && data.themes) || [];
  if (!rawT.length) return note('표시할 업무가 없습니다');
  const known = new Set(rawH.map(h => h.id)), thOf = t => (known.has(t.theme) ? t.theme : '__etc');
  const usedTh = new Set(rawT.map(thOf));
  const themes = rawH.filter(h => usedTh.has(h.id)).concat(usedTh.has('__etc') ? [{ id: '__etc', name: '기타', color: '#9b9490' }] : []);
  const kinds = (data && data.kinds) || {}, kindKeys = Object.keys(kinds);
  const kName = k => (kinds[k] && (kinds[k].name || kinds[k].label)) || k, kCol = k => hexRGB(kinds[k] && kinds[k].color);
  const sesMin = s => (s.active > 0 ? s.active / 60 : Math.max(1, (s.end || 0) - (s.start || 0)));
  let dMin = Infinity, dMax = -Infinity;
  rawT.forEach(t => (t.sessions || []).forEach(s => { if (typeof s.d === 'number' && isFinite(s.d)) { if (s.d < dMin) dMin = s.d; if (s.d > dMax) dMax = s.d; } }));
  if (!isFinite(dMin)) { dMin = 0; dMax = 0; }
  const BIN = Math.ceil((dMax - dMin + 1) / 30), D = Math.max(1, Math.ceil((dMax - dMin + 1) / BIN));   // 고리 30개 넘으면 며칠씩 묶는다
  const ringOf = d => clamp(Math.floor((d - dMin) / BIN), 0, D - 1);
  let dRef = null;
  rawT.forEach(t => (t.sessions || []).forEach(s => { if (!dRef && typeof s.d === 'number' && /^\d+\/\d+/.test(String(s.when || ''))) { const m = String(s.when).split(' ')[0].split('/'); dRef = { d: s.d, mo: +m[0], da: +m[1] }; } }));
  const dayText = d => { if (!dRef) return (d - dMin + 1) + '일째'; const t = new Date(2026, dRef.mo - 1, dRef.da + (d - dRef.d)); return (t.getMonth() + 1) + '/' + t.getDate(); };

  const TH = themes.map((h, j) => ({ id: h.id, j, name: String(h.name || ''), rgb: hexRGB(h.color), tasks: [], mins: 0, ns: 0, ni: 0 }));
  const thById = new Map(TH.map(x => [x.id, x]));
  let maxSes = 1;
  const TK = rawT.map((t, i) => {
    const ses = (t.sessions || []).filter(s => typeof s.d === 'number' && isFinite(s.d)).map(s => { const m = sesMin(s); if (m > maxSes) maxSes = m; return { s, k: ringOf(s.d), m }; });
    let last = -1, lastD = null; ses.forEach(o => { if (o.k > last) last = o.k; if (lastD === null || o.s.d > lastD) lastD = o.s.d; }); if (last < 0) last = D - 1;
    const items = t.items || {}, kl = [];
    new Set([...kindKeys, ...Object.keys(items)]).forEach(k => { const a = Array.isArray(items[k]) ? items[k] : []; if (a.length) kl.push({ k, n: a.length }); });
    return { t, i, id: t.id, title: String(t.title || ''), th: thById.get(thOf(t)), mins: Math.max(0, +t.mins || 0), ses, last, lastTxt: lastD === null ? '없음' : dayText(lastD), kl, ni: kl.reduce((a, o) => a + o.n, 0), rel: [], hx: new Float32Array(kl.length), hy: new Float32Array(kl.length) };
  });
  TK.forEach(k => { k.th.tasks.push(k); k.th.mins += k.mins; k.th.ns += k.ses.length; k.th.ni += k.ni; });
  const NT = TH.length, NK = TK.length, totMin = TH.reduce((a, x) => a + x.mins, 0), maxMin = Math.max(1, ...TK.map(k => k.mins));
  TH.forEach(x => { x.dTxt = 'd = ' + (totMin > 0 ? x.mins / totMin : x.tasks.length / NK).toFixed(4); x.css = `rgb(${x.rgb})`; });
  const byId = new Map(TK.map(k => [k.id, k]));
  const RL = ((data && data.rel) || []).map(r => ({ a: byId.get(r[0]), b: byId.get(r[1]), n: +r[2] || 1 })).filter(r => r.a && r.b && r.a !== r.b).sort((p, q) => q.n - p.n).slice(0, 160);
  const relMax = RL.length ? RL[0].n : 1;
  RL.forEach((r, q) => { r.a.rel.push(r); r.b.rel.push(r); r.ph = q * 2.399; r.strong = r.n / relMax > 0.55; });

  // ---- 살: 맨 위 한 가닥 = 날짜 자, 그다음 분야마다 부채꼴(폭 = 시간 몫과 업무 수를 섞음). 가운데 굵은 살 = 분야, 나머지 = 업무, 남는 자리는 빈 살 ----
  TH.forEach(x => { x.w = 0.55 * (totMin > 0 ? x.mins / totMin : 1 / NT) + 0.45 * (x.tasks.length + 1) / (NK + NT); });
  const GAP = clamp(TAU / (NK + NT + 1) * 0.7, 0.035, 0.16), avail = TAU - GAP * (NT + 1), STEP = avail / 30;
  const RAD = [{ th: -Math.PI / 2, kind: 0 }];   // kind 0 날짜 자, 1 분야, 2 업무, 3 빈 살
  let a0 = -Math.PI / 2 + GAP;
  TH.forEach(x => {
    const A = avail * x.w, n = x.tasks.length, m = Math.max(n + 1, Math.round(A / STEP)), c = Math.floor(m / 2);
    const others = []; for (let p = 0; p < m; p++) if (p !== c) others.push(p);
    const pick = Array.from({ length: n }, (_, q) => others[Math.floor((q + 0.5) * others.length / n)]).sort((p, q) => Math.abs(p - c) - Math.abs(q - c) || p - q);
    const own = new Map(); x.tasks.slice().sort((p, q) => q.mins - p.mins || p.i - q.i).forEach((k, q) => own.set(pick[q], k));   // 큰 업무일수록 분야 살 가까이
    for (let p = 0; p < m; p++) { const k = own.get(p), r = { th: a0 + A * (p + 0.5) / m, kind: p === c ? 1 : k ? 2 : 3, x, k }; RAD.push(r); if (p === c) x.spoke = r; if (k) k.rad = r; }
    a0 += A + GAP;
  });
  const S = RAD.length;
  RAD.forEach((r, j) => { r.j = j; r.phi = (r.th + Math.PI / 2) / TAU; });
  TH.forEach(x => { x.rads = RAD.filter(r => r.x === x); x.rim = x.rgb.map(v => Math.round(v * 0.6 + 251 * 0.4)).join(','); });   // 나선은 날짜 자에서 시작해 시계 방향으로 한 바퀴에 하루씩 바깥으로

  // ---- 캔버스, 풀이표, 범례 ----
  const cv = document.createElement('canvas'), ctx = cv.getContext('2d');
  cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block;touch-action:none';
  cv.setAttribute('role', 'img'); cv.setAttribute('aria-label', `거미줄: 가운데 나, 분야 ${NT}개, 업무 ${NK}개`);
  const mesh = window.G3D && window.G3D.mesh ? window.G3D.mesh(main, 0.8) : null;
  main.appendChild(cv);
  const HALO = 'text-shadow:0 0 5px rgba(36,21,15,.9),0 0 1.5px rgba(36,21,15,.9)';
  const tip = document.createElement('div');
  tip.style.cssText = `position:absolute;left:0;top:0;z-index:6;pointer-events:none;white-space:nowrap;color:#FBF7F0;${HALO};opacity:0;transition:opacity .15s;will-change:transform`;
  const tipRows = [`font:italic 11px/1.3 ${SERIF};opacity:.8`, `font:600 14px/1.4 ${FONT}`, `font:italic 11.5px/1.45 ${SERIF};opacity:.92`, `font:11px/1.45 ${FONT};opacity:.86`]
    .map(cs => { const d = document.createElement('div'); d.style.cssText = cs; tip.appendChild(d); return d; });
  main.appendChild(tip);
  const lg = document.createElement('div');
  lg.style.cssText = `position:absolute;left:16px;bottom:12px;z-index:4;pointer-events:none;display:flex;flex-wrap:wrap;align-items:center;gap:3px 14px;max-width:calc(100% - 32px);font:11px/1.5 ${FONT};color:rgba(251,247,240,.9);${HALO}`;
  {
    const C = 'rgba(251,247,240,.92)', sv = (w, p) => `<svg width="${w}" height="12" viewBox="0 0 ${w} 12" style="flex:none;overflow:visible">${p}</svg>`;
    const item = (svg, txt, gap = 5) => { const s = document.createElement('span'); s.style.cssText = `display:inline-flex;align-items:center;gap:${gap}px;white-space:nowrap`; s.innerHTML = svg; s.appendChild(document.createTextNode(txt)); lg.appendChild(s); return s; };
    item(sv(12, `<circle cx="6" cy="6" r="5" fill="${C}" fill-opacity=".22"/><circle cx="6" cy="6" r="1.8" fill="${C}"/>`), '가운데 = 나');
    item(sv(18, `<path d="M1 11L17 1" stroke="${C}" stroke-width="1.3"/><path d="M1 11L17 7" stroke="${C}" stroke-width=".6" stroke-opacity=".7"/>`), '살 = 분야');
    item(sv(14, `<path d="M7 6a1 1 0 0 1 1 1a2 2 0 0 1-2 2a3 3 0 0 1-3-3a4 4 0 0 1 4-4a5 5 0 0 1 5 5" fill="none" stroke="${C}" stroke-width=".8"/>`), '나선 = 날짜');
    item(sv(12, `<circle cx="6" cy="6" r="5" fill="${C}" fill-opacity=".3" stroke="${C}" stroke-width=".8"/><circle cx="4.4" cy="4.2" r="1.3" fill="#fff"/>`), '이슬 = 업무');
    item(sv(18, `<path d="M0 4L11 4" stroke="${C}" stroke-width=".5" stroke-opacity=".7"/><circle cx="3" cy="4" r="1.7" fill="${C}"/><circle cx="8" cy="4" r="1.2" fill="${C}"/><path d="M15 1V8" stroke="${C}" stroke-width=".6"/><circle cx="15" cy="9.6" r="1.7" fill="${C}"/>`), '작은 물방울 = 세션, 자료');
    item(sv(22, `<path d="M1 3Q11 15 21 3" fill="none" stroke="${C}" stroke-width=".8"/>`), '늘어진 실 = 관계');
    const kUsed = kindKeys.filter(k => TK.some(t => t.kl.some(o => o.k === k)));
    if (kUsed.length) {
      const g = item('', '자료 색', 8);
      kUsed.forEach(k => { const e = document.createElement('span'); e.style.cssText = 'display:inline-flex;align-items:center;gap:3px'; e.innerHTML = sv(7, `<circle cx="3.5" cy="6" r="2.7" fill="rgb(${kCol(k)})" stroke="${C}" stroke-width=".5"/>`); e.appendChild(document.createTextNode(kName(k))); g.appendChild(e); });
    }
  }
  main.appendChild(lg);

  // ---- 미리 그린 조각: 이슬(분야 빛깔), 오팔 테, 반사광, 작은 물방울, 가운데 빛, 반짝임 ----
  const sprite = (s, fn) => { const c = document.createElement('canvas'); c.width = c.height = s; fn(c.getContext('2d'), s / 2); return c; };
  const OPAL = ['255,196,218', '255,229,176', '196,242,216', '176,214,255', '218,194,255'];
  const conic = (g, o, cols) => {
    const gr = g.createConicGradient ? g.createConicGradient(0.6, o, o) : g.createLinearGradient(0, 0, o * 2, o * 2);
    cols.forEach((c, q) => gr.addColorStop(q / (cols.length - 1), `rgb(${c})`)); return gr;
  };
  const DS = 128, DO = 64, DR = 58, DF = DO / DR;   // 이슬 조각: 반지름 DR, 그릴 때 반폭 = r * DF
  const dropSpr = TH.map(x => sprite(DS, (g, o) => {
    let gr = g.createRadialGradient(o, o, DR * 0.85, o, o, o);
    gr.addColorStop(0, 'rgba(255,248,236,0.2)'); gr.addColorStop(1, 'rgba(255,248,236,0)'); g.fillStyle = gr; g.fillRect(0, 0, DS, DS);
    g.save(); g.beginPath(); g.arc(o, o, DR, 0, TAU); g.clip();
    gr = g.createRadialGradient(o, o + DR * 0.22, DR * 0.08, o, o + DR * 0.1, DR * 1.04);   // 젖빛 몸통: 가운데 밝고 가장자리는 굴절로 어둡게
    gr.addColorStop(0, 'rgba(255,252,246,0.6)'); gr.addColorStop(0.55, 'rgba(236,228,218,0.36)'); gr.addColorStop(0.85, 'rgba(120,100,88,0.3)'); gr.addColorStop(1, 'rgba(48,34,28,0.55)');
    g.fillStyle = gr; g.fillRect(0, 0, DS, DS);
    gr = g.createRadialGradient(o, o, 0, o, o, DR); gr.addColorStop(0, `rgba(${x.rgb},0.34)`); gr.addColorStop(1, `rgba(${x.rgb},0.06)`); g.fillStyle = gr; g.fillRect(0, 0, DS, DS);
    gr = g.createLinearGradient(0, o - DR, 0, o + DR * 0.1); gr.addColorStop(0, 'rgba(36,21,15,0.34)'); gr.addColorStop(1, 'rgba(36,21,15,0)'); g.fillStyle = gr; g.fillRect(0, 0, DS, DS);
    gr = g.createRadialGradient(o, o + DR * 0.8, 0, o, o + DR * 0.8, DR * 0.72); gr.addColorStop(0, 'rgba(255,255,252,0.9)'); gr.addColorStop(1, 'rgba(255,255,252,0)'); g.fillStyle = gr; g.fillRect(0, 0, DS, DS);
    g.restore();
    g.beginPath(); g.arc(o, o, DR - 0.8, 0, TAU); g.lineWidth = 1.8; g.strokeStyle = 'rgba(255,250,242,0.6)'; g.stroke();
  }));
  const opalSpr = sprite(DS, (g, o) => {
    g.fillStyle = conic(g, o, [...OPAL, OPAL[0]]); g.beginPath(); g.arc(o, o, DR, 0, TAU); g.fill();
    g.globalCompositeOperation = 'destination-in';   // 진주빛은 가장자리 쪽에만
    const gr = g.createRadialGradient(o, o, DR * 0.35, o, o, DR); gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(0.75, 'rgba(0,0,0,0.22)'); gr.addColorStop(1, 'rgba(0,0,0,0.5)'); g.fillStyle = gr; g.fillRect(0, 0, DS, DS);
    g.globalCompositeOperation = 'source-over';
    g.lineWidth = 4.5; g.strokeStyle = conic(g, o, [OPAL[2], OPAL[3], OPAL[4], OPAL[0], OPAL[1], OPAL[2]]); g.globalAlpha = 0.75; g.beginPath(); g.arc(o, o, DR - 2.5, 0, TAU); g.stroke();
  });
  const specSpr = sprite(32, (g, o) => { const gr = g.createRadialGradient(o, o, 0, o, o, o); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.4, 'rgba(255,255,255,0.7)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, 32, 32); });
  const beadSpr = sprite(32, (g, o) => {
    const R = o - 2, gr = g.createRadialGradient(o - R * 0.3, o - R * 0.32, 0, o, o, R);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.4, 'rgba(250,244,236,0.78)'); gr.addColorStop(0.82, 'rgba(206,192,182,0.5)'); gr.addColorStop(1, 'rgba(70,52,44,0.6)');
    g.fillStyle = gr; g.beginPath(); g.arc(o, o, R, 0, TAU); g.fill();
  });
  const kSpr = new Map(), kindSpr = k => {
    if (!kSpr.has(k)) { const c = kCol(k); kSpr.set(k, sprite(24, (g, o) => { const gr = g.createRadialGradient(o - 3, o - 3, 0, o, o, o - 1); gr.addColorStop(0, 'rgba(255,255,255,0.95)'); gr.addColorStop(0.4, `rgba(${c},0.95)`); gr.addColorStop(1, `rgba(${c.map(v => v * 0.6 | 0)},0.85)`); g.fillStyle = gr; g.beginPath(); g.arc(o, o, o - 1, 0, TAU); g.fill(); })); }
    return kSpr.get(k);
  };
  const glowSpr = sprite(128, (g, o) => { const gr = g.createRadialGradient(o, o, 0, o, o, o); gr.addColorStop(0, 'rgba(255,248,232,0.95)'); gr.addColorStop(0.18, 'rgba(255,240,215,0.45)'); gr.addColorStop(0.5, 'rgba(255,236,210,0.12)'); gr.addColorStop(1, 'rgba(255,236,210,0)'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128); });
  const starSpr = sprite(64, (g, o) => {
    let gr = g.createRadialGradient(o, o, 0, o, o, o * 0.35); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
    [[1, 0.06], [0.06, 1]].forEach(([sx, sy]) => { g.save(); g.translate(o, o); g.scale(sx, sy); gr = g.createRadialGradient(0, 0, 0, 0, 0, o); gr.addColorStop(0, 'rgba(255,255,255,0.95)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.beginPath(); g.arc(0, 0, o, 0, TAU); g.fill(); g.restore(); });
  });

  // ---- 그물 짜기 (크기가 바뀌면 다시) ----
  const KH = 0.006, DAMP = 0.986, SAG = 0.05;   // 제자리로 끄는 힘, 감쇠, 나선 실 처짐(길이 비)
  const F_TH = `700 12.5px ${FONT}`, F_D = `italic 10.5px ${SERIF}`, F_HUB = `700 15px ${FONT}`, F_DATE = `italic 10px ${SERIF}`, F_TASK = `600 11.5px ${FONT}`;
  let W = 0, H = 0, dpr = 1, sc = 1, cx = 0, cy = 0, hub = 0, N = 0, E = 0, dateStep = 1, ready = false;
  let RX, RY, UX, UY, VX, VY, IM, FX, FY, WX, WY, PX, PY, EA, EB, EK, ET, spir, frameLoop, anchors = [], beads = [];
  function layout() {
    const nd = [], ed = [];
    const add = (x, y, pin) => { nd.push(x, y, pin ? 1 : 0); return nd.length / 3 - 1; };
    const link = (a, b, k, ty) => { ed.push(a, b, k, ty); };
    sc = clamp(Math.min(W, H) / 900, 0.62, 1.45); cx = W * 0.5; cy = H * 0.5;
    const Rx = Math.max(40, W / 2 - clamp(W * 0.1, 78, 150)), Ry = Math.max(40, H / 2 - clamp(H * 0.09, 54, 92));   // 나선은 타원: 넓은 화면도 끝까지
    const RHO0 = 0.12, dR = (1 - RHO0) / D;
    hub = add(cx, cy);
    const NV = W / H > 1.25 ? 8 : 7, fr = rng(hash('틀' + NV)), FV = [];   // 바깥 틀: 화면 가장자리 가까이 꼭짓점, 닻실은 화면 밖으로
    for (let v = 0; v < NV; v++) {
      const al = -Math.PI / 2 + (v + 0.5) * TAU / NV + (fr() - 0.5) * 0.3, dx = Math.cos(al), dy = Math.sin(al);
      const tx = dx > 1e-6 ? (W - 4 - cx) / dx : dx < -1e-6 ? (4 - cx) / dx : 1e9, ty = dy > 1e-6 ? (H - 4 - cy) / dy : dy < -1e-6 ? (4 - cy) / dy : 1e9;
      const t = Math.min(tx, ty) * (0.9 + fr() * 0.08);
      FV.push({ al, x: cx + dx * t, y: cy + dy * t, id: 0 });
    }
    const hitFrame = (dx, dy) => {
      let best = 1e9;
      for (let v = 0; v < NV; v++) {
        const A = FV[v], B = FV[(v + 1) % NV], ex = B.x - A.x, ey = B.y - A.y, den = dx * ey - dy * ex; if (Math.abs(den) < 1e-9) continue;
        const ax = A.x - cx, ay = A.y - cy, t = (ax * ey - ay * ex) / den, s = (ax * dy - ay * dx) / den;
        if (t > 0 && s > -1e-6 && s < 1 + 1e-6 && t < best) best = t;
      }
      return best;
    };
    const H1 = 7 * sc, H2 = 17 * sc;   // 가운데 촘촘한 고리 둘
    spir = new Int32Array(D * S);
    for (const r of RAD) {
      const ex = Rx * Math.cos(r.th), ey = Ry * Math.sin(r.th), L = Math.hypot(ex, ey), dx = ex / L, dy = ey / L, list = [hub], dist = [0];
      const put = d => { list.push(add(cx + dx * d, cy + dy * d)); dist.push(d); };
      put(H1); put(H2);
      const d0 = (RHO0 + r.phi * dR) * L, nf = Math.max(0, Math.ceil((d0 - H2) / (36 * sc)) - 1);
      for (let q = 1; q <= nf; q++) put(H2 + (d0 - H2) * q / (nf + 1));
      r.k0 = list.length;
      for (let k = 0; k < D; k++) { put((RHO0 + (k + r.phi) * dR) * L); spir[k * S + r.j] = list[list.length - 1]; }
      const dl = dist[dist.length - 1], df = Math.max(dl + 14 * sc, hitFrame(dx, dy)), no = Math.max(1, Math.ceil((df - dl) / (40 * sc)) - 1);
      for (let q = 1; q <= no; q++) put(dl + (df - dl) * q / (no + 1));
      put(df);
      Object.assign(r, { dx, dy, list, dist, dl, df, end: list[list.length - 1], rimF: Math.min(0.9, 13 * sc / (dist[r.k0 + D] - dl)) });
      const ty = r.kind === 1 ? 2 : r.kind === 2 ? 1 : 3;
      for (let q = 1; q < list.length; q++) link(list[q - 1], list[q], q <= 2 ? 0.2 : 0.15, ty);
    }
    for (let j = 0; j < S; j++) { const a = RAD[j].list, b = RAD[(j + 1) % S].list; link(a[1], b[1], 0.18, 6); link(a[2], b[2], 0.18, 6); }
    for (let g = 0; g < D * S - 1; g++) link(spir[g], spir[g + 1], 0.1, 0);
    const fl = RAD.map(r => ({ id: r.end, a: Math.atan2(r.dy, r.dx) }));
    FV.forEach(v => { v.id = add(v.x, v.y); fl.push({ id: v.id, a: Math.atan2(v.y - cy, v.x - cx) }); });
    fl.sort((p, q) => p.a - q.a); frameLoop = fl.map(f => f.id);
    fl.forEach((f, q) => link(f.id, fl[(q + 1) % fl.length].id, 0.24, 4));
    const LP = 0.5 * Math.max(W, H); anchors = [];
    FV.forEach(v => [-0.32, 0.27].forEach(s => { const p = add(v.x + Math.cos(v.al + s) * LP, v.y + Math.sin(v.al + s) * LP, true); link(v.id, p, 0.26, 5); anchors.push(v.id, p); }));

    N = nd.length / 3; E = ed.length / 4;
    const F = () => new Float32Array(N);
    RX = F(); RY = F(); UX = F(); UY = F(); VX = F(); VY = F(); IM = F(); FX = F(); FY = F(); WX = F(); WY = F(); PX = F(); PY = F();
    EA = new Int32Array(E); EB = new Int32Array(E); EK = new Float32Array(E); ET = new Uint8Array(E);
    const ks = F();
    for (let e = 0; e < E; e++) { EA[e] = ed[4 * e]; EB[e] = ed[4 * e + 1]; EK[e] = ed[4 * e + 2]; ET[e] = ed[4 * e + 3]; ks[EA[e]] += EK[e]; ks[EB[e]] += EK[e]; }
    for (let i = 0; i < N; i++) { RX[i] = PX[i] = nd[3 * i]; RY[i] = PY[i] = nd[3 * i + 1]; IM[i] = nd[3 * i + 2] ? 0 : Math.min(1, 0.85 / (ks[i] + KH)); }   // 실이 많이 모인 마디는 무겁게(가운데가 튀지 않게)

    // 이슬(업무): 그 업무 살과 마지막 날 나선이 만나는 마디
    const dS = clamp(Math.sqrt(36 / NK), 0.62, 1.15) * sc;
    TK.forEach(k => { k.node = spir[k.last * S + k.rad.j]; k.r = dS * (4 + 10 * Math.sqrt(k.mins / maxMin)); k.px = RX[k.node]; k.py = RY[k.node] + k.r * 0.3; k.wx = k.wy = 0; k.path = k.rad.list.slice(0, k.rad.k0 + k.last + 1); });
    // 작은 물방울(세션): 그날 나선 위, 업무 살 양옆으로 줄지어
    beads = [];
    TK.forEach(k => {
      const by = new Map(); k.ses.forEach(o => { let a = by.get(o.k); if (!a) by.set(o.k, a = []); a.push(o); });
      by.forEach((arr, ring) => {
        arr.sort((p, q) => q.m - p.m);
        const top = ring === k.last, g = ring * S + k.rad.j;
        arr.forEach((o, q) => {
          const side = q % 2 ? -1 : 1, lvl = top ? Math.floor(q / 2) + 1 : Math.ceil(q / 2), off = clamp(side * (lvl * 0.15 + (top ? 0.06 : 0)), -0.47, 0.47);
          let A = off >= 0 ? g : g - 1, B = off >= 0 ? g + 1 : g, f = off >= 0 ? off : 1 + off;
          if (A < 0 || B >= D * S) { A = B = g; f = 0; }
          beads.push({ k, o, a: spir[A], b: spir[B], f, r: dS * (1.1 + 2.1 * Math.sqrt(o.m / maxSes)), x: 0, y: 0 });
        });
      });
    });
    // 분야 이름: 굵은 살의 나선 바깥과 틀 사이 가운데
    ctx.font = F_TH; TH.forEach(x => { x.nw = ctx.measureText(x.name).width; });
    ctx.font = F_D; TH.forEach(x => { x.dw = ctx.measureText(x.dTxt).width; });
    TH.forEach(x => {
      const r = x.spoke, tgt = r.dl + (r.df - r.dl) * 0.5; let best = r.k0 + D - 1;
      for (let q = best; q < r.list.length; q++) if (Math.abs(r.dist[q] - tgt) < Math.abs(r.dist[best] - tgt)) best = q;
      x.ln = r.list[best]; x.right = r.dx < -0.3;
      x.box = thBox(x, RX[x.ln], RY[x.ln]);
    });
    // 날짜: 날짜 자 위, 글자가 겹치지 않을 만큼 건너뛴다(가장 최근 날은 늘)
    dateStep = Math.max(1, Math.ceil(13 / Math.max(1, dR * Ry)));
    // 큰 업무 이름: 겹치지 않는 자리만 (자리는 처음 한 번 정하고 흔들림은 따라간다)
    const occ = TH.map(x => x.box), mr = main.getBoundingClientRect(), lr = lg.getBoundingClientRect();
    occ.push([lr.left - mr.left - 6, lr.top - mr.top - 6, lr.width + 12, lr.height + 12], [cx - 46, cy + 10 * sc, 92, 36]);
    { const ru = RAD[0], yTop = RY[ru.list[ru.k0 + D - 1]], yBot = RY[ru.list[ru.k0]]; occ.push([cx - 3, yTop - 8, 40, yBot - yTop + 16]); }
    const drops = TK.map(k => [k.px - k.r, k.py - k.r, 2 * k.r, 2 * k.r]);
    const hits = (b, self) => occ.some(q => b[0] < q[0] + q[2] && b[0] + b[2] > q[0] && b[1] < q[1] + q[3] && b[1] + b[3] > q[1]) || drops.some((q, i) => i !== self && b[0] < q[0] + q[2] && b[0] + b[2] > q[0] && b[1] < q[1] + q[3] && b[1] + b[3] > q[1]);
    const K = clamp(Math.round(W * H / 150000), 3, 10);
    ctx.font = F_TASK; TK.forEach(k => { k.lab = null; });
    TK.slice().sort((p, q) => q.mins - p.mins).slice(0, K).forEach(k => {
      const t = trunc(k.title, 14), w = ctx.measureText(t).width, x = k.px, y = k.py, g = k.r + 6, east = x >= cx;
      const cands = [[east ? g : -g, 0, east ? 'left' : 'right'], [0, -g - 4, 'center'], [0, g + 6, 'center'], [east ? -g : g, 0, east ? 'right' : 'left']];
      for (const [ox, oy, al] of cands) {
        const x0 = al === 'left' ? x + ox : al === 'right' ? x + ox - w : x - w / 2, b = [x0 - 2, y + oy - 8, w + 4, 16];
        if (b[0] < 6 || b[0] + b[2] > W - 6 || b[1] < 6 || b[1] + b[3] > H - 6 || hits(b, k.i)) continue;
        k.lab = { t, ox, oy, al }; occ.push(b); break;
      }
    });
    ready = true;
  }
  function thBox(x, px, py) {   // 분야 이름 자리 [x, y, w, h]와 글 시작점
    const w = Math.max(x.nw + 10, x.dw + 10), ty = clamp(py - 6, 14, H - 34);
    let tx = x.right ? px - 9 : px + 9; tx = x.right ? Math.max(tx, w + 10) : Math.min(tx, W - 10 - w);
    x.tx = tx; x.ty = ty;
    return [x.right ? tx - w - 4 : tx - 4, ty - 11, w + 8, 32];
  }

  // ---- 움직임: 바람, 튕김, 숨쉬기 ----
  const mq = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
  let MOVE = mq && mq.matches ? 0.05 : 1;
  const onMq = () => { MOVE = mq.matches ? 0.05 : 1; };
  if (mq && mq.addEventListener) mq.addEventListener('change', onMq);
  let T = 0, last = 0, raf = 0, hv = 0, hov = null, hovKey = '', mouse = null, down = null, LX = 0, LY = 0, tipW = 0, tipH = 0;
  function step(dt) {
    const n = clamp(Math.round(dt * 120), 1, 5), gust = (0.7 + 0.3 * Math.sin(T * 0.13)) * 0.05 * sc * MOVE, lim = 46 * sc, lim2 = lim * lim;
    for (let i = 0; i < N; i++) {
      if (!IM[i]) continue;
      const x = RX[i], y = RY[i];
      WX[i] = gust * (0.6 * Math.sin(T * 0.53 + x * 0.0042 + 0.4) + 0.4 * Math.sin(T * 1.07 - y * 0.0051 + 1.9) + 0.3 * Math.sin(T * 1.7 + (x + y) * 0.012));
      WY[i] = gust * (0.45 * Math.sin(T * 0.41 + y * 0.0037 + 2.6) + 0.35 * Math.sin(T * 0.83 + x * 0.0029) + 0.25 * Math.sin(T * 1.9 + (x - y) * 0.011));
    }
    for (let s = 0; s < n; s++) {
      for (let i = 0; i < N; i++) { FX[i] = WX[i] - KH * UX[i]; FY[i] = WY[i] - KH * UY[i]; }
      for (let e = 0; e < E; e++) { const a = EA[e], b = EB[e], k = EK[e], dx = (UX[b] - UX[a]) * k, dy = (UY[b] - UY[a]) * k; FX[a] += dx; FY[a] += dy; FX[b] -= dx; FY[b] -= dy; }
      for (let i = 0; i < N; i++) {
        const m = IM[i]; if (!m) continue;
        VX[i] = (VX[i] + FX[i] * m) * DAMP; VY[i] = (VY[i] + FY[i] * m) * DAMP; UX[i] += VX[i]; UY[i] += VY[i];
        const u2 = UX[i] * UX[i] + UY[i] * UY[i]; if (u2 > lim2) { const f = lim / Math.sqrt(u2); UX[i] *= f; UY[i] *= f; }
      }
    }
  }
  const pluck = (x0, y0, x1, y1) => {   // 커서가 지나간 선분 가까운 마디를 커서 방향으로 민다
    let dx = x1 - x0, dy = y1 - y0; const l = Math.hypot(dx, dy); if (l < 0.5 || !ready) return;
    const cap = Math.min(1, 36 / l); dx *= cap; dy *= cap;
    const R = 20 * sc, R2 = R * R, amp = 0.6 * (MOVE < 1 ? 0.25 : 1), L2 = (x1 - x0) ** 2 + (y1 - y0) ** 2;
    for (let i = 0; i < N; i++) {
      if (!IM[i]) continue;
      const qx = PX[i] - x0, qy = PY[i] - y0, u = clamp((qx * (x1 - x0) + qy * (y1 - y0)) / L2, 0, 1), ex = qx - (x1 - x0) * u, ey = qy - (y1 - y0) * u, d2 = ex * ex + ey * ey;
      if (d2 > R2) continue;
      const f = 1 - Math.sqrt(d2) / R, w = f * f * amp; VX[i] += dx * w; VY[i] += dy * w;
    }
    for (const k of TK) { const ex = k.px - x1, ey = k.py - y1, rr = k.r + 18 * sc; if (ex * ex + ey * ey < rr * rr) { k.wx += dx * 0.22; k.wy += dy * 0.22; } }
  };
  const twang = (x, y) => {   // 빈 곳을 누르면 그 자리에서 둥글게 퍼지는 떨림
    const R = 140 * sc, a = 5 * (MOVE < 1 ? 0.25 : 1);
    for (let i = 0; i < N; i++) { if (!IM[i]) continue; const ex = PX[i] - x, ey = PY[i] - y, d = Math.hypot(ex, ey); if (d > R || d < 0.01) continue; const f = (1 - d / R) ** 2 * a / d; VX[i] += ex * f; VY[i] += ey * f; }
  };

  // ---- 가리키기 ----
  const pick = () => {
    if (!mouse || !ready) return null;
    const mx = mouse.x, my = mouse.y; let best = null, bd = 1e9;
    for (const k of TK) { const d = Math.hypot(k.px - mx, k.py - my) - k.r; if (d < 5 && d < bd) { bd = d; best = k; } }
    if (best) return { type: 'task', k: best, key: 't' + best.i };
    for (const x of TH) { const b = x.box; if (mx >= b[0] && mx <= b[0] + b[2] && my >= b[1] && my <= b[1] + b[3]) return { type: 'theme', x, key: 'h' + x.j }; }
    let bb = null; bd = 1e9;
    for (const b of beads) { const d = Math.hypot(b.x - mx, b.y - my); if (d < b.r + 3.5 && d < bd) { bd = d; bb = b; } }
    return bb ? { type: 'ses', b: bb, k: bb.k, key: 's' + beads.indexOf(bb) } : null;
  };
  const tipFor = h => {
    if (h.type === 'task') { const k = h.k; return ['업무', trunc(k.title, 40), `${fmtT(k.mins)}, 세션 ${k.ses.length}개, 마지막 ${k.lastTxt}`, k.kl.length ? '자료 ' + k.kl.map(o => `${kName(o.k)} ${o.n}`).join(', ') : '']; }
    if (h.type === 'theme') { const x = h.x; return ['분야', x.name, `${fmtT(x.mins)}, 몫 ${x.dTxt.slice(4)}`, `업무 ${x.tasks.length}개, 세션 ${x.ns}개, 자료 ${x.ni}개`]; }
    const b = h.b; return ['세션', trunc(b.k.title, 40), `${b.o.s.when || dayText(b.o.s.d)}, ${fmtT(b.o.m)}`, ''];
  };
  const pos = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  const onMove = e => { const p = pos(e); if (mouse) pluck(mouse.x, mouse.y, p.x, p.y); mouse = p; };
  const onDown = e => { down = pos(e); };
  const onUp = e => {
    const p = pos(e); if (!down || Math.hypot(p.x - down.x, p.y - down.y) > 5) { down = null; return; }
    down = null; mouse = p; const h = pick();
    if (h && h.k) { if (ui && ui.open) ui.open(h.k.id); } else twang(p.x, p.y);
  };
  const onLeave = () => { mouse = null; };
  cv.addEventListener('pointermove', onMove); cv.addEventListener('pointerdown', onDown); cv.addEventListener('pointerup', onUp); cv.addEventListener('pointerleave', onLeave);

  // ---- 그리기 ----
  const IVR = '251,247,240';
  const text = (s, x, y, font, al, align) => {
    ctx.font = font; ctx.textAlign = align; ctx.textBaseline = 'middle';
    ctx.globalAlpha = al * 0.6; ctx.strokeStyle = 'rgb(36,21,15)'; ctx.lineWidth = 3; ctx.strokeText(s, x, y);
    ctx.globalAlpha = al; ctx.fillStyle = `rgb(${IVR})`; ctx.fillText(s, x, y);
  };
  let dim = 1;
  const silk = (w, a) => {   // 실 한 겹: 옅은 갈색 밑선(밝은 바탕에서도 보이게) + 상아색 실
    ctx.lineWidth = w + 1.4; ctx.strokeStyle = `rgba(36,21,15,${0.09 * dim})`; ctx.stroke();
    ctx.lineWidth = w; ctx.strokeStyle = `rgba(${IVR},${a * dim})`; ctx.stroke();
  };
  const poly = (L, n, wide, thin, al) => {   // 밝힌 길: 넓고 옅은 빛 + 갈색 밑선 + 가늘고 밝은 실
    ctx.beginPath(); ctx.moveTo(PX[L[0]], PY[L[0]]); for (let q = 1; q < n; q++) ctx.lineTo(PX[L[q]], PY[L[q]]);
    ctx.globalAlpha = 0.18 * al; ctx.lineWidth = wide; ctx.strokeStyle = 'rgb(255,240,214)'; ctx.stroke();
    ctx.globalAlpha = 0.3 * al; ctx.lineWidth = thin + 1.6; ctx.strokeStyle = 'rgb(36,21,15)'; ctx.stroke();
    ctx.globalAlpha = al; ctx.lineWidth = thin; ctx.strokeStyle = 'rgb(255,248,232)'; ctx.stroke();
  };
  const sagTo = (p, a, b) => { const ax = PX[a], ay = PY[a], bx = PX[b], by = PY[b]; p.quadraticCurveTo((ax + bx) / 2, (ay + by) / 2 + Math.hypot(bx - ax, by - ay) * SAG * 2, bx, by); };
  const relCurve = (r, p) => {
    const ax = r.a.px, ay = r.a.py, bx = r.b.px, by = r.b.py, sag = Math.hypot(bx - ax, by - ay) * 0.16 + 6 * sc;
    p.moveTo(ax, ay); p.quadraticCurveTo((ax + bx) / 2 + Math.sin(T * 0.6 + r.ph) * sag * 0.2, (ay + by) / 2 + sag * 2 * (1 + 0.07 * Math.sin(T * 0.8 + r.ph)), bx, by);
  };
  function draw() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.globalAlpha = 1;
    const hk = hov && hov.type === 'task' ? hov.k : null, hx = hov && hov.type === 'theme' ? hov.x : null; dim = 1 - 0.7 * hv;
    const focusA = k => (hk ? (k === hk ? 1 : k.rel.some(r => r.a === hk || r.b === hk) ? 0.75 : dim) : hx ? (k.th === hx ? 1 : dim) : 1);

    // 가운데 빛
    const gR = 50 * sc * (1 + 0.07 * Math.sin(T * 1.3));
    ctx.drawImage(glowSpr, PX[hub] - gR, PY[hub] - gR, gR * 2, gR * 2);
    // 닻실과 바깥 틀
    ctx.beginPath();
    for (let q = 0; q < anchors.length; q += 2) { ctx.moveTo(PX[anchors[q]], PY[anchors[q]]); ctx.lineTo(PX[anchors[q + 1]], PY[anchors[q + 1]]); }
    ctx.moveTo(PX[frameLoop[0]], PY[frameLoop[0]]); for (let q = 1; q < frameLoop.length; q++) ctx.lineTo(PX[frameLoop[q]], PY[frameLoop[q]]); ctx.closePath();
    silk(1.1, 0.44);
    // 살: 분야(굵게), 업무, 빈 살과 날짜 자
    for (let pass = 0; pass < 3; pass++) {
      ctx.beginPath();
      for (const r of RAD) {
        if ((r.kind === 1 ? 0 : r.kind === 2 ? 1 : 2) !== pass) continue;
        const L = r.list; ctx.moveTo(PX[L[0]], PY[L[0]]); for (let q = 1; q < L.length; q++) ctx.lineTo(PX[L[q]], PY[L[q]]);
      }
      silk(pass === 0 ? 1.35 : pass === 1 ? 0.8 : 0.62, pass === 0 ? 0.7 : pass === 1 ? 0.48 : 0.34);
    }
    // 가운데 고리
    ctx.beginPath();
    for (let g = 1; g <= 2; g++) { ctx.moveTo(PX[RAD[0].list[g]], PY[RAD[0].list[g]]); for (let j = 1; j <= S; j++) { const id = RAD[j % S].list[g]; ctx.lineTo(PX[id], PY[id]); } }
    ctx.lineWidth = 0.6; ctx.strokeStyle = `rgba(${IVR},${0.55 * dim})`; ctx.stroke();
    // 나선: 하루 한 바퀴, 최근일수록 밝게. 살 사이 실은 조금 처진다
    for (let k = 0; k < D; k++) {
      const g0 = k * S, g1 = Math.min(D * S - 1, g0 + S);
      ctx.beginPath(); ctx.moveTo(PX[spir[g0]], PY[spir[g0]]);
      for (let g = g0 + 1; g <= g1; g++) sagTo(ctx, spir[g - 1], spir[g]);
      silk(0.72, 0.22 + 0.3 * (D > 1 ? k / (D - 1) : 1));
    }
    // 분야 테: 나선 바깥 가장자리를 따라 분야 빛깔로 물든 실 한 가닥
    for (const x of TH) {
      ctx.beginPath(); let pa = -1;
      for (const r of x.rads) {
        const a = r.list[r.k0 + D - 1], b = r.list[r.k0 + D], f = r.rimF, px = PX[a] + (PX[b] - PX[a]) * f, py = PY[a] + (PY[b] - PY[a]) * f;
        if (pa < 0) ctx.moveTo(px, py); else ctx.lineTo(px, py); pa = 1;
      }
      const xa = hx ? (x === hx ? 1 : 0.35) : hk ? (hk.th === x ? 1 : 0.35) : 1;
      ctx.lineWidth = 2.6; ctx.strokeStyle = `rgba(36,21,15,${0.12 * xa})`; ctx.stroke();
      ctx.lineWidth = 1.5; ctx.strokeStyle = `rgba(${x.rim},${0.85 * xa})`; ctx.stroke();
    }
    // 날짜 자 눈금
    { const ru = RAD[0]; ctx.beginPath(); for (let k = 0; k < D; k++) { const id = ru.list[ru.k0 + k]; ctx.moveTo(PX[id] - 2.5, PY[id]); ctx.lineTo(PX[id] + 2.5, PY[id]); } ctx.lineWidth = 0.8; ctx.strokeStyle = `rgba(${IVR},${0.6 * dim})`; ctx.stroke(); }
    // 관계: 이슬 사이 늘어진 실
    if (RL.length) {
      const pw = new Path2D(), ps = new Path2D();
      for (const r of RL) { if (hk && (r.a === hk || r.b === hk)) continue; relCurve(r, r.strong ? ps : pw); }
      ctx.lineWidth = 0.7; ctx.strokeStyle = `rgba(${IVR},${0.26 * dim})`; ctx.stroke(pw);
      ctx.lineWidth = 0.95; ctx.strokeStyle = `rgba(${IVR},${0.42 * dim})`; ctx.stroke(ps);
    }
    // 무지개 반짝임: 빛 한 점에서 뻗은 선에 직각인 실 조각
    {
      const GP = []; for (let q = 0; q < 12; q++) GP.push(new Path2D());
      const fall = 1 / (0.5 * Math.max(W, H)) ** 2, band = 1 / (78 * sc), h = 0.34;
      for (let e = 0; e < E; e++) {
        const ty = ET[e]; if (ty === 6) continue;
        const a = EA[e], b = EB[e], ax = PX[a], ay = PY[a], dx = PX[b] - ax, dy = PY[b] - ay, l2 = dx * dx + dy * dy; if (l2 < 9) continue;
        const vib = Math.abs(VX[a]) + Math.abs(VY[a]) + Math.abs(VX[b]) + Math.abs(VY[b]);   // 튕긴 실: 떨리는 동안 빛이 실을 타고 번진다
        if (vib > 1.2) { const p = GP[vib > 4 ? 11 : 10]; p.moveTo(ax, ay); if (ty === 0) sagTo(p, a, b); else p.lineTo(ax + dx, ay + dy); }
        const mx = ax + dx * 0.5, my = ay + dy * 0.5, rx = mx - LX, ry = my - LY, r2 = rx * rx + ry * ry, l = Math.sqrt(l2), rl = Math.sqrt(r2) + 1e-3;
        const c = Math.abs(dx * rx + dy * ry) / (l * rl); if (c > 0.12) continue;
        const I = (1 - c / 0.12) / (1 + r2 * fall); if (I < 0.15) continue;
        const hb = ((rl * band - T * 0.05) % 1 + 1) % 1, p = GP[Math.floor(hb * 5) + (I > 0.5 ? 5 : 0)];
        if (ty === 0) { const sg = l * SAG; p.moveTo(mx - dx * h, my - dy * h + 0.54 * sg); p.quadraticCurveTo(mx, my + 1.46 * sg, mx + dx * h, my + dy * h + 0.54 * sg); }
        else { p.moveTo(mx - dx * h, my - dy * h); p.lineTo(mx + dx * h, my + dy * h); }
      }
      const gd = 1 - 0.45 * hv;
      for (let q = 0; q < 10; q++) { ctx.lineWidth = q < 5 ? 1.1 : 1.6; ctx.strokeStyle = `rgba(${OPAL[q % 5]},${(q < 5 ? 0.5 : 1) * gd})`; ctx.stroke(GP[q]); }
      ctx.lineWidth = 2.6; ctx.strokeStyle = 'rgba(36,21,15,0.16)'; ctx.stroke(GP[10]); ctx.stroke(GP[11]);
      ctx.lineWidth = 1.2; ctx.strokeStyle = 'rgba(255,226,170,0.7)'; ctx.stroke(GP[10]);
      ctx.lineWidth = 1.7; ctx.strokeStyle = 'rgba(255,240,205,1)'; ctx.stroke(GP[11]);
    }
    // 밝힌 길: 나 > 분야 살 > 업무 살 > 이슬, 그리고 관계 실
    if (hov && hv > 0.02) {
      if (hk) {
        poly(hk.th.spoke.list, hk.th.spoke.list.length, 4, 1.2, hv * 0.7);
        poly(hk.path, hk.path.length, 5, 1.5, hv);
        const pr = new Path2D(); hk.rel.forEach(r => relCurve(r, pr));
        ctx.globalAlpha = hv; ctx.lineWidth = 1.2; ctx.strokeStyle = 'rgb(255,236,206)'; ctx.stroke(pr);
        // 나에서 이슬로 흐르는 빛 한 점
        const L = hk.path; let tot = 0; for (let q = 1; q < L.length; q++) tot += Math.hypot(PX[L[q]] - PX[L[q - 1]], PY[L[q]] - PY[L[q - 1]]);
        let want = ((T / Math.max(0.05, MOVE) * 0.8) % 1) * tot;
        for (let q = 1; q < L.length; q++) {
          const sl = Math.hypot(PX[L[q]] - PX[L[q - 1]], PY[L[q]] - PY[L[q - 1]]);
          if (want <= sl || q === L.length - 1) { const f = sl ? Math.min(1, want / sl) : 0, x = PX[L[q - 1]] + (PX[L[q]] - PX[L[q - 1]]) * f, y = PY[L[q - 1]] + (PY[L[q]] - PY[L[q - 1]]) * f, s = 9 * sc; ctx.globalAlpha = hv; ctx.drawImage(starSpr, x - s, y - s, s * 2, s * 2); break; }
          want -= sl;
        }
      } else if (hx) {
        for (const r of RAD) if (r.x === hx && r.kind !== 3) poly(r.list, r.list.length, r.kind === 1 ? 5 : 3, r.kind === 1 ? 1.5 : 0.9, hv * (r.kind === 1 ? 1 : 0.7));
      }
      ctx.globalAlpha = 1;
    }
    // 자료: 이슬 아래 매달린 실과 끝 방울
    ctx.beginPath();
    for (const k of TK) {
      if (!k.kl.length) continue;
      const n = k.kl.length, sw = clamp(-k.wx * 0.07, -0.6, 0.6) + 0.12 * Math.sin(T * 0.9 + k.i * 1.3), bx = k.px, by = k.py + k.r * 0.8;
      for (let q = 0; q < n; q++) {
        const ang = Math.PI / 2 + sw + (q - (n - 1) / 2) * 0.32, len = (6 + 2.6 * Math.min(10, k.kl[q].n)) * sc;
        k.hx[q] = bx + Math.cos(ang) * len; k.hy[q] = by + Math.sin(ang) * len;
        if (focusA(k) > 0.99 || !hk && !hx) { ctx.moveTo(bx, by); ctx.lineTo(k.hx[q], k.hy[q]); }
      }
    }
    ctx.lineWidth = 0.55; ctx.strokeStyle = `rgba(${IVR},${hk || hx ? 0.8 : 0.5})`; ctx.stroke();
    for (const k of TK) {
      if (!k.kl.length) continue;
      ctx.globalAlpha = focusA(k) * 0.95;
      for (let q = 0; q < k.kl.length; q++) { const s = (1.3 + 0.22 * Math.min(6, k.kl[q].n)) * sc; ctx.drawImage(kindSpr(k.kl[q].k), k.hx[q] - s, k.hy[q] - s, s * 2, s * 2); }
    }
    // 세션: 나선 위 작은 물방울
    for (const b of beads) {
      const fa = focusA(b.k), r = b.r * (hov && hov.b === b ? 1.8 : hk === b.k ? 1.25 : 1);
      ctx.globalAlpha = fa * 0.92; ctx.drawImage(beadSpr, b.x - r, b.y - r, r * 2, r * 2);
    }
    // 이슬: 몸통, 도는 오팔 테, 빛 쪽 반사
    const sweep = (T % 7) / 7, gpos = sweep < 0.3 ? sweep / 0.3 * 1.5 - 0.25 : 9;
    for (const k of TK) {
      const fa = focusA(k), r = k.r * (1 + 0.035 * Math.sin(T * 1.7 + k.i)) * (k === hk ? 1 + 0.12 * hv : 1), hs = r * DF;
      const sp = Math.hypot(k.wx, k.wy), st = 1 + Math.min(0.32, sp * 0.045), vc = sp > 1e-4 ? k.wx / sp : 1, vs = sp > 1e-4 ? k.wy / sp : 0;   // 출렁일 때 움직이는 쪽으로 늘어난다
      const ma = vc * vc * st + vs * vs / st, mb = vc * vs * (st - 1 / st), md = vs * vs * st + vc * vc / st;
      ctx.setTransform(dpr * ma, dpr * mb, dpr * mb, dpr * md, dpr * k.px, dpr * k.py); ctx.globalAlpha = fa; ctx.drawImage(dropSpr[k.th.j], -hs, -hs, hs * 2, hs * 2);
      const ang = T * 0.35 + k.i * 1.7, c = Math.cos(ang), s = Math.sin(ang);
      ctx.setTransform(dpr * (ma * c + mb * s), dpr * (mb * c + md * s), dpr * (mb * c - ma * s), dpr * (md * c - mb * s), dpr * k.px, dpr * k.py); ctx.globalAlpha = fa * 0.8; ctx.drawImage(opalSpr, -hs, -hs, hs * 2, hs * 2);
      const la = Math.atan2(LY - k.py, LX - k.px), lc = Math.cos(la), ls = Math.sin(la), sx = k.px + lc * r * 0.48, sy = k.py + ls * r * 0.48;
      ctx.setTransform(dpr * lc, dpr * ls, -dpr * ls, dpr * lc, dpr * sx, dpr * sy); ctx.globalAlpha = fa * 0.95; ctx.drawImage(specSpr, -r * 0.2, -r * 0.38, r * 0.4, r * 0.76);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const u = k.px / W * 0.65 + k.py / H * 0.35, fl = Math.max(Math.exp(-(((u - gpos) / 0.035) ** 2)), Math.max(0, Math.sin(T * 0.7 + k.i * 2.4)) ** 60);
      if (fl > 0.04) { const z = r * (1.2 + 2.4 * fl); ctx.globalAlpha = fl * fa; ctx.drawImage(starSpr, sx - z, sy - z, z * 2, z * 2); }
    }
    // 글: 날짜, 나, 분야, 큰 업무
    { const ru = RAD[0]; for (let k = 0; k < D; k++) { if ((D - 1 - k) % dateStep) continue; const id = ru.list[ru.k0 + k]; text(dayText(dMin + k * BIN), PX[id] + 6, PY[id], F_DATE, (k === D - 1 ? 0.95 : 0.62) * (0.5 + 0.5 * dim), 'left'); } }
    text('나', PX[hub], PY[hub] + 24 * sc, F_HUB, 1, 'center');
    text(fmtT(totMin), PX[hub], PY[hub] + 24 * sc + 15, F_D, 0.9, 'center');
    for (const x of TH) {
      const al = hx ? (x === hx ? 1 : 0.4) : hk ? (hk.th === x ? 1 : 0.4) : 0.95;
      x.box = thBox(x, PX[x.ln], PY[x.ln]);
      const nx = x.right ? x.tx : x.tx + 10, dotX = x.right ? x.tx - x.nw - 7 : x.tx + 3;
      ctx.globalAlpha = al; ctx.fillStyle = x.css; ctx.beginPath(); ctx.arc(dotX, x.ty, 3, 0, TAU); ctx.fill();
      ctx.lineWidth = 0.8; ctx.strokeStyle = `rgba(${IVR},0.9)`; ctx.stroke();
      text(x.name, nx, x.ty, F_TH, al, x.right ? 'right' : 'left');
      text(x.dTxt, nx, x.ty + 15, F_D, al * 0.85, x.right ? 'right' : 'left');
    }
    for (const k of TK) if (k.lab && k !== hk) text(k.lab.t, k.px + k.lab.ox, k.py + k.lab.oy, F_TASK, focusA(k) * 0.92, k.lab.al);
    ctx.globalAlpha = 1;
  }

  const frame = now => {
    raf = requestAnimationFrame(frame);
    const dt = last ? clamp((now - last) / 1000, 0, 0.05) : 1 / 60; last = now;
    T += dt * MOVE;
    mesh?.draw(T * 1000 + 1);
    if (!ready) return;
    step(dt);
    const br = 1 + 0.007 * Math.sin(T * 0.5);   // 숨쉬기
    for (let i = 0; i < N; i++) { PX[i] = cx + (RX[i] - cx) * br + UX[i]; PY[i] = cy + (RY[i] - cy) * br + UY[i]; }
    for (const k of TK) { k.wx = (k.wx + (PX[k.node] - k.px) * 0.16) * 0.8; k.wy = (k.wy + (PY[k.node] + k.r * 0.3 - k.py) * 0.16) * 0.8; k.px += k.wx; k.py += k.wy; }   // 이슬은 늦게 따라와 출렁인다
    for (const b of beads) {
      const ax = PX[b.a], ay = PY[b.a], bx = PX[b.b], by = PY[b.b], f = b.f;
      b.x = ax + (bx - ax) * f; b.y = ay + (by - ay) * f + 4 * f * (1 - f) * Math.hypot(bx - ax, by - ay) * SAG + b.r * 0.3;
    }
    const al = -2.25 + 0.6 * Math.sin(T * 0.045), tx = mouse ? mouse.x : cx + Math.cos(al) * W * 0.4, ty = mouse ? mouse.y : cy + Math.sin(al) * H * 0.42;   // 빛: 혼자 천천히 돌다가 커서를 따라온다
    LX += (tx - LX) * 0.05; LY += (ty - LY) * 0.05;
    hov = pick(); hv += ((hov && hov.type !== 'ses' ? 1 : 0) - hv) * 0.14;
    cv.style.cursor = hov && hov.type !== 'ses' ? 'pointer' : 'default';
    draw();
    if (hov) {
      if (hov.key !== hovKey) { hovKey = hov.key; tipFor(hov).forEach((s, q) => { tipRows[q].textContent = s; tipRows[q].style.display = s ? '' : 'none'; }); tipW = tip.offsetWidth; tipH = tip.offsetHeight; }
      tip.style.transform = `translate(${clamp(mouse.x + 16, 6, W - tipW - 6).toFixed(0)}px,${clamp(mouse.y + 16, 6, H - tipH - 6).toFixed(0)}px)`; tip.style.opacity = 1;
    } else if (hovKey) { hovKey = ''; tip.style.opacity = 0; }
  };

  const size = () => {
    const r = main.getBoundingClientRect(); if (r.width < 20 || r.height < 20) return;
    W = r.width; H = r.height; dpr = Math.min(window.devicePixelRatio || 1, 2);
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    mesh?.size(W, H);
    if (!LX) { LX = W * 0.22; LY = H * 0.12; }
    layout();
  };
  const ro = new ResizeObserver(size); ro.observe(main); size();
  raf = requestAnimationFrame(frame);

  return () => {
    cancelAnimationFrame(raf); ro.disconnect();
    if (mq && mq.removeEventListener) mq.removeEventListener('change', onMq);
    cv.removeEventListener('pointermove', onMove); cv.removeEventListener('pointerdown', onDown); cv.removeEventListener('pointerup', onUp); cv.removeEventListener('pointerleave', onLeave);
    cv.remove(); tip.remove(); lg.remove(); mesh?.destroy();
  };
};

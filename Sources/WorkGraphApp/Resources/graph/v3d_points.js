/* 점구름 (three.js): 둥근 점으로 쌓은 계단식 산. 바탕은 다른 입체 보기(꽃, 분재, 체계)와 같은 갈색 흐름(G3D.mesh)이고 캔버스는 칠하지 않는다.
   원근 카메라로 위에서 비스듬히 내려다보며 끌어서 돌린다(관성). 먼 점은 작고 바탕에 녹아들고, 앞 점이 뒤 점을 가린다.
   나(맨 위 외로운 점) > 분야(계단 한 단, 단과 단 사이에는 빈 바퀴 하나, 쓴 시간이 많은 분야가 위쪽 안쪽)
   > 업무(단 안의 부채꼴 칸, 칸 사이는 좁은 방사 틈, 점 수 = 쓴 시간) > 세션과 자료(칸 위에 흩어진 점).
   가장 오래 쓴 업무는 꼭대기 뾰족탑(작은 고리를 쌓은 것), 세션과 자료가 가장 많은 업무 쪽으로 어수선한 능선이 뻗는다.
   관계(같은 자료를 쓴 업무)는 칸과 칸을 잇는 점 호로 산 위에 떠 있고 빛 알갱이가 흐른다(산 뒤에 가려진 부분은 흐리게).
   색은 분야가 아니라 높이: 위 레몬, 복숭아, 분홍, 연보라, 아래 민트. 점 위치는 CPU 에서 한 번 만들고 파도와 숨쉬기는 버텍스 셰이더가 입힌다.
   입체감: 점마다 지형 법선을 넣어 화면 왼쪽 위에서 오는 빛으로 음영을 입히고(돌아도 빛은 그대로라 형태가 읽힌다), 단 사이 벼랑에는 성긴 점 세 줄을 놓아 계단 옆면이 보이며,
   먼 점은 작고 옅고 가장자리가 번진다. 글자(이름표, 말풍선, 읽는 법)는 상자 없이 그림자만 두른 글자다. */
window.V3D = window.V3D || {};
window.V3D.points = function (main, data, ui) {
  let dead = false, cleanup = () => {};
  const start = () => { if (!dead) cleanup = build(window.THREE); };
  if (window.THREE) start(); else window.addEventListener('three-ready', start, { once: true });
  return () => { dead = true; window.removeEventListener('three-ready', start); cleanup(); };

  function build(THREE) {
    const FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif', BR = '36,21,15', PI2 = Math.PI * 2;
    const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
    const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
    const hash = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
    const rng = seed => () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    const M = t => Math.max(1, +t.mins || 0);
    const hm = m => (m >= 60 ? Math.floor(m / 60) + '시간 ' : '') + Math.round(m % 60) + '분';
    const reduce = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches), SPEED = reduce ? 0.04 : 1;
    const note = txt => { const p = document.createElement('p'); p.className = 'empty-note'; p.textContent = txt; main.appendChild(p); return () => p.remove(); };

    const tasks = data.tasks.filter(t => data.themes.some(h => h.id === t.theme));
    if (!tasks.length) return note('표시할 업무가 없습니다');
    const kindName = k => (data.kinds && data.kinds[k] && data.kinds[k].name) || '자료';
    const itemName = it => (it && typeof it === 'object' ? it.name || it.title : it) || '자료';

    // ---- 분야 단(계단), 업무 부채꼴 ----
    const tm = {}; tasks.forEach(t => { tm[t.theme] = (tm[t.theme] || 0) + M(t); });
    const themes = data.themes.filter(h => tm[h.id]).sort((a, b) => tm[b.id] - tm[a.id] || hash(a.id) - hash(b.id));
    const seed = hash(tasks.map(t => t.id).join(',') + themes.length);
    const NT = themes.length, NTOT = clamp(Math.round(28 + 1.4 * NT + 0.15 * tasks.length), 30, 46), T0 = 0.06, HT = 0.8, TW = 0.8;   // 점이 있는 바퀴 수, 가장 안쪽 반지름 비율, 산 높이, 안쪽일수록 감기는 각도
    const bands = themes.map((th, bi) => {
      const ts = tasks.filter(t => t.theme === th.id).sort((x, y) => M(y) - M(x) || hash(x.id) - hash(y.id)), sum = tm[th.id], off = rng(hash(th.id) + 17)() * PI2;
      let acc = 0;
      const secs = ts.map((t, si) => { const w = M(t) / sum * PI2, s = { t, ti: tasks.indexOf(t), a0: acc, w, si }; acc += w; return s; });
      return { th, bi, secs, off, sum, w: Math.pow(sum, 0.55), n: 2, cum: 0 };
    });
    { const sw = bands.reduce((s, b) => s + b.w, 0); bands.forEach(b => { b.n = Math.max(2, Math.round(NTOT * b.w / sw)); });
      let cum = 0; bands.forEach(b => { b.cum = cum; cum += b.n + 1; }); bands.total = cum; }   // 단마다 빈 바퀴 하나(벼랑)를 끼운다
    const DT = (1 - T0) / bands.total, DC = Math.min(0.075, 0.42 / NT);   // 바퀴 하나가 차지하는 t 폭, 벼랑 하나의 높이
    // 안쪽에서 rv 바퀴째의 높이: 안쪽은 가파르고 바깥은 완만한 종 모양에, 단 사이 빈 바퀴를 지날 때마다 벼랑으로 한 칸 떨어진다
    const terr = rv => {
      let st = 0; for (let i = 0; i < bands.length - 1; i++) st += sstep(0, 1, rv - (bands[i].cum + bands[i].n));
      return HT * Math.pow(1 - clamp(rv / bands.total, 0, 1), 1.45) - DC * st;
    };
    const secAt = (b, th) => { const u = ((th - b.off) % PI2 + PI2) % PI2; for (const s of b.secs) if (u < s.a0 + s.w) return [s, u]; return [b.secs[b.secs.length - 1], u]; };
    const secOfTask = ti => { for (const b of bands) for (const s of b.secs) if (s.ti === ti) return [b, s]; };

    // 가장 오래 쓴 업무(탑)와 세션과 자료가 가장 많은 업무(능선 방향)
    const busy = t => (t.sessions || []).length + Object.values(t.items || {}).reduce((s, a) => s + a.length, 0);
    let big = 0, hot = 0; tasks.forEach((t, i) => { if (M(t) > M(tasks[big])) big = i; if (busy(t) > busy(tasks[hot])) hot = i; });
    const hotPos = secOfTask(hot), thR = hotPos[0].off + hotPos[1].a0 + hotPos[1].w / 2, thP = thR + Math.PI * 0.82;
    const totalM = tasks.reduce((s, t) => s + M(t), 0);

    // ---- 지형 ----
    const S = rng(seed ^ 0x9e37), A = Array.from({ length: 8 }, () => S() * PI2);
    const wrap = d => Math.atan2(Math.sin(d), Math.cos(d));
    const ridge = th => { const d = wrap(th - thR); return Math.exp(-d * d / 0.36); };
    const surf = (th, t, o, sm) => {   // 각도 th, 안쪽에서 바깥으로 가는 값 t(T0 ~ 1) 에서의 위치(sm 이면 잔물결 없이 매끈한 지형: 법선용)
      const rv = (t - T0) / DT, tn = (t - T0) / (1 - T0), rg = ridge(th), rp = Math.max(0, Math.cos(th - thP));
      const R = 1 + 0.1 * Math.sin(th - A[0]) + 0.07 * Math.sin(2 * th - A[1]) + 0.04 * Math.sin(3 * th - A[2]) + 0.4 * rg;
      let rho = R * Math.pow(t, 0.85 + 0.12 * Math.sin(th - A[3])) * (1 + 0.03 * Math.sin(4 * th + 7 * t + A[4]) + 0.017 * Math.sin(7 * th - 11 * t + A[5])) * (1 + 0.35 * rg * tn);
      if (!sm) rho += tn * tn * 0.02 * rp * Math.sin(40 * th + 0.35 * rv + A[6]);   // 바퀴마다 위상이 조금씩 밀리는 잔물결
      const ta = th + TW * Math.pow(1 - tn, 1.6);   // 안쪽일수록 감겨서 장미처럼 소용돌이친다
      o.rho = rho; o.ta = ta; o.x = rho * Math.cos(ta); o.z = rho * Math.sin(ta);
      o.y = terr(rv) + 0.5 * rg * Math.pow(1 - tn, 0.8) + 0.01 * rp * tn * Math.sin(9 * th - 0.4 * rv + A[7]);
      return o;
    };

    // ---- 흩어질 점의 근거: 세션과 자료, 관계 ----
    const refs = [], cl = [];   // refs: 마우스를 올렸을 때 보일 이름, cl: [업무, 점 수, 날짜 비율, refs 번호]
    let maxD = 1; tasks.forEach(t => (t.sessions || []).forEach(s => { maxD = Math.max(maxD, +s.d || 0); }));
    let nSes = 0, nItm = 0;
    tasks.forEach((t, ti) => {
      (t.sessions || []).forEach(s => { nSes++; const mn = Math.max(0, (+s.end || 0) - (+s.start || 0)); cl.push([ti, clamp(2 + mn / 20, 2, 8), clamp((+s.d || 0) / maxD, 0, 1), refs.push({ lv: '세션', name: s.when || '세션', sub: `${t.title}, ${hm(mn)}` }) - 1]); });
      Object.entries(t.items || {}).forEach(([k, arr]) => (arr || []).forEach(it => { nItm++; cl.push([ti, 1, -1, refs.push({ lv: '자료', name: itemName(it), sub: `${kindName(k)}, ${t.title}` }) - 1]); }));
    });
    const tid = new Map(tasks.map((t, i) => [t.id, i]));
    const rels = (data.rel || []).filter(r => tid.has(r[0]) && tid.has(r[1]) && r[0] !== r[1]).sort((p, q) => q[2] - p[2]).slice(0, 36);
    const maxRel = Math.max(1, ...rels.map(r => r[2])), partners = tasks.map(() => []);
    rels.forEach(r => { const a = tid.get(r[0]), b = tid.get(r[1]); partners[a].push(b); partners[b].push(a); });

    // ---- 점 모으기 ----
    const RP = clamp(4600 + tasks.length * 30, 4800, 6200);
    const gen = (d, count) => {
      const r = rng(seed), g = () => (r() + r() + r() - 1.5) * 2;
      const P = [], a = [], b = [], c = [], mk = [], mt = [], mr = [], NRM = [], out = { x: 0, y: 0, z: 0, rho: 0, ta: 0 };
      let nx = 0, ny = 1, nz = 0; const nS = [0, 1, 2, 3].map(() => ({ x: 0, y: 0, z: 0, rho: 0, ta: 0 }));
      const setN = (th, t) => {   // 지형 법선(매끈한 지형에서 각도 방향 접선과 바깥 방향 접선의 외적, 위쪽이 +): 빛과 음영에 쓴다
        surf(th + 0.05, t, nS[0], 1); surf(th - 0.05, t, nS[1], 1); surf(th, Math.min(1, t + DT * 0.5), nS[2], 1); surf(th, Math.max(T0, t - DT * 0.5), nS[3], 1);
        const ax = nS[0].x - nS[1].x, ay = nS[0].y - nS[1].y, az = nS[0].z - nS[1].z, bx = nS[2].x - nS[3].x, by = nS[2].y - nS[3].y, bz = nS[2].z - nS[3].z;
        const X = ay * bz - az * by, Y = az * bx - ax * bz, Z = ax * by - ay * bx, l = Math.hypot(X, Y, Z) || 1; nx = X / l; ny = Y / l; nz = Z / l;
      };
      // 점 하나: 위치, [각도, t, 위상, 종류(0 등고선, 1 흩어진 점, 2 탑, 3 관계 호, 4 나, 5 나의 빛무리)], [크기, 업무, 분야, 무작위], [관계 상대 업무, 칸 번호 홀짝]
      const add = (x, y, z, ang, t, ph, kind, sz, ti, bi, tj, ref, sh) => { P.push(x, y, z); a.push(ang, t, ph, kind); b.push(sz, ti, bi, (r() - 0.5) * 2); c.push(tj == null ? -1 : tj, sh || 0); mk.push(kind); mt.push(ti); mr.push(ref == null ? -1 : ref); NRM.push(nx, ny, nz); };
      let nring = 0;
      // 1) 나선 등고선: 분야 단을 한 줄로 감는다. 단 사이는 빈 바퀴, 칸 사이는 좁은 방사 틈
      bands.forEach(bd => {
        const L = bd.n * PI2, many = bd.secs.length > 1;
        for (let s = 0; s < L;) {
          const t = T0 + DT * (bd.cum + s / PI2), th = s % PI2; surf(th, t, out);
          const [sc, u] = secAt(bd, th), gp = many ? Math.min(1.3 * d / Math.max(0.08, out.rho), sc.w * 0.2) : 0, rg = ridge(th), k = 0.1 * rg * (1.2 - 0.7 * (t - T0));
          if (!(u - sc.a0 < gp || sc.a0 + sc.w - u < gp)) {
            nring++;
            if (!count) { setN(th, t); const q = k * (0.5 + r()); add(out.x + g() * (0.0006 + q), out.y + g() * (0.0006 + q * 0.8), out.z + g() * (0.0006 + q), out.ta, t, r(), 0, 0.88 + 0.28 * r(), sc.ti, bd.bi, null, null, sc.si % 2); }
          }
          s += d / Math.max(0.05, out.rho) * (0.93 + 0.14 * r());
        }
      });
      if (count) return nring;
      // 2) 세션과 자료: 업무 칸 위에 흩어지는 점(일부는 능선 쪽으로 쏠린다)
      const tot = cl.reduce((s, q) => s + q[1], 0), f = clamp(clamp(1500 + tot * 2.2, 1500, 6500) / Math.max(1, tot), 0.5, 6), c3 = { x: 0, y: 0, z: 0, rho: 0, ta: 0 };
      cl.forEach(q => {
        const [bd, sc] = secOfTask(q[0]), th0 = bd.off + sc.a0 + sc.w * (0.1 + 0.8 * r()), th = th0 + (r() < 0.7 ? wrap(thR - th0) * (0.4 + 0.5 * r()) : 0), tA = T0 + DT * bd.cum, tB = tA + DT * bd.n;
        const tc = tA + (tB - tA) * clamp(0.08 + 0.84 * (q[2] < 0 ? r() : 0.62 * q[2] + 0.38 * r()), 0, 1), rg = ridge(th);
        surf(th, tc, c3); setN(th, tc);
        const cx = c3.x, cy = c3.y + 0.005 + 0.025 * r(), cz = c3.z, sg = 0.010 + 0.016 * r() + 0.024 * rg, n = Math.min(60, Math.max(1, Math.round(q[1] * f * (0.4 + 0.95 * (tc - T0) / (1 - T0)))));
        for (let i = 0; i < n; i++) {
          const k = 0.4 + 1.5 * r() * r(), push = rg * r() * r() * 0.14;
          add(cx + g() * sg * k + Math.cos(c3.ta) * push, cy + Math.abs(g()) * sg * k * 1.2 + push * 0.5, cz + g() * sg * k + Math.sin(c3.ta) * push, c3.ta, tc, r(), 1, (q[1] > 1 ? 0.5 : 0.4) + 0.5 * r() * r(), q[0], bd.bi, -1, q[3]);
        }
      });
      // 3) 꼭대기 탑: 가장 오래 쓴 업무. 등고선과 같은 간격의 작은 고리를 위로 쌓는다
      const Y0 = terr(0), bs = secOfTask(big), Hs = 0.42 + 0.16 * clamp(M(tasks[big]) / totalM * 6, 0, 1), lean = [Math.cos(thR) * 0.1, Math.sin(thR) * 0.1], NR = 16, r0 = 0.16;
      for (let j = 0; j < NR; j++) {
        const u = j / (NR - 1), rr = r0 * Math.pow(1 - u, 1.25), nn = Math.max(1, Math.round(PI2 * rr / (d * 1.2))), ph0 = r() * PI2;
        for (let i = 0; i < nn; i++) {
          const ph = ph0 + i / nn * PI2, fl = r() < 0.14 ? 1 + 0.5 * r() : 1;   // 일부는 바깥으로 튀어나와 윤곽이 거칠다
          nx = Math.cos(ph) * 0.9; ny = 0.42; nz = Math.sin(ph) * 0.9;
          add(lean[0] * u + Math.cos(ph) * rr * fl + g() * 0.001, Y0 + u * Hs + g() * 0.004, lean[1] * u + Math.sin(ph) * rr * fl + g() * 0.001, ph, u, r(), 2, 1.15 + 0.3 * r(), big, bs[0].bi);
        }
      }
      // 4) 나: 맨 꼭대기 외로운 점과 빛무리
      nx = 0; ny = 1; nz = 0;
      add(lean[0], Y0 + Hs + 0.06, lean[1], 0, 0, 0.3, 4, 1.35, -1, -1);
      add(lean[0], Y0 + Hs + 0.06, lean[1], 0, 0, 0.3, 5, 4.2, -1, -1); add(lean[0], Y0 + Hs + 0.06, lean[1], 0, 0, 0.3, 5, 8.5, -1, -1);
      // 4b) 벼랑: 단과 단 사이 빈 바퀴에 성긴 점 세 줄(위 단에서 아래 단으로 떨어지는 높이를 고르게 나눈다), 작고 옆면이라 음영이 짙다
      bands.forEach(bd => {
        if (bd.bi === bands.length - 1) return;
        const many = bd.secs.length > 1;
        for (let s = 0; s < PI2;) {
          surf(s, T0 + DT * (bd.cum + bd.n + 0.5), out);
          const [sc, u] = secAt(bd, s), gp = many ? Math.min(1.3 * d / Math.max(0.08, out.rho), sc.w * 0.2) : 0;
          if (!(u - sc.a0 < gp || sc.a0 + sc.w - u < gp)) for (let f = 1; f <= 3; f++) {
            const th = s + (r() - 0.5) * 0.4 * d / Math.max(0.2, out.rho), t = T0 + DT * (bd.cum + bd.n + f * 0.25 + (r() - 0.5) * 0.06);
            surf(th, t, out); setN(th, t);
            add(out.x + g() * 0.0016, out.y + g() * 0.0016, out.z + g() * 0.0016, out.ta, t, r(), 0, 0.5 + 0.22 * r(), sc.ti, bd.bi, null, null, sc.si % 2);
          }
          s += 2.4 * d / Math.max(0.05, out.rho) * (0.9 + 0.2 * r());
        }
      });
      nx = 0; ny = 1; nz = 0;
      const nMain = P.length / 3;
      // 5) 관계: 같은 자료를 쓴 두 업무를 잇는 점 호(산 위에 떠서 두 칸 사이를 건넌다)
      const anc = ti => { const [bd, sc] = secOfTask(ti); return [bd.off + sc.a0 + sc.w / 2, T0 + DT * (bd.cum + bd.n * 0.9)]; };
      rels.forEach(rl => {
        const ia = tid.get(rl[0]), ib = tid.get(rl[1]), [tha, ta] = anc(ia), [thb, tb] = anc(ib), dth = wrap(thb - tha), w = rl[2] / maxRel, sp = Math.min(1, Math.abs(dth) / Math.PI);
        const ref = refs.push({ lv: '관계', name: `${tasks[ia].title}, ${tasks[ib].title}`, sub: `두 업무가 같은 자료 ${rl[2]}개를 씀` }) - 1, nn = Math.round(clamp((Math.abs(dth) * 0.85 + 0.15) / 0.045, 14, 64));
        for (let i = 0; i < nn; i++) {
          const s = i / (nn - 1), bz = 4 * s * (1 - s); surf(tha + dth * s, ta + (tb - ta) * s, out);   // 산 표면을 따라 두 칸 사이를 건너고, 가운데는 살짝 떠오른다
          add(out.x, out.y + 0.05 + (0.06 + 0.16 * sp) * bz, out.z, 0, s, r(), 3, 0.55 + 0.3 * w, ia, -1, ib, ref);
        }
        [[ia, tha, ta, ib], [ib, thb, tb, ia]].forEach(([ti, th, t, tj]) => { surf(th, t, out); add(out.x, out.y + 0.05, out.z, 0, 0, r(), 6, 1.7, ti, -1, tj, ref); });   // 두 끝의 핀
      });
      return [P, a, b, c, mk, mt, mr, nMain, NRM];
    };
    let dd = 0.02; const n0 = gen(dd, true); dd *= n0 / RP;   // 점 간격을 맞춰 등고선 점 수를 RP 근처로
    const res = gen(dd, false);
    const pos = new Float32Array(res[0]), aA = new Float32Array(res[1]), aB = new Float32Array(res[2]), aC = new Float32Array(res[3]), mK = res[4], mT = res[5], mR = res[6], nMain = res[7], nrm = new Float32Array(res[8]), N = pos.length / 3;
    let y0 = 1e9, y1 = -1e9; const yy = [];
    for (let i = 0; i < nMain; i++) { const y = pos[i * 3 + 1]; y0 = Math.min(y0, y); y1 = Math.max(y1, y); if (mK[i] === 0) yy.push(y); }
    yy.sort((p, q) => p - q); const YL = yy[Math.floor(yy.length * 0.01)], YH = yy[Math.floor(yy.length * 0.995)] + 0.06, YM = (y0 + y1) / 2;   // 높이 색은 등고선 기준, 탑은 맨 위 레몬
    const dist0 = [], apexI = mK.indexOf(4); for (let i = 0; i < N; i++) dist0.push(Math.hypot(pos[i * 3], pos[i * 3 + 1] - YM, pos[i * 3 + 2])); const dist = dist0.slice(0, nMain).sort((p, q) => p - q);
    const RS = dist[Math.floor(nMain * 0.985)], apex = [pos[apexI * 3], pos[apexI * 3 + 1], pos[apexI * 3 + 2]];

    // ---- 렌더러, 장면: 캔버스는 투명, 바탕은 다른 입체 보기와 같은 갈색 흐름 ----
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ alpha: true, antialias: false, premultipliedAlpha: true, powerPreference: 'high-performance' }); }
    catch (e) { return note('이 환경에서는 3D 그래픽을 쓸 수 없습니다'); }
    renderer.setClearColor(0x000000, 0);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    const prevPos = main.style.position, madeRel = getComputedStyle(main).position === 'static'; if (madeRel) main.style.position = 'relative';
    const mesh = window.G3D && window.G3D.mesh ? window.G3D.mesh(main, 0.8) : null;   // 아래에 흐르는 갈색, 흰색 바탕(캔버스보다 먼저 깐다)
    const cv = renderer.domElement;
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;cursor:grab;touch-action:none';
    main.appendChild(cv);
    const FOV = 70, scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(FOV, 1, 0.05, 40), tilt = new THREE.Group(), spin = new THREE.Group();
    tilt.add(spin); scene.add(tilt);

    const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
    const RAMP = ['#B7ECDF', '#C2E1E6', '#C0C7E6', '#D2BDEF', '#EBBFF4', '#EEBDE6', '#EEB8D6', '#F0BACB', '#F2C0BD', '#F3CEB7', '#F2E5BC', '#F0F2BB'].map(h => new THREE.Vector3(...hex(h)));   // 아래 민트 -> 위 레몬 (참고 이미지에서 표집)
    const U = { uTime: { value: 0 }, uScale: { value: 1 }, uPx: { value: 1 }, uD: { value: 4 }, uRs: { value: RS }, uHov: { value: -9 }, uBand: { value: -9 }, uHT: { value: 0 }, uGhost: { value: 1 }, uPart: { value: new Array(8).fill(-9) },
      uY0: { value: YL }, uY1: { value: YH }, uS0: { value: -1 }, uS1: { value: 1 }, uRamp: { value: RAMP } };
    const VS = `
        uniform float uTime, uScale, uPx, uD, uRs, uHov, uBand, uHT, uGhost, uY0, uY1, uS0, uS1, uPart[8];
        uniform vec3 uRamp[12];
        attribute vec4 aA; attribute vec4 aB; attribute vec2 aC;
        varying vec3 vCol; varying float vAl, vPx, vGl, vSoft;
        vec3 ramp(float c) { float f = clamp(c, 0.0, 1.0) * 11.0; vec3 r = uRamp[0]; for (int i = 0; i < 11; i++) r = mix(r, uRamp[i + 1], clamp(f - float(i), 0.0, 1.0)); return r; }
        void main() {
          vec3 p = position; float ang = aA.x, t = aA.y, ph = aA.z, k = aA.w;
          float ring = 1.0 - step(0.5, k), dust = step(0.5, k) * (1.0 - step(1.5, k)), tower = step(1.5, k) * (1.0 - step(2.5, k)), arc = step(2.5, k) * (1.0 - step(3.5, k)), apex = step(3.5, k) * (1.0 - step(4.5, k)), glow = step(4.5, k) * (1.0 - step(5.5, k)), pin = step(5.5, k);
          arc += pin;
          vec2 rd = vec2(cos(ang), sin(ang));
          p.y += ring * 0.02 * sin(ang * 5.0 - uTime * 1.5 + t * 16.0 + ph * 0.6);               // 등고선을 따라 도는 파도
          p.xz += ring * rd * 0.009 * sin(ang * 8.0 + uTime * 0.9 - t * 22.0);
          p.y += tower * 0.012 * sin(ang * 3.0 - uTime * 1.5 + t * 9.0);                        // 탑 고리도 일렁인다
          p += (dust + 0.5 * tower) * 0.018 * vec3(sin(uTime * 0.55 + ph * 6.2831), sin(uTime * 0.47 + ph * 17.3), sin(uTime * 0.39 + ph * 9.1));   // 흩어진 점은 천천히 떠돈다
          p.y += arc * 0.012 * sin(uTime * 0.8 + t * 9.0 + ph) + (apex + glow) * 0.02 * sin(uTime * 0.9);
          vec4 mv = modelViewMatrix * vec4(p, 1.0); gl_Position = projectionMatrix * mv;
          float sN = (gl_Position.y / gl_Position.w - uS0) / (uS1 - uS0), hN = (position.y - uY0) / (uY1 - uY0);
          vec3 col = ramp((mix(sN, hN, 0.7) - 0.04) / 0.92 + aB.w * 0.03);
          col *= 1.0 - 0.07 * mod(aB.z, 2.0) * ring - 0.05 * aC.y * ring;                         // 분야 단과 칸마다 밝기를 번갈아
          float lit = smoothstep(-0.3, 0.92, dot(normalize(normalMatrix * normal), normalize(vec3(-0.5, 0.66, 0.56))));   // 화면 왼쪽 위에서 오는 빛: 돌려도 빛은 그대로라 단의 옆면과 능선의 앞뒤가 읽힌다
          col = mix(col, mix(col * 0.86, mix(col, vec3(1.0), 0.2), lit), ring + dust + tower);   // 빛 받는 쪽은 옅게, 그늘 쪽은 조금 짙게(파스텔은 그대로)
          float pulse = (ring + tower) * pow(0.5 + 0.5 * sin(t * 40.0 * ring + t * 6.0 * tower - uTime * 1.0), 10.0);   // 나선을 따라 퍼지는 빛 고리
          float flow = arc * pow(0.5 + 0.5 * sin((t * 2.5 - uTime * 0.32 + ph * 0.7) * 6.2831), 6.0);   // 관계 호를 따라 흐르는 알갱이
          col = mix(col, vec3(1.0), 0.2 * pulse + 0.5 * flow);
          col = mix(col, vec3(0.97, 0.98, 1.0), 0.55 * arc); col = mix(col, vec3(1.0), apex + glow + pin);
          float depth = clamp((-mv.z - (uD - uRs)) / (2.0 * uRs), 0.0, 1.0), fade = smoothstep(0.25, 1.0, depth);   // depth 0 가까움 1 멂, 앞쪽 절반은 또렷하게
          float rel = 0.0; for (int i = 0; i < 8; i++) rel = max(rel, 1.0 - abs(sign(aB.y - uPart[i])));                // 호버한 업무와 이어진 업무
          float hit = max(max(1.0 - abs(sign(aB.y - uHov)), 1.0 - abs(sign(aB.z - uBand))), 1.0 - abs(sign(aC.x - uHov))) * (1.0 - apex) * (1.0 - glow);
          hit = max(hit, 0.55 * rel * (1.0 - apex) * (1.0 - glow));
          float sz = aB.x * (1.0 + 0.15 * sin(uTime * 1.3 + ph * 6.2831) + 0.3 * pulse + 0.45 * flow) * mix(1.4, 0.42, depth * (1.0 - apex - glow)) * (1.0 + (0.6 - 0.35 * arc) * hit * uHT) * (1.0 + 0.4 * apex);
          col = mix(col, vec3(1.0), 0.5 * hit * uHT);
          vCol = col; vGl = glow + 2.0 * pin;
          vSoft = smoothstep(0.35, 1.0, depth) * (1.0 - apex - glow);
          vAl = mix(1.0, 0.36, fade) * (1.0 - 0.7 * uHT * (1.0 - hit) * (1.0 - apex - glow)); col *= mix(1.0, 0.86, fade);   // 먼 점은 바탕에 녹아들고 색도 조금 가라앉는다
          vAl = mix(mix(vAl, 0.38 + 0.5 * flow + 0.4 * hit * uHT, arc * 0.8), 0.9, pin) * uGhost;
          vAl = mix(vAl, 0.22, glow);
          gl_PointSize = max(1.4 * uPx, sz * uScale / -mv.z); vPx = gl_PointSize;
        }`;
    const FS = `
        varying vec3 vCol; varying float vAl, vPx, vGl, vSoft;
        void main() {
          float d = length(gl_PointCoord - 0.5), aa = 1.2 / max(vPx, 1.0);
          float a = vGl > 1.5 ? (1.0 - smoothstep(0.5 - aa, 0.5, d)) * smoothstep(0.27, 0.27 + 2.0 * aa, d) : vGl > 0.5 ? pow(max(0.0, 1.0 - 2.0 * d), 2.2) : 1.0 - smoothstep(0.5 - aa - 0.28 * vSoft, 0.5, d);   // 핀은 속 빈 고리, 빛무리는 부드럽게, 먼 점은 가장자리가 번진다(초점 밖)
          a *= 1.0 - 0.12 * vSoft;
          if (a * vAl < 0.02) discard;
          vec3 c = vGl > 0.5 ? vCol : mix(vCol, vCol * 0.8, smoothstep(0.36, 0.5, d) * 0.6);       // 가장자리를 조금 어둡게(구슬처럼)
          gl_FragColor = vec4(c, a * vAl);
        }`;
    const mat = new THREE.ShaderMaterial({ uniforms: U, transparent: true, depthTest: true, depthWrite: true, vertexShader: VS, fragmentShader: FS });
    const matA = new THREE.ShaderMaterial({ uniforms: U, transparent: true, depthTest: true, depthWrite: false, vertexShader: VS, fragmentShader: FS });   // 관계 호: 산 앞에 있는 부분
    const matG = new THREE.ShaderMaterial({ uniforms: Object.assign({}, U, { uGhost: { value: 0.22 } }), transparent: true, depthTest: true, depthFunc: THREE.GreaterDepth, depthWrite: false, vertexShader: VS, fragmentShader: FS });   // 산 뒤에 가려진 부분은 흐리게
    const attrs = { position: new THREE.BufferAttribute(pos, 3), aA: new THREE.BufferAttribute(aA, 4), aB: new THREE.BufferAttribute(aB, 4), aC: new THREE.BufferAttribute(aC, 2), normal: new THREE.BufferAttribute(nrm, 3) };
    const mkGeo = (from, cnt) => { const g = new THREE.BufferGeometry(); for (const k in attrs) g.setAttribute(k, attrs[k]); g.setDrawRange(from, cnt); g.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 0, 0), 10); return g; };
    const geo = mkGeo(0, nMain), geoA = mkGeo(nMain, N - nMain);
    const cloud = new THREE.Points(geo, mat), arcs = new THREE.Points(geoA, matA), ghost = new THREE.Points(geoA, matG); cloud.frustumCulled = arcs.frustumCulled = ghost.frustumCulled = false; arcs.renderOrder = 1; ghost.renderOrder = 2;
    cloud.position.y = arcs.position.y = ghost.position.y = -YM; spin.add(cloud); if (N > nMain) spin.add(arcs, ghost);

    // ---- 말풍선, 분야 이름표, 읽는 법: 상자 없이 그림자만 두른 글자 ----
    const el = (css, parent) => { const e = document.createElement('div'); e.style.cssText = css; (parent || main).appendChild(e); return e; };
    const CREAM = '#FBF4EA', TXT = `color:${CREAM};text-shadow:0 0 6px rgba(${BR},.95),0 0 2px rgba(${BR},.9),0 1px 1px rgba(${BR},.8)`;
    const tip = el(`position:absolute;left:0;top:0;z-index:5;pointer-events:none;display:none;max-width:320px;font:500 12px/1.4 ${FONT};${TXT};will-change:transform`);
    const tipL = el('font-size:10.5px;letter-spacing:.04em;opacity:.72;margin-bottom:1px', tip), tipT = el('font-weight:700;font-size:13px', tip), tipS = el('font-size:11px;opacity:.8;margin-top:1px', tip);
    let tipW = 0, tipH = 0;
    const lab = (txt, sub) => { const e = el(`position:absolute;left:0;top:0;z-index:4;font:600 11.5px/1 ${FONT};${TXT};white-space:nowrap;cursor:default;will-change:transform;transition:color .2s;display:none;padding:5px 0`); const n = document.createElement('span'); n.textContent = txt; e.appendChild(n);
      if (sub) { const m = document.createElement('span'); m.textContent = '  ' + sub; m.style.cssText = 'font-weight:500;opacity:.68;font-size:10.5px'; e.appendChild(m); } return e; };
    let bandHover = -1;
    const NS = 'http://www.w3.org/2000/svg', svg = document.createElementNS(NS, 'svg');   // 분야 이름표와 계단을 잇는 가는 선
    svg.setAttribute('style', 'position:absolute;inset:0;width:100%;height:100%;z-index:3;pointer-events:none;overflow:visible'); main.appendChild(svg);
    const sv = (tag, at) => { const n = document.createElementNS(NS, tag); for (const k in at) n.setAttribute(k, at[k]); svg.appendChild(n); return n; };
    const labs = bands.map(bd => {
      const e = lab(bd.th.name, `업무 ${bd.secs.length}개, ${hm(bd.sum)}`);
      e._ln0 = sv('line', { stroke: `rgba(${BR},.3)`, 'stroke-width': 3, 'stroke-linecap': 'round' }); e._ln = sv('line', { stroke: 'rgba(251,244,234,.62)' });   // 아래 어두운 굵은 선이 점 위에서도 읽히게 받친다
      e._dt = sv('circle', { r: 2.6, fill: CREAM, stroke: `rgba(${BR},.8)` });
      e.addEventListener('pointerenter', () => { bandHover = bd.bi; e.style.color = '#fff'; }); e.addEventListener('pointerleave', () => { bandHover = -1; e.style.color = CREAM; });
      return e;
    });
    const meL = lab('나'); meL.style.cssText += ';font-size:13px;font-weight:700;padding:0;pointer-events:none';
    // 읽는 법: 상자 없이 작은 글자와 작은 기호, 나 > 분야 > 업무 > 세션과 자료 순으로 한 칸씩 들여 쓴다
    const lg = el(`position:absolute;left:18px;bottom:16px;z-index:4;font:500 11px/1 ${FONT};${TXT};user-select:none;pointer-events:none`);
    const GC = 'rgba(251,244,234,.95)';
    const rows = [
      [0, '나', '1', '맨 위의 점', 'width:6px;height:6px;border-radius:50%;background:#fff;box-shadow:0 0 5px #fff'],
      [1, '분야', String(NT), '계단 한 단', `width:14px;height:9px;background:repeating-linear-gradient(to bottom,${GC} 0 1px,transparent 1px 3px)`],
      [2, '업무', String(tasks.length), '단 안의 부채꼴 칸', `width:10px;height:10px;border-radius:50%;background:conic-gradient(from -30deg,${GC} 0 55deg,transparent 55deg)`],
      [3, '세션', String(nSes), '칸 위에 흩어진 점', `width:11px;height:10px;background:radial-gradient(circle,${GC} 0.9px,transparent 1.3px) 0 0/4px 4px`],
      [3, '자료', String(nItm), '칸 위의 더 작은 점', `width:11px;height:10px;background:radial-gradient(circle,${GC} 0.7px,transparent 1.1px) 0 0/5px 5px`],
      [0, '관계', String(rels.length), '칸을 잇는 점 호', `<svg width="16" height="10" viewBox="0 0 16 10"><path d="M2.5 8 Q8 -2 13.5 8" fill="none" stroke="${GC}" stroke-width="1" stroke-dasharray="1 2"/><circle cx="2.5" cy="8" r="1.7" fill="none" stroke="#fff"/><circle cx="13.5" cy="8" r="1.7" fill="none" stroke="#fff"/></svg>`]];
    el('margin-bottom:5px;opacity:.6', lg).textContent = '읽는 법';
    rows.forEach(([lv, nm, cnt, ds, gs], i) => { const r = el(`display:flex;align-items:center;gap:8px;padding:3.5px 0 3.5px ${lv * 8}px;white-space:nowrap${i === rows.length - 1 ? ';margin-top:3px' : ''}`, lg), gl = el('width:16px;display:flex;justify-content:center;flex:none;filter:drop-shadow(0 0 2px rgba(' + BR + ',.9))', r); if (gs[0] === '<') gl.innerHTML = gs; else el(gs, gl);
      const t = el('', r), b = document.createElement('b'); b.textContent = nm + ' ' + cnt; b.style.cssText = 'font-weight:700'; const s = document.createElement('span'); s.textContent = '  ' + ds; s.style.opacity = '.68'; t.append(b, s); });

    // ---- 시점, 입력 ----
    let W = 1, H = 1, fit = 4, panY = 0, labW = 120, gut = 0, lgH = 0, edgeL = -1;
    const TV = Math.tan(THREE.MathUtils.degToRad(FOV / 2)), PITCH0 = 0.58, PMIN = 0.2, PMAX = 1.45, AUTO = 0.16 * SPEED, view = { yaw: thR + 2.1, pitch: PITCH0, zoom: 1 }, ZMIN = 0.55, ZMAX = 1.6;
    let drag = null, moved = 0, mouse = null, hoverI = -1, downI = -1, hover = -9, raf = 0, last = 0, hT = 0, clock = 0, vYaw = AUTO, vPitch = 0, lastMove = 0;
    const samples = []; for (let i = 0; i < nMain; i += Math.max(1, Math.floor(nMain / 700))) if (dist0[i] <= RS * 0.95) samples.push(i); samples.push(apexI);
    const reqD = () => {   // 지금 방향에서 점들이 화면에 꽉 차는 카메라 거리(세로 가운데는 panY)
      const th = TV * (W - gut) / H, e = cloud.matrixWorld.elements; let D = 0;
      for (const i of samples) { const x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
        D = Math.max(D, e[2] * x + e[6] * y + e[10] * z + e[14] + Math.abs(e[0] * x + e[4] * y + e[8] * z + e[12]) / (0.94 * th), e[2] * x + e[6] * y + e[10] * z + e[14] + Math.abs(e[1] * x + e[5] * y + e[9] * z + e[13] - panY) / (0.92 * TV)); }
      return D;
    };
    const size = () => {
      const r = main.getBoundingClientRect(); W = Math.max(1, r.width); H = Math.max(1, r.height);
      lg.style.display = ''; lgH = lg.offsetHeight; labW = Math.max(labW, ...labs.map(e => e.offsetWidth)); gut = clamp(Math.max(labW, lg.offsetWidth) + 44, 0, W * 0.36); if (H < 460) lg.style.display = 'none';   // 왼쪽 이름표와 읽는 법이 앉을 자리만큼 산을 오른쪽으로 민다
      renderer.setSize(W, H, false); camera.aspect = W / H; camera.setViewOffset(W, H, -gut / 2, 0, W, H); mesh?.size(W, H);
      tilt.rotation.set(PITCH0, 0, 0); const e = cloud.matrixWorld.elements; let cy = 0; panY = 0;
      for (let k = 0; k < 12; k++) { spin.rotation.y = k / 12 * PI2; scene.updateMatrixWorld(true); let lo = 1e9, hi = -1e9; for (const i of samples) { const v = e[1] * pos[i * 3] + e[5] * pos[i * 3 + 1] + e[9] * pos[i * 3 + 2] + e[13]; lo = Math.min(lo, v); hi = Math.max(hi, v); } cy += (lo + hi) / 24; }
      panY = cy; tilt.rotation.set(view.pitch, 0, 0); spin.rotation.y = view.yaw; scene.updateMatrixWorld(true); fit = reqD();   // 세로 가운데는 열두 방향의 평균, 거리는 지금 방향에 맞춘 뒤 돌아가는 방향을 따라 움직인다
      U.uPx.value = renderer.getPixelRatio(); U.uScale.value = H * U.uPx.value / (2 * TV) * 0.62 * dd;   // 등고선 점 하나의 지름 = 점 간격의 6할쯤
    };
    const ro = new ResizeObserver(size); ro.observe(main);
    labs.forEach(e => { e.style.display = ''; }); size();
    const pp = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const mvp = new THREE.Matrix4(), v4 = new THREE.Vector4();
    const pick = (mx, my) => {   // 화면에서 가장 가까운 점(가까이 있는 점을 조금 더 쳐 줌)
      const e = mvp.elements, D = U.uD.value; let best = 18 * 18, bi = -1;
      for (let i = 0; i < N; i++) {
        if (mK[i] === 5) continue;
        const x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2], w = e[3] * x + e[7] * y + e[11] * z + e[15]; if (w <= 0) continue;
        const sx = ((e[0] * x + e[4] * y + e[8] * z + e[12]) / w * 0.5 + 0.5) * W - mx; if (sx > 18 || sx < -18) continue;
        const sy = (-(e[1] * x + e[5] * y + e[9] * z + e[13]) / w * 0.5 + 0.5) * H - my, d = (sx * sx + sy * sy) * (w / D);
        if (d < best) { best = d; bi = i; }
      }
      return bi;
    };
    cv.addEventListener('pointerdown', e => { drag = pp(e); moved = 0; lastMove = performance.now(); downI = pick(drag.x, drag.y); cv.setPointerCapture(e.pointerId); cv.style.cursor = 'grabbing'; });
    cv.addEventListener('pointermove', e => {
      const p = pp(e); mouse = p; if (!drag) return;
      const dx = p.x - drag.x, dy = p.y - drag.y, now = performance.now(), dts = Math.max(0.008, (now - lastMove) / 1000); lastMove = now; moved += Math.abs(dx) + Math.abs(dy);
      view.yaw += dx * 0.006; view.pitch = clamp(view.pitch + dy * 0.004, PMIN, PMAX);
      vYaw += (clamp(dx * 0.006 / dts, -6, 6) - vYaw) * 0.5; vPitch += (clamp(dy * 0.004 / dts, -3, 3) - vPitch) * 0.5; drag = p;
    });
    const end = () => { drag = null; cv.style.cursor = 'grab'; };
    cv.addEventListener('pointerup', () => { if (drag && moved < 4 && downI >= 0 && mT[downI] >= 0) ui.open(tasks[mT[downI]].id); end(); });   // 누른 자리의 점을 기억해 두었다가 연다
    cv.addEventListener('pointercancel', end);
    cv.addEventListener('pointerleave', () => { if (!drag) mouse = null; });
    cv.addEventListener('wheel', e => { e.preventDefault(); view.zoom = clamp(view.zoom * Math.exp(e.deltaY * 0.0015), ZMIN, ZMAX); }, { passive: false });

    // ---- 말풍선 내용 ----
    const showTip = i => {
      const k = mK[i], tk = tasks[mT[i]], th = tk && themes.find(h => h.id === tk.theme);
      let L, T, Sb;
      if (k === 4) { L = '나'; T = '나'; Sb = `분야 ${NT}개, 업무 ${tasks.length}개`; }
      else if (k === 0 || k === 2) { L = k === 2 ? '업무, 가장 오래 쓴 업무' : '업무'; T = tk.title; Sb = `분야 ${th ? th.name : ''}${tk.type && tk.type !== '업무' ? ', 종류 ' + tk.type : ''}, ${hm(M(tk))}, 세션 ${(tk.sessions || []).length}개`; }
      else { const rf = refs[mR[i]]; L = rf.lv; T = rf.name; Sb = rf.sub; }
      if (tip._k !== i) { tip._k = i; tipL.textContent = L; tipT.textContent = T; tipS.textContent = Sb; tip.style.display = ''; tipW = tip.offsetWidth; tipH = tip.offsetHeight; }
      tip.style.display = ''; tip.style.transform = `translate(${Math.min(W - tipW - 8, mouse.x + 16).toFixed(1)}px,${Math.max(8, Math.min(H - tipH - 8, mouse.y + 16)).toFixed(1)}px)`;
    };

    // ---- 매 프레임 ----
    const tmp = { x: 0, y: 0, z: 0, rho: 0 };
    const proj = (x, y, z) => { v4.set(x, y, z, 1).applyMatrix4(mvp); return v4.y / v4.w; };   // 같은 줄에서 v4.x / v4.w 로 화면 가로 위치도 읽는다
    const put = (e, x, y, tx, ty, w) => { if (w <= 0 || x < -40 || x > W + 40 || y < -20 || y > H + 20) { e.style.display = 'none'; return; } e.style.display = ''; e.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) translate(${tx},${ty})`; };
    const frame = t => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (t - (last || t)) / 1000); last = t; clock += dt * SPEED;
      U.uTime.value = clock;
      if (drag) { vYaw *= Math.exp(-dt * 10); vPitch *= Math.exp(-dt * 10); }   // 누른 채 멈추면 관성도 멈춘다
      else { view.yaw += vYaw * dt; view.pitch = clamp(view.pitch + vPitch * dt, PMIN, PMAX); vYaw += (AUTO - vYaw) * (1 - Math.exp(-dt * 1.4)); vPitch *= Math.exp(-dt * 3.5); }   // 호버 중에도 멈추지 않는다
      tilt.rotation.set(view.pitch + 0.05 * Math.sin(clock * 0.23), 0, 0.025 * Math.sin(clock * 0.17)); spin.rotation.y = view.yaw; scene.updateMatrixWorld(true);
      fit += (reqD() - fit) * (1 - Math.exp(-dt * 0.6));
      const D = fit * view.zoom; U.uD.value = D;
      camera.position.set(0.07 * Math.sin(clock * 0.19), panY, D); camera.lookAt(0, panY, 0);   // 카메라가 옆으로 천천히 흔들려 앞뒤 점이 서로 어긋나 보인다(시차) camera.updateMatrixWorld();
      mvp.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse).multiply(cloud.matrixWorld);
      // 화면 위아래 색 범위: 실제 점이 차지하는 화면 높이
      let lo = 1e9, hi = -1e9, lx = 1e9; for (const i of samples) { const v = proj(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]); lo = Math.min(lo, v); hi = Math.max(hi, v); lx = Math.min(lx, (v4.x / v4.w * 0.5 + 0.5) * W); }
      edgeL = edgeL < 0 ? lx : edgeL + (lx - edgeL) * (1 - Math.exp(-dt * 3));   // 점구름의 왼쪽 끝(이름표가 점을 가리지 않도록)
      U.uS0.value = lo + 0.02 * (hi - lo); U.uS1.value = hi;
      // 호버
      hoverI = mouse && !drag ? pick(mouse.x, mouse.y) : -1;
      hover = hoverI >= 0 && mK[hoverI] !== 4 ? mT[hoverI] : -9;
      U.uHov.value = hover; U.uBand.value = bandHover < 0 ? -9 : bandHover;
      for (let i = 0; i < 8; i++) U.uPart.value[i] = hover >= 0 && i < partners[hover].length ? partners[hover][i] : -9;
      hT += ((hover >= 0 || bandHover >= 0 ? 1 : 0) - hT) * Math.min(1, dt * 9); U.uHT.value = hT;
      cv.style.cursor = hoverI >= 0 && mT[hoverI] >= 0 ? 'pointer' : drag ? 'grabbing' : 'grab';
      if (hoverI >= 0 && mouse) showTip(hoverI); else { tip.style.display = 'none'; tip._k = -1; }
      // 이름표: 분야는 왼쪽 세로 줄에 모아 놓고 각 단의 앞쪽 왼편에 가는 선으로 잇는다, 나는 맨 위 점 옆
      const e = mvp.elements, scr = (x, y, z) => { const w = e[3] * x + e[7] * y + e[11] * z + e[15]; return [(((e[0] * x + e[4] * y + e[8] * z + e[12]) / w) * 0.5 + 0.5) * W, (-((e[1] * x + e[5] * y + e[9] * z + e[13]) / w) * 0.5 + 0.5) * H, w]; };
      const thA = view.yaw + Math.PI - 0.55;   // 앞쪽 왼편(단들이 위아래로 갈라져 보이는 곳)
      const lp = bands.map((bd, i) => { surf(thA, T0 + DT * (bd.cum + bd.n * 0.5), tmp); const p = scr(tmp.x, tmp.y, tmp.z); return { i, x: p[0], y: p[1], ay: p[1], w: p[2] }; }).sort((p, q) => p.y - q.y);
      const LX = Math.max(labW + 10, Math.min(Math.min(...lp.map(p => p.x)) - 34, edgeL - 36)), yMax = lg.style.display === 'none' ? H - 20 : H - lgH - 44;
      lp.forEach((p, j) => { if (j && p.y < lp[j - 1].y + 22) p.y = lp[j - 1].y + 22; });   // 위에서 내려오며 겹치는 이름표는 밀어 낸다
      for (let j = lp.length - 1; j >= 0; j--) lp[j].y = Math.min(lp[j].y, j === lp.length - 1 ? yMax : lp[j + 1].y - 22);   // 읽는 법 자리까지 내려가면 다시 위로 올린다
      lp.forEach(p => {
        const l = labs[p.i], on = LX < p.x - 8;
        put(l, LX, p.y, '-100%', '-50%', p.w);
        for (const n of [l._ln0, l._ln]) { n.setAttribute('x1', LX + 2); n.setAttribute('y1', p.y); n.setAttribute('x2', p.x - 3); n.setAttribute('y2', p.ay); n.style.display = on ? '' : 'none'; }
        l._dt.setAttribute('cx', p.x); l._dt.setAttribute('cy', p.ay);
      });
      { const p = scr(apex[0], apex[1], apex[2]); put(meL, p[0] + 15, p[1], '0', '-50%', p[2]); }
      mesh?.draw(reduce ? t * SPEED : t); renderer.render(scene, camera);
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf); ro.disconnect();
      geo.dispose(); geoA.dispose(); mat.dispose(); matA.dispose(); matG.dispose(); renderer.dispose(); renderer.forceContextLoss(); mesh?.destroy();
      cv.remove(); tip.remove(); lg.remove(); svg.remove(); labs.forEach(l => l.remove()); meL.remove();
      if (madeRel) main.style.position = prevPos;
    };
  }
};

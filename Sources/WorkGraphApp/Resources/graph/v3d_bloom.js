/* 입체 꽃송이: H3 구면 배치. 업무 하나 = 구 표면의 꽃(돔) 하나, 꽃잎 = 그 업무의 세션과 자료 하나씩(실제 데이터만).
   꽃을 누르면 그 꽃이 정면으로 돌아 확대되고 꽃잎 이름이 보인다. 색은 실록 갈색, 하늘색, 흰색 계열만 쓴다 */
window.V3D = window.V3D || {};
window.V3D.bloom = function (main, data, ui) {
  const BROWN = '#24150f', FONT = '"SUIT", -apple-system, "Apple SD Gothic Neo", sans-serif';
  const TINT = ['#B4D0E4', '#FFFFFF', '#5E8FB3', '#F6F5F4', '#9C9690', '#736D68', '#DCE9F2'];   // 분야 색: 브랜드 팔레트 밝기 단계
  const SES = '#FFFFFF', KIND = ['#B4D0E4', '#5E8FB3', '#9C9690', '#DCE9F2', '#736D68', '#F6F5F4'], DARK = new Set(['#5E8FB3', '#9C9690', '#736D68']);
  const norm = v => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const trunc = (s, n) => (s.length > n ? s.slice(0, n) + '…' : s);
  const mulberry = a => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  const rnd = mulberry(20261007);

  const themeIx = {}; data.themes.forEach((t, i) => { themeIx[t.id] = i; });
  const kindKeys = Object.keys(data.kinds || {}), kindIx = {}; kindKeys.forEach((k, i) => { kindIx[k] = i; });
  const tasks = data.tasks.slice().sort((a, b) => (themeIx[a.theme] ?? 99) - (themeIx[b.theme] ?? 99) || b.mins - a.mins);
  const N = tasks.length, GA = Math.PI * (3 - Math.sqrt(5));

  // 꽃: 업무 하나. 꽃잎은 세션 하나씩, 자료 하나씩. 돔 위 나선 배열
  const flowers = tasks.map((t, i) => {
    const y = 1 - 2 * (i + 0.5) / N, r = Math.sqrt(1 - y * y), a = i * GA, c = [r * Math.cos(a), y, r * Math.sin(a)];
    const e1 = norm(cross(c, Math.abs(c[1]) > 0.95 ? [1, 0, 0] : [0, 1, 0])), e2 = cross(c, e1);
    const pet = t.sessions.map(s => ({ cls: 0, label: `${s.when} ${s.active}분` }));
    for (const k of Object.keys(t.items || {})) (t.items[k] || []).forEach(nm => pet.push({ cls: 1 + (kindIx[k] ?? 0) % KIND.length, label: String(nm) }));
    const n = pet.length, R = Math.max(0.07, 0.05 * Math.sqrt(n / Math.PI + 1.5)), h = 0.5 * R, ph = rnd() * 6.28;
    const P = [c.map(x => x * (1 + h))];
    pet.forEach((p, j) => {
      const rho = R * Math.sqrt((j + 0.5) / n) * (0.9 + 0.2 * rnd()), th = j * GA + ph + (rnd() - 0.5) * 0.3, u = rho * Math.cos(th), v = rho * Math.sin(th);
      const d = norm([c[0] + e1[0] * u + e2[0] * v, c[1] + e1[1] * u + e2[1] * v, c[2] + e1[2] * u + e2[2] * v]), k = 1 + h * Math.max(0, 1 - (rho / R) * (rho / R));
      P.push([d[0] * k, d[1] * k, d[2] * k]);
    });
    return { t, c, R, pet, P, n: n + 1, tint: TINT[(themeIx[t.theme] ?? 0) % TINT.length], X: new Float32Array(n + 1), Y: new Float32Array(n + 1), Z: new Float32Array(n + 1), S: new Float32Array(n + 1), rs: 10, big: n };
  });
  const hubs = data.themes.map(th => {
    const fs = flowers.filter(f => f.t.theme === th.id); if (!fs.length) return null;
    const m = fs.reduce((s, f) => [s[0] + f.c[0], s[1] + f.c[1], s[2] + f.c[2]], [0, 0, 0]);
    return { th, dir: norm(m) };
  }).filter(Boolean);

  // 화면 위 단추들
  const glass = 'position:absolute;z-index:5;font:600 12px ' + FONT + ';color:#24150f;background:rgba(255,255,255,0.72);border:0;border-radius:999px;padding:6px 13px;cursor:pointer;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);box-shadow:0 4px 14px rgba(36,21,15,0.12);display:none;white-space:nowrap';
  const mkBtn = (txt, fn) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = txt; b.style.cssText = glass; b.addEventListener('click', e => { e.stopPropagation(); fn(); }); main.appendChild(b); return b; };

  let focus = null, anim = null, hover = null, view = null;
  const wrap = a => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };
  const ease = x => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  const go = (to, t0) => { anim = { t0, from: { yaw: view.yaw, pitch: view.pitch, zoom: view.zoom }, to }; };
  const enter = f => {
    focus = f; view.hold = true;
    const hh = Math.hypot(f.c[0], f.c[2]);
    const yaw = Math.atan2(f.c[0], f.c[2]) + Math.PI, pitch = Math.max(-1.4, Math.min(1.4, Math.atan2(-f.c[1], hh)));
    go({ yaw: view.yaw + wrap(yaw - view.yaw), pitch, zoom: Math.max(1.6, Math.min(3.6, 0.46 / f.R)) }, -1);
    btn.style.display = back.style.display = 'block';
  };
  const leave = () => { if (!focus) return; focus = null; view.hold = false; go({ yaw: view.yaw, pitch: view.pitch, zoom: 1 }, -1); btn.style.display = back.style.display = 'none'; };
  const btn = mkBtn('업무 상세 →', () => focus && ui.open(focus.t.id));
  const back = mkBtn('← 전체', leave); back.style.top = '18px'; back.style.left = '24px';
  const onKey = e => { if (e.key === 'Escape') leave(); };
  window.addEventListener('keydown', onKey);

  const draw = (ctx, v, now) => {
    view = v;
    const { w, h } = v, sc = Math.min(w, h) / 700, R0 = Math.min(w, h) * 0.4 * v.zoom, D = v.dist, cx = w / 2, cy = h / 2;
    if (anim) {
      if (anim.t0 < 0) anim.t0 = now;
      const k = v.dragging ? 1 : Math.min(1, (now - anim.t0) / 600), e = ease(k);
      if (!v.dragging) { v.yaw = anim.from.yaw + (anim.to.yaw - anim.from.yaw) * e; v.pitch = anim.from.pitch + (anim.to.pitch - anim.from.pitch) * e; }
      v.zoom = anim.from.zoom + (anim.to.zoom - anim.from.zoom) * e; if (k >= 1) anim = null;
    }
    const cyw = Math.cos(v.yaw), syw = Math.sin(v.yaw), cp = Math.cos(v.pitch), sp = Math.sin(v.pitch), Rz = Math.min(w, h) * 0.4 * v.zoom;
    const pj = p => { const x = p[0] * cyw - p[2] * syw, z1 = p[0] * syw + p[2] * cyw, y = p[1] * cp - z1 * sp, z = p[1] * sp + z1 * cp, s = D / (D + z); return [cx + x * s * Rz, cy + y * s * Rz, z, s]; };
    for (const f of flowers) {
      for (let i = 0; i < f.n; i++) { const p = pj(f.P[i]); f.X[i] = p[0]; f.Y[i] = p[1]; f.Z[i] = p[2]; f.S[i] = p[3]; }
      let m = 0; for (let i = 1; i < f.n; i++) m = Math.max(m, Math.hypot(f.X[i] - f.X[0], f.Y[i] - f.Y[0])); f.rs = m * 1.1 + 8;
    }
    const order = flowers.slice().sort((a, b) => b.Z[0] - a.Z[0]);
    const zf = Math.pow(v.zoom, 0.55), alphaOf = z => 0.22 + 0.78 * Math.max(0, Math.min(1, (0.75 - z) / 1.5));
    ctx.lineCap = 'round';
    for (const f of order) {
      const dim = focus && f !== focus ? 0.13 : 1, X = f.X, Y = f.Y, Z = f.Z, S = f.S, n = f.n;
      // 가지: 중심에서 꽃잎마다 가는 선
      for (let b = 0; b < 2; b++) {
        ctx.globalAlpha = dim; ctx.beginPath();
        for (let i = 1; i < n; i++) if ((Z[i] < 0.25) === !!b) { ctx.moveTo(X[0], Y[0]); ctx.lineTo(X[i], Y[i]); }
        ctx.strokeStyle = b ? 'rgba(36,21,15,0.35)' : 'rgba(36,21,15,0.12)'; ctx.lineWidth = 1.6; ctx.stroke();
        ctx.strokeStyle = b ? 'rgba(255,255,255,0.6)' : 'rgba(255,255,255,0.2)'; ctx.lineWidth = 0.7; ctx.stroke();
      }
      // 꽃잎: 깊이 3단계 x 종류별로 묶어 그린다
      for (let bin = 0; bin < 3; bin++) {
        for (let cl = 0; cl <= KIND.length; cl++) {
          let any = false; ctx.beginPath();
          for (let i = 1; i < n; i++) {
            if (f.pet[i - 1].cls !== cl) continue;
            const b = Z[i] > 0.4 ? 0 : Z[i] > -0.3 ? 1 : 2; if (b !== bin) continue;
            const r = (3.3 + 0.5 * (cl === 0)) * sc * Math.pow(S[i], 1.6) * zf; ctx.moveTo(X[i] + r, Y[i]); ctx.arc(X[i], Y[i], r, 0, 6.2832); any = true;
          }
          if (!any) continue;
          const al = [0.3, 0.65, 1][bin] * dim, col = cl === 0 ? SES : KIND[cl - 1];
          ctx.globalAlpha = al * 0.22; ctx.fillStyle = col; ctx.lineWidth = 0;   // 빛 번짐: 같은 점을 한 번 더 크게
          if (bin > 0) { ctx.save(); ctx.lineWidth = 4 * sc * zf; ctx.strokeStyle = col; ctx.stroke(); ctx.restore(); }   // 번짐(같은 색, 옅게)
          ctx.globalAlpha = al; ctx.fill();
        }
      }
      // 중심(업무)
      if (Z[0] < 0.6) {
        const r = 5.2 * sc * Math.pow(S[0], 1.6) * zf, a = alphaOf(Z[0]) * dim;
        ctx.globalAlpha = a * 0.3; ctx.fillStyle = f.tint; ctx.beginPath(); ctx.arc(X[0], Y[0], r * 2.1, 0, 6.2832); ctx.fill();
        ctx.globalAlpha = a; ctx.fillStyle = f.tint; ctx.beginPath(); ctx.arc(X[0], Y[0], r, 0, 6.2832); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
    // 호버와 누른 곳 판정: 꽃 원판
    const hit = (mx, my) => { let best = null, bd = 1e9; for (const f of flowers) { if (f.Z[0] > 0.35) continue; const d = Math.hypot(mx - f.X[0], my - f.Y[0]) / f.rs; if (d < 1 && d < bd) { bd = d; best = f; } } return best; };
    hover = v.mouse && !v.dragging ? hit(v.mouse.x, v.mouse.y) : null;
    const cvs = main.querySelector('canvas:not(.g3dmesh)'); if (cvs) cvs.style.cursor = hover ? 'pointer' : v.dragging ? 'grabbing' : 'grab';
    ctx.textBaseline = 'middle';
    const pill = (txt, x, y, al, right) => {
      const tw = ctx.measureText(txt).width + 12, x0 = right ? x - tw : x;
      ctx.globalAlpha = 0.78 * al; ctx.fillStyle = BROWN; ctx.beginPath(); ctx.roundRect(x0, y - 9, tw, 18, 9); ctx.fill();
      ctx.globalAlpha = al; ctx.fillStyle = '#FFFFFF'; ctx.textAlign = 'left'; ctx.fillText(txt, x0 + 6, y);
      ctx.globalAlpha = 1; return [x0, y - 9, tw, 18];
    };
    ctx.font = `500 11px ${FONT}`;
    if (focus) {
      const f = focus, placed = [], X = f.X, Y = f.Y, Z = f.Z, S = f.S;
      const idx = []; for (let i = 1; i < f.n; i++) if (Z[i] < 0.1) idx.push(i); idx.sort((a, b) => Z[a] - Z[b]);
      const title = pill(trunc(f.t.title, 30), Math.max(12, Math.min(w - 12, X[0])) - 0, Math.max(14, Y[0] - f.rs - 14), 1, false);
      placed.push(title);
      for (const i of idx) {
        if (X[i] < 6 || X[i] > w - 6 || Y[i] < 6 || Y[i] > h - 6) continue;
        const dx = X[i] - X[0], dy = Y[i] - Y[0], l = Math.hypot(dx, dy) || 1, r = 3 * sc * S[i] * zf + 5, txt = trunc(f.pet[i - 1].label, 20), tw = ctx.measureText(txt).width + 12, right = dx < 0;
        const x = X[i] + dx / l * r, y = Y[i] + dy / l * r * 0.6, x0 = right ? x - tw : x;
        if (placed.some(q => x0 < q[0] + q[2] + 2 && x0 + tw > q[0] - 2 && y - 9 < q[1] + q[3] + 1 && y + 9 > q[1] - 1)) continue;
        placed.push(pill(txt, x, y, alphaOf(Z[i]), right));
      }
      // 단추: 꽃 오른쪽, 화면 안
      const bw = btn.offsetWidth || 90; btn.style.left = Math.max(8, Math.min(w - bw - 8, X[0] + f.rs + 14)) + 'px'; btn.style.top = Math.max(8, Math.min(h - 40, Y[0] - 14)) + 'px';
    } else {
      // 분야 이름
      ctx.font = `600 11px ${FONT}`;
      for (const hb of hubs) {
        const p = pj(hb.dir.map(x => x * 1.2)); if (p[2] > 0.1) continue;
        const txt = hb.th.name, tw = ctx.measureText(txt).width + 12, x = Math.max(6, Math.min(w - tw - 6, p[0] - tw / 2)), y = Math.max(14, Math.min(h - 14, p[1]));
        pill(txt, x, y, 0.9, false);
      }
      if (hover) { ctx.font = `500 12px ${FONT}`; const f = hover; pill(trunc(f.t.title, 30), Math.min(w - 40, f.X[0] + 12), Math.max(14, f.Y[0] - 16), 1, false); }
    }
  };

  const g = window.G3D(main, draw);
  g.view.onClick((x, y) => {
    let best = null, bd = 1e9;
    for (const f of flowers) { if (f.Z[0] > 0.35) continue; const d = Math.hypot(x - f.X[0], y - f.Y[0]) / f.rs; if (d < 1 && d < bd) { bd = d; best = f; } }
    if (best) { if (best !== focus) enter(best); } else leave();
  });
  return () => { window.removeEventListener('keydown', onKey); g.destroy(); btn.remove(); back.remove(); };
};

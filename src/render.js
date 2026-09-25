// 渲染层：只读游戏状态，不改状态。
// 分层绘制（DESIGN.md §3.3）：按 z 升序，每层先画轨道带（不透明），再画该层珠子。

import { TAU } from './geometry.js';
import { findSevenReaction } from './scene.js';
import { BASE_COLOR, BASE_INK, WRONG_COLOR, WRONG_INK, Z, DESIGN, modeButtonRect, menuLayout, menuButtonRect } from './config.js';
import { runStatus } from './run.js';
import { elemColor, elemName, elemGlyph, ELEM } from './elements.js';

function hexA(hex, a) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
}

function strokePoly(ctx, poly, i0, i1, width, style, dx, dy) {
  if (i1 <= i0) return;
  ctx.beginPath();
  ctx.moveTo(poly[i0].x + (dx || 0), poly[i0].y + (dy || 0));
  for (let i = i0 + 1; i <= i1; i++) ctx.lineTo(poly[i].x + (dx || 0), poly[i].y + (dy || 0));
  ctx.lineWidth = width;
  ctx.strokeStyle = style;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.stroke();
}

function drawBackground(ctx, G) {
  const v = G.view;
  const g = ctx.createRadialGradient(v.cx, v.cy, 0, v.cx, v.cy, Math.max(v.w, v.h) * 0.72);
  g.addColorStop(0, '#0d1524');
  g.addColorStop(1, '#05070c');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, v.w, v.h);

  // 细网格（实验室感，弱对比）
  const step = 48 * G.metrics.scale;
  ctx.strokeStyle = 'rgba(90,130,190,0.07)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let x = v.cx % step; x < v.w; x += step) { ctx.moveTo(x, 0); ctx.lineTo(x, v.h); }
  for (let y = v.cy % step; y < v.h; y += step) { ctx.moveTo(0, y); ctx.lineTo(v.w, y); }
  ctx.stroke();
}

function drawTrackLayer(ctx, G, z) {
  const mt = G.metrics;
  const bedW = 2 * (mt.d / 2 + mt.R) + 10 * mt.scale;
  const runs = G.runs.spawn;
  const spinePoly = G.path.pts;

  // 1) 床（不透明，负责遮挡下层）
  for (let i = 0; i < runs.length; i++) {
    const run = runs[i];
    if (run.z !== z) continue;
    if (z > 0) strokePoly(ctx, spinePoly, run.i0, run.i1, bedW, 'rgba(0,0,0,0.6)', 3 * mt.scale, 4 * mt.scale);
    strokePoly(ctx, spinePoly, run.i0, run.i1, bedW, z > 0 ? '#182338' : '#101827');
  }
  // 2) 两条轨道线
  const ids = ['eliminate', 'spawn'];
  for (let k = 0; k < ids.length; k++) {
    const id = ids[k];
    const rail = G.rails[id];
    const poly = G.railPolys[id];
    for (let i = 0; i < runs.length; i++) {
      const run = runs[i];
      if (run.z !== z) continue;
      strokePoly(ctx, poly, run.i0, run.i1, 2 * rail.radius + 4 * mt.scale,
        id === 'spawn' ? '#1d2b40' : '#182435');
      strokePoly(ctx, poly, run.i0, run.i1, 1.0 * mt.scale,
        id === 'spawn' ? 'rgba(96,142,205,0.50)' : 'rgba(80,180,150,0.40)');
    }
  }
}

// label = 球面上的字（匹配模式是碱基字母，七球模式是元素汉字：火水冰雷草岩风）
function drawBead(ctx, x, y, r, label, glow, color, ink, glowColor, frozen) {
  const fill = color || BASE_COLOR[label] || '#8899aa';
  const textInk = ink || BASE_INK[label] || '#101820';
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.fillStyle = fill;
  ctx.fill();

  const g = ctx.createRadialGradient(x - r * 0.35, y - r * 0.42, r * 0.1, x, y, r * 1.05);
  g.addColorStop(0, 'rgba(255,255,255,0.55)');
  g.addColorStop(0.45, 'rgba(255,255,255,0.08)');
  g.addColorStop(1, 'rgba(0,0,0,0.35)');
  ctx.fillStyle = g;
  ctx.fill();

  ctx.lineWidth = Math.max(1, r * 0.1);
  ctx.strokeStyle = 'rgba(0,0,0,0.5)';
  ctx.stroke();

  if (glow) {
    ctx.beginPath();
    ctx.arc(x, y, r + 3, 0, TAU);
    ctx.strokeStyle = glowColor || 'rgba(255,255,255,0.5)';
    ctx.lineWidth = Math.max(1.5, r * 0.18);
    ctx.stroke();
  }

  // ★ §57 冻结：蒙一层冰 + 白边（原神里被冻住 = 不能行动）
  if (frozen > 0) {
    ctx.beginPath();
    ctx.arc(x, y, r * 0.97, 0, TAU);
    ctx.fillStyle = 'rgba(168,236,255,0.42)';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x, y, r * 1.06, 0, TAU);
    ctx.strokeStyle = 'rgba(228,250,255,0.92)';
    ctx.lineWidth = Math.max(1.5, r * 0.14);
    ctx.stroke();
  }

  ctx.fillStyle = textInk;
  ctx.font = 'bold ' + Math.round(r * 1.05) + 'px ui-monospace, SFMono-Regular, Menlo, monospace';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label, x, y + r * 0.06);
}

// 配对连线：一条粗棒，**画在球之上**，横跨两颗球的中心之间。
// 之前画的是两条细线、且在球之前绘制 —— 两轨之间只有 2px 缝，等于看不见。
// 现在：球距拉开（railClearance 9.0）+ 画在球上层 + 粗度随缩放 -> 一眼可见。
function drawPairLink(ctx, a, b, color, scale, wrong) {
  const s0 = scale || 1;
  const dx = b.x - a.x, dy = b.y - a.y;
  const len = Math.hypot(dx, dy) || 1;
  const px = -dy / len, py = dx / len;          // 连线的法向
  ctx.strokeStyle = color;
  ctx.lineWidth = Math.max(3, 3.4 * s0);
  ctx.lineCap = 'round';
  ctx.beginPath();
  if (!wrong) {
    // 正确配对：一条直棒（DESIGN.md §24）。本来想画两条平行线当氢键，
    // 但手机 scale 0.82 下太细，改成一条粗的更好认。
    ctx.moveTo(a.x + dx * 0.26, a.y + dy * 0.26);
    ctx.lineTo(a.x + dx * 0.74, a.y + dy * 0.74);
  } else {
    // ★ 错误配对（mark=2）：画成**断掉的锯齿** —— 主题上就是"氢键接不上"（DESIGN.md §32）
    const amp = Math.max(2.5, 3.4 * s0);
    ctx.moveTo(a.x + dx * 0.26, a.y + dy * 0.26);
    ctx.lineTo(a.x + dx * 0.42 + px * amp, a.y + dy * 0.42 + py * amp);
    ctx.lineTo(a.x + dx * 0.58 - px * amp, a.y + dy * 0.58 - py * amp);
    ctx.lineTo(a.x + dx * 0.74, a.y + dy * 0.74);
  }
  ctx.stroke();
}

// 连线单独一遍，在所有珠子之上
function drawPairLinks(ctx, G, z) {
  const list = G.beads.eliminate;
  for (let i = 0; i < list.length; i++) {
    const b = list[i];
    if (b.z !== z || !b.partner) continue;
    const pairCol = b.wrong ? WRONG_COLOR : BASE_COLOR[b.base];
    drawPairLink(ctx, b, b.partner, pairCol, G.metrics.scale, b.wrong === true);
  }
}

function drawBeadLayer(ctx, G, z) {
  const ids = ['eliminate', 'spawn'];
  for (let k = 0; k < ids.length; k++) {
    const id = ids[k];
    const list = G.beads[id];
    for (let i = 0; i < list.length; i++) {
      const b = list[i];
      if (b.z !== z) continue;
      // ★ 经典祖玛（§66）：原版是纯色球、没有字母 → label 传空
      const lab = (G.rules === 'classic') ? '' : (b.label || b.base);
      drawBead(ctx, b.x, b.y, b.r, lab, b.paired === true,
        b.wrong ? WRONG_COLOR : (b.col || null), b.wrong ? WRONG_INK : (b.ink || null),
        b.pairGlow, b.frozen);
    }
  }
}

// U12：并入过程中的球。画在**同层链珠之上**（正在挤进去，得看得见），
// 但 z 仍由 wp 决定，所以跨层（桥）时顺序依然正确。
function drawMergeLayer(ctx, G, z) {
  const sc = G.sc;
  if (!sc || !sc.merges) return;
  for (let i = 0; i < sc.merges.length; i++) {
    const m = sc.merges[i];
    if (m.z !== z) continue;
    drawBead(ctx, m.x, m.y, m.r, m.base, true, null, null, null, 0);
  }
}

function drawCave(ctx, G) {
  const end = G.path.pointAt(G.path.length);
  const mt = G.metrics;
  const R = mt.R * 1.5;
  const g = ctx.createRadialGradient(end.x, end.y, R * 0.15, end.x, end.y, R * 1.3);
  g.addColorStop(0, '#000000');
  g.addColorStop(0.55, '#1a0a12');
  g.addColorStop(1, 'rgba(255,70,90,0.28)');
  ctx.beginPath();
  ctx.arc(end.x, end.y, R, 0, TAU);
  ctx.fillStyle = g;
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,90,110,0.75)';
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = 'rgba(255,150,160,0.9)';
  ctx.font = '600 ' + Math.round(11 * mt.scale) + 'px system-ui, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('降解洞穴', end.x, end.y + R + 14 * mt.scale);
}

function drawRibosome(ctx, G) {
  const sc = G.sc;
  const mt = G.metrics;
  if (!sc || !sc.rb) return;
  const rb = sc.rb;
  const R = rb.r;

  // 瞄准线
  ctx.beginPath();
  ctx.moveTo(rb.x, rb.y);
  ctx.lineTo(rb.x + Math.cos(rb.aim) * (R + 110 * mt.scale), rb.y + Math.sin(rb.aim) * (R + 110 * mt.scale));
  ctx.strokeStyle = 'rgba(150,200,255,0.30)';
  ctx.lineWidth = Math.max(1, 1.4 * mt.scale);
  ctx.stroke();

  // 本体
  ctx.beginPath();
  ctx.arc(rb.x, rb.y, R, 0, TAU);
  ctx.fillStyle = '#22303f';
  ctx.fill();
  ctx.strokeStyle = 'rgba(150,200,255,0.55)';
  ctx.lineWidth = 2;
  ctx.stroke();

  // 双珠待命：炮口那颗 + 身后那颗
  // ★ 尺寸就是模式（DESIGN.md §46）：匹配模式口中是小球、加球模式是大球。
  //   这样玩家不用看按钮也知道这一发是干什么的。
  const bR = (sc.mode === 'insert') ? mt.R : mt.r;
  // 七球模式下手里装的是元素 -> 用元素的配色与汉字画；匹配模式仍是碱基
  const sv = sc.mode === 'seven';
  const tk = function (k) { return sv ? elemColor(rb.loaded[k]) : null; };
  const ik = function (k) { return sv && ELEM[rb.loaded[k]] ? ELEM[rb.loaded[k]].ink : null; };
  const lb = function (k) { return sv ? elemGlyph(rb.loaded[k]) : rb.loaded[k]; };
  drawBead(ctx, rb.x - Math.cos(rb.aim) * R * 0.7, rb.y - Math.sin(rb.aim) * R * 0.7,
    bR * 0.8, lb(1), false, tk(1), ik(1), null, 0);
  drawBead(ctx, rb.x + Math.cos(rb.aim) * R * 0.8, rb.y + Math.sin(rb.aim) * R * 0.8,
    bR * 1.0, lb(0), true, tk(0), ik(0), null, 0);
}

// §57 绽放的草原核：一颗会脉动的草色球，外圈画剩余时间。
// 原神里草原核 6 秒后爆炸、最多 5 个 —— 这里把"还剩多久"直接画出来，
// 因为玩家要据此决定"先躲开还是先引爆"。
// ★ §57.11 对策①：瞄准提示。
//   元素层没有"看颜色就知道发哪颗"这种直觉通道，玩家得背七元素反应表 —— 这是本模式
//   最大的可用性风险。对策就是**把已经算好的结果直接说出来**：只在"这一发真的打得中"
//   的球上标（碱基互补 + 未配对 + 真会触发反应），别的一概不标，免得糊成一片。
//   ⚠ 判定必须走 scene 的 findSevenReaction —— 提示和实际结算共用一份逻辑，提示才不会骗人。
function drawReactionHints(ctx, G) {
  const sc = G.sc;
  if (!sc || sc.mode !== 'seven' || !DESIGN.elemHints) return;
  const rb = sc.rb;
  if (!rb || !rb.loaded) return;
  const bead = rb.loaded[0];
  if (!bead) return;
  const bs = sc.chain.balls;
  const mt = G.metrics;
  const maxN = DESIGN.hintMaxCount || 4;
  let shown = 0;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'bottom';
  for (let i = 0; i < bs.length && shown < maxN; i++) {
    const b = bs[i];
    if (b.paired) continue;                       // 已占用的球打不中
    const r = findSevenReaction(sc, i, bead);     // 没反应 = 打上去是废弹，不提示
    if (!r) continue;
    const txt = r.name + (r.mult > 0 ? ' ×' + r.mult : '');
    ctx.font = '700 ' + Math.max(10, Math.round(14 * mt.scale)) + 'px system-ui, sans-serif';
    const w = ctx.measureText(txt).width;
    const bh = Math.max(13, 17 * mt.scale);
    const by = b.y - b.r - Math.max(12, 20 * mt.scale);
    ctx.fillStyle = 'rgba(8,12,20,0.80)';
    ctx.fillRect(b.x - w / 2 - 4, by, w + 8, bh);
    ctx.fillStyle = elemColor(bead);
    ctx.fillText(txt, b.x, by + bh - 2);
    shown += 1;
  }
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
}

function drawCores(ctx, G) {
  const sc = G.sc;
  if (!sc || !sc.cores || !sc.cores.length) return;
  const mt = G.metrics;
  const T = DESIGN.elemCoreLife;
  for (let i = 0; i < sc.cores.length; i++) {
    const c = sc.cores[i];
    const r = mt.r * 0.78;
    const pulse = 1 + 0.16 * Math.sin((T - c.t) * 7);
    ctx.beginPath();
    ctx.arc(c.x, c.y, r * pulse, 0, TAU);
    ctx.fillStyle = 'rgba(142,222,82,0.92)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(232,255,190,0.95)';
    ctx.lineWidth = Math.max(1.5, r * 0.22);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(c.x, c.y, r * pulse + 3.5 * mt.scale, -Math.PI / 2,
      -Math.PI / 2 + TAU * Math.max(0, Math.min(1, c.t / T)));
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = Math.max(1.2, r * 0.18);
    ctx.stroke();
  }
}

function drawProjectiles(ctx, G) {
  const sc = G.sc;
  if (!sc || !sc.projectiles) return;
  for (let i = 0; i < sc.projectiles.length; i++) {
    const p = sc.projectiles[i];
    const svp = sc.mode === 'seven';
    drawBead(ctx, p.x, p.y, p.r, svp ? elemGlyph(p.base) : p.base, false,
      svp ? elemColor(p.base) : null, null, null, 0);
  }
}

// U9：run 长度徽标 + 识别窗口倒计时条。
// 存在的理由见 DESIGN.md §2.2：两轨共用一条不透明轨道带，靠内那条对比度天然更低，
// 所以「阅读框读到第几颗」必须由徽标补，不能只靠看小球。
function drawRunBadges(ctx, G) {
  const sc = G.sc;
  if (!sc || !sc.runsInfo || !sc.chain) return;
  const mt = G.metrics;
  const balls = sc.chain.balls;
  const side = sc.rails.eliminate.offset >= 0 ? 1 : -1;
  const dist = Math.abs(sc.rails.eliminate.offset) + mt.r + 16 * mt.scale;
  for (let i = 0; i < sc.runsInfo.length; i++) {
    const r = sc.runsInfo[i];
    const mid = balls[Math.floor((r.i0 + r.i1) / 2)];
    if (!mid || mid.x == null) continue;
    const n = sc.path.normalAt(mid.wp);
    const x = mid.x + n.x * dist * side;
    const y = mid.y + n.y * dist * side;
    const st = runStatus(r);
    // 把「还差几颗」直接写出来 —— 4 连/5 连不消是最反直觉的一条，得让人看见。
    const label = st.mod ? ('✓ ' + r.len + ' 颗 · 可消') : (r.len + ' 颗 · 还差 ' + st.toNext);
    ctx.font = 'bold ' + Math.round(13 * mt.scale) + 'px ui-monospace, Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const w = Math.max(34 * mt.scale, (ctx.measureText ? ctx.measureText(label).width : 30) + 14 * mt.scale);
    const h = 18 * mt.scale;
    ctx.fillStyle = st.mod ? 'rgba(30,96,64,0.92)' : 'rgba(36,46,64,0.92)';
    ctx.fillRect(x - w / 2, y - h / 2, w, h);
    ctx.strokeStyle = st.mod ? 'rgba(127,224,160,0.95)' : 'rgba(120,150,190,0.7)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x - w / 2, y - h / 2, w, h);
    ctx.fillStyle = st.mod ? '#c9ffe0' : 'rgba(200,215,235,0.9)';
    ctx.fillText(label, x, y + 1);
  }
}

// 模式按钮：右下角。点它切模式（main.js 里判点击，共用 modeButtonRect 的几何）。
// 按钮里画一颗"口中珠子"的缩略 —— 小球 = 匹配、大球 = 加球，和核糖体里的一致。
// §61 局内的「回菜单」按钮（左下角，和右下角的模式按钮对称）。
// 手机上没有 Esc，所以必须有实体按钮 —— 这是离开一关的唯一出路。
function drawMenuButton(ctx, G) {
  const mt = G.metrics;
  const b = menuButtonRect(G.view, mt);
  ctx.beginPath();
  ctx.arc(b.x, b.y, b.r, 0, TAU);
  ctx.fillStyle = 'rgba(12,20,34,0.86)';
  ctx.fill();
  ctx.lineWidth = Math.max(1.5, 2 * mt.scale);
  ctx.strokeStyle = 'rgba(150,185,230,0.8)';
  ctx.stroke();
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = Math.max(10, Math.round(12 * mt.scale)) + 'px system-ui, sans-serif';
  ctx.fillStyle = 'rgba(226,238,255,0.95)';
  ctx.fillText('菜单', b.x, b.y + 0.5);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
}

// ★ §61 开始菜单。
//   背景不是另画的 —— 它直接用**已经装配好的那一关**当背景板（main.js 在菜单态
//   不推进场景，所以是静止的）。省一整套美术，而且玩家一眼能看到自己上次在哪一关。
function drawMenu(ctx, G) {
  const v = G.view, mt = G.metrics;
  const M = menuLayout(v, mt, G.menuItems || []);

  // 暗幕
  ctx.fillStyle = 'rgba(6,10,18,0.87)';
  ctx.fillRect(0, 0, v.w, v.h);

  // 标题
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = '#e8f2ff';
  ctx.font = '800 ' + Math.max(26, Math.round(44 * mt.scale)) + 'px system-ui, sans-serif';
  ctx.fillText('RNA 祖玛', v.cx, M.titleY);
  ctx.fillStyle = 'rgba(160,195,235,0.95)';
  ctx.font = '600 ' + Math.max(11, Math.round(15 * mt.scale)) + 'px system-ui, sans-serif';
  ctx.fillText('反色配对 · 凑三颗 · 读出 mRNA', v.cx, M.titleY + Math.max(20, 30 * mt.scale));

  // 分组标题
  for (let i = 0; i < M.groups.length; i++) {
    ctx.textAlign = 'left';
    ctx.fillStyle = 'rgba(150,200,240,0.9)';
    ctx.font = '700 ' + Math.max(11, Math.round(14 * mt.scale)) + 'px system-ui, sans-serif';
    ctx.fillText(M.groups[i].name, M.x0, M.groups[i].y + 8 * mt.scale);
  }

  // 关卡按钮
  ctx.textAlign = 'center';
  for (let i = 0; i < M.buttons.length; i++) {
    const b = M.buttons[i];
    const tut = b.item.group === '新手关';
    ctx.fillStyle = tut ? 'rgba(26,60,58,0.95)' : 'rgba(22,32,50,0.95)';
    ctx.fillRect(b.x, b.y, b.w, b.h);
    ctx.lineWidth = Math.max(1.2, 1.6 * mt.scale);
    ctx.strokeStyle = tut ? 'rgba(92,201,168,0.9)' : 'rgba(120,170,230,0.7)';
    ctx.strokeRect(b.x, b.y, b.w, b.h);
    ctx.fillStyle = '#eaf4ff';
    ctx.font = '700 ' + Math.max(11, Math.round(15 * mt.scale)) + 'px system-ui, sans-serif';
    ctx.fillText(b.item.label, b.x + b.w / 2, b.y + b.h / 2);
  }

  // 底部操作说明
  ctx.fillStyle = 'rgba(150,180,215,0.9)';
  ctx.font = Math.max(10, Math.round(12 * mt.scale)) + 'px system-ui, sans-serif';
  ctx.fillText('点关卡开始 · 点画面发射 · 点核糖体换珠 · 点右下角切模式 · Esc 回菜单',
    v.cx, M.footerY);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
}

function drawModeButton(ctx, G) {
  const sc = G.sc;
  if (!sc) return;
  const mt = G.metrics;
  const btn = modeButtonRect(G.view, mt);
  // ★ §65 按钮只表示 匹配 <-> 加球 两态（七球不上按钮，见 main.js 的注释）。
  //   颜色和缩略珠子都跟着模式变，玩家不用读字也知道这一发是干什么的。
  const isIns = sc.mode === 'insert';
  const isElem = false;
  const accent = isIns ? '#ff9a3c' : '#2fd6c6';

  ctx.beginPath();
  ctx.arc(btn.x, btn.y, btn.r, 0, TAU);
  ctx.fillStyle = 'rgba(12,20,34,0.86)';
  ctx.fill();
  const flash = sc.modeFlash > 0 ? Math.min(1, sc.modeFlash / 0.28) : 0;
  ctx.lineWidth = Math.max(2, (2.6 + 3.0 * flash) * mt.scale);
  ctx.strokeStyle = accent;
  ctx.stroke();
  if (flash > 0) {                       // 按压反馈：外圈再亮一下
    ctx.beginPath();
    ctx.arc(btn.x, btn.y, btn.r + 4 * mt.scale, 0, TAU);
    ctx.lineWidth = Math.max(1.5, 2.4 * mt.scale * flash);
    ctx.strokeStyle = accent;
    ctx.globalAlpha = flash;
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  // 缩略珠子：小球 = 匹配，大球 = 加球
  const br = isIns ? btn.r * 0.50 : btn.r * 0.34;
  ctx.beginPath();
  ctx.arc(btn.x, btn.y - btn.r * 0.18, br, 0, TAU);
  ctx.fillStyle = accent;
  ctx.fill();
  if (isElem) {                     // 元素模式：缩略珠子外面套一圈元素环
    ctx.beginPath();
    ctx.arc(btn.x, btn.y - btn.r * 0.18, br * 0.62, 0, TAU);
    ctx.strokeStyle = 'rgba(255,255,255,0.92)';
    ctx.lineWidth = Math.max(1.5, br * 0.26);
    ctx.stroke();
  }

  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = Math.max(10, Math.round(13 * mt.scale)) + 'px system-ui, sans-serif';
  ctx.fillStyle = 'rgba(226,238,255,0.95)';
  ctx.fillText(isIns ? '加球' : (isElem ? '七球' : '匹配'), btn.x, btn.y + btn.r * 0.52);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
}

function drawDebug(ctx, G) {
  const pts = G.path.pts;
  ctx.strokeStyle = 'rgba(120,255,255,0.85)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let i = 0; i < pts.length; i += 20) {
    const p = pts[i];
    ctx.moveTo(p.x, p.y);
    ctx.lineTo(p.x + p.nx * 16, p.y + p.ny * 16);
  }
  ctx.stroke();

  for (let i = 0; i < G.issues.length; i++) {
    const it = G.issues[i];
    if (it.x == null) continue;
    ctx.beginPath();
    ctx.arc(it.x, it.y, 9, 0, TAU);
    ctx.strokeStyle = it.severity === 'error' ? '#ff5a5f' : (it.severity === 'warn' ? '#ffd23f' : '#43d17a');
    ctx.lineWidth = 2;
    ctx.stroke();
  }
}

function drawLegend(ctx, G) {
  const mt = G.metrics;
  const v = G.view;
  const x = 16;
  let y = v.h - 92 * Math.max(0.85, mt.scale);
  const R = mt.R * 0.85;
  const r = mt.r * 0.85;
  drawBead(ctx, x + R + 2, y, R, 'A', false);
  ctx.fillStyle = 'rgba(200,220,245,0.9)';
  ctx.font = '600 12px system-ui, sans-serif';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  ctx.fillText('出球道 · 大球  D=' + (2 * mt.R).toFixed(1) + 'px', x + R * 2 + 12, y);
  y += R + r + 18;
  drawBead(ctx, x + r + 2, y, r, 'U', false);
  ctx.fillText('三消道 · 小球  d=' + (2 * mt.r).toFixed(1) + 'px（×1/√2）', x + R * 2 + 12, y);
}

export function render(ctx, G) {
  const v = G.view;
  ctx.setTransform(v.dpr, 0, 0, v.dpr, 0, 0);
  drawBackground(ctx, G);

  const zs = G.zLevels;
  for (let k = 0; k < zs.length; k++) {
    drawTrackLayer(ctx, G, zs[k]);
    drawBeadLayer(ctx, G, zs[k]);
    drawPairLinks(ctx, G, zs[k]);
    drawMergeLayer(ctx, G, zs[k]);
  }

  // §63 静止练习关没有洞穴（也就没有失败）—— 画一个不存在的终点只会误导
  if (!(G.sc && G.sc.still)) drawCave(ctx, G);
  drawCores(ctx, G);
  drawReactionHints(ctx, G);
  drawRibosome(ctx, G);
  drawProjectiles(ctx, G);

  // ★ §61 菜单态：场景照画（当背景板），但**不画任何局内 HUD** ——
  //   关卡名/分数/徽章在菜单后面露出来会很脏。调试层是唯一的例外（它本来就不给玩家看）。
  if (G.screen === 'menu') {
    if (G.debug) drawDebug(ctx, G);
    drawMenu(ctx, G);
    return;
  }

  drawModeButton(ctx, G);
  drawMenuButton(ctx, G);
  drawRunBadges(ctx, G);
  if (G.debug) drawDebug(ctx, G);

  const mt = G.metrics;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
  ctx.fillStyle = 'rgba(210,230,255,0.95)';
  ctx.font = '700 15px system-ui, sans-serif';
  const ii0 = G.chainInfo;
  ctx.fillText(G.level.name, 16, 14);
  // ★ §60 新手关的教学提示：直接写在关卡名下面。
  //   不是"请点击此处"那种废话，而是**这一关要教的规则本身**。
  //   §64：支持多行 —— 有些规则是一整句话（比如"灰球什么时候才炸"），
  //   硬压成一行就只能含糊其辞，而含糊的提示等于没提示。
  if (G.level && G.level.hint) {
    const lines = Object.prototype.toString.call(G.level.hint) === '[object Array]'
      ? G.level.hint : [G.level.hint];
    ctx.font = '600 ' + Math.max(11, Math.round(15 * mt.scale)) + 'px system-ui, sans-serif';
    for (let i = 0; i < lines.length; i++) {
      ctx.fillStyle = i === 0 ? '#ffd76a' : 'rgba(255,215,106,0.78)';
      ctx.fillText(lines[i], 16, 14 + (19 + i * 17) * mt.scale);
    }
  }
  // 过关进度（非 debug 也显示）—— 原版是靠分数达标过关的，得让玩家看得见
  if (ii0) {
    // ★ 两类关卡目标（DESIGN.md §55）：有限球数关 = 清空过关；无尽关 = 分数过关。
    //   所以进度条画的东西不一样，而且 Infinity 绝不能漏进文案（会显示"分数 120 / Infinity"）。
    const sTgt = ii0.scoreTarget;
    const hasScoreTgt = typeof sTgt === 'number' && isFinite(sTgt) && sTgt > 0;
    ctx.font = '600 ' + Math.max(11, Math.round(15 * mt.scale)) + 'px system-ui, sans-serif';
    ctx.fillStyle = G.sc.won ? '#7ee0a0' : 'rgba(200,225,255,0.95)';
    ctx.fillText((G.sc.won ? '过关！ ' : '') +
      '场上 ' + ii0.onField + ' 颗  ·  ' +
      (ii0.endless ? '无限出球' : ('待出 ' + ii0.remaining + ' / ' + ii0.budget + ' 颗')) +
      '    命 ' + ii0.lives + '    分数 ' + ii0.score +
      (hasScoreTgt ? (' / ' + sTgt) : ''),
      16, 14 + 20 * mt.scale);
    // 进度条：有限球数关 = 出球进度（发满 + 清光才过关）；无尽关 = 分数进度
    const prog = ii0.endless
      ? (hasScoreTgt ? ii0.score / sTgt : 0)
      : (ii0.budget > 0 ? ii0.spawned / ii0.budget : 0);
    const bw = 150 * mt.scale, bh = 5 * mt.scale, by = 14 + 38 * mt.scale;
    ctx.fillStyle = 'rgba(255,255,255,0.14)';
    ctx.fillRect(16, by, bw, bh);
    ctx.fillStyle = G.sc.won ? '#7ee0a0' : '#3c8cdc';
    ctx.fillRect(16, by, bw * Math.max(0, Math.min(1, prog)), bh);
  }
  // ★ §57 元素模式：状态行（护盾/草原核/反应数/装载的元素）+ 反应横幅
  if (G.sc && G.sc.mode === 'seven' && ii0) {
    ctx.font = '600 ' + Math.max(11, Math.round(14 * mt.scale)) + 'px system-ui, sans-serif';
    ctx.fillStyle = 'rgba(225,235,255,0.92)';
    const le = ii0.loaded || [null, null];
    ctx.fillText('盾 ' + ii0.shields + '   核 ' + ii0.cores + '   反应 ' + ii0.reactions +
      '   装载 ' + elemName(le[0]) + '/' + elemName(le[1]), 16, 14 + 58 * mt.scale);
    const lr = ii0.lastReaction;
    const fl = G.sc.reactionFlash || 0;
    if (lr && fl > 0) {
      ctx.globalAlpha = Math.min(1, fl / 0.6);
      ctx.textAlign = 'center';
      ctx.font = '700 ' + Math.max(16, Math.round(26 * mt.scale)) + 'px system-ui, sans-serif';
      ctx.fillStyle = elemColor(lr.trigger);
      ctx.fillText(lr.name + (lr.mult > 0 ? '  ×' + lr.mult : ''), v.cx, v.cy + 92 * mt.scale);
      ctx.globalAlpha = 1;
      ctx.textAlign = 'left';
    }
  }

  ctx.font = '12px ui-monospace, Menlo, monospace';
  ctx.fillStyle = 'rgba(150,180,215,0.9)';
  const errs = G.issues.filter(function (i) { return i.severity === 'error'; }).length;
  const warns = G.issues.filter(function (i) { return i.severity === 'warn'; }).length;
  const bridges = G.issues.filter(function (i) { return i.code === 'BRIDGE'; }).length;
  ctx.fillText('railOrder=' + G.level.railOrder + '   scale=' + mt.scale.toFixed(3), 16, 38);
  ctx.fillText('R=' + mt.R.toFixed(1) + '  r=' + mt.r.toFixed(1) + '  R/r=' + mt.diameterRatio.toFixed(4) +
               '  area=' + mt.areaRatio.toFixed(3), 16, 56);
  ctx.fillText('d=' + mt.d.toFixed(1) + '  p=' + mt.p.toFixed(1) +
               '  L=' + G.path.length.toFixed(0) + 'px  珠=' + (G.beads.spawn.length + G.beads.eliminate.length), 16, 74);
  ctx.fillStyle = errs ? '#ff8a8f' : (warns ? '#ffd23f' : '#7fe0a0');
  ctx.fillText('校验: error=' + errs + ' warn=' + warns + ' 桥=' + bridges + '（D 看细节）', 16, 92);
  var ci = G.chainInfo;
  if (ci) {
    ctx.fillStyle = 'rgba(160,200,240,0.92)';
    ctx.fillText('分数 ' + ci.score + '     命 ' + ci.lives, 16, 164);
        // ⚠ 这里以前还印「在读=」，但阅读窗（readWindow）已经撤掉了（DESIGN.md §21），
        //   sceneInfo 不再暴露 reading -> 界面上一直显示"在读=undefined"。
        //   直接去掉这个字段，而不是硬塞一个值糊过去（smoke 的文案断言抓到的）。
        ctx.fillText('run=[' + ci.runs.join(',') + ']  已消=' + ci.stats.cleared + ' 密码子=' + ci.stats.codons, 16, 146);
    ctx.fillText('配对=' + ci.paired + '  命中: 配对 ' + ci.stats.pairs + ' / 错配 ' + ci.stats.mismatches + '  弹丸=' + ci.shots, 16, 128);
    ctx.fillText('珠串 n=' + ci.balls + '  速度=' + ci.speed.toFixed(1) + 'px/s  队头=' + ci.headWp.toFixed(0) + '/' + ci.curveLength.toFixed(0) + '  (' + (ci.progress * 100).toFixed(1) + '%）', 16, 110);
  }

  ctx.textAlign = 'right';
  ctx.fillStyle = 'rgba(150,180,215,0.9)';
  ctx.fillText('fps ' + G.fps, v.w - 16, 14);
  ctx.fillText('点画面 = 发射   点核糖体 = 换珠', v.w - 16, 32);
  ctx.fillText('[空格]/右键 换珠   [R] 重开   [1][2][3] 切关   [D] 调试', v.w - 16, 50);

  // U11 状态横幅：失败（被吞掉）/ 命尽
  const ii = G.chainInfo;
  if (ii && ii.gameOver) {
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.fillRect(0, v.cy - 62, v.w, 124);
    ctx.textAlign = 'center';
    ctx.fillStyle = '#ff8a8f';
    ctx.font = '700 34px system-ui, sans-serif';
    ctx.fillText('GAME OVER', v.cx, v.cy - 12);
    ctx.fillStyle = 'rgba(230,240,255,0.92)';
    ctx.font = '600 16px system-ui, sans-serif';
    ctx.fillText('分数 ' + ii.score + '   ［R］重开', v.cx, v.cy + 26);
    ctx.textAlign = 'left';
  } else if (ii && ii.won) {
    ctx.textAlign = 'center';
    ctx.fillStyle = '#7ee0a0';
    ctx.font = '700 34px system-ui, sans-serif';
    ctx.fillText('过 关', v.cx, v.cy - 12);
    ctx.fillStyle = 'rgba(230,240,255,0.92)';
    ctx.font = '600 16px system-ui, sans-serif';
    // ★ 写明是**哪条路**过的关（DESIGN.md §55）—— 清空和分数是完全不同的玩法目标。
    const why = ii.winReason === 'clear' ? '清空全场'
      : (ii.winReason === 'score' ? '分数达标' : '');
    ctx.fillText((why ? why + '   ' : '') + '分数 ' + ii.score +
      '   ［R］重开 · 左下角回菜单', v.cx, v.cy + 26);
    ctx.textAlign = 'left';
  } else if (ii && ii.losing) {
    ctx.textAlign = 'center';
    ctx.fillStyle = 'rgba(255,110,130,0.92)';
    ctx.font = '700 24px system-ui, sans-serif';
    ctx.fillText('被降解洞穴吞掉！剩余 ' + ii.lives + ' 命', v.cx, 56);
    ctx.textAlign = 'left';
  }
  drawLegend(ctx, G);
}


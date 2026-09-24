// 千星奇域移植：轨道骨架导出（可复用库）
//
// 为什么需要它：本作的轨道是一条 **C1 连续的解析骨架 + 法线偏移出两条平行轨**。
// 千星奇域那边只有"路径"这个资产，要重建同样的形状，必须能拿到三样东西：
//   ① 形状本身（一串点）② 两条轨的间距 ③ 沿路径的弧长（因为速度是按弧长定义的）
// 这个文件负责把本作的几何**无损地**翻译成这三种数据，别的导出工具都复用它。
//
// ⚠ 只做数据翻译，不做任何数值改写 —— 缩放/单位换算是**上游**的事。
//   一旦在这里偷偷改数，导出的 JSON 和真实游戏就对不上了。

import { metrics, viewFor, DESIGN } from '../../../src/config.js';
import { buildPath } from '../../../src/geometry.js';

// 建一条路径（和游戏本体走**同一个** buildPath，所以导出的形状不可能和游戏不一样）
export function buildLevelPath(level, viewW, viewH, samples) {
  const view = viewFor(viewW, viewH);
  const mt = metrics(view.scale);
  const spine = level.makeSpine(view, level);
  const path = buildPath(spine, { samples: samples || DESIGN.pathSamples, center: { x: view.cx, y: view.cy } });
  return { view: view, mt: mt, spine: spine, path: path };
}

// 把路径重采样成**等弧长**的 K 个点。
// 为什么不用原始采样点：原始点是等 u 的 —— 弯的地方点密、直的地方点稀；
// 而"球沿轨道等距排列"要的是等弧长。两边参数化不一样，必须显式转换。
export function resampleByArcLength(path, k) {
  const out = [];
  for (let i = 0; i < k; i++) {
    const s = (i / (k - 1)) * path.length;
    const p = path.pointAt(s);
    const nrm = path.normalAt(s);
    out.push({
      s: round(s, 3),
      u: round(s / path.length, 6),
      x: round(p.x, 3),
      y: round(p.y, 3),
      nx: round(nrm.x, 6),
      ny: round(nrm.y, 6),
      z: p.z
    });
  }
  return out;
}

// 归一化：把世界坐标映射进 [-1,1] 的方框（保持长宽比，y 保持屏幕方向：向下为正）。
// 这样导出数据与屏幕尺寸无关 —— 移植时只要知道"目标场地短边多长"就能还原比例。
export function normalizeToUnitBox(pts, view) {
  const half = Math.min(view.w, view.h) / 2;
  return pts.map(function (p) {
    return {
      s: p.s, u: p.u,
      x: round((p.x - view.cx) / half, 6),
      y: round((p.y - view.cy) / half, 6),
      nx: p.nx, ny: p.ny, z: p.z
    };
  });
}

// 两条轨：出球道 / 三消道。由**同一条骨架 + 法线偏移**生成 ——
// 这是本作最核心的几何事实，移植时必须原样保留（两条轨共用一条路径）。
export function railInfo(view) {
  const mt = metrics(view.scale);
  const half = Math.min(view.w, view.h) / 2;
  return {
    spawnOffset: round(mt.d / 2 / half, 6),
    eliminateOffset: round(-mt.d / 2 / half, 6),
    clearance: DESIGN.railClearance,
    ballGap: DESIGN.beadGap,
    bigRadius: round(mt.R / half, 6),
    smallRadius: round(mt.r / half, 6),
    diameterRatio: round(mt.diameterRatio, 6)
  };
}

export function round(v, n) {
  const k = Math.pow(10, n);
  return Math.round(v * k) / k;
}

// 生成一张 SVG：轨道带 + 两条轨中心线 + 出球口/洞穴标记 + 关键数值。
// 用途是**肉眼比对** —— 在千星奇域编辑器里照着捏形状时，有这张图比读坐标快得多。
export function pathToSVG(level, built, samples) {
  const view = built.view, mt = built.mt, path = built.path;
  const W = 900, H = 900;
  const k = Math.min(W, H) / Math.min(view.w, view.h) * 0.86;
  const ox = W / 2 - view.cx * k, oy = H / 2 - view.cy * k;
  const P = function (x, y) { return round(x * k + ox, 2) + ',' + round(y * k + oy, 2); };
  const poly = function (offset, cls) {
    const d = [];
    for (let i = 0; i < samples; i++) {
      const s = (i / (samples - 1)) * path.length;
      const p = path.pointAt(s), n = path.normalAt(s);
      d.push(P(p.x + n.x * offset, p.y + n.y * offset));
    }
    return '<polyline class="' + cls + '" points="' + d.join(' ') + '"/>';
  };
  const halfD = mt.d / 2;
  const start = path.pointAt(0), end = path.pointAt(path.length);
  const svg = [];
  svg.push('<svg xmlns="http://www.w3.org/2000/svg" width="' + W + '" height="' + H + '" viewBox="0 0 ' + W + ' ' + H + '">');
  svg.push('<rect width="100%" height="100%" fill="#070a10"/>');
  svg.push('<style>.bed{fill:none;stroke:#24374e;stroke-width:' + round(mt.d * k, 1) + '}');
  svg.push('.rail{fill:none;stroke:#5aa0d0;stroke-width:1.2;stroke-dasharray:7 7}');
  svg.push('.txt{fill:#9fc4e8;font:13px system-ui}</style>');
  svg.push(poly(0, 'bed'));
  svg.push(poly(halfD, 'rail'));
  svg.push(poly(-halfD, 'rail'));
  svg.push('<circle cx="' + round(start.x * k + ox, 1) + '" cy="' + round(start.y * k + oy, 1) + '" r="7" fill="#4a6"/>');
  svg.push('<circle cx="' + round(end.x * k + ox, 1) + '" cy="' + round(end.y * k + oy, 1) + '" r="9" fill="#c33"/>');
  svg.push('<text class="txt" x="16" y="24">' + esc(level.name) + '　轨道长 ' + round(path.length, 1) + ' 设计单位</text>');
  svg.push('<text class="txt" x="16" y="44">两轨中心距 ' + round(mt.d, 2) + '　球距 ' + round(mt.p, 2) + '　大球 R=' + round(mt.R, 2) + '　小球 r=' + round(mt.r, 2) + '</text>');
  svg.push('<text class="txt" x="16" y="64">绿点 = 出球口　红点 = 降解洞穴　虚线 = 两条轨的中心线（骨架）</text>');
  svg.push('</svg>');
  return svg.join(String.fromCharCode(10));
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

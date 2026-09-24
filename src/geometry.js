// 轨道几何内核：弧长参数化骨架 + 法线偏移双轨 + 层级分段 + 轨道校验器。
// 纯计算，不依赖 DOM，可被 node 直接 import 做单元测试（tools/test-geometry.mjs）。

export const TAU = Math.PI * 2;

export function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }

export class TrackPath {
  constructor(pts, length) {
    this.pts = pts;
    this.length = length;
  }
  get samples() { return this.pts.length; }

  // u ∈ [0,1] -> 弧长
  sAtU(u) {
    const i = Math.round(clamp(u, 0, 1) * (this.pts.length - 1));
    return this.pts[i].s;
  }

  // 弧长 -> 采样区间左端点下标
  indexAt(s) {
    const pts = this.pts;
    if (s <= 0) return 0;
    if (s >= this.length) return pts.length - 2;
    let lo = 0, hi = pts.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (pts[mid].s <= s) lo = mid; else hi = mid;
    }
    return lo;
  }

  pointAt(s) {
    const pts = this.pts;
    const sc = clamp(s, 0, this.length);
    const i = this.indexAt(sc);
    const a = pts[i], b = pts[i + 1];
    const seg = b.s - a.s;
    const t = seg > 1e-9 ? (sc - a.s) / seg : 0;
    return {
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      s: sc,
      z: t < 0.5 ? a.z : b.z
    };
  }

  // 法线（单位向量，沿弧长连续，起点背离 center）
  normalAt(s) {
    const pts = this.pts;
    const sc = clamp(s, 0, this.length);
    const i = this.indexAt(sc);
    const a = pts[i], b = pts[i + 1];
    const seg = b.s - a.s;
    const t = seg > 1e-9 ? (sc - a.s) / seg : 0;
    let nx = a.nx + (b.nx - a.nx) * t;
    let ny = a.ny + (b.ny - a.ny) * t;
    const L = Math.hypot(nx, ny) || 1;
    return { x: nx / L, y: ny / L };
  }

  zAt(s) {
    const i = this.indexAt(clamp(s, 0, this.length));
    return this.pts[i].z;
  }
}

// 采样骨架曲线并建立弧长表。spineFn(u) -> {x,y}，坐标已是像素。
export function buildPath(spineFn, opts) {
  opts = opts || {};
  const n = Math.max(64, opts.samples || 2400);
  const pts = new Array(n + 1);
  let s = 0;
  let px = 0, py = 0;
  for (let i = 0; i <= n; i++) {
    const u = i / n;
    const q = spineFn(u);
    if (i > 0) s += Math.hypot(q.x - px, q.y - py);
    px = q.x; py = q.y;
    pts[i] = { u: u, x: q.x, y: q.y, s: s, nx: 0, ny: 0, z: 0 };
  }
  const path = new TrackPath(pts, s);
  computeNormals(path, opts.center);
  return path;
}

// 法线沿弧长连续：起点用"背离中心"定向，其后用点积连续性翻正。
export function computeNormals(path, center) {
  const pts = path.pts;
  const n = pts.length;
  for (let i = 0; i < n; i++) {
    const a = pts[i > 0 ? i - 1 : 0];
    const b = pts[i < n - 1 ? i + 1 : n - 1];
    let tx = b.x - a.x, ty = b.y - a.y;
    const L = Math.hypot(tx, ty) || 1;
    tx /= L; ty /= L;
    pts[i].nx = -ty;
    pts[i].ny = tx;
  }
  if (center) {
    const p0 = pts[0];
    const rx = p0.x - center.x, ry = p0.y - center.y;
    if (rx * p0.nx + ry * p0.ny < 0) { p0.nx = -p0.nx; p0.ny = -p0.ny; }
  }
  for (let i = 1; i < n; i++) {
    if (pts[i].nx * pts[i - 1].nx + pts[i].ny * pts[i - 1].ny < 0) {
      pts[i].nx = -pts[i].nx;
      pts[i].ny = -pts[i].ny;
    }
  }
  return path;
}

// 层级：按弧长区间给骨架样本打 z
export function assignLayers(path, spec) {
  const pts = path.pts;
  for (let i = 0; i < pts.length; i++) pts[i].z = 0;
  if (!spec) return path;
  for (let k = 0; k < spec.length; k++) {
    const seg = spec[k];
    for (let i = 0; i < pts.length; i++) {
      if (pts[i].s >= seg.from && pts[i].s <= seg.to) pts[i].z = seg.z;
    }
  }
  return path;
}

// 连续同层区间
export function layerRuns(path) {
  const pts = path.pts;
  const runs = [];
  let i0 = 0;
  for (let i = 1; i <= pts.length; i++) {
    if (i === pts.length || pts[i].z !== pts[i0].z) {
      runs.push({ z: pts[i0].z, i0: i0, i1: i - 1 });
      i0 = i;
    }
  }
  return runs;
}

// 轨道折线 = 骨架沿法线偏移
export function buildRail(path, offset) {
  const pts = path.pts;
  const out = new Array(pts.length);
  for (let i = 0; i < pts.length; i++) {
    out[i] = {
      x: pts[i].x + pts[i].nx * offset,
      y: pts[i].y + pts[i].ny * offset,
      s: pts[i].s,
      z: pts[i].z
    };
  }
  return out;
}

// 曲率 κ（=1/ρ，带符号）。用三点外接圆公式。
export function curvatureAt(pts, i) {
  const n = pts.length;
  const a = pts[i > 0 ? i - 1 : 0];
  const b = pts[i];
  const c = pts[i < n - 1 ? i + 1 : n - 1];
  const abx = b.x - a.x, aby = b.y - a.y;
  const bcx = c.x - b.x, bcy = c.y - b.y;
  const acx = c.x - a.x, acy = c.y - a.y;
  const crossv = abx * bcy - aby * bcx;
  const denom = Math.hypot(abx, aby) * Math.hypot(bcx, bcy) * Math.hypot(acx, acy);
  if (denom < 1e-9) return 0;
  return (2 * crossv) / denom;
}

function segCross(o, a, b) {
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

function segIntersect(a, b, c, d) {
  const d1 = segCross(c, d, a);
  const d2 = segCross(c, d, b);
  const d3 = segCross(a, b, c);
  const d4 = segCross(a, b, d);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    const t = d1 / (d1 - d2);
    return { x: c.x + (d.x - c.x) * t, y: c.y + (d.y - c.y) * t };
  }
  return null;
}

// 自交检测（对折线抽稀后两两求交）
export function selfCrossings(poly, opts) {
  opts = opts || {};
  const step = Math.max(1, opts.step || 8);
  const segs = [];
  for (let i = 0; i + step < poly.length; i += step) {
    const j = Math.min(poly.length - 1, i + step);
    const a = poly[i], b = poly[j];
    if (Math.hypot(b.x - a.x, b.y - a.y) < 1e-6) continue;
    segs.push({ a: a, b: b, i0: i, i1: j });
  }
  const out = [];
  for (let i = 0; i < segs.length; i++) {
    for (let j = i + 1; j < segs.length; j++) {
      if (segs[j].i0 - segs[i].i1 < step * 2) continue; // 相邻段跳过
      const hit = segIntersect(segs[i].a, segs[i].b, segs[j].a, segs[j].b);
      if (hit) out.push({ x: hit.x, y: hit.y, s1: segs[i].a.s, s2: segs[j].a.s });
    }
  }
  return out;
}

// 轨道校验器（DESIGN.md §2.4）
export function validateTrack(path, mt, opts) {
  opts = opts || {};
  const issues = [];
  const maxOffset = opts.maxOffset != null ? opts.maxOffset : mt.d / 2;
  const pts = path.pts;

  // 1) 曲率 vs 偏移：κ·offset >= 1 时内偏轨道会自己折叠
  let worst = 0, worstS = 0;
  for (let i = 1; i < pts.length - 1; i++) {
    const need = Math.abs(curvatureAt(pts, i)) * maxOffset;
    if (need > worst) { worst = need; worstS = pts[i].s; }
  }
  if (worst >= 1) {
    issues.push({ code: 'CURVATURE_OFFSET', severity: 'error', s: worstS,
      detail: '偏移 ' + maxOffset.toFixed(1) + 'px 超过最小曲率半径；内偏轨道会折叠' });
  } else if (worst > 0.85) {
    issues.push({ code: 'CURVATURE_TIGHT', severity: 'warn', s: worstS,
      detail: '偏移接近最小曲率半径（占比 ' + worst.toFixed(2) + '），弯道处珠距会明显压缩' });
  }

  // 2) 间距不等式（代数保证，仍然断言，防止有人改常量改坏）
  if (mt.d < mt.R + mt.r) {
    issues.push({ code: 'RAIL_OVERLAP', severity: 'error', s: 0,
      detail: '两轨中心距 ' + mt.d.toFixed(1) + ' < 半径和 ' + (mt.R + mt.r).toFixed(1) });
  }
  if (mt.p < 2 * mt.R) {
    issues.push({ code: 'BEAD_OVERLAP', severity: 'error', s: 0,
      detail: '同轨球心距 ' + mt.p.toFixed(1) + ' < 直径 ' + (2 * mt.R).toFixed(1) });
  }

  // 3) 自交：同层 = 遮挡无解（error）；跨层 = 合法桥（info）
  const rails = opts.rails || [mt.d / 2, -mt.d / 2];
  for (let k = 0; k < rails.length; k++) {
    const poly = buildRail(path, rails[k]);
    const xs = selfCrossings(poly, { step: opts.step || 8 });
    for (let m = 0; m < xs.length; m++) {
      const x = xs[m];
      const z1 = path.zAt(x.s1);
      const z2 = path.zAt(x.s2);
      if (z1 === z2) {
        issues.push({ code: 'SELF_CROSS_SAME_Z', severity: 'error', x: x.x, y: x.y, s: x.s1,
          detail: '同一 z 层 (' + z1 + ') 自交，遮挡关系无解' });
      } else {
        issues.push({ code: 'BRIDGE', severity: 'info', x: x.x, y: x.y, s: x.s1,
          detail: '跨层桥 z' + z1 + ' / z' + z2 });
      }
    }
  }
  return issues;
}


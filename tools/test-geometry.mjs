// U2 几何内核单元测试（DESIGN.md §7 的量化验收项）。
// 用法：node tools/test-geometry.mjs
// 纯计算，无 DOM。

import { DESIGN, metrics, viewFor, BASES, COMPLEMENT } from '../src/config.js';
import {
  TAU, buildPath, assignLayers, layerRuns, buildRail, curvatureAt,
  selfCrossings, validateTrack
} from '../src/geometry.js';
import { spiralSpine, crossReturnSpine } from '../src/spines.js';
import { LEVELS } from '../src/levels.js';
import { makeRng } from '../src/rng.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

// ---------- §2.3 尺寸与不等式 ----------
group('尺寸：直径比 1:√2、面积比 2、间距不等式');
const mt = metrics(1);
check('R = 19 设计单位', Math.abs(mt.R - 19) < 1e-12, 'R=' + mt.R);
check('r = R/√2', Math.abs(mt.r - 19 / Math.SQRT2) < 1e-12, 'r=' + mt.r.toFixed(6));
check('直径比 R/r === √2（误差<1e-12）', Math.abs(mt.diameterRatio - Math.SQRT2) < 1e-12, '=' + mt.diameterRatio.toFixed(12));
check('面积比 === 2（误差<1e-12）', Math.abs(mt.areaRatio - 2) < 1e-12, '=' + mt.areaRatio.toFixed(12));
check('两轨中心距 d >= R + r', mt.d >= mt.R + mt.r - 1e-12, 'd=' + mt.d.toFixed(3) + ' R+r=' + (mt.R + mt.r).toFixed(3));
check('同轨球心距 p >= 2R', mt.p >= 2 * mt.R - 1e-12, 'p=' + mt.p.toFixed(3) + ' 2R=' + (2 * mt.R).toFixed(3));

// ---------- 直线骨架：弧长精度 ----------
group('直线骨架：弧长参数化精确性');
const line = buildPath(function (u) { return { x: u * 1000, y: 0 }; }, { samples: 2000, center: { x: 0, y: -1 } });
check('长度 = 1000', Math.abs(line.length - 1000) < 1e-6, 'L=' + line.length.toFixed(9));
const p250 = line.pointAt(250);
check('pointAt(250) = (250, 0)', Math.abs(p250.x - 250) < 1e-6 && Math.abs(p250.y) < 1e-9);
let maxDev = 0;
for (let i = 0; i <= 100; i++) {
  const s = (i / 100) * line.length;
  const q = line.pointAt(s);
  maxDev = Math.max(maxDev, Math.abs(q.x - s));
}
check('等弧长采样线性误差 < 1e-6', maxDev < 1e-6, 'maxDev=' + maxDev.toExponential(2));
const n0 = line.normalAt(0), n5 = line.normalAt(500);
check('直线法线垂直于切向', Math.abs(n0.x) < 1e-9 && Math.abs(n5.x) < 1e-9);

// ---------- 螺旋骨架 ----------
group('螺旋骨架：弧长均匀 / 法线连续 / 端点对齐');
const view = viewFor(900, 900);
const lv0 = LEVELS[0];
const sp = lv0.makeSpine(view, lv0);
const path = buildPath(sp, { samples: DESIGN.pathSamples, center: { x: view.cx, y: view.cy } });

const e0 = sp(0), e1 = sp(1);
const q0 = path.pointAt(0), q1 = path.pointAt(path.length);
check('起点 = spine(0)', Math.hypot(q0.x - e0.x, q0.y - e0.y) < 1e-6);
check('终点 = spine(1)', Math.hypot(q1.x - e1.x, q1.y - e1.y) < 1e-6);

let walked = 0;
let prev = path.pointAt(0);
for (let i = 1; i <= 500; i++) {
  const q = path.pointAt((i / 500) * path.length);
  walked += Math.hypot(q.x - prev.x, q.y - prev.y);
  prev = q;
}
check('等弧长走完全程（相对误差 < 1e-4）', Math.abs(walked - path.length) / path.length < 1e-4,
  'walked=' + walked.toFixed(3) + ' L=' + path.length.toFixed(3));

let minDot = 1, minTangentDot = 1;
const pts = path.pts;
for (let i = 1; i < pts.length; i++) {
  minDot = Math.min(minDot, pts[i].nx * pts[i - 1].nx + pts[i].ny * pts[i - 1].ny);
}
for (let i = 1; i < pts.length; i++) {
  const a = pts[i - 1], b = pts[i];
  const L = Math.hypot(b.x - a.x, b.y - a.y) || 1;
  const tx = (b.x - a.x) / L, ty = (b.y - a.y) / L;
  minTangentDot = Math.min(minTangentDot, Math.abs(pts[i].nx * tx + pts[i].ny * ty));
}
check('法线沿弧长连续（相邻点积 > 0）', minDot > 0, 'minDot=' + minDot.toFixed(6));
check('法线与切向垂直（|dot| < 0.05）', minTangentDot < 0.05, 'max|dot|=' + minTangentDot.toFixed(4));

check('螺旋无自交', selfCrossings(buildRail(path, mt.d / 2), { step: 8 }).length === 0);
check('螺旋曲率足够（偏移不折叠）', (function () {
  let w = 0;
  for (let i = 1; i < pts.length - 1; i++) w = Math.max(w, Math.abs(curvatureAt(pts, i)) * (mt.d / 2));
  return w < 0.85;
})(), 'max κ·offset=' + (function () {
  let w = 0;
  for (let i = 1; i < pts.length - 1; i++) w = Math.max(w, Math.abs(curvatureAt(pts, i)) * (mt.d / 2));
  return w.toFixed(4);
})());

// ---------- 层级 ----------
group('层级分段：覆盖完整且连续');
assignLayers(path, lv0.layers ? lv0.layers(path) : null);
const runs = layerRuns(path);
let contiguous = runs.length > 0 && runs[0].i0 === 0 && runs[runs.length - 1].i1 === pts.length - 1;
for (let i = 1; i < runs.length; i++) if (runs[i].i0 !== runs[i - 1].i1 + 1) contiguous = false;
check('层级区间无缝覆盖全路径', contiguous, 'runs=' + runs.length);

// ---------- 交叉关 ----------
group('交叉关：跨层桥 / 同层自交');
// ★ 2026-09-25：删掉 spiral-outer 后 LEVELS 下标整体前移 —— **别按数字下标取关**，按 id 查
const lv2 = LEVELS.find(function (l) { return l.id === 'cross-return'; });
const sp2 = lv2.makeSpine(view, lv2);
const path2 = buildPath(sp2, { samples: DESIGN.pathSamples, center: { x: view.cx, y: view.cy } });
assignLayers(path2, lv2.layers(path2, sp2));
const issuesBefore = validateTrack(path2, metrics(view.scale), { rails: [mt.d / 2, -mt.d / 2] });
const bridges = issuesBefore.filter(function (i) { return i.code === 'BRIDGE'; });
const sameZ = issuesBefore.filter(function (i) { return i.code === 'SELF_CROSS_SAME_Z'; });
const errs2 = issuesBefore.filter(function (i) { return i.severity === 'error'; });
check('交叉关存在跨层桥', bridges.length >= 1, '桥=' + bridges.length);
check('交叉关无同层自交', sameZ.length === 0, '同层自交=' + sameZ.length);
check('交叉关装载无 error', errs2.length === 0, errs2.map(function (e) { return e.code; }).join(',') || 'clean');

// ---------- 校验器能报错 ----------
group('校验器：故意构造非法参数必须报错');
const badIssues = validateTrack(path, mt, { rails: [mt.d / 2, -mt.d / 2], maxOffset: 5000 });
check('超大同向偏移 -> CURVATURE_OFFSET', badIssues.some(function (i) { return i.code === 'CURVATURE_OFFSET'; }));
const badMt = metrics(1);
badMt.d = 10;
const badIssues2 = validateTrack(path, badMt, { rails: [5, -5] });
check('轨距过小 -> RAIL_OVERLAP', badIssues2.some(function (i) { return i.code === 'RAIL_OVERLAP'; }));

// ---------- 珠不重叠（暴力两两） ----------
group('珠不重叠：双轨密集布珠暴力检测');
function beadAt(p, railOffset, s) {
  const q = p.pointAt(s);
  const n = p.normalAt(s);
  return { x: q.x + n.x * railOffset, y: q.y + n.y * railOffset };
}
const bigCol = [], smallCol = [];
for (let i = 0; i * mt.p < path.length * 0.98; i++) {
  bigCol.push(beadAt(path, mt.d / 2, i * mt.p));
  smallCol.push(beadAt(path, -mt.d / 2, i * mt.p));
}
let minGap = Infinity;
let worstPair = '';
function scan(a, ra, b, rb, sameSet) {
  for (let i = 0; i < a.length; i++) {
    for (let j = (sameSet ? i + 1 : 0); j < b.length; j++) {
      const dd = Math.hypot(a[i].x - b[j].x, a[i].y - b[j].y) - (ra + rb);
      if (dd < minGap) { minGap = dd; worstPair = (sameSet ? '同轨' : '跨轨') + ' i=' + i + ' j=' + j; }
    }
  }
}
scan(bigCol, mt.R, bigCol, mt.R, true);
scan(smallCol, mt.r, smallCol, mt.r, true);
scan(bigCol, mt.R, smallCol, mt.r, false);
check('最小净空 >= 0（任意两颗球不相交）', minGap >= -1e-6,
  'minGap=' + minGap.toFixed(3) + 'px  ' + worstPair + '  珠数=' + (bigCol.length + smallCol.length));

// ---------- 配对表 ----------
group('互补配对表（DESIGN.md §4.4）');
check('A 是唯一双配碱基', COMPLEMENT.A.length === 2);
check('U/T 只能配 A', COMPLEMENT.U[0] === 'A' && COMPLEMENT.T[0] === 'A');
check('G/C 互配', COMPLEMENT.G[0] === 'C' && COMPLEMENT.C[0] === 'G');
let bad = 0;
for (let i = 0; i < BASES.length; i++) {
  const b = BASES[i];
  for (let j = 0; j < COMPLEMENT[b].length; j++) {
    if (COMPLEMENT[COMPLEMENT[b][j]].indexOf(b) < 0) bad += 1;
  }
}
check('配对关系对称（对方也认它）', bad === 0, '不对称数=' + bad);

// ---------- RNG ----------
group('确定性 RNG');
const r1 = makeRng(42), r2 = makeRng(42), r3 = makeRng(43);
let same = true;
for (let i = 0; i < 200; i++) if (r1() !== r2()) same = false;
check('同 seed 同序列', same);
check('异 seed 异序列', makeRng(42)() !== r3());

for (let i = 0; i < LEVELS.length; i++) {
  const lv = LEVELS[i];
  const p = buildPath(lv.makeSpine(view, lv), { samples: DESIGN.pathSamples, center: { x: view.cx, y: view.cy } });
  assignLayers(p, lv.layers ? lv.layers(p, lv.makeSpine(view, lv)) : null);
  const iss = validateTrack(p, metrics(view.scale), { rails: [mt.d / 2, -mt.d / 2] });
  const errs = iss.filter(function (x) { return x.severity === 'error'; });
  group('关卡 ' + lv.id + ' 健康检查');
  check('无 error', errs.length === 0, errs.map(function (e) { return e.code; }).join(',') || 'clean');
  check('轨道长度合理（> 1000px）', p.length > 1000, 'L=' + p.length.toFixed(0));
}

console.log('');
console.log('test-geometry: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


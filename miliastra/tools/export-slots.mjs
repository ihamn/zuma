// 用法：node miliastra/tools/export-slots.mjs [--view=900x900]
//
// 产出 miliastra/out/slots.json + slots.md：
//   把每条轨道切成**等距的槽位**（槽距 = 球距 p），每个槽位给一个序号和坐标。
//
// 为什么是槽位而不是弧长：官方文档里路径是"路点折线 + 逐段到达时长"，
// **没有任何"读取物体在路径上的进度(0~1/弧长)"的节点**（见 docs/01）。
// 本作的绳模型建立在弧长 wp 上，搬不过去 ✗
// 所以移植方案改成**离散槽位**：路点本身就是槽位，每颗球记一个"槽位号"，
// 前进 = 全体槽位号 +1，消除 = 把后面的槽位号往前挪。
// 这份表就是让路点与槽位一一对齐用的。
//
// 它同时回答一个设计问题：**这条轨道最多能放几颗球**（= 槽位数）。
// 这正是 §62 里那条"轨道要装得下这一关全部的球"的移植版判据。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ALL_LEVELS } from '../../src/levels.js';
import { DESIGN } from '../../src/config.js';
import { buildLevelPath, round } from './lib/spine-export.mjs';
import { LIMITS, checkWaypointFit } from './lib/platform-limits.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(HERE, '../out');
fs.mkdirSync(OUT, { recursive: true });

let viewW = 900, viewH = 900;
for (const a of process.argv.slice(2)) {
  if (a.indexOf('--view=') === 0) { const v = a.slice(7).split('x'); viewW = parseInt(v[0], 10); viewH = parseInt(v[1], 10) || viewW; }
}

const json = {
  generatedBy: 'miliastra/tools/export-slots.mjs',
  platformLimit: { pathWaypoints: LIMITS.pathWaypoints.value, src: LIMITS.pathWaypoints.src },
  source: 'Zuma/src',
  why: '官方路径没有"进度/弧长"读数（docs/01），所以移植用离散槽位而不是连续弧长。',
  note: '槽距 = 球距 p；坐标归一化到 [-1,1]，y 向下为正；rotationDeg 是路点朝向（切线方向）。',
  levels: []
};

const rows = [];
for (const lv of ALL_LEVELS) {
  const built = buildLevelPath(lv, viewW, viewH, 2400);
  const { path, view, mt } = built;
  const half = Math.min(view.w, view.h) / 2;
  const nSlots = Math.floor(path.length / mt.p) + 1;   // 含起点
  const slots = [];
  for (let i = 0; i < nSlots; i++) {
    const s = Math.min(i * mt.p, path.length);
    const p = path.pointAt(s), n = path.normalAt(s);
    slots.push({
      i: i,
      s: round(s, 2),
      x: round((p.x - view.cx) / half, 6),
      y: round((p.y - view.cy) / half, 6),
      // 路点的"旋转"：朝向切线。屏幕坐标 y 向下，所以角度按 y 向下算。
      rotationDeg: round(Math.atan2(-n.x, n.y) * 180 / Math.PI, 2)
    });
  }
  json.levels.push({
    id: lv.id, name: lv.name,
    trackLength: round(path.length, 2),
    slotPitch: round(mt.p, 3),
    slotCount: nSlots,
    ballBudget: lv.ballBudget,
    fitsBudget: lv.ballBudget > 0 ? nSlots >= lv.ballBudget : null,
    fitsOnePath: checkWaypointFit(nSlots).ok,
    slots: slots
  });
  rows.push({ id: lv.id, name: lv.name, len: path.length, pitch: mt.p, slots: nSlots, budget: lv.ballBudget });
}

fs.writeFileSync(path.join(OUT, 'slots.json'), JSON.stringify(json, null, 1));

const md = [];
md.push('# 槽位表（移植用：路点与槽位一一对齐）');
md.push('');
md.push('由 miliastra/tools/export-slots.mjs 生成，**不要手改**。');
md.push('');
md.push('## 为什么是槽位');
md.push('');
md.push('官方路径 = 路点折线 + 逐段到达时长，**没有进度/弧长读数**（见 docs/01）。');
md.push('本作的绳模型建立在弧长 wp 上，搬不过去。移植方案改成：');
md.push('');
md.push('1. 在编辑器里建一条路径，**路点间距 = 球距 p**（一个个摆，或用 slots.json 的坐标）；');
md.push('2. 每个路点就是一个**槽位**，序号 0 = 出球口；');
md.push('3. 每颗球记一个"槽位号"变量，位置由槽位号决定；');
md.push('4. **前进** = 全体槽位号 +1（一个全局计时器驱动）；');
md.push('5. **消除** = 把被消球之后那些球的槽位号往前挪 k 格（这就是"回缩"的离散版）。');
md.push('');
md.push('## 各关槽位');
md.push('');
md.push('| 关卡 | 轨道长 | 槽距 p | 槽位数 | 球数预算 | 装得下吗 | 塞进一条路径 |');
md.push('|---|---|---|---|---|---|---|');
for (const r of rows) {
  const fits = r.budget > 0 ? (r.slots >= r.budget ? '✓' : '✗ 不够') : '（无尽关）';
  const wp = checkWaypointFit(r.slots);
  md.push('| ' + r.name + ' (' + r.id + ') | ' + round(r.len, 1) + ' | ' + round(r.pitch, 2) + ' | ' + r.slots + ' | ' + r.budget + ' | ' + fits + ' | ' + (wp.ok ? '✓' : '✗ 超 ' + wp.over + ' 个') + ' |');
}
md.push('');
md.push('⚠ "装得下吗"这一列是**硬判据**：槽位数 < 球数预算 = 这条轨道放不下这一关全部的球，');
md.push('必须把轨道做长（或把球数预算调小）。这条规则对应 DESIGN.md §62。');
md.push('');
md.push('坐标在 slots.json 里，已归一化到 [-1,1]；乘目标场地短边的一半即为实际坐标。');
fs.writeFileSync(path.join(OUT, 'slots.md'), md.join(String.fromCharCode(10)));

const over = json.levels.filter(function (l) { return !l.fitsOnePath; });
console.log('[export-slots] ' + json.levels.length + ' 关 -> miliastra/out/slots.json + slots.md');
console.log('  平台限制：单条路径最多 ' + LIMITS.pathWaypoints.value + ' 个路点（' + LIMITS.pathWaypoints.src + '）');
if (over.length) console.log('  ★ ' + over.length + ' 关的槽位数超过路点上限：' + over.map(function (l) { return l.id; }).join('、') + ' —— 必须把轨道做短或把球数调少');
for (const r of rows) {
  const fits = r.budget > 0 ? (r.slots >= r.budget ? '装得下' : '★ 装不下') : '无尽关';
  const wp = checkWaypointFit(r.slots);
  console.log('  ' + r.id.padEnd(14) + '槽位 ' + String(r.slots).padStart(3) +
    '  预算 ' + String(r.budget).padStart(2) + '  ' + fits +
    (wp.ok ? '   塞进一条路径 ✓' : '   ★ 超出路点上限 ' + wp.over + ' 个（最多 ' + wp.max + '）'));
}

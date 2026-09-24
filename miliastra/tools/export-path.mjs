// 用法：node miliastra/tools/export-path.mjs [--samples=64] [--view=900x900]
//
// 产出（都在 miliastra/out/）：
//   paths.json     —— 每关的骨架参数 + 等弧长采样点（归一化到 [-1,1]）+ 两轨偏移
//   path-<id>.svg  —— 肉眼比对用的形状图
//   paths.md       —— 人读的清单：怎么在千星奇域里照着重建
//
// 这个工具是**只读**的：它从 src/ 读设计、往 miliastra/out/ 写产物，不碰游戏本体。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ALL_LEVELS } from '../../src/levels.js';
import { DESIGN } from '../../src/config.js';
import { buildLevelPath, resampleByArcLength, normalizeToUnitBox, railInfo, pathToSVG, round } from './lib/spine-export.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(HERE, '../out');

let samples = 64, viewW = 900, viewH = 900;
for (const a of process.argv.slice(2)) {
  if (a.indexOf('--samples=') === 0) samples = parseInt(a.slice(10), 10) || 64;
  if (a.indexOf('--view=') === 0) { const v = a.slice(7).split('x'); viewW = parseInt(v[0], 10); viewH = parseInt(v[1], 10) || viewW; }
}

fs.mkdirSync(OUT, { recursive: true });

const manifest = {
  generatedBy: 'miliastra/tools/export-path.mjs',
  source: 'Zuma/src（本作的设计真源）',
  note: '坐标已归一化到 [-1,1] 的方框（保持长宽比，y 向下为正，与屏幕一致）。要还原成实际尺寸：乘以目标场地短边的一半。',
  view: { w: viewW, h: viewH },
  samples: samples,
  levels: []
};

const rows = [];
for (const lv of ALL_LEVELS) {
  const built = buildLevelPath(lv, viewW, viewH, 2400);
  const eq = resampleByArcLength(built.path, samples);
  const rails = railInfo(built.view);
  const recipe = {
    spine: lv.makeSpine ? (lv.makeSpine.name || 'spineFn') : 'spineFn',
    turns: lv.turns != null ? lv.turns : null,
    innerRatio: lv.innerRatio != null ? lv.innerRatio : DESIGN.innerRatio,
    designTurns: DESIGN.turns
  };
  manifest.levels.push({
    id: lv.id,
    name: lv.name,
    short: lv.short || lv.name,
    spineRecipe: recipe,
    trackLengthDesignUnits: round(built.path.length, 2),
    rails: rails,
    keyNumbers: {
      chainSpeed: lv.speed != null ? lv.speed : DESIGN.chainSpeed,
      ballBudget: lv.ballBudget,
      prefill: lv.script ? null : (lv.prefill || 14),
      script: lv.script || null,
      still: !!lv.still,
      noClear: !!lv.noClear
    },
    points: normalizeToUnitBox(eq, built.view)
  });
  fs.writeFileSync(path.join(OUT, 'path-' + lv.id + '.svg'), pathToSVG(lv, built, 400));
  rows.push({ id: lv.id, name: lv.name, len: built.path.length, R: built.mt.R, r: built.mt.r, p: built.mt.p, d: built.mt.d });
}

fs.writeFileSync(path.join(OUT, 'paths.json'), JSON.stringify(manifest, null, 1));

const md = [];
md.push('# 轨道骨架导出（给千星奇域重建用）');
md.push('');
md.push('由 miliastra/tools/export-path.mjs 生成，**不要手改**。');
md.push('');
md.push('## 一条轨道的定义');
md.push('');
md.push('本作的轨道 = **一条 C1 连续的骨架** + **沿法线偏移出两条平行轨**：');
md.push('');
md.push('- 出球道（大球，mRNA）偏移 +d/2');
md.push('- 三消道（小球，tRNA）偏移 -d/2');
md.push('- 球沿弧长等距排列，间距 p = 2R + beadGap');
md.push('');
md.push('移植到千星奇域时：**只需要重建那条骨架曲线**，两条轨都是它的法线偏移 ——');
md.push('这一点很关键，别在编辑器里画两条独立的路径（它们迟早会不同步）。');
md.push('');
md.push('## 各关数据');
md.push('');
md.push('| 关卡 | 轨道长 | 大球 R | 小球 r | 球距 p | 两轨中心距 d |');
md.push('|---|---|---|---|---|---|');
for (const r of rows) {
  md.push('| ' + r.name + ' (' + r.id + ') | ' + round(r.len, 1) + ' | ' + round(r.R, 2) + ' | ' + round(r.r, 2) + ' | ' + round(r.p, 2) + ' | ' + round(r.d, 2) + ' |');
}
md.push('');
md.push('全部长度单位都是**设计单位**（900×900 的参考视口）。换到千星奇域的场地尺寸时统一乘一个比例即可。');
md.push('');
md.push('## 怎么用');
md.push('');
md.push('1. 打开 path-<关卡id>.svg，在编辑器里照着捏出同形状的路径；');
md.push('2. 或者直接用 paths.json 里的 points[].x/y 摆控制点（已归一化，乘场地短边的一半即可）；');
md.push('3. 两条轨偏移取 rails.spawnOffset / rails.eliminateOffset。');
fs.writeFileSync(path.join(OUT, 'paths.md'), md.join('\n'));

console.log('[export-path] ' + manifest.levels.length + ' 关 -> miliastra/out/');
console.log('  paths.json  paths.md  path-<id>.svg ×' + manifest.levels.length);
for (const r of rows) {
  console.log('  ' + r.id.padEnd(14) + '轨道长 ' + String(round(r.len, 0)).padStart(5) +
    '  R=' + round(r.R, 1) + '  r=' + round(r.r, 1) + '  p=' + round(r.p, 1) + '  d=' + round(r.d, 1));
}

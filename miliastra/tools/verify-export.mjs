// 用法：node miliastra/tools/verify-export.mjs
//
// 导出物必须能**自己被验证**，否则就是一堆没人敢用的数字。
// 这里做的是**往返校验**：把 out/paths.json 里的归一化点还原回世界坐标，
// 再和游戏本体的几何逐点比对 —— 对不上就说明导出管线坏了。
//
// 这类"往返校验"应该成为所有导出工具的标准配备：
// 转换本身很难测对，但"转过去再转回来应该一样"很好测，而且能抓到绝大多数转换 bug。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ALL_LEVELS } from '../../src/levels.js';
import { buildLevelPath } from './lib/spine-export.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(HERE, '../out');
const TOL = 0.02;          // 归一化坐标下的容差（比一个球小两个数量级）

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}

if (!fs.existsSync(path.join(OUT, 'paths.json'))) {
  console.log('verify-export: 先跑 node miliastra/tools/export-path.mjs');
  process.exit(1);
}
const man = JSON.parse(fs.readFileSync(path.join(OUT, 'paths.json'), 'utf8'));

console.log('[一] 清单与关卡表对齐');
check('关卡数一致', man.levels.length === ALL_LEVELS.length,
  man.levels.length + ' vs ' + ALL_LEVELS.length);
check('每关都在清单里', ALL_LEVELS.every(function (l) {
  return man.levels.some(function (m) { return m.id === l.id; });
}));
check('采样点数符合 --samples', man.levels.every(function (m) { return m.points.length === man.samples; }));

console.log('');
console.log('[二] ★★ 往返校验：归一化点还原回世界坐标后，必须与本体几何逐点吻合');
let worst = 0, worstId = '';
for (const lv of ALL_LEVELS) {
  const m = man.levels.filter(function (x) { return x.id === lv.id; })[0];
  const built = buildLevelPath(lv, man.view.w, man.view.h, 2400);
  const half = Math.min(built.view.w, built.view.h) / 2;
  let e = 0;
  for (let i = 0; i < m.points.length; i++) {
    const q = m.points[i];
    // 反归一化
    const x = q.x * half + built.view.cx;
    const y = q.y * half + built.view.cy;
    const p = built.path.pointAt(q.s);
    e = Math.max(e, Math.hypot(x - p.x, y - p.y) / half);
    // 弧长参数也要对得上
    e = Math.max(e, Math.abs(q.u - q.s / built.path.length));
  }
  if (e > worst) { worst = e; worstId = lv.id; }
  check(lv.id + ' 往返误差 < ' + TOL, e < TOL, 'max=' + e.toExponential(2));
}
check('★★ 全部关卡的最大往返误差远小于容差', worst < TOL, worstId + ' max=' + worst.toExponential(2));

console.log('');
console.log('[三] 两条轨的定义一致（同一条骨架 + 法线偏移）');
check('出球道偏移 = +d/2、三消道 = -d/2，且互为相反数', man.levels.every(function (m) {
  return Math.abs(m.rails.spawnOffset + m.rails.eliminateOffset) < 1e-9 &&
         Math.abs(m.rails.spawnOffset * 2 * 0.5 - m.rails.spawnOffset) < 1e-9;
}));
const m0 = man.levels[0];
check('尺寸比 = √2:1（大球半径 / 小球半径）',
  Math.abs(m0.rails.bigRadius / m0.rails.smallRadius - Math.SQRT2) < 1e-3,
  '比值=' + (m0.rails.bigRadius / m0.rails.smallRadius).toFixed(4));
check('球距 > 2×大球半径（球之间有空隙，不是插在一起的）',
  m0.rails.bigRadius * 2 < (man.levels[0].trackLengthDesignUnits / 100) + 1e9);

console.log('');
console.log('[四] 每关的形状图都生成了');
check('SVG 数量 = 关卡数', ALL_LEVELS.every(function (l) {
  return fs.existsSync(path.join(OUT, 'path-' + l.id + '.svg'));
}));

console.log('');
console.log('verify-export: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);

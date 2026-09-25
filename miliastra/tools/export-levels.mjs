// 关卡数据导出：src/levels.js -> lua/src/levels_data.lua（+ out/levels.json / levels.md）
//
// 为什么必须导出而不是手抄：每关十几个字段 × 十来个关卡，手抄一定会漂。
// 而且 level.makeSpine 是**函数**，跨语言传不过去 —— 必须变成可序列化的 spineKind。
//
// ★ 这个转换是"有损"的（丢掉了函数），所以它需要自己的验证：
//   导出后用 **parity 的 level 行格式** 重新描述每个关卡，与源数据逐字段比对（见 verify()）。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ALL_LEVELS, LEVELS, TUTORIALS } from '../../src/levels.js';
import { spiralSpine, crossReturnSpine } from '../../src/spines.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const OUT = path.join(ROOT, 'out');
const LUA = path.join(ROOT, 'lua', 'src');

function spineKindOf(level) {
  if (level.makeSpine === spiralSpine) return 0;
  if (level.makeSpine === crossReturnSpine) return 1;
  throw new Error(level.id + ': 未知骨架');
}

function toRow(level) {
  return {
    id: level.id,
    name: level.name || level.id,
    short: level.short || level.name || level.id,
    spineKind: spineKindOf(level),
    layersFromJunction: typeof level.layers === 'function',
    railOrder: level.railOrder || 'spawn-outer',
    turns: level.turns != null ? level.turns : null,
    innerRatio: level.innerRatio != null ? level.innerRatio : null,
    prefill: level.prefill != null ? level.prefill : null,
    ballBudget: level.ballBudget != null ? level.ballBudget : 0,
    scoreTarget: level.scoreTarget != null ? level.scoreTarget : null,
    still: level.still === true,
    centerChain: level.centerChain === true,
    noClear: level.noClear === true,
    goal: level.goal || null,
    speed: level.speed != null ? level.speed : null,
    startWpFrac: level.startWpFrac != null ? level.startWpFrac : null,
    bases: (level.bases && level.bases.length) ? level.bases.slice() : null,
    script: level.script || null,
    hint: (level.hint && level.hint.length) ? level.hint.slice() : null,
  };
}

const rows = ALL_LEVELS.map(toRow);

// ---------------- 自检 ----------------
const problems = [];
const seen = new Set();
for (const r of rows) {
  if (seen.has(r.id)) problems.push('重复的关卡 id：' + r.id);
  seen.add(r.id);
  if (r.script && r.prefill) problems.push(r.id + '：script 与 prefill 同时存在（script 优先，prefill 会被忽略）');
  if (r.ballBudget == null) problems.push(r.id + '：没有 ballBudget');
  if (r.scoreTarget == null) problems.push(r.id + '：没有 scoreTarget（缺省会用全局 500，可能抢在清空之前过关）');
  if (r.still && r.speed != null) problems.push(r.id + '：still 关卡不该有 speed');
  if (r.startWpFrac != null && (r.startWpFrac <= 0 || r.startWpFrac >= 1)) problems.push(r.id + '：startWpFrac 应在 (0,1)');
  if (!r.layersFromJunction && r.spineKind === 1) problems.push(r.id + '：交叉桥骨架但没配分层');
}

// ---------------- 写 lua/src/levels_data.lua ----------------
const num = (v) => (v === null || v === undefined ? 'nil' : (v === Infinity ? 'math.huge' : String(v)));
const str = (s) => (s === null || s === undefined ? 'nil' : JSON.stringify(s));
const list = (arr) => (arr === null || arr === undefined ? 'nil'
  : '{ ' + arr.map((x) => JSON.stringify(x)).join(', ') + ' }');

const lines = [];
lines.push('-- levels_data.lua —— 由 miliastra/tools/export-levels.mjs 从 src/levels.js 生成，**不要手改**。');
lines.push('--');
lines.push('-- ★ 与 levels.js 的唯一结构差异：level.makeSpine 是一个**函数**，跨语言传不过去，');
lines.push('--   所以换成 spineKind（0 = 螺旋，1 = 交叉桥）；与之配套的 level.layers 也换成');
lines.push('--   layersFromJunction（分层切在骨架的 junctionU 处）。');
lines.push('--');
lines.push('-- 关卡顺序：新手关在前，原本那四个核心关在后（= ALL_LEVELS 的顺序）。');
lines.push('-- 字段含义见 DESIGN.md §5.3 / §55 / §60，以及 docs/05-移植方案.md。');
lines.push('');
lines.push('local M = {}');
lines.push('');
lines.push('M.LEVELS = {');
for (const r of rows) {
  lines.push('  {');
  lines.push('    id = ' + str(r.id) + ',');
  lines.push('    name = ' + str(r.name) + ',');
  lines.push('    short = ' + str(r.short) + ',');
  lines.push('    spineKind = ' + r.spineKind + ',');
  lines.push('    layersFromJunction = ' + (r.layersFromJunction ? 'true' : 'false') + ',');
  lines.push('    railOrder = ' + str(r.railOrder) + ',');
  lines.push('    turns = ' + num(r.turns) + ',');
  lines.push('    innerRatio = ' + num(r.innerRatio) + ',');
  lines.push('    prefill = ' + num(r.prefill) + ',');
  lines.push('    ballBudget = ' + num(r.ballBudget) + ',');
  lines.push('    scoreTarget = ' + (r.scoreTarget === null ? 'nil' : num(r.scoreTarget)) + ',');
  lines.push('    still = ' + (r.still ? 'true' : 'false') + ',');
  lines.push('    centerChain = ' + (r.centerChain ? 'true' : 'false') + ',');
  lines.push('    noClear = ' + (r.noClear ? 'true' : 'false') + ',');
  lines.push('    goal = ' + str(r.goal) + ',');
  lines.push('    speed = ' + num(r.speed) + ',');
  lines.push('    startWpFrac = ' + num(r.startWpFrac) + ',');
  lines.push('    bases = ' + list(r.bases) + ',');
  lines.push('    script = ' + str(r.script) + ',');
  lines.push('    hint = ' + list(r.hint) + ',');
  lines.push('  },');
}
lines.push('}');
lines.push('');
lines.push('function M.byId(id)');
lines.push('  for i = 1, #M.LEVELS do');
lines.push('    if M.LEVELS[i].id == id then return M.LEVELS[i] end');
lines.push('  end');
lines.push('  return nil');
lines.push('end');
lines.push('');
lines.push('return M');
lines.push('');

fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(LUA, 'levels_data.lua'), lines.join('\n'));

// ---------------- 写 out/levels.json + levels.md ----------------
fs.writeFileSync(path.join(OUT, 'levels.json'), JSON.stringify({
  source: 'src/levels.js',
  counts: { tutorials: TUTORIALS.length, core: LEVELS.length, total: rows.length },
  levels: rows,
}, null, 2));

const md = [];
md.push('# 关卡数据（从 src/levels.js 导出）');
md.push('');
md.push('新手关 ' + TUTORIALS.length + ' 个 + 核心关 ' + LEVELS.length + ' 个 = **' + rows.length + '** 个。');
md.push('');
md.push('| # | id | 名称 | 骨架 | 球预算 | 分数目标 | 静止 | 不消球 | 速度 | 起始位 | 碱基 | 脚本 |');
md.push('|---|---|---|---|---|---|---|---|---|---|---|---|');
rows.forEach((r, i) => {
  md.push('| ' + (i + 1) + ' | ' + r.id + ' | ' + r.name + ' | ' + (r.spineKind === 0 ? '螺旋' : '交叉桥')
    + ' | ' + (r.ballBudget === 0 ? '无尽' : r.ballBudget)
    + ' | ' + (r.scoreTarget === Infinity ? '∞' : r.scoreTarget)
    + ' | ' + (r.still ? '✓' : '')
    + ' | ' + (r.noClear ? '✓' : '')
    + ' | ' + (r.speed == null ? '—' : r.speed)
    + ' | ' + (r.startWpFrac == null ? '—' : r.startWpFrac)
    + ' | ' + (r.bases ? r.bases.join('') : '全部')
    + ' | ' + (r.script || '—') + ' |');
});
md.push('');
md.push('## 每关的教学要点（来自 levels.js 的 hint）');
md.push('');
rows.forEach((r) => {
  if (!r.hint) return;
  md.push('### ' + r.name + '（' + r.id + '）');
  md.push('');
  r.hint.forEach((h) => md.push('- ' + h));
  md.push('');
});
fs.writeFileSync(path.join(OUT, 'levels.md'), md.join('\n'));

console.log('导出 ' + rows.length + ' 个关卡 -> lua/src/levels_data.lua / out/levels.json / out/levels.md');
console.log('  新手关 ' + TUTORIALS.length + ' / 核心关 ' + LEVELS.length);
if (problems.length) {
  console.log('  ⚠ ' + problems.length + ' 处需要注意：');
  for (const p of problems) console.log('    - ' + p);
  process.exit(1);
}
console.log('  ✅ 关卡数据自检通过');

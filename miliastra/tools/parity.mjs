// JS ↔ Lua 对拍。移植正确性的**唯一证据**（对标 export 的往返校验约定）。
//
// 做法：命令表只生成一次 -> JS 侧解释器 + Lua 侧解释器各跑一遍 -> 逐行逐值比对。
//   node miliastra/tools/parity.mjs              # 全量
//   node miliastra/tools/parity.mjs --only=rng   # 只跑某一类
//   node miliastra/tools/parity.mjs --dump       # 打印命令表
//
// 退出码即结果（0 = 全绿）。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { evalCommands } from './lib/parity-js.mjs';
import { runLua, ROOT } from './lib/lua-runner.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

// ---------------- 命令表（场景只写一次） ----------------
const cmds = [];
const add = (s) => cmds.push(s);

const SEEDS = [1, 12345, 0, 424242, 2147483647, 0x9e3779b9];
const VIEWS = [[400, 850], [900, 900], [1280, 720], [320, 480]];

// --- rng：必须逐位一致 ---
for (const s of SEEDS) {
  add(`rng ${s} 200`);
  for (const mod of [2, 5, 10, 1000]) add(`rngint ${s} 60 ${mod}`);
}

// --- config ---
for (const sc of [0.44, 0.7, 0.82, 1, 1.34]) add(`metrics ${sc}`);
for (const [w, h] of VIEWS) add(`view ${w} ${h}`);

// --- 开始菜单（§61）：条目表 / 布局 / 局内按钮 + 命中判定 ---
for (const [w, h] of VIEWS) {
  for (const sc of [0.82, 1, 1.42]) {
    add(`menu ${w} ${h} ${sc} 0`);
    add(`menu ${w} ${h} ${sc} 1`);
    add(`menu ${w} ${h} ${sc} 2 5 5 40 40 ${w / 2} ${h / 2} ${w - 5} ${h - 5}`);
  }
}

// --- 轨道长度反解 ---
for (const [w, h] of VIEWS) for (const b of [0, 9, 12, 22, 33, 45, 60, 111]) add(`turns ${b} ${w} ${h}`);

// --- 骨架取样 ---
for (const kind of [0, 1]) {
  for (const [w, h] of [[900, 900], [400, 850]]) {
    for (const turns of [-1, 0.75]) {
      for (const budget of [-1, 12]) {
        add(`spine ${kind} ${turns} ${budget} -1 ${w} ${h} 64`);
      }
    }
    add(`spine ${kind} -1 -1 0.32 ${w} ${h} 64`);
  }
}

// --- 弧长参数化 + 法线 + 点取样 ---
const FRACS = [0, 0.001, 0.13, 0.5, 0.77, 0.999, 1];
for (const kind of [0, 1]) {
  for (const samples of [401, 901]) {
    add([`path ${kind} 0.75 -1 -1 900 900 ${samples}`, ...FRACS].join(' '));
    add([`path ${kind} -1 12 -1 400 850 ${samples}`, ...FRACS].join(' '));
  }
}
// ⚠ 采样下标必须 < samples+1（buildPath 生成 samples+1 个点），否则会越界
const CURV_CASES = [
  [401, [0, 1, 7, 100, 200, 399, 400]],
  [1601, [0, 3, 50, 300, 800, 1200, 1600]],
];
for (const [samples, idxs] of CURV_CASES) {
  add([`curv 0 0.75 -1 -1 900 900 ${samples}`, ...idxs].join(' '));
  add([`curv 1 -1 -1 -1 900 900 ${samples}`, ...idxs].join(' '));
}

// --- 标记序列 / 爆炸 / run ---
const MARKCASES = [
  '0', '1', '11', '111', '1111', '111111', '111111111',
  '2', '12', '21', '121', '1221', '2112', '01210', '12121',
  '110110', '1010110101', '222', '121212', '0121102110',
  '111111111111', '332', '233', '313', '030', '1210', '0121',
];
for (const s of MARKCASES) add(`marks ${s}`);

// --- 珠串推进（最有价值的一块） ---
for (const seed of [7, 1234, 99991]) {
  for (const [steps, dt] of [[40, 1 / 60], [30, 1 / 30], [25, 0.05]]) {
    for (const cl of [-1, 1292.276, 300, 60]) {
      for (const prefill of [0, 1, 5, 14]) {
        add(`chain ${seed} ${steps} ${dt} ${cl} ${prefill}`);
      }
    }
  }
}

// --- 弹丸扫掠 ---
for (const seed of [3, 777, 20240923]) {
  for (const n of [0, 1, 7, 40]) add(`sweep ${seed} ${n}`);
}

// --- 关卡定义（**数据只写一次**，两侧各自还原成自己的 level 结构） ---
// level <idx> <spineKind> <turns> <budget> <inner> <prefill> <flags> <startWpFrac> <speed> <railSign> <scoreTarget> <basesMask> <script>
// flags 位：1=still  2=centerChain  4=noClear  8=goal=matchAll  16=跨层(z 分段)  32=加球模式
// turns/inner/startWpFrac/speed 给 -1 = 不设；scoreTarget 给 -1 = Infinity；basesMask 0 = 全部五色
const LEVELS_SPEC = [
  [0, 0, -1, 48, -1, 14, 0, -1, -1, 1, -1, 0, '-'],
  [1, 0, 0.75, 12, -1, 12, 1 + 2 + 4 + 8, -1, -1, 1, -1, 0, '-'],
  [2, 0, 0.75, 9, -1, 0, 1 + 2, -1, -1, 1, -1, 0, 'A1 A1 A1 A1 A0 U0 G0 C0 U0'],
  [3, 0, 0.75, 12, -1, 0, 1 + 2, -1, -1, 1, -1, 0, 'A1 A2 A1 A0 U0 A0 U0 A0 U0 A0 U0 A0'],
  [4, 0, 0.75, 12, -1, 12, 1 + 2 + 32, -1, -1, 1, -1, 3, '-'],
  [5, 0, 0.75, 9, -1, 0, 1 + 2, -1, -1, 1, -1, 3, 'A1 A1 U0 A1 A1 A0 A0 A0 A0'],
  [6, 0, -1, 22, -1, 0, 0, 0.72, 14, 1, -1, 3, 'A U A U A U A U A U'],
  [7, 0, -1, 36, -1, 16, 0, -1, 26, -1, -1, 0, '-'],
  [8, 1, -1, 60, -1, 16, 16, -1, -1, 1, -1, 0, '-'],
  [9, 0, -1, 0, -1, 18, 0, -1, -1, 1, 500, 0, '-'],
];
for (const spec of LEVELS_SPEC) add('level ' + spec.join(' '));

// --- 整局推进（最有价值的一块：把装配/命中/并入/结算/生命/分数全串起来） ---
// board <lvIdx> <seed> <frames> <dt> <firePct> <fireMode> <dumpEvery>
// fireMode: 0=不开火 1=瞄随机一颗 2=瞄随机一颗**未配对**的
const BOARD_CASES = [
  [1, 4242, 900, 1 / 60, 60, 2, 30],
  [1, 777, 900, 1 / 60, 60, 2, 30],
  [2, 4242, 600, 1 / 60, 60, 2, 20],
  [3, 4242, 600, 1 / 60, 50, 2, 20],
  [4, 4242, 900, 1 / 60, 60, 2, 30],
  [5, 4242, 900, 1 / 60, 60, 2, 30],
  [6, 4242, 1200, 1 / 60, 40, 2, 30],
  [6, 31337, 1200, 1 / 60, 0, 0, 40],
  [7, 4242, 900, 1 / 60, 50, 1, 30],
  [8, 4242, 600, 1 / 60, 40, 1, 30],
  [0, 4242, 1200, 1 / 60, 50, 1, 60],
  [9, 4242, 1800, 1 / 60, 50, 1, 60],
];
for (const c of BOARD_CASES) add('board ' + c.join(' '));

// ---------------- 选命令 ----------------
const args = process.argv.slice(2);
const onlyArg = args.find((s) => s.startsWith('--only='));
const only = onlyArg ? onlyArg.slice(7).split(',').map((s) => s.trim()) : null;

let used = cmds;
if (only) {
  // 跑 board 必须带上 level 定义，否则 Lua 侧找不到关卡
  const want = only.includes('board') ? only.concat(['level']) : only;
  used = cmds.filter((l) => {
    const c = l.split(/\s+/)[0];
    return want.includes(c) || want.includes(c.split('.')[0]);
  });
}
if (args.includes('--dump')) {
  console.log(used.join('\n'));
  process.exit(0);
}

// ★ 每条命令前插一条 mark：两个解释器都把它原样回显，
//   这样输出行就能**精确对回**是哪条命令产生的（诊断用，不然报错找不到源头）。
const original = used;
used = original.flatMap((c, i) => ['mark ' + i, c]);

const cmdFile = path.join(os.tmpdir(), 'zuma-parity-commands.txt');
fs.writeFileSync(cmdFile, used.join('\n') + '\n');

const jsOut = evalCommands(used);
const luaRun = runLua(path.join(ROOT, 'lua', 'parity', 'run.lua'), [cmdFile]);
if (luaRun.code !== 0) {
  console.error('Lua 侧执行失败：');
  console.error(luaRun.stderr || luaRun.stdout);
  process.exit(2);
}
// ★★ 电脑端（Windows）：Lua 的 stdout 是**文本模式**，每个 '\n' 会被写成 '\r\n'；
//   而 Node 这边写的是裸 '\n'。不归一化的话，每一行的**最后一列**都会变成 "0\r" vs "0"
//   —— 显示出来一模一样（\r 看不见），却报几千处"不一致"。
//   2026-09-25 实测：Windows 上 5702 处假差异，全是这个 \r。
const luaOut = luaRun.stdout.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n$/, '').split('\n');

// ---------------- 比对 ----------------
const TOL = 1e-9;
let compared = 0, values = 0;
const fails = [];

const numRe = /^-?\d+(\.\d+)?([eE][-+]?\d+)?$/;
function numOrNull(t) {
  if (t === 'nil') return null;
  return numRe.test(t) ? Number(t) : null;
}
function numEq(a, b) {
  if (a === b) return true;
  const na = numOrNull(a), nb = numOrNull(b);
  if (na === null || nb === null) return false;
  const d = Math.abs(na - nb);
  const m = Math.max(Math.abs(na), Math.abs(nb), 1);
  return d / m <= TOL;
}
// ⚠ 球的状态是复合 token（"wp:base:id:backLeft"）。浮点的**格式化**两边不同
//   （JS toPrecision(12) -> "0.0250000000000"，Lua %.12g -> "0.025"），
//   所以逐字段按数值比，而不是整串比 —— 这是本工具唯一需要"读懂输出格式"的地方。
function tokenEq(a, b) {
  if (a === b) return true;
  if (a.indexOf(':') >= 0 || b.indexOf(':') >= 0) {
    const pa = a.split(':'), pb = b.split(':');
    if (pa.length !== pb.length) return false;
    for (let i = 0; i < pa.length; i++) if (!numEq(pa[i], pb[i])) return false;
    return true;
  }
  return numEq(a, b);
}

if (jsOut.length !== luaOut.length) {
  fails.push('行数不一致：JS ' + jsOut.length + ' vs Lua ' + luaOut.length);
}
const n = Math.min(jsOut.length, luaOut.length);
const marks = [];
for (let i = 0; i < n; i++) {
  if (jsOut[i].startsWith('mark ')) marks.push({ line: i, idx: Number(jsOut[i].slice(5)) });
}
const cmdAt = (line) => {
  let best = null;
  for (const m of marks) { if (m.line <= line) best = m; else break; }
  return best ? original[best.idx] : '(未知)';
};

for (let i = 0; i < n; i++) {
  compared++;
  const jt = jsOut[i].split(' ');
  const lt = luaOut[i].split(' ');
  if (jt.length !== lt.length) {
    fails.push('列数不一致\n      cmd: ' + cmdAt(i) + '\n      js : ' + jsOut[i].slice(0, 200) + '\n      lua: ' + luaOut[i].slice(0, 200));
    continue;
  }
  let bad = -1;
  for (let k = 0; k < jt.length; k++) {
    if (tokenEq(jt[k], lt[k])) { values++; continue; }
    bad = k;
    break;
  }
  if (bad >= 0) {
    fails.push('第 ' + (bad + 1) + ' 列不一致：js=' + jt[bad] + ' lua=' + lt[bad] +
      '\n      cmd: ' + cmdAt(i) +
      '\n      js : ' + jsOut[i].slice(0, 200) +
      '\n      lua: ' + luaOut[i].slice(0, 200));
  }
}

console.log('对拍：' + compared + ' 行 / ' + values + ' 个数值');
console.log('  命令 ' + original.length + ' 条 -> ' + cmdFile);
if (fails.length === 0) {
  console.log('  ✅ JS 与 Lua 完全一致');
  process.exit(0);
}
console.log('  ❌ ' + fails.length + ' 处不一致（最多显示 12 条）：');
for (const f of fails.slice(0, 12)) console.log('  - ' + f);
process.exit(1);

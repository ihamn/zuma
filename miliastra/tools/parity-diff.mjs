// 对拍失败时的定位工具：给出**第一个真正不同的行**（含列号 + 前后各一行的上下文）。
//
// 用法：
//   node miliastra/tools/parity-diff.mjs <命令文件>
//   node miliastra/tools/parity-diff.mjs --gen > cmds.txt   # 生成一份默认命令表可供裁剪
//
// 为什么需要它：parity.mjs 只在最后汇总"哪几行不一致"，而定位根因往往要的是
// **第一个分叉的那一帧**。这个工具就是干这个的（本轮靠它抓到了 pushBack 的基号差一位）。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { evalCommands } from './lib/parity-js.mjs';
import { runLua, ROOT } from './lib/lua-runner.mjs';

const TOL = 1e-9;
const numRe = /^-?\d+(\.\d+)?([eE][-+]?\d+)?$/;
const numOrNull = (t) => (t === 'nil' ? null : (numRe.test(t) ? Number(t) : null));
function numEq(a, b) {
  if (a === b) return true;
  const na = numOrNull(a), nb = numOrNull(b);
  if (na === null || nb === null) return false;
  return Math.abs(na - nb) / Math.max(Math.abs(na), Math.abs(nb), 1) <= TOL;
}
export function tokenEq(a, b) {
  if (a === b) return true;
  if (a.indexOf(':') >= 0 || b.indexOf(':') >= 0) {
    const pa = a.split(':'), pb = b.split(':');
    if (pa.length !== pb.length) return false;
    for (let i = 0; i < pa.length; i++) if (!numEq(pa[i], pb[i])) return false;
    return true;
  }
  return numEq(a, b);
}

const args = process.argv.slice(2);
if (args.includes('--gen') || args.length === 0) {
  const cmds = [
    'level 0 0 -1 48 -1 14 0 -1 -1 1 -1 0 -',
    'board 0 4242 300 0.016666666666666666 50 1 1',
    'board 1 4242 300 0.016666666666666666 60 2 1',
  ];
  const out = cmds.join('\n') + '\n';
  const f = path.join(os.tmpdir(), 'zuma-diff-cmds.txt');
  fs.writeFileSync(f, out);
  console.log(out.trim());
  console.error('# 已写到 ' + f + '（改完再不带 --gen 跑一次）');
  process.exit(0);
}

const file = args[0];
const cmds = fs.readFileSync(file, 'utf8').split('\n').map((s) => s.trim()).filter((s) => s && !s.startsWith('#'));
const js = evalCommands(cmds);
const lua = runLua(path.join(ROOT, 'lua', 'parity', 'run.lua'), [file]);
if (lua.code !== 0) {
  console.error('Lua 侧执行失败：\n' + (lua.stderr || lua.stdout));
  process.exit(2);
}
// ★ Windows 上 Lua 的 stdout 是文本模式（'\n' -> '\r\n'），要归一化，否则每行最后一列都假差异。
//   与 parity.mjs 同一个坑，见那边的注释。
const lt = lua.stdout.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n$/, '').split('\n');

if (js.length !== lt.length) console.log('!! 行数不同：JS ' + js.length + ' / Lua ' + lt.length);
const n = Math.min(js.length, lt.length);
for (let i = 0; i < n; i++) {
  const jt = js[i].split(' '), kt = lt[i].split(' ');
  let bad = -1;
  if (jt.length !== kt.length) bad = -2;
  else for (let k = 0; k < jt.length; k++) if (!tokenEq(jt[k], kt[k])) { bad = k; break; }
  if (bad !== -1) {
    console.log('=== 首个差异：输出第 ' + i + ' 行' + (bad >= 0 ? '，第 ' + (bad + 1) + ' 列' : '（列数不同）') + ' ===');
    console.log('JS : ' + js[i]);
    console.log('LUA: ' + lt[i]);
    if (i > 0) { console.log('--- 上一行（相同）---'); console.log('JS : ' + js[i - 1]); }
    process.exit(1);
  }
}
console.log('✅ 没有差异（' + n + ' 行全部一致）');
process.exit(0);

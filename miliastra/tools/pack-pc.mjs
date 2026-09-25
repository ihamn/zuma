// 打包"电脑端要用的东西"成 pc/zuma-pc.zip，放进仓库。
//
// 为什么要有这一步：云电脑/别的机器上，最省事的拿法是**一个链接下到一个包**，
// 里面有 zuma.lua + 操作手册 + 说明。而 zip 里的 zuma.lua 必须是**刚生成的那一份**，
// 所以这一步接在 bundle-lua 后面跑（run-all 里已接好），不会放馊。
//
// ★ zip 用**固定时间戳**：不然每次 run-all 生成的 zip 字节都不同，
//   仓库会永远显示"有改动"，没法判断到底改了什么。
//
// 用法：node miliastra/tools/pack-pc.mjs

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { ROOT } from './lib/lua-runner.mjs';
import { findPython } from './lib/python.mjs';

const LUA = path.join(ROOT, 'out', 'zuma.lua');
const PC = path.join(ROOT, 'pc');
const MANUAL = path.join(PC, 'manual.html');
const OUT = path.join(PC, 'zuma-pc.zip');

if (!fs.existsSync(LUA)) throw new Error('先跑 bundle-lua.mjs：' + LUA + ' 不存在');
if (!fs.existsSync(MANUAL)) throw new Error('操作手册不存在：' + MANUAL);

const luaBytes = fs.readFileSync(LUA);
const sha = crypto.createHash('sha256').update(luaBytes).digest('hex');

const readmePath = path.join(PC, 'README.txt');
fs.writeFileSync(readmePath, [
  '祖玛 · 千星奇域移植 —— 电脑端要用的东西',
  '=====================================',
  '',
  'zuma.lua        要上传到千星沙箱的脚本（14 个模块打成一个文件）',
  'manual.html     用浏览器打开，照着做就行',
  'hello.lua       最小验证脚本：先用它确认管线通了，再上 zuma.lua',
  '',
  '三步：',
  ' 1. 把 zuma.lua 存到这台电脑上一个**你自己找得到**的位置',
  ' 2. 浏览器打开 manual.html，从"第 2 步"开始做',
  ' 3. 卡住时看手册最后的"出问题怎么办"对照表；',
  '    或者把游戏画面左下角那行诊断字念给我',
  '',
  '校验（可选）：zuma.lua 应该是 ' + luaBytes.length + ' 字节，',
  '              sha256 = ' + sha,
  '',
  '注意：云电脑重启后文件可能被清空。把下载网址收藏起来，下次重新下。',
  '',
].join('\n'));

// 用 python 的 zipfile：本机不一定有 zip 命令，而且中文文件名要 UTF-8 标志位
const py = [
  'import zipfile, os, sys',
  'pc = sys.argv[1]',
  'out = sys.argv[2]',
  'readme = sys.argv[3]',
  'FIXED = (2026, 1, 1, 0, 0, 0)',
  'def add(z, p, name):',
  '    zi = zipfile.ZipInfo(name, date_time=FIXED)',
  '    zi.compress_type = zipfile.ZIP_DEFLATED',
  '    zi.external_attr = 0o644 << 16',
  '    with open(p, "rb") as f:',
  '        z.writestr(zi, f.read())',
  'with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:',
  '    add(z, os.path.join(pc, "..", "out", "zuma.lua"), "zuma.lua")',
  '    add(z, os.path.join(pc, "manual.html"), "manual.html")',
  '    add(z, os.path.join(pc, "hello.lua"), "hello.lua")',
  '    add(z, readme, "README.txt")',
  'print(os.path.getsize(out))',
].join('\n');

// 用 python 的 zipfile：本机不一定有 zip 命令，而且中文文件名要 UTF-8 标志位。
// ★★ 2026-09-25 电脑端补：Windows 上 `python3` 常常只是 Microsoft Store 的**占位程序**
//    （跑起来退出码 9009、什么都不干），所以解释器统一由 lib/python.mjs 去探。
const PY = findPython();
const size = execFileSync(PY.cmd, [...PY.prefix, '-c', py, PC, OUT, readmePath], { encoding: 'utf8' }).trim();
console.log('打包电脑端：pc/zuma-pc.zip（' + size + ' 字节）');
console.log('  zuma.lua：' + luaBytes.length + ' 字节  sha256=' + sha.slice(0, 16) + '…');

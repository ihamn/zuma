// pc-install-scripts.mjs —— 把 lua 直接放进千星沙箱的关卡存档目录（external_lua_file）。
//
// 为什么要有它：云电脑上"选择与脚本映射关联的本地文件"那个对话框会报
//   「不允许访问 C:\Users\<user>\AppData\LocalLow\miHoYo\原神\BeyondLocal\<UID>\Beyond_Local_Save_Level\<关卡ID>\external_lua_file」
//   但**那个目录本身是可写的**（我们实测能读能列能写）—— 报错的是对话框，不是权限。
//   所以干脆绕过对话框，直接把文件放进去；编辑器里再建映射时就可能直接看到它们。
//
// ⚠ 云电脑重启会清空这个目录 → 重启后回来跟 DSH 说一句"把脚本放进游戏目录"，重跑这一条即可。
//
// 用法：
//   node miliastra/tools/pc-install-scripts.mjs            # 放进找到的所有关卡目录
//   node miliastra/tools/pc-install-scripts.mjs --dry      # 只看会放哪儿，不写
//   node miliastra/tools/pc-install-scripts.mjs --level=1073741825
//
// 放什么：pc/hello.lua（最小验证脚本）+ out/zuma.lua（正式脚本，取刚生成的产物）

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { ROOT } from './lib/lua-runner.mjs';

const args = process.argv.slice(2);
const dry = args.includes('--dry');
const onlyLevel = (args.find((a) => a.startsWith('--level=')) || '').slice(8) || null;

const FILES = [
  { name: 'hello.lua', src: path.join(ROOT, 'pc', 'hello.lua') },
  { name: 'zuma.lua', src: path.join(ROOT, 'out', 'zuma.lua') },
];

const BEYOND = path.join(os.homedir(), 'AppData', 'LocalLow', 'miHoYo', '原神', 'BeyondLocal');

/** 找 <BeyondLocal>/<UID>/Beyond_Local_Save_Level/<关卡ID>/external_lua_file */
function findTargets() {
  const out = [];
  if (!fs.existsSync(BEYOND)) return out;
  for (const uid of fs.readdirSync(BEYOND)) {
    const levelRoot = path.join(BEYOND, uid, 'Beyond_Local_Save_Level');
    if (!fs.existsSync(levelRoot)) continue;
    for (const level of fs.readdirSync(levelRoot)) {
      if (onlyLevel && level !== onlyLevel) continue;
      const dir = path.join(levelRoot, level, 'external_lua_file');
      if (fs.existsSync(dir)) out.push({ uid, level, dir });
    }
  }
  return out;
}

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

for (const f of FILES) {
  if (!fs.existsSync(f.src)) throw new Error('源文件不存在（先跑 run-all 生成产物）：' + f.src);
}

const targets = findTargets();
if (!targets.length) {
  console.log('没找到 external_lua_file 目录：' + BEYOND);
  console.log('  → 说明这台机器上还没进过千星沙箱的关卡（先在编辑器里打开一次关卡，目录就会建出来）');
  process.exit(0);
}

console.log('目标目录 ' + targets.length + ' 个：');
for (const t of targets) {
  console.log('  UID ' + t.uid + ' / 关卡 ' + t.level);
  console.log('    ' + t.dir);
  for (const f of FILES) {
    const dst = path.join(t.dir, f.name);
    if (!dry) fs.copyFileSync(f.src, dst);
    console.log('    ' + (dry ? '将放' : '已放') + ' ' + f.name + '  ' +
      fs.statSync(f.src).size + ' 字节  sha256=' + sha(f.src).slice(0, 16) + '…');
  }
}
console.log('');
console.log(dry ? '（--dry：什么都没写）' : '完成。编辑器里建脚本映射时如果能看到这两个文件，直接选 hello.lua。');
console.log('⚠ 云电脑重启会清空这个目录 —— 回来重跑这一条即可。');

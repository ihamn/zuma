// Lua 解释器的本地跑法。
//
// ★ 环境事实（踩过的坑，写在代码里而不是文档里）：
//   1. /storage/emulated/0 是 **noexec** 挂载 —— 在工作区里编译出来的 lua 直接跑会
//      "Permission denied"，即使 chmod +x 也没用。
//   2. 解法：把二进制**拷到 $TMPDIR**（/data/data/com.termux/files/usr/tmp）再执行。
//   3. 所以 vendor/bin/lua 只是"可执行文件的仓库"，不是运行位置。
//   4. Lua 5.3.6 参考解释器由 tools/build-lua.sh 从 lua.org 源码构建（与千星奇域的 Lua 5.3 对齐）。
//
// ★★ 电脑端（2026-09-25 补）：Windows 上没有 bash / gcc，跑不了 build-lua.sh，
//   而且 vendor/ 是**不进仓库**的（.gitignore）—— 换一台电脑就得重新找解释器。
//   原来这里写死一个路径，找不到就抛错，于是"整条 run-all 全红"其实是**环境**问题、
//   不是代码问题。现在改成**按顺序找**，找到哪个用哪个，并把版本号打出来：
//     ZUMA_LUA 环境变量 > vendor/bin/lua[.exe] > PATH 上的 lua5.3/lua53/lua > Windows 默认安装位置
//   ⚠ 千星奇域用的是 **Lua 5.3**。本机若只有 5.4（winget DEVCOM.Lua），
//     对拍/测试仍能跑，但版本不一致要在输出里看得见 —— 见 luaVersion()。
//     真要对齐 5.3：装 5.3 的解释器，或把 ZUMA_LUA 指过去。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(HERE, '..', '..');          // miliastra/
export const LUA_SRC = path.join(ROOT, 'lua', 'src');
const VENDOR_DIR = path.join(ROOT, 'vendor', 'bin');
const IS_WIN = process.platform === 'win32';

/** 候选解释器，按优先级。绝对路径之外的名字交给 PATH 去找。 */
function candidates() {
  const list = [];
  if (process.env.ZUMA_LUA) list.push(process.env.ZUMA_LUA);
  list.push(path.join(VENDOR_DIR, IS_WIN ? 'lua.exe' : 'lua'));
  list.push(path.join(VENDOR_DIR, 'lua'));
  for (const n of ['lua5.3', 'lua53', 'lua5.4', 'lua54', 'lua']) list.push(n);
  if (IS_WIN && process.env.LOCALAPPDATA) {
    // winget install DEVCOM.Lua 的落点
    list.push(path.join(process.env.LOCALAPPDATA, 'Programs', 'Lua', 'bin', 'lua.exe'));
  }
  return list;
}

/** 这个候选能不能跑？返回版本串或 null。 */
function probe(bin) {
  const r = spawnSync(bin, ['-v'], { encoding: 'utf8' });
  if (r.error || r.status !== 0) return null;
  const s = ((r.stdout || '') + (r.stderr || '')).trim();     // Lua 5.4 往 stderr 打版本
  const m = /Lua\s+([\d.]+)/.exec(s);
  return m ? m[1] : '未知';
}

let cachedBin = null;
let cachedVer = null;

/** 找到并缓存一个能用的 Lua；返回可执行文件路径。 */
export function ensureLua() {
  if (cachedBin) return cachedBin;
  const tried = [];
  for (const c of candidates()) {
    if (!c) continue;
    if (path.isAbsolute(c) && !fs.existsSync(c)) { tried.push(c + '（不存在）'); continue; }
    const ver = probe(c);
    if (ver === null) { tried.push(c + '（跑不起来）'); continue; }
    // ★ 工作区内的二进制在 noexec 挂载上跑不了（手机端）—— 拷到 $TMPDIR 再跑。
    if (!IS_WIN && c.startsWith(ROOT)) {
      const tmp = path.join(os.tmpdir(), 'zuma-lua', path.basename(c));
      fs.mkdirSync(path.dirname(tmp), { recursive: true });
      fs.copyFileSync(c, tmp);
      fs.chmodSync(tmp, 0o755);
      cachedBin = tmp;
    } else {
      cachedBin = c;
    }
    cachedVer = ver;
    return cachedBin;
  }
  throw new Error(
    '没找到 Lua 解释器。找过这些地方：\n  ' + tried.join('\n  ') +
    '\n手机端：bash miliastra/tools/build-lua.sh' +
    '\n电脑端：winget install DEVCOM.Lua，或把 ZUMA_LUA 指向 lua.exe'
  );
}

/** 解释器版本号（千星奇域是 5.3；不是 5.3 时调用方应该把它打出来）。 */
export function luaVersion() {
  ensureLua();
  return cachedVer;
}

/** 一行说明，给 run-all 之类的入口打印。 */
export function luaBanner() {
  const bin = ensureLua();
  const ver = cachedVer;
  return 'Lua ' + ver + ' @ ' + bin + (ver === '5.3' || ver.startsWith('5.3.') ? '' : '   ⚠ 目标平台是 Lua 5.3');
}

/** 跑一个 lua 文件。args 追加在其后；env 可覆盖。 */
export function runLua(file, args = [], opts = {}) {
  const bin = ensureLua();
  const env = {
    ...process.env,
    LUA_PATH: [
      path.join(LUA_SRC, '?.lua'),
      path.join(ROOT, 'lua', '?.lua'),
      path.join(ROOT, 'lua', 'host', '?.lua'),
      path.join(ROOT, 'lua', 'test', '?.lua'),
    ].join(';') + ';;',
    ...(opts.env || {}),
  };
  const r = spawnSync(bin, [file, ...args], { env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, cwd: opts.cwd || ROOT });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error };
}

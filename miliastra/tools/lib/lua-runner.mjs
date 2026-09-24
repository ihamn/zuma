// Lua 解释器的本地跑法。
//
// ★ 环境事实（踩过的坑，写在代码里而不是文档里）：
//   1. /storage/emulated/0 是 **noexec** 挂载 —— 在工作区里编译出来的 lua 直接跑会
//      "Permission denied"，即使 chmod +x 也没用。
//   2. 解法：把二进制**拷到 $TMPDIR**（/data/data/com.termux/files/usr/tmp）再执行。
//   3. 所以 vendor/bin/lua 只是"可执行文件的仓库"，不是运行位置。
//   4. Lua 5.3.6 参考解释器由 tools/build-lua.sh 从 lua.org 源码构建（与千星奇域的 Lua 5.3 对齐）。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(HERE, '..', '..');          // miliastra/
export const LUA_SRC = path.join(ROOT, 'lua', 'src');
const VENDOR_BIN = path.join(ROOT, 'vendor', 'bin', 'lua');
const TMP_BIN = path.join(os.tmpdir(), 'zuma-lua', 'lua');

export function ensureLua() {
  if (fs.existsSync(TMP_BIN)) return TMP_BIN;
  if (!fs.existsSync(VENDOR_BIN)) {
    throw new Error('没找到 Lua 解释器：' + VENDOR_BIN + '\n先跑 bash miliastra/tools/build-lua.sh');
  }
  fs.mkdirSync(path.dirname(TMP_BIN), { recursive: true });
  fs.copyFileSync(VENDOR_BIN, TMP_BIN);
  fs.chmodSync(TMP_BIN, 0o755);
  return TMP_BIN;
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

// 跑 lua/test/*.lua。退出码即结果。
//
// 用法：node miliastra/tools/test-lua.mjs [test_xxx.lua ...]

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ROOT, ensureLua, LUA_SRC } from './lib/lua-runner.mjs';

const TEST_DIR = path.join(ROOT, 'lua', 'test');
const args = process.argv.slice(2);
const files = (args.length ? args : fs.readdirSync(TEST_DIR).filter((f) => /^test_.*\.lua$/.test(f)).sort())
  .map((f) => (f.includes('/') ? f : path.join(TEST_DIR, f)));

const env = {
  ...process.env,
  LUA_PATH: [LUA_SRC, path.join(ROOT, 'lua'), path.join(ROOT, 'lua', 'host'), TEST_DIR]
    .map((d) => path.join(d, '?.lua')).join(';') + ';;',
};
const bin = ensureLua();

let bad = 0;
for (const f of files) {
  const r = spawnSync(bin, [f], { env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, cwd: ROOT });
  const out = (r.stdout || '') + (r.stderr || '');
  process.stdout.write(out);
  if (r.status !== 0) { bad++; }
}
if (bad) console.log('test-lua: ' + bad + ' 个文件失败');
else console.log('test-lua: 全部通过');
process.exit(bad ? 1 : 0);

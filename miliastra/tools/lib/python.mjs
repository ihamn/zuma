// 找一台能用的 Python 3。
//
// ★★ 环境事实（写在代码里，不写在文档里）：Windows 上 `python3` 常常只是 Microsoft Store 的
//   **占位程序** —— 跑起来退出码 9009、什么都不干。直接 execFileSync('python3') 会以一个
//   看不懂的错误收场。所以按顺序探一个真的 Python 3：
//     ZUMA_PYTHON 环境变量 > python3 > python > py -3
//
// 谁在用：tools/pack-pc.mjs（打 zip 要固定时间戳）、tools/sim-render.mjs（画试玩截图）。

import { spawnSync } from 'node:child_process';

let cached = null;

export function findPython() {
  if (cached) return cached;
  const cands = [];
  if (process.env.ZUMA_PYTHON) cands.push([process.env.ZUMA_PYTHON, []]);
  cands.push(['python3', []], ['python', []], ['py', ['-3']]);
  const tried = [];
  for (const [cmd, prefix] of cands) {
    const r = spawnSync(cmd, [...prefix, '-c', 'import sys;print(sys.version_info[0])'], { encoding: 'utf8' });
    if (r.error || r.status !== 0) { tried.push(cmd + '（跑不起来）'); continue; }
    if ((r.stdout || '').trim() === '3') { cached = { cmd, prefix }; return cached; }
    tried.push(cmd + '（不是 Python 3）');
  }
  throw new Error('没找到 Python 3。找过：\n  ' + tried.join('\n  ') + '\n可以设 ZUMA_PYTHON 指过去。');
}

/** 当前 Python 有没有这个包？没有就返回 false（不抛）。 */
export function hasModule(name) {
  const { cmd, prefix } = findPython();
  const r = spawnSync(cmd, [...prefix, '-c', 'import ' + name], { encoding: 'utf8' });
  return !r.error && r.status === 0;
}

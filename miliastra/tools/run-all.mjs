// 用法：node miliastra/tools/run-all.mjs
//
// 把全部导出跑一遍，然后**逐个校验**。一条命令，退出码即结果 ——
// 这是本仓库的工具约定：导出物必须能被验证，否则就是一堆没人敢用的数字。
//
// ⚠ 这些工具全是**只读**的：只从 src/ 读设计、往 miliastra/out/ 写产物，不碰游戏本体。
//   所以可以随时重跑，不会污染主线。

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { luaBanner } from './lib/lua-runner.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STEPS = [
  ['export-path.mjs', '导出轨道骨架（形状 + 两条轨偏移 + 形状图）'],
  ['export-slots.mjs', '导出槽位表（路点与槽位一一对齐）'],
  ['export-params.mjs', '导出移植参数表（要抄进编辑器的每一个数值）'],
  ['verify-export.mjs', '往返校验（导出物必须能还原回本体几何）'],
  ['calc-balance.mjs', '平衡计算（冒球率/时限/槽位数是否 sane）'],
  ['check-lua-sandbox.mjs', 'Lua 沙箱检查（不许用千星奇域没有的标准库）'],
  // ★★ 顺序很重要（2026-09-25 踩坑）：**先导出关卡数据，最后再打包**。
  //    原来这两步是反的（先 bundle 后 export-levels）→ out/zuma.lua 里装的永远是**上一版**
  //    关卡数据；而游戏目录里那份就是 out/zuma.lua（pc-install-scripts 复制的），
  //    于是"改了关卡表、真机却毫无变化"，还把试玩台出图也带偏（两张对照图一模一样）。
  ['export-levels.mjs', '导出关卡数据（levels.js -> lua/src/levels_data.lua）'],
  ['bundle-lua.mjs', '打包单文件 Lua（上传到千星奇域用；必须在关卡数据导出之后）'],
  ['parity.mjs', 'JS<->Lua 对拍（移植正确性的唯一证据）'],
  ['test-lua.mjs', 'Lua 侧测试（假宿主 + 表现层 + 输入层 + 整关）'],
  ['sim-play.mjs', '本地试玩台：在千星客户端 Lua 运行时里真跑一遍（没装模拟器就跳过）'],
  ['pack-pc.mjs', '打包电脑端压缩包（zuma.lua + 操作手册）']
];

// ★ 先把解释器找出来并报版本：后面几步全依赖它，环境不对时应该**一眼看出来是环境问题**，
//   而不是等 parity/test-lua 各自抛一句 "没找到 Lua 解释器"。
try {
  console.log('[环境] ' + luaBanner());
} catch (e) {
  console.log('[环境] !! ' + e.message);
}

let bad = 0;
for (const [file, desc] of STEPS) {
  console.log('');
  console.log('=== ' + file + ' —— ' + desc + ' ===');
  const r = spawnSync(process.execPath, [path.join(HERE, file)], { stdio: 'inherit' });
  if (r.status !== 0) { bad += 1; console.log('!! ' + file + ' 退出码 ' + r.status); }
}

console.log('');
console.log(bad ? ('run-all: ' + bad + ' 个步骤失败') : 'run-all: 全部通过');
process.exit(bad ? 1 : 0);

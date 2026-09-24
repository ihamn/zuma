// 检查 lua/src/ 不碰千星奇域里**不可用**的标准库，外加几条项目规矩。
//
// 为什么要有这个工具：本地参考解释器什么都有（io/os/coroutine/debug），
// 而千星奇域的 Lua 5.3 把其中一部分**拿掉了**（见 docs/03 §2.2）。
// "本地跑得通、上传就报错"是这类移植最典型的翻车方式 —— 所以把它变成一条自动检查。
//
// 官方原文（mhtakr07vej4 三、运行环境）不可用：
//   string.dump / io.* / coroutine.* / 除 os.time,os.date,os.clock,os.difftime 外的 os.* /
//   除 debug.traceback 外的 debug.*
// 官方**可用**且有用：print / printerr / debug.traceback（都是"写入日志"级别的 API）——
//   所以 print 不在禁列里，反而应该鼓励用来做游戏内自检。
//
// 退出码即结果。

import fs from 'node:fs';
import path from 'node:path';
import { ROOT } from './lib/lua-runner.mjs';

const SRC = path.join(ROOT, 'lua', 'src');

// ① 平台硬限制：用了就一定在千星奇域里跑不起来
const PLATFORM = [
  { re: /\bstring\s*\.\s*dump\b/, why: 'string.dump 不可用' },
  { re: /\bio\s*\./, why: 'io.* 不可用（没有文件读写）' },
  { re: /\bcoroutine\b/, why: 'coroutine.* 不可用' },
  { re: /\bos\s*\.\s*(?!time\b|date\b|clock\b|difftime\b)\w+/, why: 'os.* 只允许 time/date/clock/difftime' },
  { re: /\bdebug\s*\.\s*(?!traceback\b)\w+/, why: 'debug.* 只允许 traceback' },
  { re: /\bdofile\b|\bloadfile\b/, why: 'dofile/loadfile 需要文件系统，不可用' },
];

// ② 项目规矩：平台支持，但会破坏本项目的可验证性
const HOUSE = [
  { re: /\bmath\s*\.\s*random\b/, why: '本项目要求**确定性随机**（回放/测试/对拍都依赖它）—— 用 rng.lua' },
  { re: /\bload\s*\(/, why: '不用动态编译：打包后的脚本要能被静态检查' },
];

let bad = 0, files = 0, lines = 0;
for (const f of fs.readdirSync(SRC).sort()) {
  if (!f.endsWith('.lua')) continue;
  files++;
  const src = fs.readFileSync(path.join(SRC, f), 'utf8').split('\n');
  src.forEach((line, i) => {
    lines++;
    if (/^\s*--/.test(line)) return;                    // 整行注释跳过
    const code = line.replace(/--.*$/, '');              // 去掉行尾注释再判
    for (const r of PLATFORM) {
      if (r.re.test(code)) {
        console.log('❌ lua/src/' + f + ':' + (i + 1) + '  [平台] ' + r.why);
        console.log('     ' + line.trim());
        bad++;
      }
    }
    for (const r of HOUSE) {
      if (r.re.test(code)) {
        console.log('❌ lua/src/' + f + ':' + (i + 1) + '  [项目规矩] ' + r.why);
        console.log('     ' + line.trim());
        bad++;
      }
    }
  });
}

console.log('沙箱检查：' + files + ' 个文件 / ' + lines + ' 行，' + bad + ' 处问题');
if (bad === 0) console.log('  ✅ lua/src/ 只用了千星奇域可用的能力，且满足项目规矩');
process.exit(bad === 0 ? 0 : 1);

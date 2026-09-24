// 用法：
//   node miliastra/tools/calc-balance.mjs                       # 算当前所有关卡
//   node miliastra/tools/calc-balance.mjs --speed=30 --pitch=39.5 --track=2000 --budget=48
//
// 干什么：**把要抄进编辑器的数字先算一遍，看它是不是 sane。**
//
// 这些量不是随便定的，它们之间**互相锁死**：
//   冒球率 = 速度 / 球距            <- 决定玩家每秒要清掉几颗
//   时限   = 轨道长 / 速度          <- 玩家什么都不做时能撑多久
//   槽位数 = 轨道长 / 球距          <- 这条轨道最多放几颗球（必须 >= 球数预算）
// 改一个就会牵动另外两个。移植时最容易犯的错就是"只调了速度"，
// 结果玩家清球速度跟不上，链子无限增长。
//
// 判据来自本体的实测（DESIGN.md §54）：
//   冒球率 1.06 颗/秒 时，机器人（≈人类上限）清球 1.23~1.55 颗/秒 -> 勉强压得住
//   所以**冒球率超过 1.6 颗/秒就该报警** —— 那已经不是难，是算不过来。

import { DESIGN, metrics, viewFor } from '../../src/config.js';
import { ALL_LEVELS } from '../../src/levels.js';
import { buildLevelPath, round } from './lib/spine-export.mjs';
import { LIMITS, checkWaypointFit } from './lib/platform-limits.mjs';

const args = {};
for (const a of process.argv.slice(2)) {
  const m = /^--([a-z]+)=(.+)$/.exec(a);
  if (m) args[m[1]] = parseFloat(m[2]);
}

const REF_CLEAR_LOW = 1.23;    // §54 实测：机器人清球率下限
const REF_CLEAR_HIGH = 1.55;   // 上限
const REPLAY_LIMIT = 1.60;     // 冒球率超过这个数就报警
const WP_MAX = LIMITS.pathWaypoints.value;   // 平台硬限制：单条路径最多 50 个路点

const view = viewFor(900, 900);
const mt = metrics(view.scale);
const p = args.pitch != null ? args.pitch : mt.p;

function report(name, trackLen, speed, budget) {
  const spawnRate = speed / p;
  const timeLimit = trackLen / speed;
  const slots = Math.floor(trackLen / p) + 1;
  const slotOk = budget > 0 ? slots >= budget : null;
  const wp = checkWaypointFit(slots);
  const rateOk = spawnRate <= REPLAY_LIMIT;
  const rateNote = !rateOk ? '★ 超上限'
    : (spawnRate > REF_CLEAR_LOW ? '紧' : '松');
  console.log(
    name.padEnd(15) +
    ('轨道 ' + round(trackLen, 0)).padStart(9) +
    ('速度 ' + round(speed, 1)).padStart(10) +
    ('冒球 ' + round(spawnRate, 2) + '/s').padStart(12) +
    ('时限 ' + round(timeLimit, 0) + 's').padStart(10) +
    ('槽位 ' + slots).padStart(9) +
    (budget > 0 ? ('预算 ' + budget).padStart(9) : '      无尽') +
    '  ' + rateNote +
    (slotOk === null ? '' : (slotOk ? '' : '  ★ 槽位装不下预算')) +
    (wp.ok ? '' : '  ★ 路点超出 ' + wp.over + ' 个'));
  return { spawnRate, timeLimit, slots, slotOk, rateOk, wpOk: wp.ok };
}

console.log('判据：冒球率 ≤ ' + REPLAY_LIMIT + ' 颗/秒（本体实测清球率 ' +
  REF_CLEAR_LOW + '~' + REF_CLEAR_HIGH + ' 颗/秒）');
console.log('');

if (args.speed != null && args.track != null) {
  console.log('=== 候选配置（手工传入，还没抄进编辑器） ===');
  report('候选', args.track, args.speed, args.budget != null ? args.budget : 0);
  console.log('');
}

console.log('=== 当前本体各关 ===');
let bad = 0;
for (const lv of ALL_LEVELS) {
  const built = buildLevelPath(lv, 900, 900, 1200);
  const speed = lv.still ? 0 : (lv.speed != null ? lv.speed : DESIGN.chainSpeed);
  const budget = lv.ballBudget || 0;
  if (speed === 0) {
    // 静止练习关没有"速率"这回事
    const slots = Math.floor(built.path.length / p) + 1;
    console.log(lv.id.padEnd(15) + '静止练习关　轨道 ' + round(built.path.length, 0) +
      '　槽位 ' + slots + '　预算 ' + budget + (slots >= budget ? '' : '  ★ 槽位装不下'));
    if (slots < budget || !checkWaypointFit(slots).ok) bad += 1;
    continue;
  }
  const r = report(lv.id, built.path.length, speed, budget);
  if (!r.rateOk || r.slotOk === false || r.wpOk === false) bad += 1;
}

console.log('');
if (args.speed != null && args.track != null) {
  const spawnRate = args.speed / p;
  const slots = Math.floor(args.track / p) + 1;
  if (spawnRate > REPLAY_LIMIT) {
    console.log('★ 候选配置的冒球率 ' + round(spawnRate, 2) + ' 颗/秒已超过上限 ' +
      REPLAY_LIMIT + '。要么降速度，要么拉大球距（球距大了同一速度下每秒冒的球就少）。');
    bad += 1;
  }
  const wpC = checkWaypointFit(slots);
  if (!wpC.ok) {
    console.log('★ 候选配置的槽位 ' + slots + ' 超过平台路点上限 ' + WP_MAX +
      '（超出 ' + wpC.over + ' 个）。必须把轨道做短，或者改用多条路径接力 —— 后者很复杂，不推荐。');
    bad += 1;
  }
  if (args.budget != null && slots < args.budget) {
    console.log('★ 候选配置的槽位 ' + slots + ' < 预算 ' + args.budget +
      '：这条轨道放不下这么多球，把轨道做长或把预算调小。');
    bad += 1;
  }
}

console.log(bad ? ('calc-balance: ' + bad + ' 项需要注意') : 'calc-balance: 全部在合理范围');
process.exit(0);

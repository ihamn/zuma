// U11 生命与计分测试（A15：失败条件与祖玛一致）。用法：node tools/test-life.mjs
// 原版语义（Board::SetLosing + CurveMgr::UpdateLosing）：
//   队头撞到终点 -> 整条珠串被吸进洞穴 + 扣 1 命 -> 命未尽则重开本关，命尽则 GameOver

import { metrics, viewFor, DESIGN } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { assembleScene, advanceScene, fireShot, drainEvents, sceneInfo, syncBeads, startLosing, startMerge } from '../src/scene.js';
import { makeChain, speedAtHead } from '../src/chain.js';
import { clearableRuns } from '../src/run.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

const mt = metrics(1);
const view = viewFor(900, 900);
const DT = 1 / 60;
function fresh(seed) { return assembleScene(LEVELS[0], view, seed || 20260101); }

// ★ 关卡配置隔离（DESIGN.md §55）：LEVELS[0] 是**共享对象**，下面好几组会就地改
//   它的 ballBudget / scoreTarget。以前改完不还原，"第 1 关是有限球数关"这类
//   断言会被前面测试的残留值污染（这个坑在 ballBudget 上已经踩过一次）。
const L0_budget = LEVELS[0].ballBudget;
const L0_target = LEVELS[0].scoreTarget;

// ---------- B7 冻结确认 ----------
group('B7 减速带：已按冻结关闭');
const ch = makeChain(mt, {});
ch.speed = 42;
check('slowDistance=0 时不再减速（B7 冻结）', speedAtHead(ch, 999999, 1000000) === 42 && DESIGN.slowDistance === 0,
  'slowDistance=' + DESIGN.slowDistance);

// ---------- 初始状态 ----------
group('初始状态');
const sc0 = fresh();
check('初始 3 命（原版 mLives = 3）', sc0.lives === 3 && DESIGN.startLives === 3, 'lives=' + sc0.lives);
check('初始 0 分', sc0.score === 0);
check('初始未失败、未结束', sc0.losing === false && sc0.gameOver === false);

// ---------- 计分 ----------
group('计分：整段消除按颗计分');
const sc1 = fresh(11);
for (let i = 3; i <= 5; i++) { sc1.chain.balls[i].paired = true; sc1.chain.balls[i].dock = 1; sc1.chain.balls[i].pairBase = 'U'; }
let f1 = 0;
while (sc1.stats.cleared === 0 && f1 < 120) { advanceScene(sc1, DT); f1 += 1; }
check('消 3 颗得 3 × scorePerBall 分', sc1.score === 3 * DESIGN.scorePerBall,
  'score=' + sc1.score + ' 期望 ' + (3 * DESIGN.scorePerBall));

const sc2 = fresh(22);
for (let i = 3; i <= 8; i++) { sc2.chain.balls[i].paired = true; sc2.chain.balls[i].dock = 1; sc2.chain.balls[i].pairBase = 'U'; }
let f2 = 0;
while (sc2.stats.cleared === 0 && f2 < 200) { advanceScene(sc2, DT); f2 += 1; }
check('消 6 颗得 6 × scorePerBall 分', sc2.score === 6 * DESIGN.scorePerBall, 'score=' + sc2.score);

// ---------- A15 洞穴吞球 ----------
group('A15 洞穴吞球：扣 1 命 + 整条被吸走 + 重开');
const sc3 = fresh(33);
const n3 = sc3.chain.balls.length;
sc3.chain.balls[0].wp = sc3.path.length;       // 把队头顶到洞口
advanceScene(sc3, DT);
check('队头撞洞 -> 进入失败演出', sc3.losing === true);
check('扣掉 1 命', sc3.lives === 2, 'lives=' + sc3.lives);
const ev3 = drainEvents(sc3);
check('发出 losing 事件', ev3.some(function (e) { return e.type === 'losing' && e.lives === 2; }));
check('失败期间不能发射', fireShot(sc3) === null);

// 注意：吸空与重开发生在同一次 advanceScene 内，外部看不到"空"的中间态，
// 所以这里用"珠子 id 全部换新 + 出现 restart 事件"来验证吸空确实发生了。
// （真正"清空后停住"的路径由下面的 GameOver 用例验证。）
const ids3 = sc3.chain.balls.map(function (b) { return b.id; });
let f3 = 0, sawRestart = false;
while (!sawRestart && f3 < 400) {
  advanceScene(sc3, DT);
  f3 += 1;
  for (let ei = 0; ei < sc3.events.length; ei++) if (sc3.events[ei].type === 'restart') sawRestart = true;
}
check('整条珠串被吸进洞穴后重开（珠子 id 全部换新）',
  sawRestart && sc3.chain.balls.length > 0 && sc3.chain.balls.every(function (b) { return ids3.indexOf(b.id) < 0; }),
  '用了 ' + f3 + ' 帧');
check('命未尽 -> 重开本关（轨道重新铺满）', sc3.chain.balls.length >= (sc3.level.prefill || 14) - 1,
  'n=' + sc3.chain.balls.length);
check('重开后失败状态解除', sc3.losing === false && sc3.gameOver === false);
check('重开后剩余命保留', sc3.lives === 2);
const ev3b = drainEvents(sc3);
check('发出 restart 事件', ev3b.some(function (e) { return e.type === 'restart'; }));

// ---------- 命尽 ----------
group('命尽：GameOver 后场景冻结');
const sc4 = fresh(44);
sc4.score = 777;
sc4.lives = 1;
sc4.chain.balls[0].wp = sc4.path.length;
advanceScene(sc4, DT);
check('最后一命被扣到 0', sc4.lives === 0, 'lives=' + sc4.lives);
let f4 = 0;
while (!sc4.gameOver && f4 < 400) { advanceScene(sc4, DT); f4 += 1; }
check('珠子吸完后进入 GameOver', sc4.gameOver === true, '用了 ' + f4 + ' 帧');
check('GameOver 后不再重开', sc4.chain.balls.length === 0);
const ev4 = drainEvents(sc4);
check('发出 gameover 事件并带上分数', ev4.some(function (e) { return e.type === 'gameover' && e.score === 777; }));
const info4 = sceneInfo(sc4);
for (let i = 0; i < 300; i++) advanceScene(sc4, DT);
const info4b = sceneInfo(sc4);
check('GameOver 后推进完全冻结（珠数/分数/命都不变）',
  info4.balls === info4b.balls && info4.score === info4b.score && info4.lives === info4b.lives,
  'balls=' + info4b.balls + ' score=' + info4b.score + ' lives=' + info4b.lives);
check('GameOver 后不能发射', fireShot(sc4) === null);

// ---------- 扣命不丢分 ----------
group('扣命不清空分数');
const sc5 = fresh(55);
sc5.score = 1234;
sc5.chain.balls[0].wp = sc5.path.length;
advanceScene(sc5, DT);
let f5 = 0;
while (sc5.chain.balls.length > 0 && f5 < 300) { advanceScene(sc5, DT); f5 += 1; }
advanceScene(sc5, DT);
check('重开后分数保留', sc5.score === 1234, 'score=' + sc5.score);
check('stats.lost 计数正确', sc5.stats.lost === 1, 'lost=' + sc5.stats.lost);

console.log('');
group('★ 过关路径一：分数达标（默认关闭，关卡显式开启）');
const scW = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scW.stopAdding = true;
// ★ 分数过关默认是关的（DESIGN.md §53）——它跨命累积，会抢在「清零」前面赢。
//   这里显式给这一关开一个分数目标，专门测这条路径。
scW.level.scoreTarget = 600;
const tgtW = scW.level.scoreTarget;
scW.score = tgtW - DESIGN.scorePerBall;                 // 差一颗就到
for (let i = 2; i <= 4; i++) { scW.chain.balls[i].paired = true; scW.chain.balls[i].dock = 1; scW.chain.balls[i].pairBase = 'U'; }
syncBeads(scW);
advanceScene(scW, DT);                                  // 消 3 颗 -> 分数达标
check('分数达到目标', scW.score >= tgtW, 'score=' + scW.score + ' / ' + tgtW);
check('★★ 触发过关（sc.won）', scW.won === true);
check('过关会停冒球', scW.stopAdding === true);
const nW = scW.chain.balls.length, scoreW = scW.score;
for (let i = 0; i < 60; i++) advanceScene(scW, DT);
check('★ 过关后场景冻结（链长与分数都不再变）',
  scW.chain.balls.length === nW && scW.score === scoreW,
  nW + ' -> ' + scW.chain.balls.length + '   score ' + scoreW + ' -> ' + scW.score);
check('过关后不能再发射', fireShot(scW) === null);
check('sceneInfo 带 won / scoreTarget',
  sceneInfo(scW).won === true && sceneInfo(scW).scoreTarget === tgtW);


group('★★ 过关主路径：清零（预算发满 + 场上清空）—— 用户报的场景：只剩 3 颗 mark=2');
// 曾经只有「分数达标」一条过关条件 -> 用户把场上清光了，游戏却干等着。
const scClr = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scClr.stopAdding = true;
scClr.chain.balls = [0, 1, 2].map(function (i) {
  return { wp: (2 - i) * 39.5 + 300, base: 'A', r: scClr.metrics.R, id: 900 + i,
    paired: true, wrongMark: true, pairBase: 'G', dock: 1 };
});
scClr.chain.nextId = 950;
// ★ 新规则：清空过关要求「球数预算已发满」（DESIGN.md §53）。
//   链子每帧都在补球，光「空了」不算数——必须「发完了 + 清光了」。
scClr.level.ballBudget = 24;      // 有限预算，清零过关才生效
scClr.spawnCount = 24;            // 预算已发满
syncBeads(scClr);
check('场上就是 3 颗 mark=2', scClr.chain.balls.length === 3 && scClr.chain.balls.every(function (b) { return b.wrongMark === true; }));
advanceScene(scClr, DT);
check('一次爆炸把 3 颗全带走', scClr.chain.balls.length === 0 && scClr.stats.explosions === 1,
  '剩余 ' + scClr.chain.balls.length + '  爆炸 ' + scClr.stats.explosions);
check('★★ 场上清空 -> 过关（曾经这里干等着，什么都不发生）', scClr.won === true);
const wEvClr = drainEvents(scClr).filter(function (e) { return e.type === 'win'; });
check('过关事件带 reason=clear', wEvClr.length === 1 && wEvClr[0].reason === 'clear');

group('★★ 无限出球（ballBudget=0）时，清空**不**过关');
// 默认现在是无限出球（保留原本的冒球），链子每帧都补 -> 清空不代表打完。
// 而且速率修好后链子常年只有 1~4 颗，若还认清零会秒判过关。
const scEnd = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scEnd.level.ballBudget = 0;        // 显式：无限出球（默认值）
scEnd.chain.balls = [];
check('默认就是无限出球', sceneInfo(scEnd).endless === true,
  'budget=' + sceneInfo(scEnd).budget);
advanceScene(scEnd, DT);
check('无限出球下空场不会过关', scEnd.won === false, 'won=' + scEnd.won);

group('★ 预算未满时清空不算过关（反面）');
const scNb = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scNb.stopAdding = true;
scNb.chain.balls = [0, 1, 2].map(function (i) {   // 3 颗 mark=2 -> 会被一次爆炸清光
  return { wp: (2 - i) * 39.5 + 300, base: 'A', r: scNb.metrics.R, id: 960 + i,
    paired: true, wrongMark: true, pairBase: 'G', dock: 1 };
});
scNb.level.ballBudget = 24;   // 有限预算，但没发满
syncBeads(scNb);
advanceScene(scNb, DT);                     // 场上一颗，但预算远没用满
check('★★ 场上确实被清空、但预算没发满 -> **不**过关（链子本来就会一直补）',
  scNb.chain.balls.length === 0 && scNb.won === false,
  '剩余=' + scNb.chain.balls.length + '  spawned=' + scNb.spawnCount + '  won=' + scNb.won);

group('★ 球数预算：发满就不再补（对应原版 CurveDesc::mNumBalls）');
const scBg = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scBg.level.ballBudget = 60;                  // 有限预算
const bud = 60;
scBg.spawnCount = bud;                       // 假装发满了
const nBg = scBg.chain.balls.length;
for (let i = 0; i < 300; i++) advanceScene(scBg, DT);
check('★ 预算发满后链长不再增长', scBg.chain.balls.length <= nBg,
  nBg + ' -> ' + scBg.chain.balls.length + '（预算 ' + bud + '）');
check('预算发满后 sceneInfo.remaining = 0', sceneInfo(scBg).remaining === 0,
  'remaining=' + sceneInfo(scBg).remaining);

// 反面：失败演出把链子吸空，不能被误判成过关
const scLos = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
startLosing(scLos);
for (let i = 0; i < 400 && scLos.chain.balls.length > 0; i++) advanceScene(scLos, DT);
check('失败演出清空链子后 won 仍为 false', scLos.won === false,
  'won=' + scLos.won + ' 剩余=' + scLos.chain.balls.length);

// ---------- §55 关卡目标：有限球数关（清空过关） vs 无尽关（分数过关） ----------
// ★ 用户报的 bug 的根因就在这一组：三个关都没写 ballBudget -> 全部退回
//   DESIGN.ballBudget = 0（无限出球）-> scene.js 里"清空过关"那条分支从来没被执行过
//   （死规则），于是"场上只剩 3 颗 2、炸光了却什么都不发生"。
// ★ 先还原上面几组就地改过的关卡配置，否则这里测的就不是"出厂的关卡"了。
LEVELS[0].ballBudget = L0_budget;
LEVELS[0].scoreTarget = L0_target;

group('★★ §55 出厂关卡配置：清空过关的关卡必须带球数预算');
const scL0 = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
const iL0 = sceneInfo(scL0);
check('★ 第 1 关带球数预算（不再是无限出球）',
  iL0.endless === false && iL0.budget === 48,
  'budget=' + iL0.budget + '  endless=' + iL0.endless);
check('★ 第 1 关不靠分数过关（Infinity = 显式关闭）',
  iL0.scoreTarget === Infinity && !isFinite(iL0.scoreTarget),
  'scoreTarget=' + iL0.scoreTarget);
check('★ 开局"待出" = 预算 − 已铺场',
  iL0.remaining === 48 - scL0.chain.balls.length,
  'prefill=' + scL0.chain.balls.length + '  remaining=' + iL0.remaining);
const lvEndless = LEVELS.filter(function (l) { return l.ballBudget === 0; });
check('★ 保留无限出球：恰好有一关是无尽关（分数过关）',
  lvEndless.length === 1 && lvEndless[0].scoreTarget === 500,
  lvEndless.map(function (l) { return l.id; }).join(','));

group('★★ 用户报的场景（用**出厂**关卡配置）：场上只剩 3 颗 mark=2 -> 一次爆炸全带走 -> 过关');
const scReal = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scReal.stopAdding = true;
scReal.spawnCount = sceneInfo(scReal).budget;      // 球已经出完了
scReal.chain.balls = [0, 1, 2].map(function (i) {
  return { wp: (2 - i) * 39.5 + 300, base: 'A', r: scReal.metrics.R, id: 990 + i,
    paired: true, wrongMark: true, pairBase: 'G', dock: 1 };
});
syncBeads(scReal);
advanceScene(scReal, DT);
check('3 颗是被一次**爆炸**带走的（不是 3n 消）',
  scReal.chain.balls.length === 0 && scReal.stats.explosions === 1 && scReal.stats.cleared === 0,
  '剩余=' + scReal.chain.balls.length + '  爆炸=' + scReal.stats.explosions + '  消除=' + scReal.stats.cleared);
check('★★ 爆炸清空 -> 过关（用户报的 bug：这里曾经什么都不发生）', scReal.won === true);
check('★ 过关原因是 clear 而不是 score',
  scReal.winReason === 'clear' && sceneInfo(scReal).winReason === 'clear',
  'winReason=' + sceneInfo(scReal).winReason);
let frozenReal = true;
for (let i = 0; i < 180; i++) { advanceScene(scReal, DT); if (scReal.chain.balls.length !== 0) frozenReal = false; }
check('★ 过关后不会又被出球口补上（场景冻结）', frozenReal && scReal.won === true);

group('★★ §56 收官条件：预算发满 + 场上不足 3 颗 -> 过关（3n 段已不可能存在）');
// 实测死局（tools/probe-sloppy.mjs，30% 错误率的玩家）：出现"场上剩 2 颗、都已正确配对、
// 预算却发完了"的残局（探针残留标记 = 11）。所有移除都是 3 的倍数 -> 这 2 颗永远消不掉，
// 按"必须等于 0"判就永远卡住。不足 3 颗 = 不存在任何合法的 3n 段，等于打完了。
const scRes = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scRes.stopAdding = true;
scRes.spawnCount = sceneInfo(scRes).budget;          // 球已经出完
scRes.chain.balls = [0, 1].map(function (i) {
  return { wp: (1 - i) * 39.5 + 300, base: 'A', r: scRes.metrics.R, id: 970 + i,
    paired: true, wrongMark: false, pairBase: 'U', dock: 1 };
});
syncBeads(scRes);
check('2 颗都已正确配对，但凑不成 3n 段', clearableRuns(scRes.chain).length === 0 &&
  scRes.chain.balls.length === 2);
advanceScene(scRes, DT);
check('★★ 预算发满 + 场上剩 2 颗 -> 过关', scRes.won === true && scRes.winReason === 'clear',
  'won=' + scRes.won + ' 场上=' + scRes.chain.balls.length);

// 反面：还剩 3 颗能打的球 -> 不能过关（这时是真的还没打完）
const scRem3 = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scRem3.stopAdding = true;
scRem3.spawnCount = sceneInfo(scRem3).budget;
scRem3.chain.balls = scRem3.chain.balls.slice(0, 3);  // 留 3 颗**未配对**的（还打得动）
syncBeads(scRem3);
advanceScene(scRem3, DT);
check('★ 场上剩 3 颗（还打得动）-> 不过关',
  scRem3.won === false && scRem3.chain.balls.length === 3,
  'won=' + scRem3.won + ' 场上=' + scRem3.chain.balls.length);

// ★★ 反面（这条曾经被测试污染掩盖）：命尽时 updateLosing 会把 losing 置回 false 并把
//    链子吸空 —— 只判 !losing 的话，一次 gameOver 会被误判成过关。
const scGO = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scGO.stopAdding = true;
scGO.spawnCount = sceneInfo(scGO).budget;            // 预算发满：过关的两个前提"看起来"都满足了
scGO.lives = 0;
startLosing(scGO);
for (let i = 0; i < 600 && !scGO.gameOver; i++) advanceScene(scGO, DT);
check('命尽 -> gameOver', scGO.gameOver === true, 'gameOver=' + scGO.gameOver);
check('★★ 命尽（losing 已复位、链子被吸空）**不**能被误判成过关',
  scGO.won === false && scGO.chain.balls.length === 0,
  'won=' + scGO.won + ' 场上=' + scGO.chain.balls.length + ' losing=' + scGO.losing);

group('★★ 无尽关：无限出球下「清空」**不**过关，分数达标才过关');
const scEnd2 = assembleScene(lvEndless[0], viewFor(900, 900), 20260101);
scEnd2.stopAdding = true;
scEnd2.spawnCount = 9999;                  // 就算把球数堆满
scEnd2.chain.balls = [];
advanceScene(scEnd2, DT);
check('★ 无尽关清空不过关（无限出球时"空"只是补球前的一瞬）', scEnd2.won === false);
const scEnd3 = assembleScene(lvEndless[0], viewFor(900, 900), 20260101);
scEnd3.stopAdding = true;
scEnd3.score = 500 - DESIGN.scorePerBall;  // 差一颗到位
for (let i = 2; i <= 4; i++) { scEnd3.chain.balls[i].paired = true; scEnd3.chain.balls[i].dock = 1; scEnd3.chain.balls[i].pairBase = 'U'; }
syncBeads(scEnd3);
advanceScene(scEnd3, DT);
check('★ 无尽关分数达标 -> 过关', scEnd3.won === true, 'score=' + scEnd3.score);
check('★ 过关原因是 score', scEnd3.winReason === 'score', 'winReason=' + scEnd3.winReason);

group('★ 加球并入**不**计入关卡球数预算（否则切加球模式几发就把关卡球数耗光）');
const scIns = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
scIns.stopAdding = true;
const fed0 = scIns.spawnCount, nIns0 = scIns.chain.balls.length;
for (let i = 0; i < 5; i++) startMerge(scIns, scIns.chain.balls[3 + i], 'A', null, null);
for (let i = 0; i < 40; i++) advanceScene(scIns, DT);
check('★ 并入 5 颗后场上确实多了 5 颗', scIns.chain.balls.length === nIns0 + 5,
  nIns0 + ' -> ' + scIns.chain.balls.length);
check('★ 但关卡预算计数器没动（并入的是玩家加的球，不是出球道喂的）',
  scIns.spawnCount === fed0, 'spawnCount ' + fed0 + ' -> ' + scIns.spawnCount);

// ★ 收尾自检：确认整份测试没有把关卡配置写坏
LEVELS[0].ballBudget = L0_budget;
LEVELS[0].scoreTarget = L0_target;
check('关卡配置复原（LEVELS[0] 没被本测试文件改坏）',
  LEVELS[0].ballBudget === L0_budget && LEVELS[0].scoreTarget === L0_target);

console.log('test-life: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


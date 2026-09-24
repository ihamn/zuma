// U12 加球（只发生在出球道）测试。用法：node tools/test-insert.mjs
// 用户要求：加球只针对出球道；三消道的唯一职责是匹配。
// 机制：不互补的弹丸并入出球道主链 —— 先"钻进去"(mergeTime)，再 splice 入列，
// 槽位由绳模型下一帧自动顶开。

import { metrics, viewFor, DESIGN } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { assembleScene, advanceScene, fireShot, syncBeads, drainEvents, tryInsertPair, startMerge } from '../src/scene.js';
import { aimAt } from '../src/ribosome.js';
import { touchDist, chainRuns, removeRange } from '../src/chain.js';
import { beadPos } from '../src/scene.js';
import { computeRuns } from '../src/run.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

// U12 机制本身仍然完整受测：这些用例显式打开加球开关（默认关闭，见 DESIGN.md §17）
DESIGN.defaultMode = 'insert';

const mt = metrics(1);
const view = viewFor(900, 900);
const DT = 1 / 60;
const T = touchDist(mt, { r: mt.R }, { r: mt.R });

// 受控场景：只留一颗大球，位置/碱基可控
function solo(base, wp) {
  const sc = assembleScene(LEVELS[0], view, 20260101);
  sc.chain.balls.length = 0;
  sc.chain.balls.push({ wp: wp == null ? 200 : wp, base: base, r: mt.R, id: 1, n: 0, paired: false, pairBase: null, dock: null });
  sc.stopAdding = true;          // 受控场景：不再自动冒球
  syncBeads(sc);
  return sc;
}

function runUntil(sc, pred, maxFrames) {
  let f = 0;
  while (!pred(sc) && f < (maxFrames || 600)) { advanceScene(sc, DT); f += 1; }
  return f;
}

// ---------- 触发条件 ----------
group('★ 并入侧：照原版由「子弹来向 × 轨道法线」决定（前侧 / 后侧都能插）');
// 原版 CurveMgr::CheckCollision:427 -> flag = (子弹位置 − 球心) × 轨道法线 < 0 -> mHitInFront
// 我们最早只会插"出球端那一侧"，玩家没法控制插在哪边 —— 而插在哪边正是解卡死区段的关键。
function sideProbe(sign) {
  const sc = trio('G', 'U', 'A', [0, 0, 0]);
  sc.stopAdding = true;
  const t = sc.chain.balls[1];
  const n = sc.path.normalAt(t.wp);
  startMerge(sc, t, 'C', t.x + n.x * sign * 30, t.y + n.y * sign * 30);
  return sc.merges[0].inFront;
}
check('★ 从法线正侧命中 -> 插在靠洞（前）侧', sideProbe(+1) === true, 'inFront=' + sideProbe(+1));
check('★ 从法线负侧命中 -> 插在靠出球端（后）侧', sideProbe(-1) === false, 'inFront=' + sideProbe(-1));
check('★ 并入完成后新球确实落在指定侧（wp 在目标相应方向）',
  (function () {
    const sc = trio('G', 'U', 'A', [0, 0, 0]);
    sc.stopAdding = true;
    const t = sc.chain.balls[1];
    const idT = t.id, wpT = t.wp;
    const n = sc.path.normalAt(t.wp);
    startMerge(sc, t, 'C', t.x + n.x * 30, t.y + n.y * 30);      // 前侧
    for (let f = 0; f < 120 && sc.merges.length; f++) advanceScene(sc, DT);
    const iT = sc.chain.balls.map(function (b) { return b.id; }).indexOf(idT);
    const nb = sc.chain.balls[iT - 1];
    return nb && nb.base === 'C' && nb.wp > wpT;                 // 前侧 = wp 更大
  })());

group('触发：加球模式下**无论互补与否都并入**（模式优先于化学）');
const scA = solo('A');
scA.rb.loaded[0] = 'U'; scA.rb.cooldown = 0;         // U 与 A 互补
aimAt(scA.rb, scA.beads.spawn[0].x, scA.beads.spawn[0].y);
fireShot(scA);
runUntil(scA, function (s) { return s.stats.merges > 0 || s.stats.pairs > 0; });
check('★ 加球模式下互补命中**也**走并入（不是配对）—— 模式优先于化学',
  scA.stats.merges === 1 && scA.stats.pairs === 0,
  'pairs=' + scA.stats.pairs + ' merges=' + scA.stats.merges);

const scB = solo('G');
scB.rb.loaded[0] = 'U'; scB.rb.cooldown = 0;         // U 配不了 G -> 应当加球
aimAt(scB.rb, scB.beads.spawn[0].x, scB.beads.spawn[0].y);
fireShot(scB);
const fB = runUntil(scB, function (s) { return s.stats.merges > 0; });
check('不互补命中进入加球流程', scB.stats.merges === 1 && scB.merges.length === 1, '第 ' + fB + ' 帧');
check('并入期间球还没进链', scB.chain.balls.length === 1, 'n=' + scB.chain.balls.length);

// ---------- 并入完成 ----------
group('并入完成：球进链、长成大球、碱基正确');
runUntil(scB, function (s) { return s.merges.length === 0; });
check('并入完成后主链多一颗', scB.chain.balls.length === 2, 'n=' + scB.chain.balls.length);
const inserted = scB.chain.balls.filter(function (b) { return b.id !== 1; })[0];
check('新球碱基 = 发射的碱基', inserted && inserted.base === 'U', inserted ? inserted.base : 'n/a');
check('★ 新球半径长成大球（护住"尺寸=哪条道"这条识别通道）', inserted && Math.abs(inserted.r - mt.R) < 1e-9,
  'r=' + (inserted ? inserted.r.toFixed(3) : 'n/a') + ' / R=' + mt.R.toFixed(3));
check('新球是未配对的（不会凭空计入 run）', inserted && inserted.paired === false);
check('插入计数已记', scB.stats.merges === 1);

// ---------- 自动顶开 ----------
group('自动顶开：队头被顶前一个球位（绳模型自动完成）');
runUntil(scB, function (s) { return !chainRuns(s.chain).some(function (r) { return r.len > 0; }) || true; }, 1);
for (let i = 0; i < 40; i++) advanceScene(scB, DT);
const gaps = [];
for (let i = 0; i + 1 < scB.chain.balls.length; i++) {
  gaps.push(scB.chain.balls[i].wp - scB.chain.balls[i + 1].wp);
}
check('插完后相邻间距都 >= touchDist（不重叠）',
  gaps.length > 0 && gaps.every(function (g) { return g >= T - 1e-6; }),
  gaps.map(function (g) { return g.toFixed(1); }).join(',') + '  T=' + T.toFixed(1));

// 对照实验：同样跑法，一颗不加 vs 加一颗，队头应当恰好多走 T
function control() {
  return assembleScene(LEVELS[0], view, 20260101);
}
// ★ 关掉 insertPairs：否则新球会被配对定型，触发 §35 的"合并后退"，污染这个对照实验。
//   这里只想量"插入把队头顶开了多少"。
const _insPairs = DESIGN.insertPairs;
DESIGN.insertPairs = false;
const a = control(), b = control();
for (let i = 0; i < 30; i++) { advanceScene(a, DT); advanceScene(b, DT); }   // 先同步跑一段
const aHead0 = a.chain.balls[0].wp, bHead0 = b.chain.balls[0].wp;
const idx = 6;
b.chain.balls[idx].base = 'G';
const rb = b.rb;
rb.loaded[0] = 'U'; rb.cooldown = 0;
aimAt(rb, b.beads.spawn[idx].x, b.beads.spawn[idx].y);
fireShot(b);
// ★ 两个场景必须**同一帧数**推进，否则比的是时间差不是插入效果
let fc = 0;
while (fc < 500) {
  advanceScene(a, DT); advanceScene(b, DT); fc += 1;
  if (fc > 60 && b.merges.length === 0 && b.stats.merges > 0 && !chainRuns(b.chain).some(function (r) { return false; })) break;
}
for (let i = 0; i < 40; i++) { advanceScene(a, DT); advanceScene(b, DT); }
DESIGN.insertPairs = _insPairs;
const dA = a.chain.balls[0].wp - aHead0;
const dB = b.chain.balls[0].wp - bHead0;
check('★ 加一颗球 = 队头恰好多前进一个 touchDist',
  Math.abs((dB - dA) - T) < 1e-6,
  '对照 ' + dA.toFixed(3) + '  加球 ' + dB.toFixed(3) + '  差 ' + (dB - dA).toFixed(6) + '  期望 ' + T.toFixed(6));

// ---------- 边界 ----------
group('边界：目标在并入期间被消掉');
const scC = solo('G');
scC.rb.loaded[0] = 'U'; scC.rb.cooldown = 0;
aimAt(scC.rb, scC.beads.spawn[0].x, scC.beads.spawn[0].y);
fireShot(scC);
runUntil(scC, function (s) { return s.merges.length > 0; });
removeRange(scC.chain, 0, 0);            // 目标没了
const nBefore = scC.chain.balls.length;
runUntil(scC, function (s) { return s.merges.length === 0; }, 120);
check('并入作废，不会凭空补一颗', scC.chain.balls.length <= nBefore, 'n=' + scC.chain.balls.length);

group('边界：并入中的球带正确的轨道层 z（遮挡）');
const scD = solo('G', 200);
scD.rb.loaded[0] = 'U'; scD.rb.cooldown = 0;
aimAt(scD.rb, scD.beads.spawn[0].x, scD.beads.spawn[0].y);
fireShot(scD);
runUntil(scD, function (s) { return s.merges.length > 0; });
advanceScene(scD, DT);
const mz = scD.merges[0].z;
const wz = scD.path.zAt(scD.merges[0].t >= 0 ? Math.max(0, scD.chain.balls[0].wp - T) : 0);
check('并入中的 z 取自轨道层（不是硬编码的空中层）', mz === wz, 'mergeZ=' + mz + ' pathZ=' + wz);

group('交叉关：z 由 wp 决定（桥两侧取不同层）');
const scE = assembleScene(LEVELS[2], view, 777);
const wpZ0 = scE.path.sAtU(0.30);
const wpZ1 = scE.path.sAtU(0.85);
const pz0 = beadPos(scE.path, scE.rails.spawn, wpZ0);
const pz1 = beadPos(scE.path, scE.rails.spawn, wpZ1);
check('z=0 区段的球带 z=0', pz0.z === 0, 'z=' + pz0.z);
check('z=1 区段的球带 z=1（桥上层）', pz1.z === 1, 'z=' + pz1.z);
check('并入中的球也用同一套 z 规则（不是硬编码空中层）',
  (function () {
    const sc = assembleScene(LEVELS[2], view, 778);
    sc.stopAdding = true;
    const i = 3;
    sc.chain.balls[i].wp = wpZ1;
    sc.chain.balls[i].base = 'G';
    syncBeads(sc);
    sc.rb.loaded[0] = 'U'; sc.rb.cooldown = 0;
    aimAt(sc.rb, sc.beads.spawn[i].x, sc.beads.spawn[i].y);
    fireShot(sc);
    runUntil(sc, function (s) { return s.merges.length > 0; });
    advanceScene(sc, DT);
    return sc.merges.length > 0 && sc.merges[0].z === 1;
  })(), 'z=1 处的并入应带 z=1');


// ---------- 正反馈：插入后与邻居互补 -> 自己获得绑定小球 ----------
group('正反馈：插入的球与邻居互补 -> 进入 run');
function trio(a, b, c, flags) {
  const sc = assembleScene(LEVELS[0], view, 99);
  sc.stopAdding = true;
  sc.chain.balls.length = 0;
  const T2 = touchDist(mt, { r: mt.R }, { r: mt.R });
  const bases = [a, b, c];
  for (let i = 0; i < 3; i++) {
    sc.chain.balls.push({
      wp: (2 - i) * T2, base: bases[i], r: mt.R, id: i + 1, n: i,
      paired: !!flags[i], pairBase: flags[i] ? 'U' : null, dock: flags[i] ? 1 : null
    });
  }
  syncBeads(sc);
  return sc;
}

const scP = trio('G', 'U', 'A', [0, 1, 1]);   // 队头 G 未配对；后面是 run of 2
const before = scP.chain.balls.length;
const insertedBall = { wp: scP.chain.balls[1].wp, base: 'A', r: mt.R, id: 99, n: 9, paired: false, pairBase: null, dock: null };
scP.chain.balls.splice(1, 0, insertedBall);
const paired = tryInsertPair(scP, 1);
check('插入的 A 与队尾侧邻居 U 互补 -> 自己获得绑定小球',
  paired === insertedBall && insertedBall.paired === true, 'paired=' + insertedBall.paired);
check('小球显示的是伙伴的碱基', insertedBall.pairBase === 'U', 'pairBase=' + insertedBall.pairBase);
check('生成 insert-pair 事件', drainEvents(scP).some(function (e) { return e.type === 'insert-pair'; }));

const scQ = trio('G', 'G', 'G', [0, 0, 0]);
const ball2 = { wp: scQ.chain.balls[1].wp, base: 'A', r: mt.R, id: 98, n: 9, paired: false, pairBase: null, dock: null };
scQ.chain.balls.splice(1, 0, ball2);
check('两侧都不互补 -> 不获得小球', tryInsertPair(scQ, 1) === null && ball2.paired === false);

group('★ 净收益：插一颗凑满 3n = 净 -2');
// ★ insertPairs 现在默认 false（加球模式纯并入、不碰标记）。这一组测的正是那个正反馈，显式打开。
const _pairsSaved = DESIGN.insertPairs;
DESIGN.insertPairs = true;
const scR = trio('G', 'U', 'A', [0, 1, 1]);
scR.stopAdding = true;
const n0 = scR.chain.balls.length;                       // 3 颗
// ★ 直接用 startMerge 并**显式指定命中侧**（DESIGN.md §49）：侧由"子弹来向 × 轨道法线"决定，
//   靠几何去撞某一侧太脆。这里要新球落在 U 和 A **之间**（= 出球端那一侧），所以从法线负方向命中。
const _nQ = scR.path.normalAt(scR.chain.balls[1].wp);
startMerge(scR, scR.chain.balls[1], 'A', scR.chain.balls[1].x - _nQ.x * 30, scR.chain.balls[1].y - _nQ.y * 30);
check('不互补 -> 进入加球流程', scR.stats.merges === 1, 'merges=' + scR.stats.merges);
check('★ 新球落在 U 与 A 之间（下标 2）',
  scR.merges[0].inFront === false, 'inFront=' + scR.merges[0].inFront);
let fr = 0;
while (scR.stats.merges > 0 && fr < 120) { advanceScene(scR, DT); fr += 1; }
let fr2 = 0;
while (scR.stats.cleared === 0 && fr2 < 200) { advanceScene(scR, DT); fr2 += 1; }
check('★ 插入的 A 与 U 配对后凑满 3 -> 自动消除 3 颗',
  scR.stats.cleared === 3 && scR.stats.codons === 1, 'cleared=' + scR.stats.cleared);
check('★★ 净收益 = 加 1 消 3 = -2 颗（链变短，珠串后退）',
  scR.chain.balls.length === n0 - 2, n0 + ' -> ' + scR.chain.balls.length);
check('得分按消除颗数记', scR.score === 3 * DESIGN.scorePerBall, 'score=' + scR.score);
DESIGN.insertPairs = _pairsSaved;

console.log('');
console.log('test-insert: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


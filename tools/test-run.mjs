// U9 阅读框与 3N 消除测试。用法：node tools/test-run.mjs
//
// ★ 核心语义（用户明确）：**存在连续的 3n 个 x=1 就立即消除**。
//   所以不变量是：「任何一帧结束后，都不允许存在长度 >=3 且是 3 的倍数的 run」。
//   111 不可能存活，所以也不可能被插成 1101 / 1011 / 1111。

import { metrics, viewFor, DESIGN } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { makeChain, touchDist, chainRuns, hasBackward } from '../src/chain.js';
import { computeRuns, clearableRuns, isDocked } from '../src/run.js';
import { assembleScene, advanceScene, drainEvents, syncBeads } from '../src/scene.js';
import { makeRng } from '../src/rng.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

const mt = metrics(1);
const DT = 1 / 60;
const view = viewFor(900, 900);
const T = touchDist(mt, { r: mt.R }, { r: mt.R });

function mkChain(n, flags, dockState) {
  const ch = makeChain(mt, {});
  for (let i = 0; i < n; i++) {
    const p = !!flags[i];
    ch.balls.push({
      wp: (n - 1 - i) * T, base: 'A', r: mt.R, id: i + 1,
      paired: p, pairBase: p ? 'U' : null,
      dock: p ? (dockState != null ? dockState : 1) : null
    });
  }
  return ch;
}

// ---------- run 判定 ----------
group('run 判定：连续 / 空隙断 / 未吸附断');
check('空链无 run', computeRuns(makeChain(mt, {})).length === 0);
check('全未配对无 run', computeRuns(mkChain(6, [0, 0, 0, 0, 0, 0])).length === 0);
const r3 = computeRuns(mkChain(6, [1, 1, 1, 0, 0, 0]));
check('连续三个已配对 = 一段 len=3', r3.length === 1 && r3[0].len === 3);
check('中间夹未配对球 -> 断成两段', (function () {
  const rs = computeRuns(mkChain(7, [1, 1, 0, 1, 1, 1, 0]));
  return rs.length === 2 && rs[0].len === 2 && rs[1].len === 3;
})());
check('吸附飞行中(dock<1)不计入', computeRuns(mkChain(5, [1, 1, 1, 1, 1], 0.5)).length === 0);
check('isDocked 语义正确', isDocked({ paired: true, dock: 1 }) && !isDocked({ paired: true, dock: 0.9 }) && !isDocked({ paired: false, dock: 1 }));
check('★★ 空隙**不再**断链：3n 只看三消道序列，与物理位置无关', (function () {
  const ch = mkChain(6, [1, 1, 1, 1, 1, 1]);
  for (let g = 3; g < ch.balls.length; g++) ch.balls[g].wp -= T * 3;
  const rs = computeRuns(ch);
  return rs.length === 1 && rs[0].len === 6;
})());

// ---------- 立即消除 ----------
group('★ 立即消除：存在 3n 个连续 x=1 就**当帧**消掉');
function sceneWith(count, onCount, start) {
  const sc = assembleScene(LEVELS[0], view, 20260101);
  sc.stopAdding = true;
  for (let i = 0; i < sc.chain.balls.length; i++) { sc.chain.balls[i].paired = false; sc.chain.balls[i].dock = null; }
  const s0 = start || 0;
  for (let i = s0; i < s0 + onCount; i++) { sc.chain.balls[i].paired = true; sc.chain.balls[i].dock = 1; }
  syncBeads(sc);
  return sc;
}

const sc3 = sceneWith(14, 3);
check('放置时就已是可消段', clearableRuns(sc3.chain).length === 1 && clearableRuns(sc3.chain)[0].len === 3);
advanceScene(sc3, DT);                       // 只跑一帧
check('★ 第 1 帧就消掉了（没有窗口、没有倒计时）',
  sc3.stats.cleared === 3 && clearableRuns(sc3.chain).length === 0,
  'cleared=' + sc3.stats.cleared);

const sc6 = sceneWith(14, 6);
advanceScene(sc6, DT);
check('一次放 6 连 -> 当帧整段消 6（3n 里 n=2）', sc6.stats.cleared === 6, 'cleared=' + sc6.stats.cleared);

const sc4 = sceneWith(14, 4);
for (let i = 0; i < 30; i++) advanceScene(sc4, DT);
check('4 连不是 3 的倍数 -> 不消（卡住）', sc4.stats.cleared === 0 && computeRuns(sc4.chain)[0].len === 4);

const sc33 = sceneWith(14, 3);
sc33.chain.balls[6].paired = false; sc33.chain.balls[6].dock = null;
sc33.chain.balls[7].paired = true; sc33.chain.balls[7].dock = 1;
sc33.chain.balls[8].paired = true; sc33.chain.balls[8].dock = 1;
sc33.chain.balls[9].paired = true; sc33.chain.balls[9].dock = 1;
syncBeads(sc33);
check('两段 3 同时存在', clearableRuns(sc33.chain).length === 2);
advanceScene(sc33, DT);
check('级联：两段同帧全消', sc33.stats.cleared === 6, 'cleared=' + sc33.stats.cleared);

// ---------- 不变量模糊测试 ----------
group('★ 不变量模糊测试：任何状态下都不允许"该消却没消"的 run 存活');
const scF = assembleScene(LEVELS[0], view, 7);
// ★ 关掉两个过关条件：模糊测试要的是「任何状态」的样本，过关会冻结场景、提前结束采样。
const _winClear = DESIGN.winOnClear, _scoreTgt = DESIGN.scoreTarget;
DESIGN.winOnClear = false;
DESIGN.scoreTarget = Infinity;
// 预算也放开：模糊测试要的是「任何状态」的样本，球发完就没得采样了。
scF.level.ballBudget = 1 << 20;
const rng = makeRng(31337);
let violations = 0, maxRun = 0, clears = 0, frames = 0;
for (let f = 0; f < 4000; f++) {
  // 随机制造"配对完成"事件（模拟射击命中后吸附完成）
  const balls = scF.chain.balls;
  if (balls.length > 3 && rng() < 0.25) {
    const i = rng.int(balls.length);
    if (!balls[i].paired) { balls[i].paired = true; balls[i].pairBase = 'U'; balls[i].dock = 1; }
  }
  if (balls.length > 3 && rng() < 0.06) {
    const i = rng.int(balls.length);
    if (!balls[i].paired) { balls[i].paired = true; balls[i].pairBase = 'A'; balls[i].dock = 0; }  // 走吸附飞行
  }
  advanceScene(scF, DT);
  frames++;
  const rs = computeRuns(scF.chain);
  for (let i = 0; i < rs.length; i++) {
    maxRun = Math.max(maxRun, rs[i].len);
    if (rs[i].len >= 3 && rs[i].len % 3 === 0) violations++;
  }
}
clears = scF.stats.cleared;
check('★ 4000 帧模糊测试：0 次"该消没消"的不变量违反', violations === 0,
  '违反 ' + violations + ' 次；期间消除 ' + clears + ' 颗；观察到的最大 run = ' + maxRun);
check('模糊测试期间确实发生了消除（测试有效）', clears >= 30, 'cleared=' + clears);
DESIGN.winOnClear = _winClear; DESIGN.scoreTarget = _scoreTgt;

// ---------- 消除后：原版行为 + 原版式后退冲量 ----------
group('★ 消除后：原版行为（留空隙）+ 原版式渐进后退冲量');
const scB = sceneWith(14, 0, 0);
for (let i = 0; i < 90; i++) advanceScene(scB, DT);        // 先跑一段，让队尾腾出后退空间
for (let i = 3; i <= 5; i++) { scB.chain.balls[i].paired = true; scB.chain.balls[i].dock = 1; scB.chain.balls[i].pairBase = 'U'; }
syncBeads(scB);
const nBefore = scB.chain.balls.length;
advanceScene(scB, DT);
check('中间 3 连当帧消掉', scB.stats.cleared === 3, 'cleared=' + scB.stats.cleared);
check('链长正好少 3 颗', scB.chain.balls.length === nBefore - 3, nBefore + ' -> ' + scB.chain.balls.length);
check('★ 留下物理空隙（原版行为，不做瞬移回填）', chainRuns(scB.chain).length === 2,
  '物理段数=' + chainRuns(scB.chain).length);
const driven = scB.chain.balls.filter(function (b) { return b.backLeft > 0; })[0];
check('后退标记已挂上（每球自带 backLeft / backSpeed，对应原版 Ball::SetBackwardsCount）',
  !!driven && driven.backSpeed > 0,
  driven ? ('backLeft=' + driven.backLeft + '  speed=' + driven.backSpeed.toFixed(1) + 'px/s') : '没有球被标记');
check('★ 标记打在**洞端最外那颗**（下标 0）—— 对应原版 mBallList.back()->SetBackwardsCount(1)',
  scB.chain.balls[0].backLeft > 0 && !scB.chain.balls[6].backLeft,
  '下标0=' + scB.chain.balls[0].backLeft + '  下标6=' + (scB.chain.balls[6] ? scB.chain.balls[6].backLeft : 'n/a'));
const wpAtImpulse = scB.chain.balls[0].wp;
let fb = 0;
while (hasBackward(scB.chain) && fb < 400) { advanceScene(scB, DT); fb += 1; }
const retreated = wpAtImpulse - scB.chain.balls[0].wp;
check('★ 后退总量 ≈ 被消颗数 × touchDist（渐进，不是瞬移）',
  Math.abs(retreated - 3 * T) < T * 0.25, '实测 ' + retreated.toFixed(2) + '  期望 ' + (3 * T).toFixed(2));
check('后退有过程：用满 backFrames 帧', fb >= DESIGN.backFrames - 2, '用了 ' + fb + ' 帧 / backFrames=' + DESIGN.backFrames);
for (let i = 0; i < 240; i++) advanceScene(scB, DT);
check('后退结束后恢复喂入并重新接上', scB.chain.balls.length > 0 && Number.isFinite(scB.chain.balls[0].wp));

// ---------- 用户点名的可能 bug 点：绑定小球是否跟随后退 ----------
group('★ 绑定小球是否跟随后退（用户点名的 bug 点）');
function advanceUnpaired(seed, frames) {
  const sc = assembleScene(LEVELS[0], view, seed);
  for (let i = 0; i < sc.chain.balls.length; i++) { sc.chain.balls[i].paired = false; sc.chain.balls[i].dock = null; }
  for (let i = 0; i < frames; i++) advanceScene(sc, DT);
  return sc;
}
function setPattern(sc, pattern) {
  for (let i = 0; i < sc.chain.balls.length; i++) { sc.chain.balls[i].paired = false; sc.chain.balls[i].dock = null; sc.chain.balls[i].pairBase = null; }
  for (let i = 0; i < pattern.length; i++) {
    if (pattern[i] && sc.chain.balls[i]) { sc.chain.balls[i].paired = true; sc.chain.balls[i].dock = 1; sc.chain.balls[i].pairBase = 'U'; }
  }
  syncBeads(sc);
}

const scM = advanceUnpaired(4242, 90);
setPattern(scM, [0, 1, 1, 0, 1, 1, 1]);      // 0..1 是一段 len=2（不会消），4..6 是 len=3（会消并触发后退）
const mateId = scM.chain.balls[1].id;
advanceScene(scM, DT);                        // 消 4..6 -> 施加后退冲量
const mateWp0 = scM.chain.balls.filter(function (b) { return b.id === mateId; })[0].wp;
let okFollow = true, dMin = Infinity, dMax = 0, fM = 0;
while (hasBackward(scM.chain) && fM < 400) {
  advanceScene(scM, DT); fM += 1;
  const big = scM.chain.balls.filter(function (b) { return b.id === mateId; })[0];
  const small = scM.beads.eliminate.filter(function (e) { return e.partner && e.partner.id === mateId; })[0];
  if (!big || !small) { okFollow = false; break; }
  const dd = Math.hypot(small.x - big.x, small.y - big.y);
  dMin = Math.min(dMin, dd); dMax = Math.max(dMax, dd);
  if (Math.abs(dd - scM.metrics.d) > 1e-6) okFollow = false;
}
check('★ 后退全过程：绑定小球与伙伴的距离恒 = 轨距 d（严丝合缝跟随）', okFollow,
  'd 范围 [' + dMin.toFixed(4) + ', ' + dMax.toFixed(4) + ']  期望 ' + scM.metrics.d.toFixed(4));
const mateWp1 = scM.chain.balls.filter(function (b) { return b.id === mateId; })[0].wp;
check('★ 配对球本身确实跟着后退了', (mateWp0 - mateWp1) > T, '后退 ' + (mateWp0 - mateWp1).toFixed(2) + 'px');
check('★ 后退过程中小球从未丢失', fM >= DESIGN.backFrames - 2 && okFollow, '跟踪了 ' + fM + ' 帧');

group('★ 级联多次消除时后退量必须累加（不是覆盖）');
const scCC = advanceUnpaired(9898, 90);
setPattern(scCC, [1, 1, 1, 0, 1, 1, 1]);     // 两段 len=3，中间隔 1 颗 -> 同帧级联消 6
advanceScene(scCC, DT);
check('同帧级联消 6 颗', scCC.stats.cleared === 6, 'cleared=' + scCC.stats.cleared);
const headCC = scCC.chain.balls[0].wp;
let fCC = 0;
while (hasBackward(scCC.chain) && fCC < 600) { advanceScene(scCC, DT); fCC += 1; }
const backCC = headCC - scCC.chain.balls[0].wp;
check('★★ 后退量按 6 颗累加，并受「退无可退」夹紧的上限约束',
  backCC > 3 * T * 1.05 && backCC <= 6 * T + 1,
  '实测 ' + backCC.toFixed(2) + '   3T=' + (3 * T).toFixed(2) + '   6T=' + (6 * T).toFixed(2) +
  '（>3T 说明累加生效；到不了 6T 是因为出球端余量不够，链子退无可退）');

// ---------- 回归：后退只退"洞穴那一侧"，不吃队尾 ----------
group('★ 回归：后退只退洞穴那一侧，绝不把队尾的球拖着吃光');
// 曾经的 bug：写成"整链无差别平移" -> 消除留下的缝挡不住后退，队尾刚冒出来的球
// 被拖着退出冒球口回收（3000 帧吃掉 20 颗，最后链被吃空）。
// 再改成"从下标 0 开始、遇缝即断"仍然不对：消除若在链首附近，下标 0 就是队尾那截了。
// 正解 = 照原版给**具体的球**打标记（Ball::SetBackwardsCount）。
const scR = advanceUnpaired(4242, 200);
setPattern(scR, [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0]);
advanceScene(scR, DT);
check('消除已发生（下标 7..9 的三连）', scR.stats.cleared === 3, 'cleared=' + scR.stats.cleared);
let flagged = 0, flaggedTail = 0;
for (let i = 0; i < scR.chain.balls.length; i++) {
  if (scR.chain.balls[i].backLeft > 0) { flagged += 1; if (i >= 7) flaggedTail += 1; }
}
check('★ 只标记洞端那颗（下标 0）；出球端那截绝不标记', flagged === 1 && flaggedTail === 0 && scR.chain.balls[0].backLeft > 0,
  'flagged=' + flagged + ' 其中在接缝之后的有 ' + flaggedTail + ' 颗');
const nAfterClear = scR.chain.balls.length;
for (let i = 0; i < 60; i++) advanceScene(scR, DT);
check('★★ 整个后退过程没有吃掉任何球（回归：整链平移时会被吃）',
  (scR.chain.stats.leftField || 0) === 0,
  'leftField=' + (scR.chain.stats.leftField || 0) + '  链长 ' + nAfterClear + ' -> ' + scR.chain.balls.length);
check('后退标记在冲量结束后被清掉', scR.chain.balls.every(function (b) { return !(b.backLeft > 0); }));

// 消除发生在**贴洞端**（i0 = 0）—— 实测这是实战里的绝大多数情况（玩家总打最靠洞的那几颗）。
// 这时**不该**后退：洞端那一侧本来就是空的，而且删除本身已经把队头往后送了 k 个球位
// （实测 k=3 时当帧退 117.8 = 3×touchDist），奖励已经兑现，再退就是双重兑现。
// ⚠ 曾经为了让这里"也有滑动"而改成一律标记，结果总退 (2k+1) 个球位，还回收掉 36~40 颗球。
const scR2 = advanceUnpaired(777, 200);
setPattern(scR2, [1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
const headBeforeR2 = scR2.chain.balls.length ? scR2.chain.balls[0].wp : 0;
advanceScene(scR2, DT);
check('链首三连也能消', scR2.stats.cleared === 3, 'cleared=' + scR2.stats.cleared);
check('★ 消除贴洞端：**不**打后退标记（洞端那侧本来是空的）',
  scR2.chain.balls.length > 0 && !(scR2.chain.balls[0].backLeft > 0),
  '下标0 backLeft = ' + (scR2.chain.balls[0] ? scR2.chain.balls[0].backLeft : 'n/a'));
const instantR2 = headBeforeR2 - scR2.chain.balls[0].wp;
check('★ 但删除本身已经兑现了奖励：队头当帧就退了约 k×touchDist',
  Math.abs(instantR2 - 3 * T) < T * 0.2, '当帧退 ' + instantR2.toFixed(1) + '  期望约 ' + (3 * T).toFixed(1));
const headWpR2 = scR2.chain.balls[0].wp;
for (let i = 0; i < 40; i++) advanceScene(scR2, DT);
const slidR2 = headWpR2 - scR2.chain.balls[0].wp;
check('★★ 之后**没有**额外后退（避免把已经兑现的 k 个球位再退一遍）',
  Math.abs(slidR2) < T, '净位移 ' + slidR2.toFixed(1) + ' 单位（T=' + T.toFixed(1) + '）');
check('没有球被拖出冒球口回收', (scR2.chain.stats.leftField || 0) === 0,
  'leftField=' + (scR2.chain.stats.leftField || 0));


// ---------- 用户给的编号重排例子 ----------
group('★ 用户给的例子：1.1 0.2 1.3 1.4 1.5 0.6 0.7 1.8  ->  1.1 0.2 0.3 0.4 1.5');
const scN = assembleScene(LEVELS[0], view, 555);
scN.stopAdding = true;
scN.chain.balls.length = 0;
const pat = [1, 0, 1, 1, 1, 0, 0, 1];
for (let i = 0; i < pat.length; i++) {
  scN.chain.balls.push({
    wp: (pat.length - 1 - i) * T, base: 'A', r: mt.R, id: i + 1, n: i,
    paired: !!pat[i], pairBase: pat[i] ? 'U' : null, dock: pat[i] ? 1 : null
  });
}
syncBeads(scN);
const xOf = function (ch) {
  return ch.chain.balls.map(function (b) { return (b.paired && (b.dock == null || b.dock >= 1)) ? 1 : 0; }).join('');
};
check('初始 x 序列 = 10111001', xOf(scN) === '10111001', xOf(scN));
advanceScene(scN, DT);
check('★★ 消除后 x 序列 = 10001（与用户写的完全一致）', xOf(scN) === '10001', xOf(scN));
check('★ 编号重排：后面的珠子编号变小（id 6/7/8 -> 第 3/4/5 颗）',
  scN.chain.balls[2].id === 6 && scN.chain.balls[3].id === 7 && scN.chain.balls[4].id === 8,
  '消除后 id 序列 = ' + scN.chain.balls.map(function (b) { return b.id; }).join(','));
check('被消掉的正是 id 3/4/5（原第 3/4/5 颗）', scN.stats.cleared === 3 && scN.chain.balls.length === 5,
  'cleared=' + scN.stats.cleared + ' n=' + scN.chain.balls.length);
check('链上不再存在 id 3/4/5', scN.chain.balls.every(function (b) { return b.id < 3 || b.id > 5; }));

console.log('');
console.log('test-run: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


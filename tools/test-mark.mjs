// 2 态（错误配对，mark = 2）测试。用法：node tools/test-mark.mjs
//
// ★ 语义（DESIGN.md §30-§32）：
//   x ∈ {0,1,2}；judge 重述为「那颗 2 的两侧是否同为 1 / 同为非 1」。
//   同为 -> 爆炸（移除它 + 左右各一颗 = 3 颗）；一边 1 一边非 1 -> 稳定（边界标记）。
//   只有左右都有**真邻居**的 2 才参与判定（链首/链尾"待定"）。
//   结算：**先爆炸，后 3n 消，循环到不动点**；一次一个、从左到右。

import { metrics, viewFor, DESIGN } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { makeChain, touchDist } from '../src/chain.js';
import { computeRuns, clearableRuns, isDocked, isMarked, markFinal, findExplosion } from '../src/run.js';
import { assembleScene, advanceScene, drainEvents, syncBeads } from '../src/scene.js';
import { makeProjectile } from '../src/projectile.js';
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

// marks[i] ∈ {0,1,2}
function mkChainMarks(marks) {
  const n = marks.length;
  const ch = makeChain(mt, {});
  for (let i = 0; i < n; i++) {
    const m = marks[i];
    ch.balls.push({
      wp: (n - 1 - i) * T, base: 'A', r: mt.R, id: i + 1,
      paired: m !== 0, wrongMark: m === 2,
      pairBase: m === 2 ? 'G' : (m === 1 ? 'U' : null),
      dock: m !== 0 ? 1 : null
    });
  }
  return ch;
}
const fe = function (marks) { return findExplosion(mkChainMarks(marks)); };
const lens = function (marks) {
  return computeRuns(mkChainMarks(marks)).map(function (r) { return r.len; }).join(',');
};

// 场景：把链换成指定 marks；tailWp 用来给冒球腾空间
function sceneMarks(marks, tailWp) {
  const sc = assembleScene(LEVELS[0], view, 20260101);
  sc.stopAdding = true;
  const n = marks.length;
  const balls = [];
  for (let i = 0; i < n; i++) {
    const m = marks[i];
    balls.push({
      wp: (n - 1 - i) * T + (tailWp || 0), base: 'A', r: mt.R, id: 1000 + i,
      paired: m !== 0, wrongMark: m === 2,
      pairBase: m === 2 ? 'G' : (m === 1 ? 'U' : null),
      dock: m !== 0 ? 1 : null
    });
  }
  sc.chain.balls = balls;
  sc.chain.nextId = 5000;
  syncBeads(sc);
  return sc;
}

// ---------- 三态读取 ----------
group('三态：mark ∈ {0,1,2} 的读取口径');
check('markFinal: 未配对=0 / 正确=1 / 错误=2',
  markFinal({ paired: false }) === 0 &&
  markFinal({ paired: true, dock: 1 }) === 1 &&
  markFinal({ paired: true, dock: 1, wrongMark: true }) === 2);
check('未定型的标记（吸附飞行中）一律算 0',
  markFinal({ paired: true, dock: 0.5 }) === 0 &&
  markFinal({ paired: true, dock: 0.5, wrongMark: true }) === 0);
check('isMarked: 1 和 2 都算"已占用"',
  isMarked({ paired: true, dock: 1 }) && isMarked({ paired: true, dock: 1, wrongMark: true }) && !isMarked({ paired: false }));
check('★ isDocked 只认 1：错误配对和"未配对"一样不算读出',
  isDocked({ paired: true, dock: 1 }) &&
  !isDocked({ paired: true, dock: 1, wrongMark: true }) &&
  !isDocked({ paired: false }));

// ---------- 2 断开 run ----------
group('★ 2 会断开 run（和 0 一样）');
check('1 2 1 1 -> 两段 1,2', lens([1, 2, 1, 1]) === '1,2', '实测 ' + lens([1, 2, 1, 1]));
check('1 1 2 1 1 -> 两段 2,2', lens([1, 1, 2, 1, 1]) === '2,2', '实测 ' + lens([1, 1, 2, 1, 1]));
check('★★ 2 与 0 对 run 的作用完全相同（把 2 换成 0 结果不变）',
  lens([1, 1, 2, 1, 1]) === lens([1, 1, 0, 1, 1]));
check('1 1 1 2 1 1 1 -> 两段 3,3（各自独立，不合并）',
  lens([1, 1, 1, 2, 1, 1, 1]) === '3,3', '实测 ' + lens([1, 1, 1, 2, 1, 1, 1]));

// ---------- 爆炸判据 ----------
group('★ 爆炸判据：两侧同为 1 或同为非 1 -> 爆；一边 1 一边非 1 -> 稳');
check('1 2 0 -> 稳（边界标记）', fe([1, 2, 0]) === -1, '返回 ' + fe([1, 2, 0]));
check('0 2 1 -> 稳', fe([0, 2, 1]) === -1, '返回 ' + fe([0, 2, 1]));
check('★★ 0 2 0 -> 不爆（两侧都没有绑定小球 -> 待定）', fe([0, 2, 0]) === -1, '返回 ' + fe([0, 2, 0]));
check('1 2 1 -> 爆（下标 1）', fe([1, 2, 1]) === 1, '返回 ' + fe([1, 2, 1]));
check('没有 2 时永不爆', fe([1, 1, 0, 1, 0, 1]) === -1);
check('吸附飞行中的 2 不参与判定（还没定型）', (function () {
  const ch = mkChainMarks([1, 2, 1]);
  ch.balls[1].dock = 0.4;
  return findExplosion(ch) === -1;
})());

// ---------- 邻居也是 2 ----------
group('★ 邻居也是 2：按"非 1"处理，不需要额外规则');
check('1 2 2 0 -> 不爆（第二颗右侧是没绑定球的 0）', fe([1, 2, 2, 0]) === -1, '返回 ' + fe([1, 2, 2, 0]));
check('1 2 2 1 -> 不爆（两侧 非1,1 不同）', fe([1, 2, 2, 1]) === -1, '返回 ' + fe([1, 2, 2, 1]));
// 注意：这里判的是**第一颗** 2（下标 1），它的两侧是 (0, 2) —— 都算"非 1" -> 爆。
// 「0 2 2 1 稳定」说的是**第二颗** 2（两侧 非1,1 不同），见下一条。
check('0 2 2 1 -> 不爆（第一颗左侧没绑定球；第二颗两侧 2/1 不同）', fe([0, 2, 2, 1]) === -1, '返回 ' + fe([0, 2, 2, 1]));
check('1 2 0 2 1 -> 两颗 2 都稳定（120 稳、021 稳）', fe([1, 2, 0, 2, 1]) === -1, '返回 ' + fe([1, 2, 0, 2, 1]));
check('1 2 2 1 -> 两侧都是标记但 1/2 不同 -> 稳', fe([1, 2, 2, 1]) === -1);
check('1 2 2 2 1 -> 中间那颗爆（两侧都是 2）', fe([1, 2, 2, 2, 1]) === 2, '返回 ' + fe([1, 2, 2, 2, 1]));

// ---------- 边界待定 ----------
group('★ 边界：链首/链尾的 2 不参与判定（待定）');
check('链首 2 1 ... -> 不爆', fe([2, 1, 1, 1]) === -1);
check('链尾 ... 0 2 -> 不爆', fe([1, 1, 0, 2]) === -1);
check('两颗球 2 2 -> 不爆（都缺真邻居）', fe([2, 2]) === -1);
check('三颗球 1 2 1 -> 中间那颗有真邻居，正常判定', fe([1, 2, 1]) === 1);

// ---------- 场景级：爆炸 = 移除 3 颗 ----------
group('★★ 爆炸 = 移除 3 颗（2 + 左右各一颗），保住 mod-3');
const scE = sceneMarks([1, 2, 1]);
advanceScene(scE, DT);
check('1 2 1 一次爆炸', scE.stats.explosions === 1, 'explosions=' + scE.stats.explosions);
check('★ 移除 3 颗（不是 1 颗）', scE.chain.balls.length === 0, '剩余 ' + scE.chain.balls.length);
check('爆炸不计分（它是成本不是奖励）', scE.score === 0, 'score=' + scE.score);

// ---------- 用户的反例 ----------
group('★★ 用户的反例：1111 2 1111 爆炸后 -> 111111 -> 消 6');
const scU = sceneMarks([1, 1, 1, 1, 2, 1, 1, 1, 1]);
advanceScene(scU, DT);
check('一次爆炸', scU.stats.explosions === 1, 'explosions=' + scU.stats.explosions);
check('★★ 随后合并成 6 并整段消掉', scU.stats.cleared === 6, 'cleared=' + scU.stats.cleared);
check('全清（9 = 3 爆炸 + 6 消除）', scU.chain.balls.length === 0, '剩余 ' + scU.chain.balls.length);
const scU0 = sceneMarks([1, 1, 1, 1, 0, 1, 1, 1, 1]);
advanceScene(scU0, DT);
check('对照：中间是 0（没有爆炸）时，两段 4 都消不掉',
  scU0.stats.cleared === 0 && scU0.chain.balls.length === 9,
  'cleared=' + scU0.stats.cleared + ' 剩余=' + scU0.chain.balls.length);

// ---------- 重叠三元组 ----------
group('★ 重叠三元组 1 2 1 2 1：顺序结算 -> 结果唯一，不会歧义');
const scO = sceneMarks([1, 2, 1, 2, 1]);
advanceScene(scO, DT);
check('只爆一次（先爆的那个把后面那颗一起清掉）', scO.stats.explosions === 1, 'explosions=' + scO.stats.explosions);
check('剩 2 颗', scO.chain.balls.length === 2, '剩余 ' + scO.chain.balls.length);
check('剩下的是 [2, 1]，且那颗 2 现在处于链首 -> 待定',
  scO.chain.balls[0].wrongMark === true && scO.chain.balls[1].wrongMark !== true);
const scO2 = sceneMarks([1, 2, 1, 2, 1]);
advanceScene(scO2, DT);
check('★ 结果确定：重跑一次完全相同',
  scO2.stats.explosions === scO.stats.explosions && scO2.chain.balls.length === scO.chain.balls.length);

// ---------- 不可达状态 ----------
group('★ 立即结算把病态状态剪掉（0 2 2 0 / 2020… 都不可达）');
const scX = sceneMarks([1, 2, 2, 0]);
advanceScene(scX, DT);
check('★ 0 2 0 这种「两侧都没绑定小球」的形态现在是稳定的（不会莫名爆炸）',
  (function () { const s2 = sceneMarks([0, 2, 0]); advanceScene(s2, DT); return s2.stats.explosions === 0 && s2.chain.balls.length === 3; })());
check('直接注入 2 0 2 0 2：全是无绑定球邻居 -> 一颗都不爆',
  (function () {
    const sc = sceneMarks([2, 0, 2, 0, 2]);
    advanceScene(sc, DT);
    return sc.stats.explosions === 0 && sc.chain.balls.length === 5;
  })());

// ---------- 链尾待定转正 ----------
group('★ 链尾的 2 待定 -> 新球冒出来把它顶出边界 -> 立刻按正常规则判定');
const scT = sceneMarks([1, 1, 0, 2], 60);
scT.stopAdding = false;
advanceScene(scT, DT);
check('★ ...0 2 + 新冒的 0 -> 0 2 0：按新规则不爆（两侧都没绑定小球）',
  scT.stats.explosions === 0, 'explosions=' + scT.stats.explosions);
check('链保持完整', scT.chain.balls.length === 5, '剩余 ' + scT.chain.balls.length);

// ---------- 错误配对走同一条配对路径 ----------
group('★ 错误配对复用配对路径（DESIGN.md §32）：占用 + 吸附 + 三消道出小球');
const scH = sceneMarks([0, 0, 0, 0, 0, 0], 300);
const tgtH = scH.chain.balls[2];
scH.projectiles.push(makeProjectile({ base: 'G', x: tgtH.x, y: tgtH.y, angle: 0 }, mt));
advanceScene(scH, DT);
const hitBall = scH.chain.balls[2];
check('命中后目标被"占用"（paired = true）', hitBall && hitBall.paired === true);
check('★ 状态值记成 2（wrongMark）', hitBall && hitBall.wrongMark === true, 'wrongMark=' + (hitBall && hitBall.wrongMark));
check('★ 也走了吸附飞行（dock 在 0~1 之间飞，不是立即生效）',
  hitBall && hitBall.dock > 0 && hitBall.dock < 1, 'dock=' + (hitBall && hitBall.dock));
check('★ 三消道上出现了一颗标记为 wrong 的小球',
  scH.beads.eliminate.length === 1 && scH.beads.eliminate[0].wrong === true,
  'eliminate=' + scH.beads.eliminate.length + ' wrong=' + (scH.beads.eliminate[0] && scH.beads.eliminate[0].wrong));
check('定型前（dock<1）不参与爆炸判定', findExplosion(scH.chain) === -1);
check('大球描边是警示红', hitBall && hitBall.pairGlow === '#ff5555', 'pairGlow=' + (hitBall && hitBall.pairGlow));
check('错误配对的球不能再被打中（sweepHit 跳过"已占用"）',
  (function () {
    const before = scH.stats.mismatches;
    scH.projectiles.push(makeProjectile({ base: 'G', x: hitBall.x, y: hitBall.y, angle: 0 }, mt));
    advanceScene(scH, DT);
    return scH.stats.mismatches === before;
  })());

// ---------- 爆炸的两个性质 ----------
group('★ 爆炸：不卷进没绑定小球的球 + 会给后退冲量');
check('★ 爆炸移除的 3 颗都带绑定小球（不会卷进「没绑定小球」的球）',
  (function () {
    const sc = sceneMarks([1, 1, 1, 1, 2, 1, 1, 0, 0, 0, 0], 300);
    const before = sc.chain.balls.map(function (b) { return { id: b.id, mk: markFinal(b) }; });
    advanceScene(sc, DT);
    const after = {};
    for (const b of sc.chain.balls) after[b.id] = 1;
    const gone = before.filter(function (b) { return !after[b.id]; });
    return sc.stats.explosions === 1 && gone.length === 3 &&
           gone.every(function (b) { return b.mk !== 0; });
  })());
check('★★ 爆炸也和 3n 消一样给后退冲量（几何上一样：都移除 3 颗）',
  (function () {
    const sc = sceneMarks([1, 1, 1, 1, 2, 1, 1, 0, 0, 0, 0], 300);
    advanceScene(sc, DT);
    if (sc.stats.explosions !== 1 || sc.stats.cleared !== 0) return false;
    const flagged = sc.chain.balls.filter(function (b) { return b.backLeft > 0; });
    if (flagged.length !== 1 || flagged[0] !== sc.chain.balls[0]) return false;
    const h0 = sc.chain.balls[0].wp;
    for (let k = 0; k < 34; k++) advanceScene(sc, DT);
    const slid = h0 - sc.chain.balls[0].wp;
    return Math.abs(slid - 3 * T) < T * 0.3;      // 3 颗 -> 退 3 个球位
  })());
check('爆炸贴洞端（i0<=1）时不额外退（奖励已由删除兑现）',
  (function () {
    const sc = sceneMarks([1, 2, 1, 0, 0, 0, 0, 0], 300);   // 2 在下标 1 -> 移除 0,1,2 -> headEnd = 0
    advanceScene(sc, DT);
    return sc.stats.explosions === 1 && sc.chain.backLeft === undefined &&
           sc.chain.balls.every(function (b) { return !(b.backLeft > 0); });
  })());

// ---------- 回归：配对不应引起任何移动 ----------
group('★ 回归：配对定型不应引起链的任何移动（曾经误加了原版「合并后退」）');
// 曾经的 bug：把「配对」映射成原版的「合并(suck)」，于是每配对一颗球就给它洞端侧那颗邻居
// 打后退标记 -> 配对点后面的球退 15 单位、前面的不动 -> **链裂开一条缝**，
// 同时 stopTime 每帧被重置 -> **整链冻结约 30 帧**。
// 根因：原版的合并是「两颗同色球物理合并成一颗」，链真的缩短了；我们的配对只是贴一个标记，
// 链的几何完全不变 —— 两者不同构，不该套用。
function pairScn(dockAt) {
  const sc = sceneMarks([0, 0, 1, 0, 0, 0, 0, 0], 200);
  sc.stopAdding = true;
  sc.chain.balls[dockAt].dock = 0.999;
  sc.chain.balls[dockAt].dockDone = false;
  return sc;
}
check('★ 配对定型后没有任何球被打上后退标记',
  (function () {
    const sc = pairScn(2);
    advanceScene(sc, DT);
    return sc.chain.balls.every(function (b) { return !(b.backLeft > 0); });
  })());
check('★ 配对定型不冻结推进（stopTime 保持 0）',
  (function () {
    const sc = pairScn(2);
    advanceScene(sc, DT);
    return sc.chain.stopTime === 0;
  })());
check('★ 配对不会让链裂开一条缝（相邻间距仍 <= touchDist）',
  (function () {
    const sc = pairScn(2);
    for (let f = 0; f < 30; f++) advanceScene(sc, DT);
    const b = sc.chain.balls;
    for (let i = 1; i < b.length; i++) {
      if (b[i - 1].wp - b[i].wp > T + 1e-6) return false;
    }
    return true;
  })());
check('配对本身照常生效（mark 变为已定型）',
  (function () {
    const sc = pairScn(2);
    advanceScene(sc, DT);
    return markFinal(sc.chain.balls[2]) === 1 && sc.beads.eliminate.length === 1;
  })());


// ---------- 不变量模糊测试 ----------
group('★ 不变量模糊测试：结算到不动点后 (a) 无该消的 run (b) 无该爆的 2');
const rng = makeRng(20260919);
let viol = 0, totExpl = 0, totClear = 0, maxRun = 0, badCase = '';
for (let trial = 0; trial < 500; trial++) {
  const n = 6 + (trial % 12);
  const marks = [];
  for (let i = 0; i < n; i++) {
    const r = rng();
    marks.push(r < 0.30 ? 0 : (r < 0.82 ? 1 : 2));
  }
  const sc = sceneMarks(marks, 90);
  advanceScene(sc, DT);
  totExpl += sc.stats.explosions;
  totClear += sc.stats.cleared;
  if (findExplosion(sc.chain) !== -1) { viol += 1; badCase = '有该爆没爆的 2 @' + JSON.stringify(marks); }
  const rs = clearableRuns(sc.chain);
  if (rs.length) { viol += 1; badCase = '有该消没消的 run @' + JSON.stringify(marks); }
  const all = computeRuns(sc.chain);
  for (let k = 0; k < all.length; k++) maxRun = Math.max(maxRun, all[k].len);
}
check('★ 500 局随机注入：0 次不变量违反', viol === 0, viol ? badCase : '违反 0 次');
check('模糊测试确实触发了爆炸与消除（测试有效）', totExpl > 50 && totClear > 50,
  '爆炸 ' + totExpl + ' 次，消掉 ' + totClear + ' 颗，观察到的最大 run = ' + maxRun);

console.log('\ntest-mark: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


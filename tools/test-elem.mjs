// §57 七球模式测试。用法：node tools/test-elem.mjs
//
// ★ 用户的定调：「直接来个七球模式，匹配相当于元素反应」。
//   所以这里测的是**一层**结构：球的身份就是元素，珠子也是元素，
//   **两个元素之间有反应 = 匹配成功**。反应表既是效果表、也是匹配表。
//
// ★ 反应倍率逐条对着官方 WIKI「元素反应」条目核过（DESIGN.md §58）。
//   这个文件同时是"来源可核对"的载体 —— 表被改错，这里就红。

import { metrics, viewFor, DESIGN } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { assembleScene, advanceScene, fireShot, drainEvents, sceneInfo, setMode, toggleMode,
         sevenHit, findSevenReaction, syncBeads } from '../src/scene.js';
import { ELEMENTS, QUICK, canAttach, reactionFor, sevenReaction, beadElemsFor,
         SHATTER, elemGlyph } from '../src/elements.js';
import { aimAt } from '../src/ribosome.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

const mt = metrics(1);
const view = viewFor(900, 900);
const DT = 1 / 60;

function sevenScene(seed) {
  const sc = assembleScene(LEVELS[0], view, seed || 20260101);
  setMode(sc, 'seven');
  sc.stopAdding = true;
  syncBeads(sc);
  return sc;
}
// 把第 i 颗球设成某个元素（七球模式下身份 = 元素）
function putBall(sc, i, elem) {
  const b = sc.chain.balls[i];
  b.elem = elem; b.base = elem;
  b.paired = false; b.wrongMark = false; b.dock = null; b.pairBase = null;
  b.amp = 0; b.quickened = false; b.frozen = 0; b.burn = 0;
  return b;
}
function countPaired(sc) {
  let n = 0;
  for (let i = 0; i < sc.chain.balls.length; i++) if (sc.chain.balls[i].paired) n += 1;
  return n;
}

// ---------- 一、匹配表 ----------
group('一、匹配表 = 反应表（球在左，珠子在上；· = 没有反应 = 废弹）');
(function () {
  console.log('        ' + ELEMENTS.map(function (e) { return elemGlyph(e); }).join('  '));
  for (let r = 0; r < ELEMENTS.length; r++) {
    const ball = ELEMENTS[r];
    const cells = ELEMENTS.map(function (bead) {
      const x = sevenReaction(ball, bead);
      return x ? elemGlyph(bead) : '·';
    });
    console.log('  ' + elemGlyph(ball) + '     ' + cells.join('  ') +
      '    可配 ' + beadElemsFor(ball).length + '/6');
  }
})();
check('★ 火球 6/6：除火自己之外全都能配', beadElemsFor('pyro').length === 6);
check('★ 水球 6/6', beadElemsFor('hydro').length === 6);
check('★ 冰球 5/6（跟草没反应）', beadElemsFor('cryo').length === 5);
check('★ 雷球 6/6', beadElemsFor('electro').length === 6);
check('★ 草球只有 3/6（火/水/雷）—— 全场最难打的球',
  beadElemsFor('dendro').length === 3 &&
  beadElemsFor('dendro').join(',') === 'pyro,hydro,electro',
  beadElemsFor('dendro').join(','));
check('★ 风球 4/6（火/水/雷/冰 -> 扩散）', beadElemsFor('anemo').length === 4);
check('★ 岩球 4/6（火/水/雷/冰 -> 结晶）', beadElemsFor('geo').length === 4);
check('同元素 -> 没有反应（打上去就是废弹）',
  ELEMENTS.every(function (e) { return sevenReaction(e, e) === null; }));

group('一.1 反向查询：风 / 岩 不能作先手（§57.3）');
check('风球 + 火珠 = 扩散', (sevenReaction('anemo', 'pyro') || {}).name === '扩散');
check('岩球 + 冰珠 = 结晶', (sevenReaction('geo', 'cryo') || {}).name === '结晶');
check('草球 + 风珠 = 无（官方表里草和风不反应）', sevenReaction('dendro', 'anemo') === null);
check('草球 + 岩珠 = 无', sevenReaction('dendro', 'geo') === null);
check('风球 + 岩珠 = 无', sevenReaction('anemo', 'geo') === null);
check('草球 + 冰珠 = 无', sevenReaction('dendro', 'cryo') === null);

group('一.2 倍率方向（后手吃倍率）');
check('水打在火球上 = 蒸发 2.0（正克制）', sevenReaction('pyro', 'hydro').mult === 2.0);
check('火打在水球上 = 蒸发 1.5（逆克制）', sevenReaction('hydro', 'pyro').mult === 1.5);
check('火打在冰球上 = 融化 2.0', sevenReaction('cryo', 'pyro').mult === 2.0);
check('冰打在火球上 = 融化 1.5', sevenReaction('pyro', 'cryo').mult === 1.5);
check('超载 2.75 / 超导 1.5 / 感电 2 / 燃烧 0.25 / 绽放 2 / 扩散 0.6',
  sevenReaction('pyro', 'electro').mult === 2.75 &&
  sevenReaction('cryo', 'electro').mult === 1.5 &&
  sevenReaction('hydro', 'electro').mult === 2 &&
  sevenReaction('dendro', 'pyro').mult === 0.25 &&
  sevenReaction('dendro', 'hydro').mult === 2 &&
  sevenReaction('pyro', 'anemo').mult === 0.6);

group('一.3 特殊情况：碎冰 / 激化');
const scFz = sevenScene(9);
putBall(scFz, 5, 'cryo');
scFz.chain.balls[5].frozen = 3;
check('冻结的球被岩打中 -> 碎冰（优先于冰+岩的结晶）',
  findSevenReaction(scFz, 5, 'geo').id === 'shatter');
putBall(scFz, 5, 'cryo');
check('没冻结时，冰球 + 岩 = 结晶（不是碎冰）',
  findSevenReaction(scFz, 5, 'geo').id === 'crystallize');
const scQ2 = sevenScene(9);
putBall(scQ2, 5, 'dendro');
scQ2.chain.balls[5].quickened = true;
check('带激元素的球 + 雷 = 超激化 1.15', findSevenReaction(scQ2, 5, 'electro').mult === 1.15);
check('带激元素的球 + 草 = 蔓激化 1.25', findSevenReaction(scQ2, 5, 'dendro').mult === 1.25);

// ---------- 二、命中分流 ----------
group('二、命中分流：有反应 = 读出；没反应 = 错误配对（废弹）');
const scA = sevenScene();
putBall(scA, 3, 'pyro');
const rA = sevenHit(scA, 3, 'hydro');
check('匹配成功返回那个反应', rA && rA.id === 'vaporize');
check('球被读出（mark 1，可以参与 3n 消）',
  scA.chain.balls[3].paired === true && scA.chain.balls[3].wrongMark === false);
check('绑定小球记的是"打中它的那个元素"', scA.chain.balls[3].pairBase === 'hydro');
check('stats.pairs +1', scA.stats.pairs === 1);
check('增幅反应给球打上 amp', scA.chain.balls[3].amp === 2.0);
const scB = sevenScene();
putBall(scB, 3, 'pyro');
const rB = sevenHit(scB, 3, 'pyro');            // 同元素 = 没反应
check('同元素 -> 匹配失败', rB === null);
check('失败走"错误配对"（mark 2，之后会爆炸）',
  scB.chain.balls[3].paired === true && scB.chain.balls[3].wrongMark === true);
check('stats.mismatches +1', scB.stats.mismatches === 1);

// ---------- 三、各反应的效果 ----------
group('三.1 超载：就地移除 3 颗（和爆炸同一条铁律）');
const scC = sevenScene();
putBall(scC, 6, 'pyro');
const nC = scC.chain.balls.length;
sevenHit(scC, 6, 'electro');
check('移除 3 颗', scC.chain.balls.length === nC - 3, nC + ' -> ' + scC.chain.balls.length);
check('不计进"错误配对爆炸"的计数', scC.stats.explosions === 0 && scC.stats.reactionRemoves === 1);

group('三.2 超导：自动"读出"若干颗，帮玩家凑 3n 段');
const scD = sevenScene();
putBall(scD, 8, 'cryo');
const d0 = countPaired(scD);
sevenHit(scD, 8, 'electro');
check('自动配对了若干颗', countPaired(scD) > d0, d0 + ' -> ' + countPaired(scD));
check('自动配对的是正确配对（mark 1）',
  scD.chain.balls.filter(function (b) { return b.paired && b.wrongMark; }).length === 0);

group('三.3 感电：向"带水"的球传导放电（WIKI 原文：周围有附着水的敌人会间歇放电）');
const scE = sevenScene();
putBall(scE, 4, 'hydro');
putBall(scE, 12, 'electro');
const e0 = countPaired(scE);
sevenHit(scE, 12, 'hydro');                     // 雷球 + 水珠 = 感电
check('对带水的球放电（传导）', countPaired(scE) - e0 >= 2, e0 + ' -> ' + countPaired(scE));

group('三.4 冻结：整链停止前进（原神里冻结 = 无法行动）');
const scG = sevenScene();
putBall(scG, 3, 'cryo');
sevenHit(scG, 3, 'hydro');
check('冻结设置到链上', scG.chain.freezeTime > 0, 'freezeTime=' + scG.chain.freezeTime);
const wp0 = scG.chain.balls[0].wp;
for (let i = 0; i < 60; i++) advanceScene(scG, DT);
check('冻结期间整链一点都不动', Math.abs(scG.chain.balls[0].wp - wp0) < 1e-9);
for (let i = 0; i < 240; i++) advanceScene(scG, DT);
check('冻结结束后恢复前进', scG.chain.balls[0].wp > wp0);

group('三.5 扩散：被扩散的元素能进一步引发其他反应（WIKI 原文）');
const scH = sevenScene();
for (let i = 0; i < scH.chain.balls.length; i++) putBall(scH, i, 'dendro');
putBall(scH, 9, 'hydro');
putBall(scH, 10, 'anemo');
const rx0 = scH.stats.reactions;
sevenHit(scH, 10, 'pyro');                      // 风球 + 火珠 = 扩散
check('扩散本身算了 1 次反应', scH.stats.reactions >= 1);
check('★ 扩散还能再引发别的反应（火碰上邻居的水 -> 蒸发）',
  scH.stats.reactions - rx0 >= 2, '反应次数 ' + (scH.stats.reactions - rx0));
check('★ 扩散不改写邻居的身份（七球里身份不能被覆盖）',
  scH.chain.balls.filter(function (b) { return b.elem === 'dendro'; }).length >= 5);

group('三.6 结晶：护盾抵挡一次洞穴吞噬（不扣命）');
const scI = sevenScene();
putBall(scI, 2, 'pyro');
sevenHit(scI, 2, 'geo');
check('岩打火球 = 结晶 -> 护盾', scI.shields === 1, 'shields=' + scI.shields);
check('结晶不造成伤害（倍率 0）', sevenReaction('pyro', 'geo').mult === 0);
const lives0 = scI.lives;
scI.chain.balls[0].wp = scI.path.length;
advanceScene(scI, DT);
check('护盾挡下一次洞穴吞噬：不扣命', scI.lives === lives0 && scI.shields === 0,
  'lives ' + lives0 + ' -> ' + scI.lives);
check('挡下来会报一声', drainEvents(scI).some(function (e) { return e.type === 'shieldBlock'; }));

group('三.7 碎冰：冻结的球 + 岩 -> 移除 3 颗');
const scJ = sevenScene();
putBall(scJ, 6, 'cryo');
scJ.chain.balls[6].frozen = 3;
const nJ = scJ.chain.balls.length;
sevenHit(scJ, 6, 'geo');
check('碎冰移除 3 颗', scJ.chain.balls.length === nJ - 3, nJ + ' -> ' + scJ.chain.balls.length);

group('三.8 绽放 / 超绽放');
const scK = sevenScene();
putBall(scK, 5, 'dendro');
sevenHit(scK, 5, 'hydro');
check('草球 + 水珠 = 绽放 -> 草原核', scK.cores.length === 1, 'cores=' + scK.cores.length);
putBall(scK, 5, 'dendro');
scK.chain.balls[5].paired = true;
drainEvents(scK);                                // 清掉绽放那次的事件
const nK = scK.chain.balls.length;
const rK = sevenHit(scK, 5, 'electro');         // 雷打在这颗挂着核的草球上
const evK = drainEvents(scK).filter(function (e) { return e.type === 'reaction'; });
check('★ 核被雷打中 -> 超绽放（和 草+雷 的原激化是**两件事**，都会发生）',
  evK.some(function (e) { return e.id === 'hyperbloom'; }),
  JSON.stringify(evK.map(function (e) { return e.name; })));
check('★ 超绽放移除 3 颗', scK.chain.balls.length === nK - 3 - (evK.some(function (e) { return e.id === 'quicken'; }) ? 0 : 0),
  nK + ' -> ' + scK.chain.balls.length);

group('三.9 原激化 / 燃烧');
const scL = sevenScene();
putBall(scL, 4, 'dendro');
sevenHit(scL, 4, 'electro');
check('草球 + 雷珠 = 原激化 -> 打上"激"标记', scL.chain.balls[4].quickened === true);
check('★ 但球的**身份没有被改写**（还是草）—— 七球里身份 = 元素，不能动',
  scL.chain.balls[4].elem === 'dendro', 'elem=' + scL.chain.balls[4].elem);
const scM = sevenScene();
putBall(scM, 6, 'dendro');
sevenHit(scM, 6, 'pyro');
check('草球 + 火珠 = 燃烧 -> 挂上状态', scM.chain.balls[6].burn > 0);
// ⚠ 不能只数"当前还有几颗配对的"：燃烧点亮的球一旦凑满 3n 就被消掉了，
//   那个数会**变小**（第一版就是这么假红的：1 -> 0 反而判失败）。
//   正确的进展信号 = 现在配对的 + 已经被消掉的。
const burnProg = function () { return countPaired(scM) + scM.stats.cleared; };
const q0 = burnProg();
for (let i = 0; i < 60; i++) advanceScene(scM, DT);
check('燃烧持续自动配对（每秒 4 跳）', burnProg() > q0,
  '配对的+已消的 ' + q0 + ' -> ' + burnProg());

// ---------- 四、mod-3 ----------
group('四、mod-3 铁律：反应造成的移除也必须是 3 的倍数');
(function () {
  const sc = sevenScene(99);
  const sizes = [];
  for (let k = 0; k < 3; k++) {
    const i = 3 + k * 3;
    if (i >= sc.chain.balls.length) break;
    putBall(sc, i, 'pyro');
    const n0 = sc.chain.balls.length;
    sevenHit(sc, i, 'electro');                 // 超载：纯移除
    sizes.push(n0 - sc.chain.balls.length);
  }
  check('★★ 每次超载都恰好移除 3 颗', sizes.length > 0 && sizes.every(function (x) { return x === 3; }),
    '每次移除 ' + sizes.join(','));
})();

// ---------- 五、模式切换 ----------
group('五、模式：匹配 -> 加球 -> 七球 -> 匹配（身份空间要跟着换）');
const scN = assembleScene(LEVELS[0], view, 5);
setMode(scN, 'match');
check('起点是匹配', scN.mode === 'match');
toggleMode(scN); check('切到加球', scN.mode === 'insert');
toggleMode(scN); check('切到七球', scN.mode === 'seven');
toggleMode(scN); check('转回匹配', scN.mode === 'match');
check('setMode 不认的字符串退回匹配', setMode(scN, 'nonsense') === 'match');
const scO = assembleScene(LEVELS[0], view, 6);
check('★ 七球模式之外的球不带元素', scO.chain.balls.every(function (b) { return !b.elem; }));
setMode(scO, 'seven');
check('★★ 切进七球：场上球的身份变成元素（base 和 elem 同一个值）',
  scO.chain.balls.every(function (b) { return ELEMENTS.indexOf(b.base) >= 0 && b.elem === b.base; }),
  '首颗=' + scO.chain.balls[0].base);
check('★ 手里两颗也换成元素', scO.rb.loaded.every(function (t) { return ELEMENTS.indexOf(t) >= 0; }),
  scO.rb.loaded.join(','));
check('★ rb.tokens 跟着换（drawBase 的兜底要看它）', scO.rb.tokens === ELEMENTS);
setMode(scO, 'match');
check('★★ 切回匹配：身份变回碱基', scO.chain.balls.every(function (b) { return ['A','U','G','C','T'].indexOf(b.base) >= 0; }),
  '首颗=' + scO.chain.balls[0].base);
check('手里变回碱基', scO.rb.loaded.every(function (t) { return ['A','U','G','C','T'].indexOf(t) >= 0; }));
check('七球里的元素留在 elem 上不会污染匹配模式（清成 null）',
  scO.chain.balls.every(function (b) { return !b.elem; }));
check('sceneInfo 会报手里装着什么', Array.isArray(sceneInfo(scO).loaded));

// ---------- 六、提示不许骗人 ----------
group('★ 六、瞄准提示（§57.11）必须和实际结算**完全一致**');
// 元素层没有"看颜色发反色"那种直觉通道，玩家唯一的依据就是提示 ——
// 提示骗人比没有提示更糟。对每种情形跑两遍：一遍只问，一遍真打。
function hintVsActual(ballElem, beadElem, label) {
  const a = sevenScene(77);
  const b = sevenScene(77);
  putBall(a, 5, ballElem);
  putBall(b, 5, ballElem);
  const hint = findSevenReaction(a, 5, beadElem);
  const rr = sevenHit(b, 5, beadElem);
  const hinted = hint ? hint.id : null;
  const actual = rr ? rr.id : null;
  check(label, hinted === actual, '提示=' + (hinted || '无') + '  实际=' + (actual || '无'));
}
hintVsActual('pyro', 'hydro', '火球 + 水 -> 蒸发');
hintVsActual('pyro', 'electro', '火球 + 雷 -> 超载');
hintVsActual('cryo', 'hydro', '冰球 + 水 -> 冻结');
hintVsActual('anemo', 'pyro', '风球 + 火 -> 扩散（反向查）');
hintVsActual('geo', 'pyro', '岩球 + 火 -> 结晶');
hintVsActual('dendro', 'electro', '草球 + 雷 -> 原激化');
hintVsActual('pyro', 'pyro', '火球 + 火 -> 两边都报"无反应"');
hintVsActual('dendro', 'cryo', '草球 + 冰 -> 两边都报"无反应"');
check('提示是**纯读**的：问一百遍也不改任何状态', (function () {
  const sc = sevenScene(77);
  putBall(sc, 5, 'pyro');
  const n0 = sc.chain.balls.length, r0 = sc.stats.reactions, s0 = sc.score;
  for (let i = 0; i < 100; i++) findSevenReaction(sc, 5, 'hydro');
  return sc.chain.balls.length === n0 && sc.stats.reactions === r0 && sc.score === s0 &&
    sc.chain.balls[5].paired === false;
})());

// ---------- 七、整条链路 ----------
group('七、整条链路：装元素 -> 发射 -> 命中 -> 匹配 = 反应');
const scP = sevenScene(31);
putBall(scP, 3, 'pyro');
scP.rb.loaded[0] = 'hydro';
syncBeads(scP);
scP.rb.x = scP.chain.balls[3].x - 200;
scP.rb.y = scP.chain.balls[3].y;
aimAt(scP.rb, scP.chain.balls[3].x, scP.chain.balls[3].y);
const shot = fireShot(scP);
check('发射成功，且这一发带的是元素', !!shot && shot.base === 'hydro', shot ? 'base=' + shot.base : 'null');
for (let i = 0; i < 30 && scP.projectiles.length; i++) advanceScene(scP, DT);
const rc = drainEvents(scP).filter(function (e) { return e.type === 'reaction'; });
check('★★ 命中即触发反应（火球 + 水 = 蒸发）',
  rc.length === 1 && rc[0].id === 'vaporize',
  JSON.stringify(rc.map(function (e) { return e.name + '×' + e.mult; })));
check('★ 匹配成功 = 读出 + 反应，是一件事', scP.stats.pairs === 1 && scP.stats.reactions === 1);


console.log('\ntest-elem: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);

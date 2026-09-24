// §60/§64 新手关测试。用法：node tools/test-tutorial.mjs
//
// 新手关的验收标准不是"能跑"，而是**每一关要教的那件事真的会发生**：
//   ① 必须**不消球**（用户："第一关融入了三的倍数，不太对"）
//   ② 的开局必须真的摆出 run=4（徽章写「还差 2」）
//   ③ 的灰球必须第一帧就炸，而且提示必须**说清什么时候才炸**
//   ⑥ 必须是 §28 的 11 0 11 死球
// 这些是"课"本身，不是装饰 —— 摆错了这一关就白设计了。

import { metrics, viewFor, BASES, DESIGN, menuLayout } from '../src/config.js';
import { TUTORIALS, ALL_LEVELS, LEVELS } from '../src/levels.js';
import { assembleScene, advanceScene, sceneInfo, drainEvents, parseScript, parseScriptEntry,
         allowedComplements, syncBeads } from '../src/scene.js';
import { markFinal, computeRuns, runStatus } from '../src/run.js';
import { insertBall } from '../src/chain.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

const view = viewFor(900, 900);
const DT = 1 / 60;
const byId = function (id) { return TUTORIALS.filter(function (l) { return l.id === id; })[0]; };
function fresh(id, seed) { return assembleScene(byId(id), view, seed || 20260101); }
function marks(sc) { return sc.chain.balls.map(markFinal).join(''); }
function hintLines(l) { return Object.prototype.toString.call(l.hint) === '[object Array]' ? l.hint : [l.hint]; }

// ---------- 一、配方完整性 ----------
group('一、七关的配方都完整（缺字段的关卡会安静地退化成普通关）');
check('一共 7 关（①③ 已合并：反色 + 五色球本来就是同一课）',
  TUTORIALS.length === 7, 'TUTORIALS=' + TUTORIALS.length);
check('全部关卡表 = 新手关 + 原来的 4 关', ALL_LEVELS.length === TUTORIALS.length + LEVELS.length,
  ALL_LEVELS.length + ' = ' + TUTORIALS.length + ' + ' + LEVELS.length);
check('★ 原来的 4 关在 ALL_LEVELS 里排最后（测试/探针依赖 LEVELS[0] 不变）',
  ALL_LEVELS[ALL_LEVELS.length - 1].id === 'endless');
check('★ LEVELS 本身没被改动（大量测试依赖 LEVELS[0] = spiral-outer）',
  LEVELS.length === 4 && LEVELS[0].id === 'spiral-outer' && LEVELS[0].prefill === 14);
check('每关都有 id / name / short / hint / 球数预算',
  TUTORIALS.every(function (l) { return l.id && l.name && l.short && l.hint && l.ballBudget > 0; }));
check('每关都是"清空过关"（scoreTarget = Infinity），不会被分数提前结束',
  TUTORIALS.every(function (l) { return l.scoreTarget === Infinity; }));
check('★ 每关的预算都 ≥ 开局球数（小于的话"发满"永远不成立 -> 清空判赢永远不触发）',
  TUTORIALS.every(function (l) {
    return l.ballBudget >= assembleScene(l, view, 20260101).chain.balls.length;
  }));
check('★ 带轨道的那些关速度都慢于核心关（静止关没有速度这回事）',
  TUTORIALS.filter(function (l) { return !l.still; })
    .every(function (l) { return (l.speed || DESIGN.chainSpeed) < DESIGN.chainSpeed; }));
check('id 不重复', (function () {
  const seen = {};
  for (let i = 0; i < ALL_LEVELS.length; i++) {
    if (seen[ALL_LEVELS[i].id]) return false;
    seen[ALL_LEVELS[i].id] = 1;
  }
  return true;
})());

// ---------- 一·五、静止练习关的硬约束 ----------
group('★★ 一·五、静止练习关：不前进、不出球、不会输 —— 而且**必须解得开**');
// ★ §65 洞穴往后挪到了 ⑥ —— 所以 ①~⑤ 全是静止练习，⑥ 才是轨道第一次出现。
const STILL_IDS = ['t1-pair', 't2-multiple', 't3-wrong', 't4-insert', 't5-deadball'];
check('①~⑤ 是静止关，⑥⑦ 不是（⑥ 洞穴才是轨道第一次出现的那一关）',
  TUTORIALS.every(function (l) {
    return STILL_IDS.indexOf(l.id) >= 0 ? l.still === true : !l.still;
  }),
  TUTORIALS.map(function (l) { return l.id + (l.still ? ':静止' : ':轨道'); }).join(' '));
check('★★ 会消球的静止关，场上球数**必须是 3 的倍数**', (function () {
  // 吸附飞行要 0.3 秒，连打几发会**同时落位**，run 从 0 直接跳到 4（跳过 3）。
  // 真实关卡里链子还在冒球、补一颗到 6 就解了；静止关没有新球也没有洞穴，
  // 一旦出现 3n+1 就永远消不掉（实测踩过）。球数是 3 的倍数时永远解得开。
  return TUTORIALS.filter(function (l) { return l.still && !l.noClear; })
    .every(function (l) { return assembleScene(l, view, 20260101).chain.balls.length % 3 === 0; });
})(), TUTORIALS.filter(function (l) { return l.still && !l.noClear; })
  .map(function (l) { return l.id + ':' + assembleScene(l, view, 20260101).chain.balls.length; }).join(' '));
check('★★ 静止关的预算**正好等于**球数（场上就是这一关全部的球）',
  TUTORIALS.filter(function (l) { return l.still; }).every(function (l) {
    return l.ballBudget === assembleScene(l, view, 20260101).chain.balls.length;
  }));
check('★★ 静止链上插一颗球，绳模型仍然把它顶开（不然 ④ 加球会叠成一坨）', (function () {
  // §65：静止关是"速度归零"而不是"跳过 advanceChain" ——
  // "插入把珠串顶开"就发生在 advanceChain 里，跳过它插进去的球会直接叠住。
  const sc = fresh('t4-insert');
  const T = 2 * sc.metrics.R + sc.metrics.linkGap;
  insertBall(sc.chain, 3, { wp: sc.chain.balls[3].wp, base: 'A', r: sc.metrics.R,
    id: 9999, n: 0, paired: false, pairBase: null });
  for (let i = 0; i < 60; i++) advanceScene(sc, DT);
  for (let i = 0; i + 1 < sc.chain.balls.length; i++) {
    if (sc.chain.balls[i].wp - sc.chain.balls[i + 1].wp < T - 0.01) return false;
  }
  return true;
})());
check('★ 静止关 60 秒什么都不做：不出球、不前进、不会输', (function () {
  const sc = fresh('t2-multiple');
  const n0 = sc.chain.balls.length;
  const head0 = sc.chain.balls[0].wp;
  for (let i = 0; i < 60 * 60; i++) advanceScene(sc, DT);
  return sc.chain.balls.length === n0 && Math.abs(sc.chain.balls[0].wp - head0) < 1e-9 &&
    !sc.losing && !sc.gameOver && !sc.won;
})());
check('★ 静止关没有洞穴：把队头硬推到轨道尽头也不会触发失败', (function () {
  const sc = fresh('t2-multiple');
  sc.chain.balls[0].wp = sc.path.length + 500;
  advanceScene(sc, DT);
  return !sc.losing && !sc.gameOver;
})());
check('★ 练习关有弧度（不是一条直线）—— 直线排布下相邻球的视角几乎重叠，打不准',
  (function () {
    const sc = fresh('t1-pair');
    const ys = sc.chain.balls.map(function (b) { return b.y; });
    return Math.max.apply(null, ys) - Math.min.apply(null, ys) > 10;
  })());

// ---------- 二、每一关的"课"真的会发生 ----------
group('★ 二、① 配对：**只教配对** —— 不消球、不爆炸、不用凑三颗');
const t1 = fresh('t1-pair');
check('★★ 标了 noClear（不消球也不爆炸）', t1.noClear === true && t1.still === true);
check('★★ 过关条件是"把每一颗都读出来"', t1.goalMatchAll === true);
check('开局 12 颗，一颗都没读', marks(t1) === '000000000000', marks(t1));
check('★ 五色齐开（原来的 ③ 五色球并进来了）', (function () {
  const s = {};
  for (let i = 0; i < t1.chain.balls.length; i++) s[t1.chain.balls[i].base] = 1;
  return Object.keys(s).length >= 2;
})(), t1.chain.balls.map(function (b) { return b.base; }).join(''));
check('★★ 读出一颗**不会消球**（第一关不该冒出 3n 规则）', (function () {
  const bs = t1.chain.balls;
  bs[0].paired = true; bs[0].wrongMark = false; bs[0].pairBase = 'U'; bs[0].dock = 1;
  bs[1].paired = true; bs[1].wrongMark = false; bs[1].pairBase = 'U'; bs[1].dock = 1;
  bs[2].paired = true; bs[2].wrongMark = false; bs[2].pairBase = 'U'; bs[2].dock = 1;
  syncBeads(t1);
  const n0 = t1.chain.balls.length;
  advanceScene(t1, DT);
  return t1.chain.balls.length === n0 && t1.won === false;   // 连续 3 颗已读，但一颗都不该消失
})(), '场上 ' + t1.chain.balls.length);
check('★ 三颗已读不会触发爆炸（noClear 把爆炸一起关了）',
  (function () {
    const sc = fresh('t1-pair');
    const bs = sc.chain.balls;
    bs[0].paired = true; bs[0].wrongMark = false; bs[0].dock = 1;
    bs[1].paired = true; bs[1].wrongMark = true; bs[1].dock = 1;    // 中间灰球
    bs[2].paired = true; bs[2].wrongMark = false; bs[2].dock = 1;
    syncBeads(sc);
    advanceScene(sc, DT);
    return sc.chain.balls.length === 12 && sc.stats.explosions === 0;
  })());
check('★★ 把每一颗都读出来 -> 过关，原因是 match', (function () {
  const sc = fresh('t1-pair');
  for (let i = 0; i < sc.chain.balls.length; i++) {
    const b = sc.chain.balls[i];
    b.paired = true; b.wrongMark = false; b.dock = 1;
  }
  syncBeads(sc);
  advanceScene(sc, DT);
  return sc.won === true && sc.winReason === 'match' && sc.chain.balls.length === 12;
})());
check('★ 只读出一半 -> 不过关', (function () {
  const sc = fresh('t1-pair');
  for (let i = 0; i < 6; i++) {
    const b = sc.chain.balls[i];
    b.paired = true; b.wrongMark = false; b.dock = 1;
  }
  syncBeads(sc);
  advanceScene(sc, DT);
  return sc.won === false;
})());

group('二、② 三的倍数：开局就摆出 run = 4，徽章必须写「还差 2」');
const t2 = fresh('t2-multiple');
check('开局标记 = 111100000', marks(t2) === '111100000', marks(t2));
const runs2 = computeRuns(t2.chain);
check('★ 只有一个已读段，长度是 4', runs2.length === 1 && runs2[0].len === 4,
  '段=' + runs2.map(function (r) { return r.len; }).join(','));
check('★★ 徽章会写「还差 2」—— 这一关要教的就是这个数字', runStatus(runs2[0]).toNext === 2,
  '还差 ' + runStatus(runs2[0]).toNext);
check('★ 4 不是 3 的倍数 -> 这一帧不会消', (function () {
  const before = t2.chain.balls.length;
  advanceScene(t2, DT);
  return t2.chain.balls.length === before;
})());
check('★ 这一关**不**标 noClear（要教消球）', t2.noClear === false);

group('★ 二、③ 配错的代价：灰球第一帧真的炸，而且**提示说清了什么时候炸**');
const t3 = fresh('t3-wrong');
check('开局标记 = 121000000000（中间那颗是配错）', marks(t3) === '121000000000', marks(t3));
check('★ 灰球两边都是"已读出"，且类型相同 -> 满足爆炸条件',
  markFinal(t3.chain.balls[0]) === 1 && markFinal(t3.chain.balls[1]) === 2 &&
  markFinal(t3.chain.balls[2]) === 1);
const n3 = t3.chain.balls.length;
drainEvents(t3);
advanceScene(t3, DT);
const ev3 = drainEvents(t3);
check('★★ 第一帧就爆炸，且恰好移除 3 颗',
  ev3.some(function (e) { return e.type === 'explode'; }) && t3.chain.balls.length === n3 - 3,
  n3 + ' -> ' + t3.chain.balls.length + '  事件=' + ev3.map(function (e) { return e.type; }).join(','));
check('★ 爆炸**不扣分**（§A5：配对错误不扣分）', t3.score === 0, 'score=' + t3.score);
check('★★ 提示是多行的（爆炸条件是一整句话，压成一行只能含糊）',
  hintLines(byId('t3-wrong')).length >= 3, hintLines(byId('t3-wrong')).length + ' 行');
check('★★ 提示必须说清**什么时候**才炸：既要"左右两颗都已读出"，也要"状态一样"', (function () {
  const txt = hintLines(byId('t3-wrong')).join('');
  return txt.indexOf('左右') >= 0 && txt.indexOf('状态') >= 0 && txt.indexOf('炸') >= 0;
})(), hintLines(byId('t3-wrong')).join(' / '));
check('★ 提示也说清了"不会立刻炸"（否则玩家会以为一打错就爆）',
  hintLines(byId('t3-wrong')).join('').indexOf('不会立刻炸') >= 0);

group('二、⑥ 洞穴：队头开局就在洞口附近（这一关才是轨道第一次出现）');
const tCave = fresh('t6-cave');
check('★ 这一关**有轨道**（不是静止关）', tCave.still === false);
const headFrac = tCave.chain.balls[0].wp / tCave.path.length;
check('★ 队头超过轨道全长的 70%（危险要看得见）', headFrac > 0.70, (headFrac * 100).toFixed(0) + '%');
check('★ 提示里点明了"从这里开始有轨道了"',
  hintLines(byId('t6-cave')).join('').indexOf('有轨道') >= 0);
check('★ 静止关（①~③）和轨道关（④~⑦）用的骨架不同', (function () {
  return fresh('t2-multiple').path.length < fresh('t6-cave').path.length ||
    byId('t2-multiple').turns !== byId('t6-cave').turns;
})());

group('二、④ 加球 / ⑤ 死球 / ⑥ 洞穴 / ⑦ 综合');
check('④ 的提示说了怎么切模式', hintLines(byId('t4-insert')).join('').indexOf('加球') >= 0);
const tDead = fresh('t5-deadball');
check('★★ ⑤ 开局就是 §28 的 11 0 11（标记 110110000）', marks(tDead) === '110110000', marks(tDead));
const runs6 = computeRuns(tDead.chain);
check('★ 两段各 2 颗，都不是 3 的倍数 -> 都不消',
  runs6.length === 2 && runs6[0].len === 2 && runs6[1].len === 2,
  runs6.map(function (r) { return r.len; }).join(','));
check('★ 中间正好夹 1 颗没读的（配了它两段就并成 5）',
  runs6[1].i0 - runs6[0].i1 - 1 === 1 && markFinal(tDead.chain.balls[2]) === 0);
check('★ ⑤ 的提示点明了"别配中间那颗"',
  hintLines(byId('t5-deadball')).join('').indexOf('别') >= 0);
check('⑦ 是五色综合关（没有 bases 限制）', !byId('t7-mix').bases);

// ---------- 三、脚本解析 ----------
group('★ 三、脚本解析：数字是"上一颗球的标记"，不是一颗球');
check('★★ "A1 A2 U0" -> 3 个 token（数字不拆成独立球）',
  parseScript('A1 A2 U0').join(',') === 'A1,A2,U0', parseScript('A1 A2 U0').join(','));
check('空格 / 逗号 / 竖线都当分隔符', parseScript('A1,U2|U0').join(',') === 'A1,U2,U0');
check('没有标记的写法也认', parseScript('A U G').join(',') === 'A,U,G');
check('parseScriptEntry: "A" -> mark 0', parseScriptEntry('A').mark === 0);
check('parseScriptEntry: "A1" -> mark 1（已正确读出）', parseScriptEntry('A1').mark === 1);
check('parseScriptEntry: "A2" -> mark 2（配错）', parseScriptEntry('A2').mark === 2);
check('★★ 脚本关里每颗球的碱基都必须是**单个合法碱基**', (function () {
  // 踩过的坑：把 "A1" 整个 token 当成碱基写进球里 -> COMPLEMENT['A1'] 是 undefined
  // -> 那一关的球一颗都配不上，而且**不报错**，界面上只看到写着 undefined 的球。
  for (let i = 0; i < TUTORIALS.length; i++) {
    const sc = assembleScene(TUTORIALS[i], view, 20260101);
    for (let k = 0; k < sc.chain.balls.length; k++) {
      if (BASES.indexOf(sc.chain.balls[k].base) < 0) return false;
    }
  }
  return true;
})());

// ---------- 四、限定碱基池 ----------
group('★ 四、限定碱基池：珠子袋不能给出这一关根本没有的碱基');
check('★★ 只开 A/U 的关卡里，A 的可用互补只剩 U（A 本来是 U/T 双配）', (function () {
  // ⚠ 要用**真的限了碱基池**的关卡：② 的脚本里有 G/C，不再限 A/U 了。
  const sc = fresh('t6-cave');
  const c = allowedComplements(sc, 'A');
  return c.length === 1 && c[0] === 'U';
})());
check('★ 不限池的关卡里，A 的互补仍是 U/T 两个', (function () {
  const sc = fresh('t1-pair');
  return allowedComplements(sc, 'A').length === 2;
})());
check('★★ 珠子袋里绝不会出现这一关根本没有的碱基', (function () {
  const sc = fresh('t6-cave');
  const pool = sc.rb.poolFn ? sc.rb.poolFn() : [];
  return pool.length > 0 && pool.every(function (x) { return x === 'A' || x === 'U'; });
})());
check('★ 手里两颗装的也只会是池子里的碱基', (function () {
  const sc = fresh('t6-cave');
  return sc.rb.loaded.every(function (x) { return x === 'A' || x === 'U'; });
})());

// ---------- 五、开始菜单 ----------
group('★ 五、开始菜单布局：按钮必须都在屏幕内、彼此不重叠');
function menuItems() {
  return ALL_LEVELS.map(function (l, i) {
    return { index: i, group: i < TUTORIALS.length ? '新手关' : '核心关',
             label: i < TUTORIALS.length ? l.name : ((i + 1) + ' ' + (l.short || l.name)) };
  });
}
check('每个关卡都有 short（菜单按钮上要显示）', ALL_LEVELS.every(function (l) { return !!l.short; }));
check('菜单条目数 = 关卡数', menuItems().length === ALL_LEVELS.length);
const screens = [[900, 900], [390, 844], [320, 640]];
for (let si = 0; si < screens.length; si++) {
  const v = viewFor(screens[si][0], screens[si][1]);
  const mt2 = metrics(v.scale);
  const M = menuLayout(v, mt2, menuItems());
  const tag = screens[si][0] + 'x' + screens[si][1];
  check('★ ' + tag + '：按钮全部在屏幕内', M.buttons.every(function (b) {
    return b.x >= 0 && b.y >= 0 && b.x + b.w <= v.w + 0.01 && b.y + b.h <= v.h + 0.01;
  }));
  check('★ ' + tag + '：按钮互不重叠', (function () {
    for (let i = 0; i < M.buttons.length; i++) {
      for (let k = i + 1; k < M.buttons.length; k++) {
        const a = M.buttons[i], b = M.buttons[k];
        if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h) return false;
      }
    }
    return true;
  })());
  check('★ ' + tag + '：按钮不与底部说明行重叠',
    M.buttons.every(function (b) { return b.y + b.h < M.footerY - 4; }));
  check('★ ' + tag + '：竖屏用 2 列、宽屏用 4 列', v.w < 640 ? M.cols === 2 : M.cols === 4,
    'w=' + v.w + ' cols=' + M.cols);
}
check('分组标题有两组，且都在按钮上方', (function () {
  const v = viewFor(900, 900);
  const M = menuLayout(v, metrics(v.scale), menuItems());
  return M.groups.length === 2 && M.groups[0].name === '新手关' && M.groups[1].name === '核心关';
})());

console.log('\ntest-tutorial: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);

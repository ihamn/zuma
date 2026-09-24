// U6/U7/U8 单元 + 集成测试。用法：node tools/test-shot.mjs
// 覆盖：真实碱基配对表、扫掠碰撞（防穿透/最近优先/已配对穿透）、核糖体双珠与冷却、吸附飞行、端到端命中。

import { BASES, COMPLEMENT, isComplement, metrics, viewFor, DESIGN, BASE_COLOR, complementColor, modeButtonRect } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { assembleScene, syncBeads, advanceScene, fireShot, drainEvents, usefulPool, weightedPool, setMode } from '../src/scene.js';
import { makeRibosome, aimAt, swapLoaded, fire, tickRibosome, drawBase } from '../src/ribosome.js';
import { makeProjectile, advanceProjectile, sweepHit } from '../src/projectile.js';
import { makeRng } from '../src/rng.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

// 本文件默认用**匹配模式**（DESIGN.defaultMode）；只有「不互补 -> 并入」那两条临时切到加球模式
const mt = metrics(1);
const view = viewFor(900, 900);
const DT = 1 / 60;

// ---------- A16：配对表 = 真实碱基 ----------
group('A16 配对表：A-U / A-T / G≡C');
const real = { 'A|U': 1, 'U|A': 1, 'A|T': 1, 'T|A': 1, 'G|C': 1, 'C|G': 1 };
let tableOk = true, wrong = [];
for (let i = 0; i < BASES.length; i++) {
  for (let j = 0; j < BASES.length; j++) {
    const got = isComplement(BASES[i], BASES[j]) ? 1 : 0;
    const want = real[BASES[i] + '|' + BASES[j]] || 0;
    if (got !== want) { tableOk = false; wrong.push(BASES[i] + '|' + BASES[j]); }
  }
}
check('25 组合全部符合真实碱基配对', tableOk, wrong.length ? ('不符: ' + wrong.join(',')) : '25/25');
check('A 是唯一双配碱基', COMPLEMENT.A.length === 2 && COMPLEMENT.U.length === 1 && COMPLEMENT.T.length === 1);
check('配对关系对称', BASES.every(function (a) {
  return COMPLEMENT[a].every(function (b) { return COMPLEMENT[b].indexOf(a) >= 0; });
}));
check('同碱基永远不配对（A-A / U-U …）', BASES.every(function (a) { return !isComplement(a, a); }));

// ---------- 互补碱基的颜色互为反色 ----------
group('★ 互补碱基的颜色必须互为反色（色相相差约 180 度）');
function hueOf(hex) {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  if (d === 0) return 0;
  let h;
  if (mx === r) h = ((g - b) / d) % 6;
  else if (mx === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return ((h * 60) + 360) % 360;
}
let devs = [], worst = 0;
for (let i = 0; i < BASES.length; i++) {
  const b = BASES[i];
  for (let k = 0; k < COMPLEMENT[b].length; k++) {
    const p = COMPLEMENT[b][k];
    const raw360 = ((hueOf(BASE_COLOR[p]) - hueOf(BASE_COLOR[b])) % 360 + 360) % 360;
    const dev = Math.abs(raw360 - 180);
    devs.push(b + '->' + p + ' 偏' + dev.toFixed(0) + '度');
    worst = Math.max(worst, dev);
  }
}
check('★★ 每一对互补碱基的色相都相差约 180 度（偏差 < 35 度）', worst < 35, devs.join('  '));
check('五种碱基的颜色互不相同（字母之外的第二通道）', (function () {
  const seen = {};
  for (let i = 0; i < BASES.length; i++) { if (seen[BASE_COLOR[BASES[i]]]) return false; seen[BASE_COLOR[BASES[i]]] = 1; }
  return true;
})());
check('complementColor() 返回的就是配对对象的颜色',
  complementColor('A') === BASE_COLOR[COMPLEMENT.A[0]] && complementColor('G') === BASE_COLOR['C'] && complementColor('C') === BASE_COLOR['G'],
  'A->' + complementColor('A') + '  G->' + complementColor('G') + '  C->' + complementColor('C'));

// ---------- 回归：模式优先于化学 ----------
group('★ 回归：先看模式，再看化学（曾经把 isComplement 放在最前面）');
check('★★ 加球模式下打中一颗**恰好互补**的球 -> 仍然并入，不配对',
  (function () {
    const _m = DESIGN.defaultMode;
    DESIGN.defaultMode = 'insert';
    const r = shootAt('A', 'U');        // U 与 A 互补 —— 若分支顺序错了就会配对
    DESIGN.defaultMode = _m;
    const paired = r.sc.chain.balls.some(function (b) { return b.paired === true; });
    return r.sc.stats.merges === 1 && r.sc.stats.pairs === 0 && !paired &&
           r.evs.some(function (e) { return e.type === 'insert'; });
  })());
check('加球模式默认不产生配对（insertPairs=false，语义彻底分离）',
  DESIGN.insertPairs === false);
check('★ 匹配模式下同一发仍然是配对（模式确实分流了）',
  (function () {
    const _m = DESIGN.defaultMode;
    DESIGN.defaultMode = 'match';
    const r = shootAt('A', 'U');
    DESIGN.defaultMode = _m;
    return r.sc.stats.pairs === 1 && r.sc.stats.merges === 0;
  })());
check('切模式会让按钮闪一下（modeFlash 被点亮）',
  (function () {
    const sc = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
    setMode(sc, 'insert');
    return sc.modeFlash > 0;
  })());

// ---------- 过期刷新 + 加权池（DESIGN.md §54）----------
group('★★ 过期刷新：手里这颗若已无目标，自动换成当前池子里能用的');
// 为什么必须有：珠子是上一发时抽的备用珠，等它被顶上来目标早没了。
// 实测修之前 **85.7% 的帧手里这颗没有可打的目标**，发射率 0.87 发/秒（冷却允许 6.3），
// 清球 0.70 颗/秒 < 冒球 1.06 颗/秒 -> 链子无限增长、必输。这不是难度问题，是弹药对不上目标。
function bagScene(base) {
  const sc = assembleScene(LEVELS[0], viewFor(900, 900), 20260101);
  sc.stopAdding = true;
  sc.level.ballBudget = 0;
  sc.chain.balls = [0, 1, 2].map(function (i) {
    return { wp: (2 - i) * 39.5 + 300, base: base, r: sc.metrics.R, id: 800 + i,
      paired: false, wrongMark: false, pairBase: null, dock: null };
  });
  sc.chain.nextId = 900;
  syncBeads(sc);
  return sc;
}
check('★ 手里是用不上的珠子（场上只有 A，手里 C）-> 会被换成能用的',
  (function () {
    const sc = bagScene('A');
    sc.rb.loaded = ['C', 'C'];
    tickRibosome(sc.rb, 1 / 60);
    return sc.rb.loaded.every(function (b) { return b === 'U' || b === 'T'; });
  })());
check('手里本来就是能用的 -> 不会被换掉',
  (function () {
    const sc = bagScene('A');
    sc.rb.loaded = ['U', 'T'];
    tickRibosome(sc.rb, 1 / 60);
    return sc.rb.loaded[0] === 'U' && sc.rb.loaded[1] === 'T';
  })());
check('场上没有未配对的球时不乱换（没有池子可用）',
  (function () {
    const sc = bagScene('A');
    for (const b of sc.chain.balls) b.paired = true;
    syncBeads(sc);
    sc.rb.loaded = ['C', 'C'];
    tickRibosome(sc.rb, 1 / 60);
    return sc.rb.loaded[0] === 'C' && sc.rb.loaded[1] === 'C';
  })());
check('★ 加权池按目标数量加权（不去重）：3 颗 A -> 池子里 3 个 U/T 条目',
  (function () {
    const sc = bagScene('A');
    const pool = weightedPool(sc);
    return pool.length === 6 && pool.every(function (b) { return b === 'U' || b === 'T'; });
  })());

// ---------- 模式按钮几何 ----------
group('★ 模式按钮：几何在屏幕内、不压核糖体（render 画、main 判点击共用同一份）');
check('900x900 下按钮圆心在屏幕内、半径合理',
  (function () {
    const b = modeButtonRect(viewFor(900, 900), metrics(1));
    return b.x > 0 && b.x < 900 && b.y > 0 && b.y < 900 && b.r > 8;
  })());
check('★ 手机 400x850（scale 0.82）下也在屏幕内',
  (function () {
    const v = viewFor(400, 850);
    const b = modeButtonRect(v, metrics(v.scale));
    return b.x > 0 && b.x < 400 && b.y > 0 && b.y < 850;
  })());
check('按钮离核糖体（视口中心）足够远，不会误触',
  (function () {
    const v = viewFor(400, 850);
    const b = modeButtonRect(v, metrics(v.scale));
    return Math.hypot(b.x - v.cx, b.y - v.cy) > b.r * 3;
  })());

// ---------- 珠子袋不重复 ----------
group('★ 珠子袋：补的那颗不与手里那颗重复（DESIGN.md §39）');
check('池子里有别的碱基时，补的珠子 != 手里那颗',
  (function () {
    const rb2 = makeRibosome(0, 0, metrics(1), makeRng(7));
    rb2.poolFn = function () { return ['A', 'U']; };
    rb2.loaded = ['A', null];
    let ok = true;
    for (let k = 0; k < 40; k++) { if (drawBase(rb2) === 'A') ok = false; }
    return ok;
  })());
check('池子里只有一种时，只能给那一种（不硬凑）',
  (function () {
    const rb2 = makeRibosome(0, 0, metrics(1), makeRng(7));
    rb2.poolFn = function () { return ['A'] };
    rb2.loaded = ['A', null];
    return drawBase(rb2) === 'A';
  })());
check('★ 开局长局端到端：两颗手里珠子不重复（3 个种子各查 20 次补珠）',
  (function () {
    const seeds = [20260101, 4242, 909090];
    for (const sd of seeds) {
      const sc2 = assembleScene(LEVELS[0], viewFor(900, 900), sd);
      if (sc2.rb.loaded[0] === sc2.rb.loaded[1]) return false;
      for (let k = 0; k < 20; k++) {
        if (sc2.rb.poolFn().length > 1 && sc2.rb.loaded[0] === sc2.rb.loaded[1]) return false;
      }
    }
    return true;
  })());

// ---------- U7 扫掠碰撞 ----------
group('U7 扫掠碰撞：不穿透 / 最近优先 / 已配对穿透');
const balls = [
  { x: 100, y: 0, r: 19, paired: false },
  { x: 300, y: 0, r: 19, paired: false },
  { x: 500, y: 0, r: 19, paired: false }
];
check('正面命中', !!sweepHit(balls, 0, 0, 200, 0, 12));
check('打偏不命中', sweepHit(balls, 0, 200, 600, 200, 12) === null);
const far = sweepHit(balls, 0, 0, 5000, 0, 12);
check('一帧扫过 5000px 仍命中最近的那颗（不穿透）', !!far && far.index === 0, far ? ('t=' + far.t.toFixed(4)) : 'null');
const mid = sweepHit(balls, 0, 0, 1000, 0, 12);
check('取最先撞上的（index=0 而非 2）', mid && mid.index === 0, 'index=' + (mid ? mid.index : 'null'));
const onlyFar = sweepHit([{ x: 100, y: 0, r: 19, paired: true }, balls[1]], 0, 0, 1000, 0, 12);
check('已配对的球是惰性的，弹丸直接穿过', onlyFar && onlyFar.index === 1, 'index=' + (onlyFar ? onlyFar.index : 'null'));
check('空数组不炸', sweepHit([], 0, 0, 10, 10, 5) === null);

// ---------- U6 核糖体 ----------
group('U6 核糖体：双珠待命 / 冷却 / 瞄准');
const rng = makeRng(7);
const rb = makeRibosome(0, 0, mt, rng);
check('初始两颗待命', rb.loaded.length === 2 && BASES.indexOf(rb.loaded[0]) >= 0 && BASES.indexOf(rb.loaded[1]) >= 0);
const before = [rb.loaded[0], rb.loaded[1]];
const shot = fire(rb);
check('发射打出口中第一颗', shot && shot.base === before[0]);
check('第二颗顶上来、再补一颗', rb.loaded[0] === before[1] && BASES.indexOf(rb.loaded[1]) >= 0);
check('冷却期内拒绝发射', fire(rb) === null, 'cooldown=' + rb.cooldown.toFixed(3) + 's');
for (let i = 0; i < Math.ceil(DESIGN.fireCooldown / DT) + 1; i++) tickRibosome(rb, DT);
check('冷却结束后可再发', fire(rb) !== null);
const rb2 = makeRibosome(0, 0, mt, makeRng(9));
const a0 = rb2.loaded[0], a1 = rb2.loaded[1];
swapLoaded(rb2);
check('空格/右键交换两颗', rb2.loaded[0] === a1 && rb2.loaded[1] === a0);
aimAt(rb2, 0, -10);
check('向上瞄准 = -90°', Math.abs(rb2.aim + Math.PI / 2) < 1e-9, 'aim=' + (rb2.aim * 180 / Math.PI).toFixed(1) + '°');
aimAt(rb2, 10, 0);
check('向右瞄准 = 0°', Math.abs(rb2.aim) < 1e-9);

// ---------- 集成 ----------
group('端到端：只留一颗球的受控场景');
function soloScene(base) {
  const sc = assembleScene(LEVELS[0], view, 20260101);
  sc.chain.balls.length = 0;
  sc.chain.balls.push({ wp: 200, base: base, r: sc.metrics.R, id: 1, n: 0, paired: false, pairBase: null, dock: null });
  syncBeads(sc);
  return sc;
}

function shootAt(targetBase, firedBase) {
  const sc = soloScene(targetBase);
  const target = sc.beads.spawn[0];
  sc.rb.loaded[0] = firedBase;
  sc.rb.cooldown = 0;
  aimAt(sc.rb, target.x, target.y);
  const p = fireShot(sc);
  const evs = [];
  for (let f = 0; f < 90; f++) {
    advanceScene(sc, DT);
    const got = drainEvents(sc);
    for (let i = 0; i < got.length; i++) evs.push(got[i]);
    if (evs.length > 0) break;
  }
  return { sc: sc, evs: evs, shot: p };
}

const hitPair = shootAt('A', 'U');       // A 应当被 U 配对
check('互补命中 -> 记录 pair 事件', hitPair.evs.length === 1 && hitPair.evs[0].type === 'pair',
  hitPair.evs.map(function (e) { return e.type + '(' + e.base + '->' + e.target + ')'; }).join(','));
check('目标球被标记为已配对', hitPair.sc.chain.balls[0].paired === true);
check('配对碱基被记录（tRNA 侧）', hitPair.sc.chain.balls[0].pairBase === 'U');
const eb = hitPair.sc.beads.eliminate[0];
const bigBase = hitPair.sc.chain.balls[0].base;
check('★★ 小球的颜色 = 伙伴颜色的反色（由调色板保证，不需要覆写）',
  !!eb && BASE_COLOR[eb.base] === complementColor(bigBase),
  eb ? ('大球 ' + bigBase + ' 色=' + BASE_COLOR[bigBase] + '   小球 ' + eb.base + ' 色=' + BASE_COLOR[eb.base] + '   互补色=' + complementColor(bigBase)) : 'n/a');
check('★ 被配对的大球带上「该发什么色」的描边提示',
  hitPair.sc.chain.balls[0].pairGlow === complementColor(bigBase),
  'pairGlow=' + hitPair.sc.chain.balls[0].pairGlow + '  期望=' + complementColor(bigBase));
check('stats.pairs 累加', hitPair.sc.stats.pairs === 1 && hitPair.sc.stats.mismatches === 0);

const hitAT = shootAt('A', 'T');         // A 也可以被 T 配对（A 双配）
check('A 也能被 T 配对', hitAT.evs.length === 1 && hitAT.evs[0].type === 'pair');

// ★ 模式切换（DESIGN.md §46）：只有这一条链路要验证"并入"，临时切到加球模式。
//   匹配模式下的不互补命中会记成**错误配对（mark=2）**，不再并入。
const _savedMode = DESIGN.defaultMode;
DESIGN.defaultMode = 'insert';
const hitBad = shootAt('G', 'U');        // G 只能被 C 配对
DESIGN.defaultMode = _savedMode;
const insEv = hitBad.evs.filter(function (e) { return e.type === 'insert'; });
check('加球模式下不互补命中 -> 记录 insert 事件（不是 mismatch：这是主动并入，不是失误）',
  insEv.length === 1 && insEv[0].target === 'G',
  hitBad.evs.map(function (e) { return e.type; }).join(','));
check('不互补 -> 同时触发加球（并入出球道）',
  hitBad.evs.some(function (e) { return e.type === 'merge'; }) && hitBad.sc.stats.merges === 1,
  'merges=' + hitBad.sc.stats.merges);
check('互补命中不会触发加球', hitPair.sc.stats.merges === 0 && hitPair.evs.every(function (e) { return e.type !== 'merge'; }));
check('加球模式下不互补：目标球不被配对', hitBad.sc.chain.balls[0].paired === false);
check('加球模式不计 mismatch 统计（它不是失误）',
  hitBad.sc.stats.mismatches === 0 && hitBad.sc.stats.pairs === 0,
  'mismatches=' + hitBad.sc.stats.mismatches);

// ★ 对照：**匹配模式**下的不互补命中 -> 错误配对（mark = 2），链不变
const _m2 = DESIGN.defaultMode;
DESIGN.defaultMode = 'match';
const hitMm = shootAt('G', 'U');
DESIGN.defaultMode = _m2;
check('★ 匹配模式下不互补命中 -> 记 mismatch + 目标变成错误配对（mark=2），且不并入',
  hitMm.sc.stats.mismatches === 1 && hitMm.sc.stats.merges === 0 &&
  hitMm.sc.chain.balls[0].paired === true && hitMm.sc.chain.balls[0].wrongMark === true,
  'mismatches=' + hitMm.sc.stats.mismatches + ' merges=' + hitMm.sc.stats.merges +
  ' wrongMark=' + hitMm.sc.chain.balls[0].wrongMark);

group('U8 吸附飞行：0 -> 1，用时 = dockTime');
const sc8 = soloScene('A');
const tgt = sc8.beads.spawn[0];
sc8.rb.loaded[0] = 'U';
sc8.rb.cooldown = 0;
aimAt(sc8.rb, tgt.x, tgt.y);
fireShot(sc8);
let f8 = 0;
while (sc8.chain.balls[0].paired !== true && f8 < 90) { advanceScene(sc8, DT); f8 += 1; }
const d0 = sc8.chain.balls[0].dock;
check('命中当帧即进入吸附飞行（0 <= dock < 1）', d0 !== null && d0 >= 0 && d0 < 1, '第 ' + f8 + ' 帧命中 dock=' + d0.toFixed(3));
check('吸附中不算 docked', sc8.beads.eliminate.length === 1 && sc8.beads.eliminate[0].docked === false);
let f9 = 0;
while (!sc8.beads.eliminate[0].docked && f9 < 120) { advanceScene(sc8, DT); f9 += 1; }
check('吸附完成（docked）', sc8.beads.eliminate[0].docked === true, '再花 ' + f9 + ' 帧');
const ebb = sc8.beads.eliminate[0];
const bigb = sc8.chain.balls[0];
const dist = Math.hypot(ebb.x - bigb.x, ebb.y - bigb.y);
check('吸附完成后小球恰好落在三消道上（与大球间距 == 轨距 d）', Math.abs(dist - sc8.metrics.d) < 1e-6,
  '实测 ' + dist.toFixed(6) + ' / 期望 d=' + sc8.metrics.d.toFixed(6));
check('大球与小球半径符合 1:√2（直径比 √2:1）', Math.abs(bigb.r / ebb.r - Math.SQRT2) < 1e-12);
const expectFrames = Math.ceil(DESIGN.dockTime / DT);
check('吸附时长与 dockTime 一致（误差 <= 2 帧）', Math.abs(f9 - expectFrames) <= 2,
  '实测 ' + f9 + ' 帧 / 期望 ' + expectFrames + ' 帧');

group('弹丸生命周期');
const scL = soloScene('A');
scL.chain.balls.length = 0;
syncBeads(scL);
aimAt(scL.rb, 900, 450);
fireShot(scL);
check('打出后弹丸在场', scL.projectiles.length === 1);
let fl = 0;
while (scL.projectiles.length > 0 && fl < 400) { advanceScene(scL, DT); fl += 1; }
check('无命中时会被回收（不无限累积）', scL.projectiles.length === 0, '存活 ' + fl + ' 帧');
check('回收后场景继续推进不炸', (function () { for (let i = 0; i < 120; i++) advanceScene(scL, DT); return true; })());

console.log('');
console.log('test-shot: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


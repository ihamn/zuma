// 无头自检台：mock DOM + mock canvas，跑真实打包产物，验证 600 帧不炸、切关不炸、极端尺寸不炸。
// 用法：node tools/smoke.mjs
// 注意：ctx 是空操作代理，所以这里测的是"逻辑 + 几何"的稳定性，不是真实渲染耗时。

import { modeButtonRect, menuButtonRect, menuLayout } from '../src/config.js';
import vm from 'node:vm';
import { buildHtml } from './build.mjs';

let pass = 0, fail = 0;
function group(t) { console.log('\n[' + t + ']'); }
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}

const built = buildHtml();
const m = built.html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.log('smoke: 打包产物里找不到内联 script'); process.exit(1); }
const code = m[1];

let clock = 0;
let raf = null;
const grad = { addColorStop: function () {} };
// ★ 录下所有 fillText 的文案 —— HUD 写错字（比如把 Infinity 印到"分数 / 目标"里）
//   在空操作代理上是**看不出来**的，只能靠把文案截下来断言。
const texts = [];
const ctxTarget = {
  canvas: null,
  fillText: function (t) { texts.push(String(t)); },
  createLinearGradient: function () { return grad; },
  createRadialGradient: function () { return grad; },
  createPattern: function () { return null; },
  measureText: function () { return { width: 10 }; }
};
const ctx = new Proxy(ctxTarget, {
  get: function (t, p) { if (p in t) return t[p]; return function () {}; },
  set: function (t, p, v) { t[p] = v; return true; }
});
const canvasListeners = {};
const canvas = {
  width: 0, height: 0, style: {},
  getContext: function () { return ctx; },
  addEventListener: function (t, fn) { (canvasListeners[t] = canvasListeners[t] || []).push(fn); },
  getBoundingClientRect: function () { return { left: 0, top: 0, width: 900, height: 900 }; }
};
const documentMock = {
  getElementById: function () { return canvas; },
  addEventListener: function () {},
  createElement: function () { return canvas; },
  querySelector: function () { return canvas; },
  body: { appendChild: function () {} }
};
const sandbox = {
  console: console,
  document: documentMock,
  devicePixelRatio: 1,
  innerWidth: 900,
  innerHeight: 900,
  performance: { now: function () { return clock; } },
  requestAnimationFrame: function (cb) { raf = cb; return 1; },
  cancelAnimationFrame: function () {},
  addEventListener: function () {},
  removeEventListener: function () {},
  setTimeout: setTimeout,
  clearTimeout: clearTimeout
};
sandbox.window = sandbox;

vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'zuma.bundle.js' });

const Z = sandbox.__ZUMA__;
check('注入 __ZUMA__ 调试钩子', !!Z);
if (!Z) process.exit(1);

// ★★ §61 开局在开始菜单 —— 这一步**不能省**：
//   菜单态下 update() 不推进场景，忘了先开始游戏的话，后面所有"帧在推进"的断言
//   都会静默失败（而且看起来像是物理坏了）。
group('★ 开始菜单（§61）');
check('★ 开局在菜单，不是直接进游戏', Z.screen === 'menu', 'screen=' + Z.screen);
check('★ 菜单条目 = 全部关卡（7 新手 + 正式关）', (Z.menuItems || []).length === Z.levelCount,
  '条目=' + (Z.menuItems || []).length);
check('★ 菜单条目分了两组', (function () {
  const g = {};
  (Z.menuItems || []).forEach(function (it) { g[it.group] = (g[it.group] || 0) + 1; });
  return g['新手关'] === 7 && g['核心关'] === Z.levelCount - 7;   // 2026-09-25 删了 spiral-outer：核心关 4 → 3
})(), (Z.menuItems || []).map(function (i) { return i.group; }).filter(function (v, i, a) { return a.indexOf(v) === i; }).join('/'));
const _headMenu = Z.state.sc.chain.balls[0].wp;
pump(90);
check('★★ 菜单态下场景**不推进**（否则挑关卡时链子自己爬进洞口了）',
  Math.abs(Z.state.sc.chain.balls[0].wp - _headMenu) < 1e-9,
  _headMenu.toFixed(1) + ' -> ' + Z.state.sc.chain.balls[0].wp.toFixed(1));
// 菜单态渲染不许抛异常（画的是场景 + 暗幕 + 12 个按钮）
check('★ 菜单态渲染不抛异常', (function () {
  try { Z.renderOnce(); return true; } catch (e) { return false; }
})());
// 菜单**真的把内容画出来了**（不是一片黑的空屏）
texts.length = 0;
Z.renderOnce();
check('★ 菜单画了标题', texts.some(function (t) { return t.indexOf('RNA 祖玛') >= 0; }),
  texts.filter(function (t) { return t.indexOf('RNA') >= 0; }).join('/') || '(没画)');
check('★ 菜单画了关卡按钮的标签', texts.some(function (t) { return t.indexOf('① 配对') >= 0; }),
  '① 配对');
check('★ 菜单画了分组标题', texts.indexOf('新手关') >= 0 && texts.indexOf('核心关') >= 0);
check('★ 菜单态**不画局内 HUD**（关卡名/分数不该从菜单后面透出来）',
  !texts.some(function (t) { return t.indexOf('待出') >= 0 || t.indexOf('命中:') >= 0; }));
// ★ §63 注意：第 1~4 关是**静止练习关**（链子不动、没有洞穴）。
//   下面的物理/洞穴测试必须跑在**核心关**上，所以这里从第一个核心关开始。
//   （踩过一次：忘了这件事的话，"珠串在滚动"和"洞穴吞球"会一起失败。）
const CORE0 = Z.levelCount - 3;   // ★ 2026-09-25：核心关只剩 3 个（删了 spiral-outer）
check('★ 第 1 关是静止练习关（不前进、没有洞穴）', Z.state.level.still === true,
  '关卡=' + Z.state.level.name);
Z.start(CORE0);                  // <- 从这里开始才是"在玩"
check('★ start(0) 进入游戏', Z.screen === 'play' && Z.state.screen === 'play', 'screen=' + Z.screen);
pump(1);

function pump(n) {
  for (let i = 0; i < n; i++) {
    clock += 1000 / 60;
    const cb = raf;
    if (!cb) throw new Error('rAF 队列空了：主循环没有续帧');
    raf = null;
    cb(clock);
  }
}

const t0 = process.hrtime.bigint();
pump(600);
const ms = Number(process.hrtime.bigint() - t0) / 1e6;
check('600 帧无异常', Z.frameCount >= 600, Z.frameCount + ' 帧 / ' + ms.toFixed(0) + 'ms（含 mock 渲染）');

const S = Z.state;
const ci = Z.state.chainInfo;
check('珠串在滚动（600 帧后队头已推进）', !!ci && ci.headWp > 0 && ci.speed > 0,
  ci ? ('n=' + ci.balls + ' head=' + ci.headWp.toFixed(0) + ' speed=' + ci.speed.toFixed(1)) : 'no chainInfo');
check('珠串无 NaN', !!ci && Number.isFinite(ci.headWp) && Number.isFinite(ci.tailWp));
check('几何已装配（轨道长度 > 0）', S.path && S.path.length > 100, 'L=' + (S.path ? S.path.length.toFixed(0) : 'n/a'));
check('两条轨道各自成型', !!S.railPolys.spawn && !!S.railPolys.eliminate);
check('层级列表非空', S.zLevels.length >= 1, 'z=' + JSON.stringify(S.zLevels));

check('尺寸比 = √2:1（半径比）', Math.abs(S.metrics.R / S.metrics.r - Math.SQRT2) < 1e-12,
  'R/r=' + (S.metrics.R / S.metrics.r).toFixed(6));
check('面积比 = 2', Math.abs(S.metrics.areaRatio - 2) < 1e-12, 'area=' + S.metrics.areaRatio.toFixed(6));

for (let i = 0; i < Z.levelCount; i++) {
  Z.setLevel(i);
  pump(60);
  const st = Z.state;
  const errs = st.issues.filter(function (x) { return x.severity === 'error'; });
  check('关卡 ' + (i + 1) + ' 装载无 error  ' + st.level.name, errs.length === 0,
    'issues=' + st.issues.map(function (x) { return x.code; }).join(','));
}

Z.toggleDebug();
pump(30);
check('调试层渲染无异常', Z.frameCount > 690);
Z.toggleDebug();

const sizes = [[320, 480], [360, 800], [2000, 1000], [900, 1600]];
for (let i = 0; i < sizes.length; i++) {
  sandbox.innerWidth = sizes[i][0];
  sandbox.innerHeight = sizes[i][1];
  Z.resize();
  pump(20);
  check('极端尺寸 ' + sizes[i][0] + 'x' + sizes[i][1] + ' 不炸', true,
    'R=' + Z.state.metrics.R.toFixed(1) + ' 珠=' + Z.state.beads.spawn.length);
}

sandbox.innerWidth = 900;
sandbox.innerHeight = 900;
sandbox.devicePixelRatio = 3;
Z.resize();
pump(10);
check('DPR 钳制在 2 以内', Z.state.view.dpr <= 2, 'dpr=' + Z.state.view.dpr);

Z.setLevel(CORE0);
pump(30);
for (let i = 0; i < 20; i++) { Z.aim(450 + Math.cos(i) * 300, 450 + Math.sin(i) * 300); Z.fire(); pump(12); }
pump(120);
const st = Z.state.sc.stats;
check('连续发射 20 发无异常', Z.state.sc.projectiles.length < 40, '在场弹丸=' + Z.state.sc.projectiles.length);
check('20 发全部打出（冷却自洽）', st.fired === 20, JSON.stringify(st));
check('命中分流产生了事件（配对+错配 = 命中数）', st.pairs + st.mismatches > 0, '配对=' + st.pairs + ' 错配=' + st.mismatches);
// ★ 2 态之后：**错误配对（mark=2）也会占用 + 在散消道上出现小球**（DESIGN.md §32）。
//   所以"小球数"对应的是「已占用的球数」= 正确配对 + 错误配对，不再等于 st.pairs。
const markedBalls = Z.state.sc.chain.balls.filter(function (b) { return b.paired; });
check('每个已占用的球都带 tRNA 碱基（正确与错误配对都一样）',
  markedBalls.length > 0 && markedBalls.every(function (b) { return !!b.pairBase; }),
  '已占用=' + markedBalls.length);
check('三消道小球数 == 已占用的球数（正确 + 错误配对）',
  Z.state.sc.beads.eliminate.length === markedBalls.length,
  '小球=' + Z.state.sc.beads.eliminate.length + ' 已占用=' + markedBalls.length +
  ' （配对 ' + st.pairs + ' + 错配 ' + st.mismatches + '）');

// ⚠ 别写死 2：§60 把 8 个新手关加到了前面，交叉关的位置整体后移了。
//   按"核心关里的第 3 个"算更稳（核心关永远排在最后）。
Z.setLevel(Z.levelCount - 2);
pump(10);
const bridges = Z.state.issues.filter(function (x) { return x.code === 'BRIDGE'; });
check('交叉关存在跨层桥（遮挡系统有戏可演）', bridges.length >= 1,
  '桥=' + bridges.length + '  关卡=' + Z.state.level.name);

Z.setLevel(CORE0);
pump(30);
const scx = Z.state.sc;
scx.chain.balls[0].wp = scx.path.length;
pump(240);
check('U11 洞穴吞球 -> 扣 1 命 -> 重开本关，全程不炸',
  Z.state.sc.lives === 2 && Z.state.sc.chain.balls.length > 0,
  'lives=' + Z.state.sc.lives + ' n=' + Z.state.sc.chain.balls.length);

const scy = Z.state.sc;
scy.lives = 1;
scy.chain.balls[0].wp = scy.path.length;
pump(320);
check('U11 命尽 -> GameOver', Z.state.sc.gameOver === true, 'lives=' + Z.state.sc.lives);
const g1 = Z.state.sc.chain.balls.length, s1 = Z.state.sc.score;
pump(120);
check('U11 GameOver 后场景冻结', Z.state.sc.chain.balls.length === g1 && Z.state.sc.score === s1);

group('★ 切换轨道（模式）端到端');
// 前面的 U11 测试已经把局面打到 GameOver（fireShot 会直接返回 null），先重开一局
Z.setLevel(CORE0);
pump(5);
check('重开后不是 GameOver', !Z.state.sc.gameOver, 'gameOver=' + Z.state.sc.gameOver);
check('开局默认是匹配模式', Z.mode === 'match', 'mode=' + Z.mode);
Z.handleKey({ key: 'Tab', preventDefault: function () {} });
check('★ 按 Tab -> 切到加球模式', Z.mode === 'insert', 'mode=' + Z.mode);
Z.handleKey({ key: 'Tab', preventDefault: function () {} });
check('★★ 再按 Tab -> 回到匹配（§65 之后按钮是**两**态：匹配 <-> 加球）',
  Z.mode === 'match', 'mode=' + Z.mode);
// ★★ 用户：「七球模式请不要加入右下角的切换按钮，我们先不管」
//   —— 这条要**测**：来回切 6 次，七球一次都不该出现。
check('★★ 来回切 6 次，模式循环里**永远不出现七球**', (function () {
  for (let i = 0; i < 6; i++) {
    Z.handleKey({ key: 'Tab', preventDefault: function () {} });
    if (Z.mode === 'seven') return false;
  }
  return Z.mode === 'match';
})(), '现在 mode=' + Z.mode);
Z.setMode('insert');
check('setMode("insert") 生效', Z.mode === 'insert' && Z.state.sc.mode === 'insert');
Z.state.sc.rb.cooldown = 0;
const pIns = Z.fire();
check('★ 加球模式打出去的是大球（尺寸 = 模式）',
  !!pIns && Math.abs(pIns.r - Z.state.sc.metrics.R * 0.9) < 1e-6,
  pIns ? ('r=' + pIns.r.toFixed(2) + '  大球 R*0.9=' + (Z.state.sc.metrics.R * 0.9).toFixed(2)) : 'no shot');
Z.toggleMode();
check('toggleMode() 从加球 -> 匹配（不经过七球）', Z.mode === 'match', 'mode=' + Z.mode);
Z.state.sc.rb.cooldown = 0;
const pMat = Z.fire();
check('匹配模式打出去的是小球',
  !!pMat && Math.abs(pMat.r - Z.state.sc.metrics.r * 0.9) < 1e-6,
  pMat ? ('r=' + pMat.r.toFixed(2) + '  小球 r*0.9=' + (Z.state.sc.metrics.r * 0.9).toFixed(2)) : 'no shot');
check('sceneInfo 里带 mode', Z.state.sc.mode === 'match');
// ★ §57 七球模式：球的身份就是元素，打出去的小球装的也是元素。
//   §65：它**不在按钮的循环里**，只能走调试钩子进来（下面这些是给它的功能测试）。
Z.setMode('seven');
check('★ 用调试钩子仍能进七球（代码没删，只是不上按钮）', Z.mode === 'seven', 'mode=' + Z.mode);
Z.state.sc.rb.cooldown = 0;
const pElem = Z.fire();
check('★ 七球模式打出去的是小球（尺寸同匹配）',
  !!pElem && Math.abs(pElem.r - Z.state.sc.metrics.r * 0.9) < 1e-6,
  pElem ? 'r=' + pElem.r.toFixed(2) : 'no shot');
check('★★ 七球模式的弹丸带的就是元素', !!pElem && ['pyro','hydro','cryo','electro','dendro','geo','anemo'].indexOf(pElem.base) >= 0,
  pElem ? 'elem=' + pElem.elem : 'no shot');
check('★ 七球模式下渲染不抛异常（元素配色 + 草原核 + 反应横幅）', (function () {
  try { Z.renderOnce(); return true; } catch (e) { return false; }
})());
const _SEV = ['pyro','hydro','cryo','electro','dendro','geo','anemo'];
check('★★ 切进七球：场上每颗球的身份都变成元素（base 与 elem 同一个值）',
  Z.state.sc.chain.balls.every(function (b) { return _SEV.indexOf(b.base) >= 0 && b.elem === b.base; }),
  '首颗=' + Z.state.sc.chain.balls[0].base);
check('★ 手里两颗也换成元素', Z.state.sc.rb.loaded.every(function (t) { return _SEV.indexOf(t) >= 0; }),
  Z.state.sc.rb.loaded.join(','));
Z.setMode('match');
// ★ 真的派发一次点击到按钮位置
const _v = Z.state.view, _mt = Z.state.metrics;
const _b = modeButtonRect(_v, _mt);
Z.setMode('match');
const _before = Z.mode;
const _h = canvasListeners['mousedown'] && canvasListeners['mousedown'][0];
check('mock canvas 捕获到了 mousedown 监听器', typeof _h === 'function');
if (typeof _h === 'function') {
  // 两态循环：点两下必须回到原点，中间只经过加球
  const _seen = [];
  for (let k = 0; k < 2; k++) { _h({ clientX: _b.x, clientY: _b.y }); _seen.push(Z.mode); }
  check('★★ 点右下角按钮按 加球 -> 匹配 循环（没有七球）',
    _seen.join(',') === 'insert,match', _before + ' -> ' + _seen.join(' -> '));
  // 点别处应该是发射而不是切模式
  const _m0 = Z.mode;
  Z.state.sc.rb.cooldown = 0;
  _h({ clientX: _v.cx, clientY: 40 });
  check('点别处不切模式', Z.mode === _m0, 'mode=' + Z.mode);
}

// ★ 回归：模式必须跨 rebuild 保留（模式是玩家偏好，不是场景状态）
//   曾经的 bug：rebuild 新建场景 -> 模式静默重置回 match。手机浏览器地址栏收起/展开
//   就会触发 resize -> rebuild，表现就是"按了按钮没反应 / 切了又跳回去"。
Z.setMode('insert');
Z.resize();                       // 模拟 resize -> rebuild
check('★★ resize（rebuild）之后模式仍然是加球', Z.mode === 'insert' && Z.state.sc.mode === 'insert',
  'G.mode=' + Z.mode + '  sc.mode=' + Z.state.sc.mode);
Z.setLevel(1);
check('★★ setLevel（也是 rebuild）之后模式仍然是加球', Z.mode === 'insert' && Z.state.sc.mode === 'insert',
  'G.mode=' + Z.mode + '  sc.mode=' + Z.state.sc.mode);
Z.setMode('match');
check('切回匹配也保留', Z.mode === 'match' && Z.state.sc.mode === 'match');
Z.setLevel(CORE0);

// ★ §61 换关入口从"右上角一排小圆点"改成了**开始菜单**。
//   这一组测的就是新的那套：左下角「菜单」按钮 + 菜单里的关卡按钮。
group('★ 菜单按钮：局内点它能回菜单，菜单里点关卡能开始');
check('★ 局内左下角有「菜单」按钮，且在屏幕内',
  (function () {
    const v = Z.state.view, mt = Z.state.metrics;
    const b = menuButtonRect(v, mt);
    return b.x - b.r > 0 && b.x + b.r < v.w && b.y + b.r < v.h;
  })());
check('★★ 局内点左下角 -> 回到菜单',
  (function () {
    const h = canvasListeners['mousedown'] && canvasListeners['mousedown'][0];
    if (typeof h !== 'function') return false;
    Z.start(CORE0);
    const b = menuButtonRect(Z.state.view, Z.state.metrics);
    h({ clientX: b.x, clientY: b.y });
    return Z.screen === 'menu';
  })(), 'screen=' + Z.screen);
check('★★ 菜单里点第 3 个按钮 -> 开始第 3 关（并且离开菜单）',
  (function () {
    const h = canvasListeners['mousedown'] && canvasListeners['mousedown'][0];
    if (typeof h !== 'function') return false;
    const M = menuLayout(Z.state.view, Z.state.metrics, Z.menuItems || []);
    const b = M.buttons[2];
    h({ clientX: b.x + b.w / 2, clientY: b.y + b.h / 2 });
    return Z.screen === 'play' && Z.state.levelIndex === 2;
  })(), 'screen=' + Z.screen + ' 关卡=' + Z.state.levelIndex + ' (' + Z.state.level.name + ')');
check('★ 菜单态点空白处**不会发射**（免得在菜单里把珠子打了）',
  (function () {
    Z.setScreen('menu');
    const before = Z.state.sc.projectiles.length;
    const h = canvasListeners['mousedown'] && canvasListeners['mousedown'][0];
    h({ clientX: 4, clientY: 4 });
    return Z.state.sc.projectiles.length === before && Z.screen === 'menu';
  })());
check('★ Esc 回菜单、Enter 继续',
  (function () {
    Z.start(2);
    Z.handleKey({ key: 'Escape' });
    if (Z.screen !== 'menu') return false;
    Z.handleKey({ key: 'Enter' });
    return Z.screen === 'play' && Z.state.levelIndex === 2;
  })());
Z.setLevel(CORE0);
Z.start(CORE0);

check('★ 两种模式下渲染都不抛异常（含右下角模式按钮 + 左下角菜单按钮）', (function () {
  try {
    Z.setMode('insert'); Z.renderOnce();
    Z.setMode('match'); Z.renderOnce();
    Z.setMode('insert'); Z.renderOnce();
    return true;
  } catch (e) { return false; }
})());

console.log('');
group('★★ HUD 文案：有限球数关的目标要写清楚，且不许泄漏 Infinity / NaN');
// sceneInfo.scoreTarget 在有限球数关是 Infinity（= 不靠分数过关）。
// 老代码用 ' / ' + scoreTarget 直接拼字符串 -> 界面上会出现"分数 120 / Infinity"。
Z.setLevel(CORE0);
if (Z.state.debug) Z.toggleDebug();     // 只断言玩家能看到的界面（调试层有自己的一堆读数）
Z.rebuild();
texts.length = 0;
Z.renderOnce();
const hudAll = texts.slice();
const hud = hudAll.join(String.fromCharCode(10));
const hudLine = hudAll.filter(function (t) { return t.indexOf('待出') >= 0 || t.indexOf('无限出球') >= 0; })[0] || '(没找到 HUD 行)';
check('★ 第 1 关 HUD 写的是「待出 N / 总预算 颗」', /待出 \d+ \/ \d+ 颗/.test(hudLine), hudLine);
check('★ HUD 里有分数、但不带分数目标（有限球数关靠清空过关）',
  hudLine.indexOf('分数') >= 0 && hudLine.indexOf('Infinity') < 0, hudLine);
const leak = hudAll.filter(function (t) { return /Infinity|NaN|undefined|null/.test(t); });
check('★★ 整个界面没有任何文案泄漏 Infinity / NaN / undefined / null',
  leak.length === 0, leak.length ? leak.join(' | ') : '(干净)');

// ★ §57 七球模式的 HUD 多了一行「盾 / 核 / 反应 / 装载」和一个反应横幅，也要过同一关。
// ⚠ render 读的是 G.chainInfo —— 那是**每帧 update 时缓存的**一份快照，
//   光调 renderOnce() 不会刷新它。所以这里必须先 step 一帧，否则断言看到的是上一帧的
//   （也就是切换模式之前的）状态，会误判成"装载 —/—"。这是测试写法问题，不是产品问题。
Z.setMode('seven');
pump(1);                      // 用真正的帧循环推一帧（这样 dt 也是对的）
texts.length = 0;
Z.renderOnce();
const elemLeak = texts.filter(function (t) { return /Infinity|NaN|undefined|null/.test(t); });
check('★★ 七球模式的 HUD 也没有泄漏 Infinity / NaN / undefined / null',
  elemLeak.length === 0, elemLeak.length ? elemLeak.join(' | ') : '(干净)');
const elemLine = texts.filter(function (t) { return t.indexOf('装载') >= 0; })[0] || '(没找到七球状态行)';
check('★ 七球模式 HUD 有「盾 / 核 / 反应 / 装载」状态行',
  elemLine.indexOf('盾') >= 0 && elemLine.indexOf('反应') >= 0 && elemLine.indexOf('装载') >= 0,
  elemLine);
check('★ 状态行里"装载"写的是元素汉字（不是碱基/破折号）',
  ['火','水','冰','雷','草','岩','风'].some(function (n) { return elemLine.indexOf(n) >= 0; }),
  elemLine);
// ★ 造一个"一定会触发反应"的局面，验证**瞄准提示真的画出来了**（§57.11 对策①）。
//   随机局面下提示未必出现，所以这里手工摆一颗带火附着的邻居 + 手里一颗水的珠子。
const _scH = Z.state.sc;
const _bsH = _scH.chain.balls;
const _mkBall = function (b, e) {
  b.elem = e; b.base = e; b.paired = false; b.wrongMark = false; b.dock = null; b.pairBase = null;
};
for (let i = 0; i < _bsH.length; i++) _mkBall(_bsH[i], 'dendro');
_mkBall(_bsH[1], 'pyro');         // 场上一颗火球
_scH.rb.loaded[0] = 'hydro';      // 手里是水 -> 火球上应该标出「蒸发 ×2」
texts.length = 0;
Z.renderOnce();
const _hintTxt = texts.filter(function (t) { return t.indexOf('蒸发') >= 0; })[0];
check('★★ 瞄准提示画出来了：火球上标出「蒸发 ×2」', !!_hintTxt, _hintTxt || '(没画)');
// 反面：全换成岩球、手里也拿岩 -> 同元素没有反应 -> 一个提示都不该有
for (let i = 0; i < _bsH.length; i++) _mkBall(_bsH[i], 'geo');
_scH.rb.loaded[0] = 'geo';
texts.length = 0;
Z.renderOnce();
// ⚠ 别拿 '×' 当判据 —— 图例里本来就有"d=26.9px（×1/√2）"。要按**反应名**判。
const _RN = ['蒸发','融化','超载','超导','感电','冻结','碎冰','扩散','结晶','燃烧','绽放','激化'];
check('★ 反面：一个能反应的目标都没有时，不标任何提示',
  !texts.some(function (t) {
    return _RN.some(function (n) { return t.indexOf(n) >= 0; });
  }),
  texts.filter(function (t) { return _RN.some(function (n) { return t.indexOf(n) >= 0; }); }).join(' | ') || '(干净)');
for (let i = 0; i < _bsH.length; i++) _mkBall(_bsH[i], 'dendro');
Z.setMode('match');

console.log('');
console.log('smoke: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


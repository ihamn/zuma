// U1 骨架 + U2 几何：主循环、状态、输入、调试钩子。装配逻辑在 scene.js，渲染在 render.js。

import { metrics, viewFor, modeButtonRect, menuLayout, menuButtonRect, DESIGN } from './config.js';
import { ALL_LEVELS, TUTORIALS } from './levels.js';
import { assembleScene, advanceScene, sceneInfo, fireShot, setMode } from './scene.js';
import { aimAt, swapLoaded, rotateAim } from './ribosome.js';
import { render } from './render.js';

const canvas = document.getElementById('stage');
const ctx = canvas.getContext('2d');

const G = {
  view: viewFor(900, 900),
  metrics: metrics(1),
  levelIndex: 0,
  level: ALL_LEVELS[0],
  path: null,
  rails: null,
  railPolys: null,
  runs: null,
  beads: { spawn: [], eliminate: [] },
  zLevels: [0],
  issues: [],
  debug: false,
  // ★ §61 开局进菜单。update() 在菜单态**不推进场景** —— 否则玩家在菜单里挑关卡时，
  //   链子会自己往洞口爬，点进去已经快输了。
  screen: 'menu',
  menuItems: [],
  mode: DESIGN.defaultMode,     // ★ 模式是**玩家偏好**，不属于场景状态 —— 见下面的 rebuild 注释
  frame: 0,
  time: 0,
  fps: 0
};

function rebuild() {
  const sc = assembleScene(ALL_LEVELS[G.levelIndex], G.view, 20260101 + G.levelIndex * 977);
  G.sc = sc;
  G.level = sc.level;
  G.rules = sc.rules;        // ★ 经典祖玛（§66）：渲染要按 ruleset 决定配色/字母
  G.rulesName = sc.rules;
  G.metrics = sc.metrics;
  // ★ 模式是玩家偏好，不是场景状态：rebuild 会新建场景（初始模式是 defaultMode），
  //   这里把玩家选过的模式贴回去。否则 **手机浏览器地址栏收起/展开触发的 resize**
  //   会重建场景、把模式静默重置回 match —— 表现就是"按了按钮没反应/切了又跳回去"。
  setMode(sc, G.mode);
  G.path = sc.path;
  G.rails = sc.rails;
  G.railPolys = sc.railPolys;
  G.runs = sc.runs;
  G.zLevels = sc.zLevels;
  G.issues = sc.issues;
  G.beads = sc.beads;
  G.chainInfo = sceneInfo(sc);          // 菜单态也要有，调试层要用
  // 菜单条目在这里算一次：render 画按钮、onPointerDown 判点击，两边共用同一份
  // ★ 分组优先读关卡自己的 group（经典祖玛那组就是这么来的）；
  //   没写的仍按老规矩分：新手关（TUTORIALS）/ 核心关 —— 现有 10 关的显示**一个字不变**。
  G.menuItems = ALL_LEVELS.map(function (l, i) {
    const tut = i < TUTORIALS.length;
    const grp = l.group || (tut ? '新手关' : '核心关');
    const labeled = l.group ? (l.name || l.short) : (tut ? (l.name || l.short) : ((i + 1) + ' ' + (l.short || l.name)));
    return { index: i, group: grp, label: labeled };
  });
}

function resize() {
  const w = Math.max(320, Math.round(window.innerWidth || 900));
  const h = Math.max(320, Math.round(window.innerHeight || 900));
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  if (canvas.style) { canvas.style.width = w + 'px'; canvas.style.height = h + 'px'; }
  const v = viewFor(w, h);
  v.dpr = dpr;
  G.view = v;
  rebuild();
}

const STEP = 1 / 60;
let last = 0;
let acc = 0;
let fpsAcc = 0;
let fpsN = 0;

function update(dt) {
  G.time += dt;
  if (G.screen === 'menu') return;        // 菜单态：场景冻住当背景板
  if (G.sc) {
    advanceScene(G.sc, dt);
    G.chainInfo = sceneInfo(G.sc);
  }
}

function frame(now) {
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(frame);
  const t = typeof now === 'number' ? now : 0;
  if (!last) last = t;
  let dt = (t - last) / 1000;
  last = t;
  if (!(dt > 0)) dt = 0;
  if (dt > 0.25) dt = 0.25;

  acc += dt;
  let guard = 0;
  while (acc >= STEP && guard < 8) { update(STEP); acc -= STEP; guard += 1; }

  render(ctx, G);
  G.frame += 1;

  fpsAcc += dt; fpsN += 1;
  if (fpsAcc >= 0.5) { G.fps = Math.round(fpsN / fpsAcc); fpsAcc = 0; fpsN = 0; }
}

function setLevel(i) {
  if (i < 0 || i >= ALL_LEVELS.length) return;
  G.levelIndex = i;
  rebuild();
}

// 换屏（菜单 <-> 局内）
function setScreen(s) {
  G.screen = (s === 'menu') ? 'menu' : 'play';
  return G.screen;
}
// 从菜单开始某一关
function startLevel(i) {
  if (typeof i === 'number') setLevel(i);
  setScreen('play');
  return G.levelIndex;
}

// 模式：改场景 + 记在 G 上（rebuild 时贴回去）
// ★★ §65 右下角按钮**只在 匹配 <-> 加球 之间切**。
//   用户：「七球模式请不要加入右下角的切换按钮，我们先不管」——
//   七球（元素）那套代码留着，但不上按钮：它现在是个没定型的试验，
//   摆在玩家的模式循环里只会让人误以为那是个正式玩法。
//   要用它就走调试钩子 __ZUMA__.setMode('seven')（测试和探针就是这么用的）。
function applyMode(m) {
  G.mode = (m === 'seven') ? 'seven' : ((m === 'insert') ? 'insert' : 'match');
  if (G.sc) setMode(G.sc, G.mode);
  return G.mode;
}
function cycleMode() {
  return applyMode(G.mode === 'insert' ? 'match' : 'insert');
}

function onKey(e) {
  const k = e && e.key;
  if (!k) return;
  if (k === 'd' || k === 'D') { G.debug = !G.debug; return; }
  if (k === 'Escape') { setScreen('menu'); return; }
  if (k === 'Enter' || k === 'Return') {
    if (G.screen === 'menu') startLevel(G.levelIndex);
    return;
  }
  if (k >= '1' && k <= '9') { startLevel(parseInt(k, 10) - 1); return; }
  // 菜单态下别的游戏按键一律不响应（免得在菜单里把珠子打了）
  if (G.screen === 'menu') return;
  if (k === 'r' || k === 'R') { rebuild(); return; }
  if (k === ' ' || k === 'Spacebar') { if (G.sc) swapLoaded(G.sc.rb); return; }
  if (k === 'Tab' || k === 'q' || k === 'Q') { cycleMode(); if (e.preventDefault) e.preventDefault(); return; }
  if (k === 'ArrowLeft') { if (G.sc) rotateAim(G.sc.rb, -0.06); return; }
  if (k === 'ArrowRight') { if (G.sc) rotateAim(G.sc.rb, 0.06); return; }
  if (k === 'o' || k === 'O') {
    const lv = ALL_LEVELS[G.levelIndex];
    lv.railOrder = lv.railOrder === 'spawn-outer' ? 'spawn-inner' : 'spawn-outer';
    rebuild();
  }
}

function pointerPos(e) {
  const rect = (canvas.getBoundingClientRect ? canvas.getBoundingClientRect() : { left: 0, top: 0 });
  let px = 0, py = 0;
  if (e.touches && e.touches.length) { px = e.touches[0].clientX; py = e.touches[0].clientY; }
  else if (e.changedTouches && e.changedTouches.length) { px = e.changedTouches[0].clientX; py = e.changedTouches[0].clientY; }
  else { px = e.clientX || 0; py = e.clientY || 0; }
  return { x: px - (rect.left || 0), y: py - (rect.top || 0) };
}

function onPointerMove(e) {
  if (!G.sc) return;
  const p = pointerPos(e);
  aimAt(G.sc.rb, p.x, p.y);
}

function onPointerDown(e) {
  if (!G.sc) return;
  const p = pointerPos(e);
  // ★ 菜单态：只判菜单按钮，点别处什么都不做（尤其**不能发射**）
  if (G.screen === 'menu') {
    const M = menuLayout(G.view, G.metrics, G.menuItems || []);
    for (let i = 0; i < M.buttons.length; i++) {
      const b = M.buttons[i];
      if (p.x >= b.x && p.x <= b.x + b.w && p.y >= b.y && p.y <= b.y + b.h) {
        startLevel(b.item.index);
        return;
      }
    }
    return;
  }
  // 左下角「菜单」按钮：手机上没有 Esc，这是唯一出路
  const mb = menuButtonRect(G.view, G.metrics);
  if (Math.hypot(p.x - mb.x, p.y - mb.y) <= mb.r * 1.3) { setScreen('menu'); return; }
  const rb = G.sc.rb;
  // 换关走左下角「菜单」（§61）。原来右上角那排 12 个小圆点是"还没有菜单时的权宜之计"，
  // 现在有了菜单就是**第二个换关入口**，反而更乱，删掉。
  // 右下角模式按钮：点它切模式，不发射
  const btn = modeButtonRect(G.view, G.metrics);
  if (Math.hypot(p.x - btn.x, p.y - btn.y) <= btn.r * 1.25) {
    cycleMode();
    return;
  }
  // 触屏没有右键：点核糖体本体 = 换珠（与空格/右键等价），点别处 = 瞄准并发射
  if (Math.hypot(p.x - rb.x, p.y - rb.y) <= rb.r * 1.9) {
    swapLoaded(rb);
    return;
  }
  aimAt(rb, p.x, p.y);
  fireShot(G.sc);
}

// 右键 = 切换口中两颗（与空格等价）
function onContextMenu(e) {
  if (e && e.preventDefault) e.preventDefault();
  if (G.sc) swapLoaded(G.sc.rb);
}

if (typeof canvas.addEventListener === 'function') {
  canvas.addEventListener('mousemove', onPointerMove);
  canvas.addEventListener('mousedown', onPointerDown);
  canvas.addEventListener('touchstart', onPointerDown);
  canvas.addEventListener('touchmove', onPointerMove);
  canvas.addEventListener('contextmenu', onContextMenu);
}

if (typeof window !== 'undefined' && window.addEventListener) {
  window.addEventListener('keydown', onKey);
  window.addEventListener('resize', resize);
}

if (typeof window !== 'undefined') {
  window.__ZUMA__ = {
    get state() { return G; },
    get frameCount() { return G.frame; },
    get levelCount() { return ALL_LEVELS.length; },
    rebuild: rebuild,
    resize: resize,
    setLevel: setLevel,
    setScreen: setScreen,
    start: startLevel,
    get screen() { return G.screen; },
    get menuItems() { return G.menuItems; },
    toggleDebug: function () { G.debug = !G.debug; },
    handleKey: onKey,
    fire: function () { return G.sc ? fireShot(G.sc) : null; },
    aim: function (x, y) { return G.sc ? aimAt(G.sc.rb, x, y) : 0; },
    swap: function () { return G.sc ? swapLoaded(G.sc.rb) : null; },
    setMode: function (m) { return applyMode(m); },
    toggleMode: function () { return cycleMode(); },
    get mode() { return G.mode; },
    // ★ 必须给 dt 兜底：update(dt) 直接暴露出去的话，任何 Z.step() 空调用都会
    //   把 dt=undefined 灌进 advanceScene -> speed 变 NaN -> 整个局面静默烂掉
    //   （smoke 里就这么踩了一次）。调试钩子不该有这么尖的角。
    step: function (dt) { update(typeof dt === 'number' ? dt : 1 / 60); },
    renderOnce: function () { render(ctx, G); }
  };
}

resize();
if (typeof requestAnimationFrame === 'function') requestAnimationFrame(frame);


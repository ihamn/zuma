// U6 核糖体（玩家）：固定在轨道系统中心，只能旋转瞄准；口中双珠待命。
// 对应原版 Gun/Gun.cpp，但 demo 不需要后坐力与动画，只保留规则本身。

import { BASES, DESIGN } from './config.js';
import { ELEMENTS, canAttach } from './elements.js';

export function makeRibosome(x, y, mt, rng) {
  return {
    x: x,
    y: y,
    r: DESIGN.ribosomeRadius * mt.scale,
    aim: -Math.PI / 2,
    loaded: [rng.pick(BASES), rng.pick(BASES)],   // [0] 在炮口，[1] 待命
    // ★ 元素（DESIGN.md §57）：与 loaded 平行的数组，索引一一对应。
    //   故意**不动** loaded 的结构 —— 它是碱基，被一堆测试和 poolFn/freshFn 依赖，
    //   把元素塞进同一个槽位会把「碱基」和「元素」两层的语义搅在一起。
    loadedElem: [rng.pick(ELEMENTS), rng.pick(ELEMENTS)],
    cooldown: 0,
    // ★ 身份token 的取值域：匹配模式是碱基，七球模式是元素（§57 改版）。
    //   drawBase 的兜底抽取必须看这个，否则七球模式下会抽回碱基来。
    tokens: BASES,
    rng: rng
  };
}

export function aimAt(rb, tx, ty) {
  rb.aim = Math.atan2(ty - rb.y, tx - rb.x);
  return rb.aim;
}

export function rotateAim(rb, d) {
  rb.aim += d;
  return rb.aim;
}

// 空格 / 右键：交换口中两颗（原版同款双珠待命）
export function swapLoaded(rb) {
  const t = rb.loaded[0];
  rb.loaded[0] = rb.loaded[1];
  rb.loaded[1] = t;
  // 元素跟着一起换 —— 玩家真正想换的往往是元素（碱基只决定「打哪颗」）
  if (rb.loadedElem) {
    const e = rb.loadedElem[0];
    rb.loadedElem[0] = rb.loadedElem[1];
    rb.loadedElem[1] = e;
  }
  return rb.loaded[0];
}

// 抽碱基。若挂了 poolFn（场景给的可用心池），按 bagBias 的概率从池里抽；
// 池空则退化为均匀抽。对应当原版 CurveMgr::GetRandomPendingBallColor —— 它就是"从场上存在的颜色里抽"。
export function drawBase(rb) {
  if (rb.poolFn && rb.rng() < DESIGN.bagBias) {
    const pool = rb.poolFn();
    if (pool && pool.length) {
      // ★ 避免和手里那颗重复：池子里还有别的碱基就换一个（DESIGN.md §39）。
      //   原先两次是**独立**抽的，池子只有 2 种时重复率就有 50% ——
      //   两颗一样的话，其中一颗的目标会被另一颗打光，剩下那颗立刻变成废弹。
      //   实测："两颗手里珠子全都用不上"的帧里，63% 是这个原因。
      let cand = pool;
      if (pool.length > 1 && rb.loaded && rb.loaded[0]) {
        const alt = pool.filter(function (b) { return b !== rb.loaded[0]; });
        if (alt.length) cand = alt;
      }
      return rb.rng.pick(cand);
    }
  }
  return rb.rng.pick(rb.tokens || BASES);
}

// ★★ 过期刷新（DESIGN.md §54）：手里已有的珠子若"场上已经没有它能配的未配对球"，
//   就从当前池子里重抽一颗（能配上才换）。
//
//   为什么必须有：珠子是**上一发时抽的备用珠**，等它被顶上来已经过了一发的时间，
//   目标早被配掉/消掉了。实测 **85.7% 的帧手里这颗没有可打的目标**，
//   发射率只有 0.87 发/秒（冷却允许 6.3），清球 0.7 颗/秒 < 冒球 1.06 颗/秒 -> 必输。
//   这不是难度问题，是"弹药与目标对不上"。
function refreshStale(rb) {
  if (!rb.poolFn || !rb.freshFn) return;
  for (let k = 0; k < rb.loaded.length; k++) {
    if (rb.freshFn(rb.loaded[k])) continue;
    for (let tries = 0; tries < 6; tries++) {
      const nb = drawBase(rb);
      if (rb.freshFn(nb)) { rb.loaded[k] = nb; break; }
    }
  }
}

// 抽一个元素。★ 不做「必须可附着」的硬过滤 —— 风/岩是有用的（扩散/结晶），
//   只是它们需要场上先有附着。这里只保证**不会连着两颗都是风/岩**，
//   否则玩家会连续两发什么都触发不了（和 §39「避免手里两颗重复」同一个道理）。
export function drawElem(rb) {
  const first = rb.loadedElem && rb.loadedElem[0];
  const pool = (first === 'anemo' || first === 'geo')
    ? ELEMENTS.filter(function (e) { return canAttach(e); })
    : ELEMENTS;
  return rb.rng.pick(pool);
}

export function tickRibosome(rb, dt) {
  refreshStale(rb);
  if (rb.cooldown > 0) rb.cooldown = Math.max(0, rb.cooldown - dt);
}

export function canFire(rb) {
  return rb.cooldown <= 0;
}

// 返回一发"发射请求"（位置/角度/碱基），冷却未好则返回 null。
export function fire(rb) {
  if (rb.cooldown > 0) return null;
  const shot = {
    x: rb.x + Math.cos(rb.aim) * rb.r,
    y: rb.y + Math.sin(rb.aim) * rb.r,
    angle: rb.aim,
    base: rb.loaded[0],
    elem: rb.loadedElem ? rb.loadedElem[0] : null
  };
  rb.loaded[0] = rb.loaded[1];
  rb.loaded[1] = drawBase(rb);
  if (rb.loadedElem) rb.loadedElem[1] = drawElem(rb);
  rb.cooldown = DESIGN.fireCooldown;
  return shot;
}


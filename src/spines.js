// 骨架原型（DESIGN.md §5.1）。返回 spineFn(u) -> {x,y}（像素坐标）。
// 关键：接缝必须 C1 连续，否则法线偏移会在接缝处折叠（校验器会报 CURVATURE_OFFSET）。

import { TAU } from './geometry.js';
import { DESIGN, metrics } from './config.js';

// ★★ §62 轨道长度：按**这一关自己的球数**定，不再所有关共用一个 1.9 圈螺旋。
//
//   起因（用户：「新手关没必要再来一个长长的轨道吧？或者说其实普遍不需要吧？」）+ 实测：
//   20 颗球 × 球距 39.5 = 790 单位，而 1.9 圈的螺旋有 3204 单位 ——
//   **t1 把这一关所有的球全堆上轨道，也只占 25%**。换手速更慢的玩家也一样：
//   球数是关卡的硬上限，所以那段轨道按构造就用不到。
//
//   规则：轨道至少装得下这一关**全部的球**，留 25% 余量。
//   实测 L 与 turns 几乎成正比（900x900 视图下 1 圈 ≈ 1704 单位），所以直接反解 turns。
//
//   ⚠ 无尽关（ballBudget = 0）不套这条 —— 它的球数没有上限，轨道要按最长的来。
//
// ★★ §63 但轨道**不能短到没有弧度**（我试过把练习关做成一条直线，做不到）：
//   球距 39.5、球半径 19 —— 球几乎是挨着的，所以**在任何距离上相邻两颗的视角都几乎重叠**
//   （距离 h 处相邻球夹角 atan(39.5/h)，而一颗球的视角宽 2·asin(19/dist)，两者恒差不到 1°）。
//   实测直线排布：12 发里 5 发擦到隔壁那颗，整排变成 122112211 的废球。
//   螺旋/弧线不一样 —— 球分布在不同半径上，每颗都有独立的角度，所以打得准。
//   结论：练习关用 **0.75 圈的小弧**（球正好铺满），而不是直线，也不是 1.9 圈的大螺旋。
export const UNITS_PER_TURN = 1704;    // 900x900 视图、innerRatio 0.32 下，1 圈螺旋的轨道长

export function turnsForBudget(view, budget) {
  if (!(budget > 0)) return DESIGN.turns;                 // 无尽关：球无上限，用最长轨道
  const p = metrics(view.scale).p;                        // 一颗球占的弧长
  const cap = budget * 1.25;                              // 要装得下全部球，再留 25% 余量
  const perTurn = UNITS_PER_TURN * (Math.min(view.w, view.h) / 900);
  const t = cap * p / perTurn;
  // 下限 0.55 圈：再短就不像一条"轨道"了（会退化成一小段弧）
  return Math.max(0.55, Math.min(DESIGN.turns, t));
}

// 经典螺旋内收：rad 1 -> innerRatio，共 turns 圈
export function spiralSpine(view, level) {
  const turns = (level && level.turns != null)
    ? level.turns
    : turnsForBudget(view, level && level.ballBudget);
  const inner = level && level.innerRatio != null ? level.innerRatio : DESIGN.innerRatio;
  const phase = -Math.PI / 2;
  return function (u) {
    const th = phase + u * turns * TAU;
    const rad = 1 - (1 - inner) * u;
    return { x: view.cx + Math.cos(th) * rad * view.rx, y: view.cy + Math.sin(th) * rad * view.ry };
  };
}

// 遮挡演示骨架：内收螺旋 + 出核孔回程。
// 回程不是拼接的贝塞尔，而是同一条极坐标曲线：把 dr/dθ 从 -a 平滑过渡到 +b，
// 于是全程 C1 连续（接缝处不可能出现折角），而回程的半径增长必然追上前一圈 -> 自然产生跨层桥。
export function crossReturnSpine(view, level) {
  const r1 = 0.50;      // 内收终点半径
  const turnsIn = 1.6;
  const turnsOut = 0.9;
  const r2 = 0.88;      // 回程终点半径（降解洞穴）
  const th1 = turnsIn * TAU;
  const dth = turnsOut * TAU;
  const a = (1 - r1) / th1;                     // 内收段 dr/dθ（正数，代表向内）
  const b = 2 * (r2 - r1) / dth + a;            // 解出回程末端 dr/dθ，使 r(th1+dth) = r2
  const phase = -Math.PI / 2;

  function radiusAt(t) {   // t = θ - phase ∈ [0, th1+dth]
    if (t <= th1) return 1 - (1 - r1) * (t / th1);
    const s = Math.min(1, (t - th1) / dth);
    return r1 - a * dth * s + (a + b) * dth * (s * s * s - s * s * s * s / 2);
  }

  const fn = function (u) {
    const t = u * (th1 + dth);
    const th = phase + t;
    const rad = radiusAt(t);
    return { x: view.cx + Math.cos(th) * rad * view.rx, y: view.cy + Math.sin(th) * rad * view.ry };
  };
  fn.junctionU = th1 / (th1 + dth);   // 内收/回程接缝所在的 u（层级分界用它）
  return fn;
}


// U7 弹丸：子步扫掠碰撞 + 存活期回收。
// 扫掠判据 = "胶囊测试"（线段到球心的距离 <= 半径和），等价于连续时间的圆-圆相交，
// 因此再快也不会穿透。原版对应 Ball::Intersects(p1, v1, t)。

import { DESIGN } from './config.js';

export function makeProjectile(shot, mt, mode) {
  const speed = DESIGN.shotSpeed * mt.scale;
  return {
    x: shot.x,
    y: shot.y,
    px: shot.x,
    py: shot.y,
    vx: Math.cos(shot.angle) * speed,
    vy: Math.sin(shot.angle) * speed,
    // 加球模式打出去的是大球（尺寸 = 模式，见 DESIGN.md §46）
    r: (mode === 'insert' ? mt.R : mt.r) * DESIGN.shotRadiusRatio,
    base: shot.base,
    elem: shot.elem || null,      // §57 元素模式：这一发带的是什么元素
    life: 0
  };
}

export function advanceProjectile(p, dt) {
  p.px = p.x;
  p.py = p.y;
  p.x += p.vx * dt;
  p.y += p.vy * dt;
  p.life += dt;
  return p;
}

// 在 (x0,y0)->(x1,y1) 这一段位移上找**最先**撞到的球。
// 已配对（paired）的球是惰性的：弹丸直接穿过 —— 对应 DESIGN.md §4.2 的合法目标定义。
export function sweepHit(balls, x0, y0, x1, y1, pr, skipPaired) {
  const dx = x1 - x0, dy = y1 - y0;
  const len2 = dx * dx + dy * dy;
  let best = -1, bestT = Infinity, hx = 0, hy = 0;
  for (let i = 0; i < balls.length; i++) {
    const b = balls[i];
    if (skipPaired !== false && b.paired === true) continue;
    const rr = pr + b.r;
    let t = 0;
    if (len2 > 1e-12) {
      t = ((b.x - x0) * dx + (b.y - y0) * dy) / len2;
      if (t < 0) t = 0;
      else if (t > 1) t = 1;
    }
    const cx = x0 + dx * t, cy = y0 + dy * t;
    const ddx = b.x - cx, ddy = b.y - cy;
    if (ddx * ddx + ddy * ddy > rr * rr) continue;
    if (t < bestT) { bestT = t; best = i; hx = cx; hy = cy; }
  }
  if (best < 0) return null;
  return { index: best, t: bestT, x: hx, y: hy };
}

export function projectileExpired(p, view, mt) {
  if (p.life > DESIGN.shotMaxLife) return true;
  const m = mt.R * 8;
  return p.x < -m || p.y < -m || p.x > view.w + m || p.y > view.h + m;
}


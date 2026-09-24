-- projectile.lua —— src/projectile.js 的 Lua 5.3 移植。
-- 扫掠判据 = "胶囊测试"（线段到球心的距离 <= 半径和），等价于连续时间的圆-圆相交。

local CFG = require('config')
local M = {}

function M.makeProjectile(shot, mt, mode)
  local D = CFG.DESIGN
  local speed = D.shotSpeed * mt.scale
  return {
    x = shot.x, y = shot.y, px = shot.x, py = shot.y,
    vx = math.cos(shot.angle) * speed,
    vy = math.sin(shot.angle) * speed,
    r = (mode == 'insert' and mt.R or mt.r) * D.shotRadiusRatio,
    base = shot.base,
    elem = shot.elem or nil,
    life = 0,
  }
end

function M.advanceProjectile(p, dt)
  p.px, p.py = p.x, p.y
  p.x = p.x + p.vx * dt
  p.y = p.y + p.vy * dt
  p.life = p.life + dt
  return p
end

-- 在 (x0,y0)->(x1,y1) 这一段位移上找**最先**撞到的球。
-- 返回 { index = i(1 基), t = , x = , y = } 或 nil。
function M.sweepHit(balls, x0, y0, x1, y1, pr, skipPaired)
  local dx, dy = x1 - x0, y1 - y0
  local len2 = dx * dx + dy * dy
  local best, bestT, hx, hy = -1, math.huge, 0, 0
  if skipPaired == nil then skipPaired = true end
  for i = 1, #balls do
    local b = balls[i]
    -- ★ 本帧刚冒出来、还没 syncBeads 的球没有 x/y。
    --   JS 那边 x 是 undefined -> 全是 NaN -> 所有比较为 false -> 自然地"跳过"这颗。
    --   Lua 里对 nil 做算术会直接报错，所以这里显式跳过 —— 语义与 JS 完全一致。
    if b.x ~= nil and b.y ~= nil and not (skipPaired and b.paired == true) then
      local rr = pr + b.r
      local t = 0
      if len2 > 1e-12 then
        t = ((b.x - x0) * dx + (b.y - y0) * dy) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
      end
      local cx, cy = x0 + dx * t, y0 + dy * t
      local ddx, ddy = b.x - cx, b.y - cy
      if ddx * ddx + ddy * ddy <= rr * rr then
        if t < bestT then bestT, best, hx, hy = t, i, cx, cy end
      end
    end
  end
  if best < 0 then return nil end
  return { index = best, t = bestT, x = hx, y = hy }
end

function M.projectileExpired(p, view, mt)
  local D = CFG.DESIGN
  if p.life > D.shotMaxLife then return true end
  local m = mt.R * 8
  return p.x < -m or p.y < -m or p.x > view.w + m or p.y > view.h + m
end

return M

-- chain.lua —— src/chain.js 的 Lua 5.3 移植。U3 珠串模型（绳子/推动）。
--
-- ★ 下标约定：**balls[1] 最靠近洞穴（队头），balls[#balls] 是刚冒出来的队尾。**
--   JS 版是 0 基：JS 的 balls[0] = Lua 的 balls[1]，JS 的 balls[n-1] = Lua 的 balls[#balls]。
--   removeRange / insertBall 的下标参数在 Lua 侧一律是 **1 基**。

local CFG = require('config')
local M = {}

-- 相邻两颗球"相接"所需的弧长距离。逐对算半径（两轨球大小不同，1:√2）。
function M.touchDist(mt, a, b)
  return a.r + b.r + mt.linkGap
end

function M.makeChain(mt, opts)
  opts = opts or {}
  local D = CFG.DESIGN
  return {
    mt = mt,
    balls = {},
    speed = 0,
    targetSpeed = opts.speed ~= nil and opts.speed or D.chainSpeed * mt.scale,
    accel = D.chainAccel * mt.scale,
    decel = D.chainDecel * mt.scale,
    slowDistance = D.slowDistance * mt.scale,
    slowFactor = D.slowFactor,
    spawnWp = opts.spawnWp ~= nil and opts.spawnWp or 0,
    stopTime = 0,
    freezeTime = 0,
    nextId = 1,
    stats = { spawned = 0, drained = 0, removed = 0 },
  }
end

-- 速度平滑：加速慢、减速快
function M.smoothSpeed(ch, dt)
  local t = ch.targetSpeed
  if ch.speed < t then
    ch.speed = math.min(t, ch.speed + ch.accel * dt)
  elseif ch.speed > t then
    ch.speed = math.max(t, ch.speed - ch.decel * dt)
  end
  return ch.speed
end

-- 洞穴前的减速带（B7 冻结：slowDistance = 0 即禁用）
function M.speedAtHead(ch, headWp, curveLength)
  if not (ch.slowDistance > 0) then return ch.speed end
  local slope = curveLength - ch.slowDistance
  if headWp <= slope then return ch.speed end
  if headWp >= curveLength then return ch.speed / ch.slowFactor end
  local t = (headWp - slope) / ch.slowDistance
  return ch.speed * (1 - t) + (ch.speed / ch.slowFactor) * t
end

-- 一帧推进：只推队尾 -> 推动逐节向队头传递（遇空隙即断）
function M.advanceChain(ch, dt, curveLength)
  local balls = ch.balls
  local n = #balls                     -- ★ 与 JS 一致：先取 n，后面用这个 n

  -- §57 冻结反应：整链停止前进
  if ch.freezeTime > 0 then
    ch.freezeTime = math.max(0, ch.freezeTime - dt)
    return
  end

  local movedBack = M.advanceBackwardBalls(ch, dt)
  if movedBack then ch.stopTime = math.max(ch.stopTime, CFG.DESIGN.backStopFrames) end
  M.recycleFront(ch)
  if movedBack or ch.stopTime > 0 then
    if ch.stopTime > 0 then ch.stopTime = ch.stopTime - 1 end
    return
  end

  M.smoothSpeed(ch, dt)
  if n == 0 then return end

  local head = balls[1]
  local effSpeed = curveLength ~= nil and M.speedAtHead(ch, head.wp, curveLength) or ch.speed
  balls[n].wp = balls[n].wp + effSpeed * dt

  for i = n - 1, 1, -1 do
    local back = balls[i + 1]
    local front = balls[i]
    local d = back.wp + M.touchDist(ch.mt, front, back)
    if front.wp < d then
      front.visOff = (front.visOff or 0) - (d - front.wp)
      front.wp = d
    end
  end
end

-- 给**某一颗球**施加后退（对应原版 Ball::SetBackwardsCount / SetBackwardsSpeed）。
function M.applyBackward(ch, i, frames, dist)
  local b = ch.balls[i]
  if not b then return nil end
  local f = math.max(1, frames)
  local bl = b.backLeft or 0
  local remain = 0
  if bl > 0 then remain = b.backSpeed * (bl / 60) end
  b.backLeft = math.max(bl, f)
  b.backSpeed = (remain + dist) / (b.backLeft / 60)
  return b.backSpeed
end

function M.hasBackward(ch)
  local balls = ch.balls
  for i = 1, #balls do
    if (balls[i].backLeft or 0) > 0 then return true end
  end
  return false
end

-- ★ CurveMgr::AdvanceBackwardBalls 的同构实现：从洞端扫到出球端
function M.advanceBackwardBalls(ch, dt)
  local balls = ch.balls
  local anyMoved, collided, speed = false, false, 0
  for i = 1, #balls do
    local b = balls[i]
    if (b.backLeft or 0) > 0 then
      speed = b.backSpeed
      b.wp = b.wp - speed * dt
      b.backLeft = b.backLeft - 1
      collided = true
      anyMoved = true
    end
    if collided then
      local nb = balls[i + 1]
      if not nb then break end                 -- ★ 与 JS 的 break 一致
      local T = M.touchDist(ch.mt, b, nb)
      if b.wp - nb.wp <= T + 1e-6 then
        nb.wp = nb.wp - speed * dt             -- 挨着 -> 同速拖
      else
        local over = (b.wp - T) - nb.wp
        if over < speed * dt then
          nb.wp = b.wp - T
          speed = dt > 0 and (over / dt) or 0
        else
          collided = false                     -- 缝太大 -> 停止传递
        end
      end
    end
  end
  return anyMoved
end

-- 回收滚出出球端的球（原版 RemoveBallsAtFront）
function M.recycleFront(ch)
  local balls = ch.balls
  local cut = 0
  while cut < #balls and balls[#balls - cut].wp < ch.spawnWp do cut = cut + 1 end
  for _ = 1, cut do table.remove(balls) end
  if cut > 0 then
    ch.stats.leftField = (ch.stats.leftField or 0) + cut
  end
  return cut
end

-- 从队尾冒一颗新球；必须等队尾让出位置
function M.spawnBall(ch, base, radius)
  local balls = ch.balls
  local r = radius ~= nil and radius or ch.mt.R
  local cand = { wp = ch.spawnWp, base = base, r = r, id = ch.nextId }
  ch.nextId = ch.nextId + 1                   -- ★ 与 JS 一致：先自增（即使后面 return nil）
  if #balls > 0 then
    local tail = balls[#balls]
    if tail.wp < cand.wp + M.touchDist(ch.mt, cand, tail) then return nil end
  end
  balls[#balls + 1] = cand
  ch.stats.spawned = ch.stats.spawned + 1
  return cand
end

-- 队头越过洞穴即被吸入
function M.drainHead(ch, curveLength)
  local out = {}
  local balls = ch.balls
  while #balls > 0 and balls[1].wp >= curveLength do
    out[#out + 1] = table.remove(balls, 1)
    ch.stats.drained = ch.stats.drained + 1
  end
  return out
end

-- 按"相接"判据切出连续段（队头在前）。返回的 i0/i1 是 **1 基**。
function M.chainRuns(ch)
  local balls = ch.balls
  local runs = {}
  if #balls == 0 then return runs end
  local i0 = 1
  for i = 1, #balls - 1 do
    local linked = (balls[i].wp - balls[i + 1].wp) <= M.touchDist(ch.mt, balls[i], balls[i + 1]) + 1e-6
    if not linked then
      runs[#runs + 1] = { i0 = i0, i1 = i }
      i0 = i + 1
    end
  end
  runs[#runs + 1] = { i0 = i0, i1 = #balls }
  return runs
end

function M.chainHasGap(ch)
  return #M.chainRuns(ch) > 1
end

-- 闭区间移除（1 基闭区间）
function M.removeRange(ch, i0, i1)
  local balls = ch.balls
  local removed = {}
  for _ = 1, (i1 - i0 + 1) do
    removed[#removed + 1] = table.remove(balls, i0)
  end
  ch.stats.removed = ch.stats.removed + #removed
  return removed
end

-- 预装珠串：i=0 放在队头（wp 最大），队尾正好落在 wp=0 的冒球口。
-- ★ 必须把下标 i 传给回调（§60）：固定开局序列要靠它取第 i 颗。
function M.prefillChain(ch, count, baseFn)
  local opts = { r = ch.mt.R }
  local T = M.touchDist(ch.mt, opts, opts)
  for i = 0, count - 1 do
    table.insert(ch.balls, 1, {
      wp = i * T, base = baseFn(i), r = ch.mt.R, id = ch.nextId,
      n = i, paired = false, pairBase = nil,
    })
    ch.nextId = ch.nextId + 1
  end
  return ch
end

-- 把一颗球插进珠串（U12 加球）。index 是 **1 基**。
function M.insertBall(ch, index, ball)
  table.insert(ch.balls, index, ball)
  if ch.stats.inserted == nil then ch.stats.inserted = 0 end
  ch.stats.inserted = ch.stats.inserted + 1
  return ball
end

function M.chainLength(ch)
  return #ch.balls
end

return M

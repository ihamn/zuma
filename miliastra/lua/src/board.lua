-- board.lua —— src/scene.js 的 Lua 5.3 移植（**规则层**：装配 + 每帧推进 + 结算）。
--
-- ★ 与 scene.js 的差异只有两条（其余逐字对应）：
--   1. 下标 1 基（Lua 惯例）。balls[1] = 洞端，balls[#balls] = 出球端。
--   2. 关卡用**纯数据**（level.spineKind）而不是 level.makeSpine 函数 ——
--      真实关卡数据里不该有函数，这对千星奇域尤其重要（那边的关卡是表）。
--
-- 没移植：七球模式（元素反应）。sc.mode == 'seven' 时不工作。
-- 已移植：装配、命中分流、加球/并入、结算循环（爆炸 + 3n 消）、后退冲量、生命、分数、过关。

local CFG = require('config')
local GEO = require('geometry')
local RNG = require('rng')
local CH = require('chain')
local RUN = require('run')
local PJ = require('projectile')
local RB = require('ribosome')
local SP = require('spines')
local EL = require('elements')

local M = {}
local DESIGN = CFG.DESIGN

-- ==================== §60 固定开局序列的解析 ====================

function M.parseScript(str)
  local out = {}
  for i = 1, #str do
    local c = str:sub(i, i)
    if c ~= ' ' and c ~= ',' and c ~= '|' then
      -- 数字是**紧跟着上一颗球的标记**，不是独立的一颗球
      if c == '0' or c == '1' or c == '2' then
        if #out > 0 then out[#out] = out[#out]:sub(1, 1) .. c end
      else
        out[#out + 1] = c
      end
    end
  end
  return out
end

-- "A" 未配对 / "A1" 已正确读出 / "A2" 配错（灰球）
function M.parseScriptEntry(tok)
  local d = tok:sub(2, 2)
  local mark = (d == '1') and 1 or ((d == '2') and 2 or 0)
  return { base = tok:sub(1, 1), mark = mark, paired = mark ~= 0 }
end

function M.allowedComplements(sc, base)
  local c = CFG.COMPLEMENT[base]
  if not c then return {} end
  local pool = sc.bases or CFG.BASES
  local out = {}
  for i = 1, #c do
    for j = 1, #pool do
      if pool[j] == c[i] then out[#out + 1] = c[i]; break end
    end
  end
  return out
end

function M.inPool(sc, base)
  local pool = sc.bases or CFG.BASES
  for i = 1, #pool do if pool[i] == base then return true end end
  return false
end

-- 珠袋可用池（去重）。七球模式未移植。
function M.usefulPool(sc)
  local out = {}
  if sc.mode == 'seven' then return out end
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    if not b.paired then
      local c = M.allowedComplements(sc, b.base)
      for k = 1, #c do
        local seen = false
        for j = 1, #out do if out[j] == c[k] then seen = true; break end end
        if not seen then out[#out + 1] = c[k] end
      end
    end
  end
  return out
end

-- ★★ 加权池（DESIGN.md §54）：**不去重** —— 场上每有一颗粒子需要某个碱基，它就多出现一次。
function M.weightedPool(sc)
  local out = {}
  if sc.mode == 'seven' then return out end
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    if not b.paired then
      local c = M.allowedComplements(sc, b.base)
      for k = 1, #c do out[#out + 1] = c[k] end
    end
  end
  return out
end

-- 轨道上的球心 = 骨架点 + 法线偏移（k：0 = 贴合主轨，1 = 完全落到三消道）
function M.beadPos(path, rail, wp, k)
  local s = k == nil and 1 or k
  local p = path:pointAt(wp)
  local n = path:normalAt(wp)
  return { x = p.x + n.x * rail.offset * s, y = p.y + n.y * rail.offset * s, z = p.z }
end

local function makeSpine(level, view)
  if level.spineKind == 1 then return SP.crossReturnSpine(view, level) end
  return SP.spiralSpine(view, level)
end

-- ==================== 装配 ====================

-- 按关卡配方把珠串铺上轨道（assembleScene 与 restartBoard 共用一份 —— 单一真源）
local function fillChain(sc, ch)
  local level = sc.level
  if level.script then
    local bs2 = M.parseScript(level.script)
    local n = #bs2
    -- 下标方向：prefillChain 的第 i 次调用对应 wp = i*T，而 balls[1] = 洞端，
    -- 所以脚本的第 1 颗要放到**最后一次**调用。
    CH.prefillChain(ch, n, function(i) return M.parseScriptEntry(bs2[n - i]).base end)
    for i = 1, #ch.balls do
      local spec = M.parseScriptEntry(bs2[i])
      local b = ch.balls[i]
      if spec.mark ~= 0 then
        local c = CFG.COMPLEMENT[b.base]
        b.paired = true
        b.wrongMark = (spec.mark == 2)
        b.pairBase = (c and #c > 0) and c[1] or nil
        b.dock = 1
      end
    end
  else
    CH.prefillChain(ch, level.prefill or 14, function() return sc.rng.pick(sc.bases) end)
  end
  -- 用**占轨道全长的比例**：语义是"让**队头**落在这个比例处"
  if level.startWpFrac and #ch.balls > 0 then
    local off = level.startWpFrac * sc.path.length - ch.balls[1].wp
    if off > 0 then
      for i = 1, #ch.balls do ch.balls[i].wp = ch.balls[i].wp + off end
    end
  end
  -- 静止练习关：把整链摆到轨道正中间
  if level.centerChain and #ch.balls > 0 then
    local lo, hi = math.huge, -math.huge
    for i = 1, #ch.balls do
      lo = math.min(lo, ch.balls[i].wp); hi = math.max(hi, ch.balls[i].wp)
    end
    local off = sc.path.length / 2 - (lo + hi) / 2
    for i = 1, #ch.balls do ch.balls[i].wp = ch.balls[i].wp + off end
  end
end
M.fillChain = fillChain

function M.assembleScene(level, view, seed)
  local mt = CFG.metrics(view.scale)
  local spine = makeSpine(level, view)
  local path = GEO.buildPath(spine, { samples = DESIGN.pathSamples, center = { x = view.cx, y = view.cy } })
  local spec = nil
  if level.layersFromJunction then
    local cut = path:sAtU(spine.junctionU or 0.64)
    spec = { { from = 0, to = cut, z = 0 }, { from = cut, to = path.length, z = 1 } }
  end
  GEO.assignLayers(path, spec)

  local sign = (level.railOrder == 'spawn-outer') and 1 or -1
  local rails = {
    spawn = { id = 'spawn', offset = sign * mt.d / 2, radius = mt.R },
    eliminate = { id = 'eliminate', offset = -sign * mt.d / 2, radius = mt.r },
  }
  local railPolys = {
    spawn = GEO.buildRail(path, rails.spawn.offset),
    eliminate = GEO.buildRail(path, rails.eliminate.offset),
  }
  local runs = { spawn = GEO.layerRuns(path), eliminate = GEO.layerRuns(path) }
  local zLevels = {}
  for i = 1, #runs.spawn do
    local z = runs.spawn[i].z
    local seen = false
    for j = 1, #zLevels do if zLevels[j] == z then seen = true; break end end
    if not seen then zLevels[#zLevels + 1] = z end
  end
  table.sort(zLevels)

  local issues = GEO.validateTrack(path, mt, { rails = { rails.spawn.offset, rails.eliminate.offset } })

  local rng = RNG.makeRng(seed)
  local chain = CH.makeChain(mt, {})
  local rb = RB.makeRibosome(view.cx, view.cy, mt, rng)

  local sc = {
    level = level, spine = spine, metrics = mt, path = path, rails = rails,
    railPolys = railPolys, runs = runs, zLevels = zLevels, issues = issues,
    view = view, rng = rng, chain = chain, rb = rb,
    projectiles = {}, merges = {}, events = {}, spawnCount = 0, drained = 0,
    winReason = nil,
    still = (level.still == true),
    noClear = (level.noClear == true),
    goalMatchAll = (level.goal == 'matchAll'),
    shields = 0, cores = {}, nextCoreId = 1, lastReaction = nil, reactionFlash = 0,
    stopAdding = (level.stopAdding == true),
    mode = DESIGN.defaultMode, modeFlash = 0,
    lives = DESIGN.startLives, score = 0, losing = false, gameOver = false, won = false,
    runsInfo = {}, lastClear = nil,
    stats = { fired = 0, pairs = 0, mismatches = 0, merges = 0, cleared = 0, codons = 0, lost = 0,
              explosions = 0, reactions = 0, cores = 0, freezes = 0, reactionRemoves = 0 },
    beads = { spawn = {}, eliminate = {} },
  }

  sc.bases = (level.bases and #level.bases > 0) and level.bases or CFG.BASES
  fillChain(sc, chain)
  if level.still then
    chain.targetSpeed = 0
  elseif level.speed ~= nil then
    chain.targetSpeed = level.speed * mt.scale
  end
  sc.spawnCount = #chain.balls

  rb.poolFn = function() return M.weightedPool(sc) end
  rb.freshFn = function(tok)
    local bs = sc.chain.balls
    for i = 1, #bs do
      if not bs[i].paired then
        if sc.mode == 'seven' then
          error('七球模式未移植')
        elseif CFG.isComplement(tok, bs[i].base) and M.inPool(sc, tok) then
          return true
        end
      end
    end
    return false
  end
  rb.tokens = (sc.mode == 'seven') and EL.ELEMENTS or (sc.bases or CFG.BASES)
  rb.loaded = {}
  rb.loaded[1] = RB.drawBase(rb)
  rb.loaded[2] = RB.drawBase(rb)
  M.syncBeads(sc)
  return sc
end

-- 同步"被规则读到"的位置量（渲染用的颜色/描边不在这里，但 pairGlow 留着给 UI 用）
function M.syncBeads(sc)
  local spawn, eliminate = {}, {}
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    local wpv = b.wp + (b.visOff or 0)
    b.wpv = wpv
    local p = M.beadPos(sc.path, sc.rails.spawn, wpv, nil)
    b.x, b.y, b.z = p.x, p.y, p.z
    b.index = i
    b.label = b.base
    b.pairGlow = b.paired and (b.wrongMark and CFG.WRONG_GLOW or CFG.complementColor(b.base)) or nil
    spawn[#spawn + 1] = b
    if b.paired then
      local k = b.dock == nil and 1 or b.dock
      local q = M.beadPos(sc.path, sc.rails.eliminate, wpv, k)
      eliminate[#eliminate + 1] = {
        x = q.x, y = q.y, z = q.z, r = sc.metrics.r, base = b.pairBase,
        partner = b, paired = true, wrong = (b.wrongMark == true), docked = (k >= 1), index = i,
      }
    end
  end
  sc.beads.spawn = spawn
  sc.beads.eliminate = eliminate
end

local function pushEvent(sc, ev)
  sc.events[#sc.events + 1] = ev
  if #sc.events > 64 then
    for _ = 1, #sc.events - 64 do table.remove(sc.events, 1) end
  end
end
M.pushEvent = pushEvent

-- ==================== 命中分流 ====================

local function resolveHit(sc, p, hit)
  local ball = sc.chain.balls[hit.index]
  local ev = { type = '', index = hit.index, x = hit.x, y = hit.y, base = p.base,
               target = ball.base, mode = p.mode }
  if sc.mode == 'seven' then error('七球模式未移植') end
  if p.mode == 'insert' then
    ev.type = 'insert'
    local mg = M.startMerge(sc, ball, p.base, hit.x, hit.y)
    mg.elem = p.elem or nil
    ev.willMerge = true
  elseif CFG.isComplement(p.base, ball.base) then
    ball.paired = true
    ball.wrongMark = false
    ball.pairBase = p.base
    ball.dock = 0
    ev.type = 'pair'
    sc.stats.pairs = sc.stats.pairs + 1
  else
    ball.paired = true
    ball.wrongMark = true
    ball.pairBase = p.base
    ball.dock = 0
    ev.type = 'mismatch'
    sc.stats.mismatches = sc.stats.mismatches + 1
  end
  pushEvent(sc, ev)
  return ev
end
M.resolveHit = resolveHit

-- ★ 命中侧判定（§49）：flag = (子弹位置 − 球心) × 轨道法线 < 0 -> 插在靠洞那一侧
function M.startMerge(sc, target, base, hitX, hitY)
  local n = sc.path:normalAt(target.wp)
  local dx = (hitX == nil and target.x or hitX) - target.x
  local dy = (hitY == nil and target.y or hitY) - target.y
  local inFront = (dx * n.y - dy * n.x) < 0
  local m = {
    targetId = target.id, base = base, inFront = inFront, t = 0,
    x = target.x, y = target.y, z = target.z, r = sc.metrics.r,
  }
  sc.merges[#sc.merges + 1] = m
  sc.stats.merges = sc.stats.merges + 1
  pushEvent(sc, { type = 'merge', base = base, index = target.index })
  return m
end

-- 返回 1 基下标，找不到返回 -1
function M.findBallIndex(ch, id)
  for i = 1, #ch.balls do if ch.balls[i].id == id then return i end end
  return -1
end

local function updateMerges(sc, dt)
  local mt = sc.metrics
  for i = #sc.merges, 1, -1 do
    local m = sc.merges[i]
    local idx = M.findBallIndex(sc.chain, m.targetId)
    if idx < 0 then
      table.remove(sc.merges, i)          -- 目标被消掉了，并入作废
    else
      local target = sc.chain.balls[idx]
      m.t = m.t + dt / DESIGN.mergeTime
      local k = math.min(1, m.t)
      local T = CH.touchDist(sc.chain.mt, target, { r = mt.R })
      local wp = m.inFront and (target.wp + T * k) or math.max(0, target.wp - T * k)
      local p = M.beadPos(sc.path, sc.rails.spawn, wp, nil)
      m.x, m.y, m.z = p.x, p.y, p.z
      m.r = mt.r + (mt.R - mt.r) * k
      if m.t >= 1 then
        -- 下标 1 = 洞端。插在靠洞那侧 -> idx；靠出球端那侧 -> idx+1
        local at = m.inFront and idx or (idx + 1)
        local nb = {
          wp = wp, base = m.base, r = mt.R, id = sc.chain.nextId,
          n = nil, paired = false, wrongMark = false, pairBase = nil, dock = nil,
          elem = m.elem or nil,
        }
        sc.chain.nextId = sc.chain.nextId + 1
        CH.insertBall(sc.chain, at, nb)
        if DESIGN.insertPairs then M.tryInsertPair(sc, at) end
        table.remove(sc.merges, i)
      end
    end
  end
end

-- 加球的正反馈（§18）：插入后若与**任一邻居**互补，这颗新球自己获得绑定小球。
function M.tryInsertPair(sc, i)
  local balls = sc.chain.balls
  local b = balls[i]
  if not b or b.paired then return nil end
  local head = balls[i - 1]
  local tail = balls[i + 1]
  local mate = nil
  if head and CFG.isComplement(b.base, head.base) then
    mate = head
  elseif tail and CFG.isComplement(b.base, tail.base) then
    mate = tail
  end
  if not mate then return nil end
  b.paired = true
  b.wrongMark = false
  b.pairBase = mate.base
  b.dock = 0
  pushEvent(sc, { type = 'insert-pair', base = b.base, with = mate.base })
  return b
end

local function updateProjectiles(sc, dt)
  local list = sc.projectiles
  for i = #list, 1, -1 do
    local p = list[i]
    PJ.advanceProjectile(p, dt)
    local hit = PJ.sweepHit(sc.chain.balls, p.px, p.py, p.x, p.y, p.r, p.mode ~= 'insert')
    if hit then
      resolveHit(sc, p, hit)
      table.remove(list, i)
    elseif PJ.projectileExpired(p, sc.view, sc.metrics) then
      table.remove(list, i)
    end
  end
end

-- ★ 消除后退（§42）：消掉 k 颗 -> 往出球端方向共退 k 个球位。
--   判定条件只有一个：**消除段是不是贴在洞端**（headEnd <= 1 就不退 —— 删除本身已经兑现过奖励）。
--
--   ⚠ headEnd 在 Lua 侧是 **1 基**下标：JS 的条件是 headEnd <= 0（0 基），
--     换算过来就是 <= 1。这一处差一位曾经让"爆炸后退"整条路径对不上（对拍抓到过）。
local function pushBack(sc, clearedCount, headEnd)
  local ch = sc.chain
  if #ch.balls == 0 then return nil end
  if headEnd == nil or headEnd <= 1 then return nil end
  local T = CH.touchDist(ch.mt, { r = sc.metrics.R }, { r = sc.metrics.R })
  return CH.applyBackward(ch, 1, DESIGN.backFrames, clearedCount * T)   -- Lua 下标 1 = 洞端
end

-- ★ 过关：分数达标 / 场上清空 / 全部读出（三选一）。
local function win(sc, reason)
  if sc.won then return false end
  sc.won = true
  sc.stopAdding = true
  sc.winReason = reason
  pushEvent(sc, { type = 'win', score = sc.score, reason = reason })
  return true
end
M.win = win

-- ★ 爆炸：移除那颗 2 **加上左右各一颗**，共 3 颗。i 是 1 基下标。
--   爆炸**不施加**后退冲量 —— 后退是 3n 消的奖励，爆炸是玩家主动付出的成本。
local function explodeAt(sc, i)
  local bs = sc.chain.balls
  local pat = {
    (i - 2 >= 1) and RUN.markFinal(bs[i - 2]) or -1,
    (i - 1 >= 1) and RUN.markFinal(bs[i - 1]) or -1,
    2,
    (i + 1 <= #bs) and RUN.markFinal(bs[i + 1]) or -1,
    (i + 2 <= #bs) and RUN.markFinal(bs[i + 2]) or -1,
  }
  local removed = CH.removeRange(sc.chain, i - 1, i + 1)
  sc.stats.explosions = sc.stats.explosions + 1
  pushEvent(sc, { type = 'explode', index = i, n = #removed, pat = pat })
  -- 爆炸也走后退 —— 它移除 3 颗，和 3n 消在几何上完全一样。
  -- headEnd = i - 1：接缝靠洞端那一侧的下界（和 eliminateRun 传 run.i0 同义）。
  pushBack(sc, #removed, i - 1)
  return #removed
end

-- ★ 结算循环（§32）：**先爆炸，后 3n 消，循环到不动点**。
--   一次只处理一个爆炸、从左到右扫 —— 结果因此是确定的。
local function settle(sc)
  local total = 0
  if not sc.noClear then
    for _ = 1, 128 do
      local ei = RUN.findExplosion(sc.chain)
      if ei >= 0 then
        total = total + explodeAt(sc, ei)
      else
        local cleared = M.clearImmediately(sc)
        if cleared == 0 then break end
        total = total + cleared
      end
    end
  end
  sc.runsInfo = RUN.computeRuns(sc.chain)

  -- §64 读出全部：判据用 mark ~= 0（读对读错都算"打中过"）
  if sc.goalMatchAll and not sc.losing and not sc.gameOver and not sc.won and #sc.chain.balls > 0 then
    local all = true
    for i = 1, #sc.chain.balls do
      if RUN.markFinal(sc.chain.balls[i]) == 0 then all = false; break end
    end
    if all then win(sc, 'match') end
  end

  -- 清空过关：**预算已发满** + 场上不足 3 颗（不足 3 颗 = 逻辑上已经不可能再消）
  if DESIGN.winOnClear and not sc.losing and not sc.gameOver and not sc.won and #sc.chain.balls < 3 then
    local bud = sc.level.ballBudget ~= nil and sc.level.ballBudget or DESIGN.ballBudget
    if bud > 0 and sc.spawnCount >= bud then win(sc, 'clear') end
  end
  return total
end
M.settle = settle

-- 立即消除 + 级联到不动点（从后往前删，避免下标位移）。
-- ★ 整帧只结算一次后退（同一帧可能连续消多段，每段各施加一次会互相踩到）。
function M.clearImmediately(sc)
  local total = 0
  local minPos = -1
  for _ = 1, 64 do
    local hits = RUN.clearableRuns(sc.chain)
    if #hits == 0 then break end
    for i = #hits, 1, -1 do
      local run = hits[i]
      total = total + #M.eliminateRun(sc, run)
      if run.i0 > 1 and (minPos < 0 or run.i0 < minPos) then minPos = run.i0 end
    end
  end
  if total > 0 then
    pushBack(sc, total, minPos)
    sc.runsInfo = RUN.computeRuns(sc.chain)
  end
  return total
end

-- 整段消除。消除后**不回填、不瞬移**：留下空隙，由绳模型的后段追上来补。
function M.eliminateRun(sc, run)
  local removed = CH.removeRange(sc.chain, run.i0, run.i1)
  sc.stats.cleared = sc.stats.cleared + #removed
  sc.stats.codons = sc.stats.codons + 1
  local gained = 0
  for k = 1, #removed do gained = gained + DESIGN.scorePerBall * (removed[k].amp or 1) end
  sc.score = sc.score + math.floor(gained + 0.5)
  -- 过关条件一：分数达标
  local sTgt = sc.level.scoreTarget ~= nil and sc.level.scoreTarget or DESIGN.scoreTarget
  if not sc.won and sTgt > 0 and sc.score >= sTgt then win(sc, 'score') end
  sc.lastClear = { i0 = run.i0, i1 = run.i1, len = run.len }
  pushEvent(sc, { type = 'clear', len = run.len, i0 = run.i0, i1 = run.i1 })
  sc.runsInfo = RUN.computeRuns(sc.chain)
  return removed
end

-- A15 失败条件：队头撞到降解洞穴 -> 整条珠串被吸进去，扣 1 命。
function M.startLosing(sc)
  if sc.losing or sc.gameOver then return sc.lives end
  -- 结晶护盾（§57）：晶片抵挡一次洞穴吞噬 —— 不扣命，把整链往回拽一截。
  if sc.shields > 0 then
    sc.shields = sc.shields - 1
    local bs = sc.chain.balls
    if #bs > 0 then
      local pull = 3 * CH.touchDist(sc.chain.mt, bs[1], bs[math.min(2, #bs)])
      for i = 1, #bs do bs[i].wp = math.max(0, bs[i].wp - pull) end
      sc.chain.stopTime = DESIGN.backStopFrames
    end
    pushEvent(sc, { type = 'shieldBlock', shields = sc.shields })
    return sc.lives
  end
  sc.losing = true
  sc.lives = math.max(0, sc.lives - 1)
  sc.stats.lost = sc.stats.lost + 1
  pushEvent(sc, { type = 'losing', lives = sc.lives })
  return sc.lives
end

local function updateLosing(sc, dt)
  local ch = sc.chain
  local endLen = sc.path.length
  local step = DESIGN.losingSpeed * sc.metrics.scale * dt
  local keep = {}
  for i = 1, #ch.balls do
    local b = ch.balls[i]
    b.wp = b.wp + step
    if b.wp < endLen then keep[#keep + 1] = b end
  end
  ch.balls = keep
  M.syncBeads(sc)
  if #ch.balls > 0 then return end
  if sc.lives <= 0 then
    sc.losing = false
    sc.gameOver = true
    pushEvent(sc, { type = 'gameover', score = sc.score })
    return
  end
  M.restartBoard(sc)
end

-- 扣命后重开本关（分数与剩余命保留）
function M.restartBoard(sc)
  local ch = sc.chain
  ch.balls = {}
  ch.speed = 0
  fillChain(sc, ch)
  sc.spawnCount = #ch.balls
  sc.runsInfo = {}
  sc.projectiles = {}
  sc.merges = {}
  sc.cores = {}
  sc.losing = false
  pushEvent(sc, { type = 'restart', lives = sc.lives })
  M.syncBeads(sc)
end

-- ★ 切模式（scene.js setMode 的同构）。只支持 match / insert；七球模式未移植。
--   对应原版的"一发两用"之外的取舍：模式决定这一发干什么，化学只决定匹配模式下的结果。
function M.setMode(sc, mode)
  if mode == 'seven' then error('七球模式未移植') end
  sc.mode = (mode == 'insert') and 'insert' or 'match'
  sc.modeFlash = DESIGN.modeFlashTime
  return sc.mode
end

function M.toggleMode(sc)
  return M.setMode(sc, sc.mode == 'insert' and 'match' or 'insert')
end

function M.fireShot(sc)
  if sc.losing or sc.gameOver or sc.won then return nil end
  local shot = RB.fire(sc.rb)
  if not shot then return nil end
  local p = PJ.makeProjectile(shot, sc.metrics, sc.mode)
  p.mode = sc.mode
  sc.projectiles[#sc.projectiles + 1] = p
  sc.stats.fired = sc.stats.fired + 1
  return p
end

-- 视觉滞后量的指数衰减。纯渲染量，但 visOff 会进 wpv -> x/y，而 x/y 被命中判定读到。
local function decayVisual(sc, dt)
  local k = math.exp(-dt / (DESIGN.retreatTime / 3))
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    if b.visOff then
      b.visOff = b.visOff * k
      if math.abs(b.visOff) < 0.05 then b.visOff = 0 end
    end
  end
end

-- 一帧推进：冒球 -> 绳子推进 -> 核糖体/弹丸 -> 吸附 -> 结算 -> 洞穴吞球 -> 同步位置
function M.advanceScene(sc, dt)
  if sc.gameOver then return end
  if sc.won then return end
  if sc.losing then updateLosing(sc, dt); return end
  local ch = sc.chain

  local budget = sc.level.ballBudget ~= nil and sc.level.ballBudget or DESIGN.ballBudget
  local underBudget = budget <= 0 or sc.spawnCount < budget
  if not sc.still and not sc.stopAdding and underBudget and ch.stopTime <= 0 and not CH.hasBackward(ch) then
    local tail = #ch.balls > 0 and ch.balls[#ch.balls].base or nil
    -- ⚠ 本体里 DESIGN.baseRepeat **已经被删掉了**（DESIGN.md §54.1 说它无效），
    --   于是 scene.js 里 sc.rng() < undefined 恒为 false —— 即"永远换成不同的碱基"。
    --   这里照抄这个行为：**抽一次随机数**（必须消耗，否则随机序列错位），但条件恒假。
    local bt = DESIGN.baseRepeat
    local takeRepeat = false
    if tail then
      local r = sc.rng()
      if bt ~= nil and r < bt then takeRepeat = true end
    end
    local base
    if takeRepeat then
      base = tail
    else
      local pool = sc.bases or CFG.BASES
      base = sc.rng.pick(pool)
      local guard = 0
      while base == tail and guard < 16 do
        base = sc.rng.pick(pool)
        guard = guard + 1
      end
    end
    local ball = CH.spawnBall(ch, base)
    if ball then
      ball.n = sc.spawnCount
      sc.spawnCount = sc.spawnCount + 1
    end
  end

  CH.advanceChain(ch, dt, sc.path.length)
  RB.tickRibosome(sc.rb, dt)
  updateProjectiles(sc, dt)
  updateMerges(sc, dt)
  -- tickElements：七球模式专用（草原核/燃烧/冻结）；匹配模式下它什么都不做，故未移植。

  for i = 1, #ch.balls do
    local b = ch.balls[i]
    if not (b.dock == nil or b.dock >= 1) then
      b.dock = math.min(1, b.dock + dt / DESIGN.dockTime)
      if b.dock >= 1 and b.dockDone ~= true then b.dockDone = true end
    end
  end

  if sc.modeFlash > 0 then sc.modeFlash = math.max(0, sc.modeFlash - dt) end
  decayVisual(sc, dt)

  settle(sc)

  if not sc.still and #ch.balls > 0 and ch.balls[1].wp >= sc.path.length then M.startLosing(sc) end

  M.syncBeads(sc)
end

-- 给渲染/测试用的读数（对应 scene.js 的 sceneInfo）
function M.sceneInfo(sc)
  local ch = sc.chain
  local runs = {}
  for i = 1, #sc.runsInfo do runs[i] = sc.runsInfo[i].len end
  return {
    balls = #ch.balls,
    headWp = #ch.balls > 0 and ch.balls[1].wp or 0,
    tailWp = #ch.balls > 0 and ch.balls[#ch.balls].wp or 0,
    speed = ch.speed,
    curveLength = sc.path.length,
    progress = #ch.balls > 0 and (ch.balls[1].wp / sc.path.length) or 0,
    paired = #sc.beads.eliminate,
    runs = runs,
    shots = #sc.projectiles,
  }
end

function M.drainEvents(sc)
  local out = sc.events
  sc.events = {}
  return out
end

return M

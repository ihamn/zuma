-- ribosome.lua —— src/ribosome.js 的 Lua 5.3 移植。U6 核糖体（玩家）。
--
-- ★★ 这个文件里**每一次 rng 抽样都必须与 JS 严格同序**：
--   makeRibosome 抽 4 次（2 碱基 + 2 元素），drawBase 抽 1~2 次，refreshStale 最多 6 次/颗。
--   少一次或多一次，后面的整条随机序列就全错位 —— 而且**不会报错**，只会"玩起来不一样"。
--   只有逐值对拍能抓到这类错。

local CFG = require('config')
local EL = require('elements')

local M = {}

function M.makeRibosome(x, y, mt, rng)
  return {
    x = x, y = y,
    r = CFG.DESIGN.ribosomeRadius * mt.scale,
    aim = -math.pi / 2,
    loaded = { rng.pick(CFG.BASES), rng.pick(CFG.BASES) },          -- [1] 在炮口，[2] 待命
    loadedElem = { rng.pick(EL.ELEMENTS), rng.pick(EL.ELEMENTS) },
    cooldown = 0,
    tokens = CFG.BASES,
    rng = rng,
  }
end

function M.aimAt(rb, tx, ty)
  -- Lua 5.3 没有 math.atan2：两参数的 math.atan(y, x) 就是 atan2
  rb.aim = math.atan(ty - rb.y, tx - rb.x)
  return rb.aim
end

function M.rotateAim(rb, d)
  rb.aim = rb.aim + d
  return rb.aim
end

function M.swapLoaded(rb)
  rb.loaded[1], rb.loaded[2] = rb.loaded[2], rb.loaded[1]
  if rb.loadedElem then
    rb.loadedElem[1], rb.loadedElem[2] = rb.loadedElem[2], rb.loadedElem[1]
  end
  return rb.loaded[1]
end

-- 抽一个身份 token。挂了 poolFn（场景给的加权池）就按 bagBias 的概率从池里抽。
function M.drawBase(rb)
  if rb.poolFn and rb.rng() < CFG.DESIGN.bagBias then
    local pool = rb.poolFn()
    if pool and #pool > 0 then
      -- ★ 避免和手里那颗重复（DESIGN.md §39）
      local cand = pool
      if #pool > 1 and rb.loaded and rb.loaded[1] then
        local alt = {}
        for i = 1, #pool do
          if pool[i] ~= rb.loaded[1] then alt[#alt + 1] = pool[i] end
        end
        if #alt > 0 then cand = alt end
      end
      return rb.rng.pick(cand)
    end
  end
  return rb.rng.pick(rb.tokens or CFG.BASES)
end

-- ★★ 过期刷新（DESIGN.md §54）：手里的珠子若"场上已经没有它能配的未配对球"，就重抽。
function M.refreshStale(rb)
  if not (rb.poolFn and rb.freshFn) then return end
  for k = 1, #rb.loaded do
    if not rb.freshFn(rb.loaded[k]) then
      for _ = 1, 6 do
        local nb = M.drawBase(rb)
        if rb.freshFn(nb) then rb.loaded[k] = nb; break end
      end
    end
  end
end

-- 抽一个元素。不做"必须可附着"的硬过滤，只保证不会连着两颗都是风/岩。
function M.drawElem(rb)
  local first = rb.loadedElem and rb.loadedElem[1]
  local pool
  if first == 'anemo' or first == 'geo' then
    pool = {}
    for i = 1, #EL.ELEMENTS do
      if EL.canAttach(EL.ELEMENTS[i]) then pool[#pool + 1] = EL.ELEMENTS[i] end
    end
  else
    pool = EL.ELEMENTS
  end
  return rb.rng.pick(pool)
end

function M.tickRibosome(rb, dt)
  M.refreshStale(rb)
  if rb.cooldown > 0 then rb.cooldown = math.max(0, rb.cooldown - dt) end
end

function M.canFire(rb)
  return rb.cooldown <= 0
end

function M.fire(rb)
  if rb.cooldown > 0 then return nil end
  local shot = {
    x = rb.x + math.cos(rb.aim) * rb.r,
    y = rb.y + math.sin(rb.aim) * rb.r,
    angle = rb.aim,
    base = rb.loaded[1],
    elem = rb.loadedElem and rb.loadedElem[1] or nil,
  }
  rb.loaded[1] = rb.loaded[2]
  rb.loaded[2] = M.drawBase(rb)
  if rb.loadedElem then rb.loadedElem[2] = M.drawElem(rb) end
  rb.cooldown = CFG.DESIGN.fireCooldown
  return shot
end

return M

-- ============================================================
-- zuma.lua —— 由 miliastra/tools/bundle-lua.mjs 自动生成，**不要手改**。
-- 源文件：miliastra/lua/src/*.lua（那边才是真源）
--
-- 用法：整个文件作为**一个客户端脚本**上传 -> 在客户端控件容器的
--       脚本页签里挂上它 -> 把控件模板索引填进脚本变量（见 lua/src/game.lua 顶部）。
-- ============================================================

local __M = {}
local __cache = {}
local function __require(name)
  local hit = __cache[name]
  if hit ~= nil then return hit end
  local f = __M[name]
  if not f then error("module not found: " .. tostring(name)) end
  local v = f()
  if v == nil then v = true end
  __cache[name] = v
  return v
end
local require = __require   -- ★ 必须在模块体之前，模块体里的 require 才绑得到它

-- ---------------- rng ----------------
__M["rng"] = function()
-- rng.lua —— src/rng.js 的 Lua 5.3 移植。
--
-- ★ 必须**逐位**复刻 JS 的 32 位语义：Math.imul / >>> / |0 在 Lua 里都要手写。
--   Lua 5.3 的整数是 64 位，所以每个中间结果都要 & 0xFFFFFFFF 收回 32 位。
--   两个 32 位数直接相乘会溢出 64 位（(2^32)^2 ≈ 1.8e19 > 2^63），
--   所以 imul 拆成 16 位半字相乘 —— 这是本文件唯一需要小心的地方。
--
-- ★ 与 JS 的**唯一**接口差异：JS 的 rng 是函数对象，Lua 的函数不能挂字段，
--   所以这里用"可调用的表"（__call）。用法仍然是 rng() / rng.int(n) / rng.pick(t)。

local M = {}

local U32 = 0xFFFFFFFF

local function imul(a, b)
  a = a & U32
  b = b & U32
  local a0, a1 = a & 0xFFFF, a >> 16
  local b0, b1 = b & 0xFFFF, b >> 16
  local lo = a0 * b0
  local mid = ((a0 * b1 + a1 * b0) & 0xFFFF) << 16
  return (lo + mid) & U32
end
M.imul = imul

function M.makeRng(seed)
  local a = seed & U32
  if a == 0 then a = 0x9e3779b9 end

  local function step()
    a = (a + 0x6d2b79f5) & U32
    local t = imul(a ~ (a >> 15), (1 | a) & U32)
    t = ((t + imul(t ~ (t >> 7), (61 | t) & U32)) & U32) ~ t
    t = t & U32
    return ((t ~ (t >> 14)) & U32) / 4294967296
  end

  local rng = setmetatable({}, { __call = function(_, ...) return step() end })
  rng.int = function(n) return math.floor(step() * n) end
  rng.pick = function(arr) return arr[rng.int(#arr) + 1] end   -- Lua 数组从 1 开始
  rng.seed = seed & U32                                        -- 与 JS 一致：记的是**入参** seed
  return rng
end

return M
end

-- ---------------- config ----------------
__M["config"] = function()
-- config.lua —— src/config.js 的 Lua 5.3 移植。
-- 数值一律与 config.js 逐字对应；改数值只改这里（对应本体的"只改一个文件"约定）。

local M = {}

M.BASES = { 'A', 'U', 'G', 'C', 'T' }

-- 互补配对表（不对称：A 是唯一的双配碱基）
M.COMPLEMENT = {
  A = { 'U', 'T' },
  U = { 'A' },
  T = { 'A' },
  G = { 'C' },
  C = { 'G' },
}

-- 颜色（第二通道）。互补碱基的颜色互为反色。
M.BASE_COLOR = {
  A = '#e05cff', T = '#5cc93f', U = '#9dff7a', G = '#33b8ff', C = '#ff6b33',
}
M.BASE_INK = {
  A = '#1c0a24', T = '#0d2205', U = '#132a08', G = '#04203a', C = '#2b0f04',
}
M.WRONG_COLOR = '#6b7280'
M.WRONG_INK = '#0b1220'
M.WRONG_GLOW = '#ff5555'

function M.complementColor(base)
  local c = M.COMPLEMENT[base]
  if c then return M.BASE_COLOR[c[1]] end
  return '#ffffff'
end

M.DESIGN = {
  base = 900,
  spawnRadius = 19,
  smallDiameterRatio = 1 / math.sqrt(2),
  railClearance = 9.0,
  beadGap = 1.5,
  pathSamples = 2400,
  outerFit = 0.45,
  outerFitWide = 0.62,
  outerFitTall = 0.86,
  minScale = 0.82,
  innerRatio = 0.32,
  turns = 1.9,

  chainSpeed = 42,
  chainAccel = 30,
  chainDecel = 620,
  slowDistance = 0,
  slowFactor = 2.6,

  ribosomeRadius = 30,
  fireCooldown = 0.16,
  shotSpeed = 1150,
  shotRadiusRatio = 0.9,
  shotMaxLife = 3.0,
  dockTime = 0.30,
  readWindow = 0.30,

  startLives = 3,
  ballBudget = 0,
  scoreTarget = 500,
  winOnClear = true,
  scorePerBall = 10,
  losingSpeed = 1500,

  mergeTime = 0.26,
  defaultMode = 'match',

  elemFreezeTime = 3.0,
  elemAutoPairCount = 3,
  elemSwirlRange = 2,
  elemBurnTime = 3.0,
  elemBurnTick = 0.25,
  elemCoreLife = 6.0,
  elemCoreMax = 5,
  elemReactionDepth = 4,
  elemShieldMax = 3,
  elemScorePerReaction = 10,
  reactionFlashTime = 1.2,
  elemHints = true,
  hintMaxCount = 4,
  modeFlashTime = 0.28,

  bagBias = 1.0,
  retreatTime = 0.22,
  backFrames = 30,
  backStopFrames = 20,
  insertPairs = false,
}

M.Z = { projectile = 50, actor = 60, fx = 70, hud = 100 }

function M.metrics(scale)
  local D = M.DESIGN
  local R = D.spawnRadius * scale
  local r = R * D.smallDiameterRatio
  local d = R + r + D.railClearance * scale
  local linkGap = D.beadGap * scale
  local p = 2 * R + linkGap
  return {
    scale = scale,
    R = R,
    r = r,
    d = d,
    p = p,
    linkGap = linkGap,
    diameterRatio = R / r,
    areaRatio = (R * R) / (r * r),
  }
end

function M.viewFor(w, h)
  local D = M.DESIGN
  local base = math.min(w, h)
  local scale = math.max(base / D.base, math.min(D.minScale, base / 450))
  local portrait = h > w * 1.25
  local capX = base * D.outerFitWide
  local capY = base * (portrait and D.outerFitTall or D.outerFitWide)
  return {
    w = w, h = h, dpr = 1,
    cx = w / 2, cy = h / 2,
    rx = math.min(w * D.outerFit, capX),
    ry = math.min(h * D.outerFit, capY),
    base = base, scale = scale, portrait = portrait,
  }
end

-- 模式按钮矩形（render / main 共用一份）
function M.modeButtonRect(view, mt)
  local r = 40 * mt.scale
  local pad = 26 * mt.scale
  return { x = view.w - r - pad, y = view.h - r - pad, r = r }
end

function M.menuButtonRect(view, mt)
  local r = 22 * mt.scale
  local pad = 26 * mt.scale
  return { x = r + pad, y = view.h - r - pad, r = r }
end

function M.isComplement(tRNA, mRNA)
  local c = M.COMPLEMENT[mRNA]
  if not c then return false end
  for i = 1, #c do if c[i] == tRNA then return true end end
  return false
end

return M
end

-- ---------------- elements ----------------
__M["elements"] = function()
-- elements.lua —— src/elements.js 的 Lua 5.3 移植（**部分**）。
--
-- ⚠ 只移植了"匹配/加球模式跑得起来"所需的部分：七元素表 + canAttach / elemName / elemColor。
--   **反应表（REACTIONS / sevenReaction / beadElemsFor）没有移植** ——
--   七球模式已被用户明确搁置（§65「先不管」），移植它没有意义。
--   如果以后要做，照 elements.js 逐条抄数据即可（它是考证结论，不是平衡数值）。
--
-- 为什么必须先有 canAttach：核糖体的 loadedElem 初始化要抽两次元素，
-- **这会消耗确定性随机数**（rng 的调用次数必须与 JS 完全一致，否则整条链全错位）。

local M = {}

M.ELEMENTS = { 'pyro', 'hydro', 'cryo', 'electro', 'dendro', 'geo', 'anemo' }

M.ELEM = {
  pyro    = { name = '火', color = '#ff7a45', ink = '#3a1204', attachable = true },
  hydro   = { name = '水', color = '#49b6ff', ink = '#04223a', attachable = true },
  cryo    = { name = '冰', color = '#a8ecff', ink = '#0b2b38', attachable = true },
  electro = { name = '雷', color = '#c08cff', ink = '#220b3a', attachable = true },
  dendro  = { name = '草', color = '#8ede52', ink = '#10300a', attachable = true },
  geo     = { name = '岩', color = '#ffc94d', ink = '#3a2604', attachable = false },
  anemo   = { name = '风', color = '#6fe8c8', ink = '#0a332a', attachable = false },
}

M.QUICK = 'quick'

function M.canAttach(elem)
  local e = M.ELEM[elem]
  return (e ~= nil) and (e.attachable == true)
end

function M.elemName(elem)
  if elem == M.QUICK then return '激' end
  local e = M.ELEM[elem]
  return e and e.name or '—'
end

function M.elemColor(elem)
  if elem == M.QUICK then return '#d9f24a' end
  local e = M.ELEM[elem]
  return e and e.color or '#8899aa'
end

return M
end

-- ---------------- geometry ----------------
__M["geometry"] = function()
-- geometry.lua —— src/geometry.js 的 Lua 5.3 移植。
--
-- ★ 唯一的**非逐字**改动：数组下标从 0 基改成 1 基（Lua 惯例）。
--   凡是涉及"第几个"的地方都标注了 -- 1基。跨端对拍由 tools/parity.mjs 负责对账。
--
-- 语义与 geometry.js 完全一致：弧长参数化 + 法线偏移双轨 + 层级分段 + 校验器。

local M = {}

M.TAU = math.pi * 2

local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end
M.clamp = clamp

local function hypot(x, y) return math.sqrt(x * x + y * y) end

local TrackPath = {}
TrackPath.__index = TrackPath

function M.newPath(pts, length)
  return setmetatable({ pts = pts, length = length }, TrackPath)
end

function TrackPath:samples() return #self.pts end

-- u ∈ [0,1] -> 弧长
function TrackPath:sAtU(u)
  local n = #self.pts
  local i0 = math.floor(clamp(u, 0, 1) * (n - 1) + 0.5)   -- 0 基
  if i0 < 0 then i0 = 0 elseif i0 > n - 1 then i0 = n - 1 end
  return self.pts[i0 + 1].s
end

-- 弧长 -> 采样区间左端点下标（返回 1 基下标）
function TrackPath:indexAt(s)
  local pts = self.pts
  local n = #pts
  if s <= 0 then return 1 end
  if s >= self.length then return n - 1 end
  local lo, hi = 1, n
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if pts[mid].s <= s then lo = mid else hi = mid end
  end
  return lo
end

function TrackPath:pointAt(s)
  local pts = self.pts
  local sc = clamp(s, 0, self.length)
  local i = self:indexAt(sc)
  local a, b = pts[i], pts[i + 1]
  local seg = b.s - a.s
  local t = seg > 1e-9 and (sc - a.s) / seg or 0
  return {
    x = a.x + (b.x - a.x) * t,
    y = a.y + (b.y - a.y) * t,
    s = sc,
    z = (t < 0.5) and a.z or b.z,
  }
end

function TrackPath:normalAt(s)
  local pts = self.pts
  local sc = clamp(s, 0, self.length)
  local i = self:indexAt(sc)
  local a, b = pts[i], pts[i + 1]
  local seg = b.s - a.s
  local t = seg > 1e-9 and (sc - a.s) / seg or 0
  local nx = a.nx + (b.nx - a.nx) * t
  local ny = a.ny + (b.ny - a.ny) * t
  local L = hypot(nx, ny)
  if L == 0 then L = 1 end
  return { x = nx / L, y = ny / L }
end

function TrackPath:zAt(s)
  local i = self:indexAt(clamp(s, 0, self.length))
  return self.pts[i].z
end

-- 采样骨架曲线并建立弧长表。spineFn(u) -> {x,y}
function M.buildPath(spineFn, opts)
  opts = opts or {}
  local n = math.max(64, opts.samples or 2400)
  local pts = {}
  local s, px, py = 0, 0, 0
  for i = 0, n do
    local u = i / n
    local q = spineFn(u)
    if i > 0 then s = s + hypot(q.x - px, q.y - py) end
    px, py = q.x, q.y
    pts[i + 1] = { u = u, x = q.x, y = q.y, s = s, nx = 0, ny = 0, z = 0 }
  end
  local path = M.newPath(pts, s)
  M.computeNormals(path, opts.center)
  return path
end

-- 法线沿弧长连续：起点用"背离中心"定向，其后用点积连续性翻正。
function M.computeNormals(path, center)
  local pts = path.pts
  local n = #pts
  for i = 1, n do
    local a = pts[i > 1 and i - 1 or 1]
    local b = pts[i < n and i + 1 or n]
    local tx, ty = b.x - a.x, b.y - a.y
    local L = hypot(tx, ty)
    if L == 0 then L = 1 end
    tx, ty = tx / L, ty / L
    pts[i].nx, pts[i].ny = -ty, tx
  end
  if center then
    local p0 = pts[1]
    local rx, ry = p0.x - center.x, p0.y - center.y
    if rx * p0.nx + ry * p0.ny < 0 then p0.nx, p0.ny = -p0.nx, -p0.ny end
  end
  for i = 2, n do
    if pts[i].nx * pts[i - 1].nx + pts[i].ny * pts[i - 1].ny < 0 then
      pts[i].nx, pts[i].ny = -pts[i].nx, -pts[i].ny
    end
  end
  return path
end

function M.assignLayers(path, spec)
  local pts = path.pts
  for i = 1, #pts do pts[i].z = 0 end
  if not spec then return path end
  for k = 1, #spec do
    local seg = spec[k]
    for i = 1, #pts do
      if pts[i].s >= seg.from and pts[i].s <= seg.to then pts[i].z = seg.z end
    end
  end
  return path
end

function M.layerRuns(path)
  local pts = path.pts
  local runs = {}
  local i0 = 1
  for i = 2, #pts + 1 do
    if i == #pts + 1 or pts[i].z ~= pts[i0].z then
      runs[#runs + 1] = { z = pts[i0].z, i0 = i0, i1 = i - 1 }
      i0 = i
    end
  end
  return runs
end

function M.buildRail(path, offset)
  local pts = path.pts
  local out = {}
  for i = 1, #pts do
    out[i] = {
      x = pts[i].x + pts[i].nx * offset,
      y = pts[i].y + pts[i].ny * offset,
      s = pts[i].s,
      z = pts[i].z,
    }
  end
  return out
end

function M.curvatureAt(pts, i)
  local n = #pts
  local a = pts[i > 1 and i - 1 or 1]
  local b = pts[i]
  local c = pts[i < n and i + 1 or n]
  local abx, aby = b.x - a.x, b.y - a.y
  local bcx, bcy = c.x - b.x, c.y - b.y
  local acx, acy = c.x - a.x, c.y - a.y
  local crossv = abx * bcy - aby * bcx
  local denom = hypot(abx, aby) * hypot(bcx, bcy) * hypot(acx, acy)
  if denom < 1e-9 then return 0 end
  return (2 * crossv) / denom
end

local function segCross(o, a, b)
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
end

local function segIntersect(a, b, c, d)
  local d1 = segCross(c, d, a)
  local d2 = segCross(c, d, b)
  local d3 = segCross(a, b, c)
  local d4 = segCross(a, b, d)
  if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then
    local t = d1 / (d1 - d2)
    return { x = c.x + (d.x - c.x) * t, y = c.y + (d.y - c.y) * t }
  end
  return nil
end

function M.selfCrossings(poly, opts)
  opts = opts or {}
  local step = math.max(1, opts.step or 8)
  local segs = {}
  local i = 1
  while i + step <= #poly do
    local j = math.min(#poly, i + step)
    local a, b = poly[i], poly[j]
    if hypot(b.x - a.x, b.y - a.y) >= 1e-6 then
      segs[#segs + 1] = { a = a, b = b, i0 = i, i1 = j }
    end
    i = i + step
  end
  local out = {}
  for x = 1, #segs do
    for y = x + 1, #segs do
      if segs[y].i0 - segs[x].i1 >= step * 2 then
        local hit = segIntersect(segs[x].a, segs[x].b, segs[y].a, segs[y].b)
        if hit then out[#out + 1] = { x = hit.x, y = hit.y, s1 = segs[x].a.s, s2 = segs[y].a.s } end
      end
    end
  end
  return out
end

function M.validateTrack(path, mt, opts)
  opts = opts or {}
  local issues = {}
  local maxOffset = opts.maxOffset ~= nil and opts.maxOffset or mt.d / 2
  local pts = path.pts

  local worst, worstS = 0, 0
  for i = 2, #pts - 1 do
    local need = math.abs(M.curvatureAt(pts, i)) * maxOffset
    if need > worst then worst, worstS = need, pts[i].s end
  end
  if worst >= 1 then
    issues[#issues + 1] = { code = 'CURVATURE_OFFSET', severity = 'error', s = worstS,
      detail = '偏移 ' .. string.format('%.1f', maxOffset) .. 'px 超过最小曲率半径；内偏轨道会折叠' }
  elseif worst > 0.85 then
    issues[#issues + 1] = { code = 'CURVATURE_TIGHT', severity = 'warn', s = worstS,
      detail = '偏移接近最小曲率半径（占比 ' .. string.format('%.2f', worst) .. '），弯道处珠距会明显压缩' }
  end

  if mt.d < mt.R + mt.r then
    issues[#issues + 1] = { code = 'RAIL_OVERLAP', severity = 'error', s = 0,
      detail = '两轨中心距 ' .. string.format('%.1f', mt.d) .. ' < 半径和 ' .. string.format('%.1f', mt.R + mt.r) }
  end
  if mt.p < 2 * mt.R then
    issues[#issues + 1] = { code = 'BEAD_OVERLAP', severity = 'error', s = 0,
      detail = '同轨球心距 ' .. string.format('%.1f', mt.p) .. ' < 直径 ' .. string.format('%.1f', 2 * mt.R) }
  end

  local rails = opts.rails or { mt.d / 2, -mt.d / 2 }
  for k = 1, #rails do
    local poly = M.buildRail(path, rails[k])
    local xs = M.selfCrossings(poly, { step = opts.step or 8 })
    for m = 1, #xs do
      local x = xs[m]
      local z1 = path:zAt(x.s1)
      local z2 = path:zAt(x.s2)
      if z1 == z2 then
        issues[#issues + 1] = { code = 'SELF_CROSS_SAME_Z', severity = 'error', x = x.x, y = x.y, s = x.s1,
          detail = '同一 z 层 (' .. tostring(z1) .. ') 自交，遮挡关系无解' }
      else
        issues[#issues + 1] = { code = 'BRIDGE', severity = 'info', x = x.x, y = x.y, s = x.s1,
          detail = '跨层桥 z' .. tostring(z1) .. ' / z' .. tostring(z2) }
      end
    end
  end
  return issues
end

return M
end

-- ---------------- spines ----------------
__M["spines"] = function()
-- spines.lua —— src/spines.js 的 Lua 5.3 移植。骨架原型（DESIGN.md §5.1）。
-- 关键：接缝必须 C1 连续，否则法线偏移会在接缝处折叠（geometry.validateTrack 会报 CURVATURE_OFFSET）。

local GEO = require('geometry')
local CFG = require('config')

local M = {}

M.UNITS_PER_TURN = 1704   -- 900x900 视图、innerRatio 0.32 下，1 圈螺旋的轨道长

-- ★★ §62 轨道长度按这一关自己的球数定（规则见 DESIGN.md §62）
function M.turnsForBudget(view, budget)
  local D = CFG.DESIGN
  if budget == nil or not (budget > 0) then return D.turns end   -- 无尽关：球无上限，用最长轨道
  local p = CFG.metrics(view.scale).p
  local cap = budget * 1.25
  local perTurn = M.UNITS_PER_TURN * (math.min(view.w, view.h) / 900)
  local t = cap * p / perTurn
  return math.max(0.55, math.min(D.turns, t))   -- 下限 0.55 圈：再短就不像一条"轨道"了
end

-- ★ 与 JS 的接口差异：JS 的函数是对象，可以挂字段（crossReturnSpine 会挂 junctionU）。
--   Lua 的函数不能挂字段，所以这里统一返回"**可调用的表**"（__call），
--   调用方式与 JS 完全相同：fn(u)、fn.junctionU。rng.lua 用的是同一招。
local function callable(f, fields)
  local t = setmetatable({}, { __call = function(_, ...) return f(...) end })
  if fields then
    for k, v in pairs(fields) do t[k] = v end
  end
  return t
end
M.callable = callable

-- 经典螺旋内收：rad 1 -> innerRatio，共 turns 圈
function M.spiralSpine(view, level)
  local D = CFG.DESIGN
  local turns
  if level and level.turns ~= nil then turns = level.turns
  else turns = M.turnsForBudget(view, level and level.ballBudget) end
  local inner = (level and level.innerRatio ~= nil) and level.innerRatio or D.innerRatio
  local phase = -math.pi / 2
  return callable(function(u)
    local th = phase + u * turns * GEO.TAU
    local rad = 1 - (1 - inner) * u
    return { x = view.cx + math.cos(th) * rad * view.rx, y = view.cy + math.sin(th) * rad * view.ry }
  end)
end

-- 遮挡演示骨架：内收螺旋 + 出核孔回程（同一条极坐标曲线，全程 C1 连续）
function M.crossReturnSpine(view, level)
  local r1 = 0.50
  local turnsIn = 1.6
  local turnsOut = 0.9
  local r2 = 0.88
  local th1 = turnsIn * GEO.TAU
  local dth = turnsOut * GEO.TAU
  local a = (1 - r1) / th1
  local b = 2 * (r2 - r1) / dth + a
  local phase = -math.pi / 2

  local function radiusAt(t)
    if t <= th1 then return 1 - (1 - r1) * (t / th1) end
    local s = math.min(1, (t - th1) / dth)
    return r1 - a * dth * s + (a + b) * dth * (s * s * s - s * s * s * s / 2)
  end

  return callable(function(u)
    local t = u * (th1 + dth)
    local th = phase + t
    local rad = radiusAt(t)
    return { x = view.cx + math.cos(th) * rad * view.rx, y = view.cy + math.sin(th) * rad * view.ry }
  end, { junctionU = th1 / (th1 + dth) })
end

return M
end

-- ---------------- chain ----------------
__M["chain"] = function()
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
end

-- ---------------- run ----------------
__M["run"] = function()
-- run.lua —— src/run.js 的 Lua 5.3 移植。三消道的 3N 消除。纯逻辑。
--
-- 记号：x_i ∈ {0,1} 表示序列里第 i 颗主链球是否"已被读出"。
-- ★ 这里的"序列"就是 chain.balls 的顺序：balls[1] = 洞端，balls[#balls] = 出球端。

local M = {}

-- 标记是否已"定型"（吸附飞行结束）。1 和 2 都算标记，只是含义不同。
function M.isMarked(b)
  return b.paired == true and (b.dock == nil or b.dock >= 1)
end

-- 定型后的状态值：0 = 空、1 = 正确配对、2 = 错误配对。
function M.markFinal(b)
  if not M.isMarked(b) then return 0 end
  return b.wrongMark == true and 2 or 1
end

-- 一颗球是否"已被读出"（x=1）：**正确**配对，且吸附飞行已完成。
-- 注意：错误配对（2）在这里和 0 一样返回 false —— 所以 2 会像 0 一样断开 run。
function M.isDocked(b)
  return M.isMarked(b) and b.wrongMark ~= true
end

-- ★ 爆炸判定（DESIGN.md §32 / §34）。返回下标（1 基），无则返回 -1。
function M.findExplosion(chain)
  local balls = chain.balls
  for i = 2, #balls - 1 do
    if M.markFinal(balls[i]) == 2 then
      local l = M.markFinal(balls[i - 1])
      local r = M.markFinal(balls[i + 1])
      if l ~= 0 and r ~= 0 then
        if (l == 1) == (r == 1) then return i end
      end
    end
  end
  return -1
end

-- run = 标记序列上的极大连续区间（只看序列相邻，与出球道的物理空隙无关）
function M.computeRuns(chain)
  local balls = chain.balls
  local runs = {}
  local cur = nil
  for i = 1, #balls do
    local b = balls[i]
    if not M.isDocked(b) then
      cur = nil
    else
      if cur == nil then
        cur = { i0 = i, i1 = i, len = 1, key = b.id }
        runs[#runs + 1] = cur
      else
        cur.i1 = i
        cur.len = cur.len + 1
      end
    end
  end
  return runs
end

-- 当前所有"该消"的段：长度是 3 的倍数且 >= 3
function M.clearableRuns(chain)
  local out = {}
  local runs = M.computeRuns(chain)
  for i = 1, #runs do
    local r = runs[i]
    if r.len >= 3 and r.len % 3 == 0 then out[#out + 1] = r end
  end
  return out
end

-- 给渲染用的读数
function M.runStatus(run)
  local mod = run.len % 3 == 0
  return {
    len = run.len,
    mod = mod,
    toNext = mod and 0 or (3 - (run.len % 3)),
  }
end

return M
end

-- ---------------- projectile ----------------
__M["projectile"] = function()
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
end

-- ---------------- ribosome ----------------
__M["ribosome"] = function()
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
end

-- ---------------- board ----------------
__M["board"] = function()
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
end

-- ---------------- levels_data ----------------
__M["levels_data"] = function()
-- levels_data.lua —— 由 miliastra/tools/export-levels.mjs 从 src/levels.js 生成，**不要手改**。
--
-- ★ 与 levels.js 的唯一结构差异：level.makeSpine 是一个**函数**，跨语言传不过去，
--   所以换成 spineKind（0 = 螺旋，1 = 交叉桥）；与之配套的 level.layers 也换成
--   layersFromJunction（分层切在骨架的 junctionU 处）。
--
-- 关卡顺序：新手关在前，原本那四个核心关在后（= ALL_LEVELS 的顺序）。
-- 字段含义见 DESIGN.md §5.3 / §55 / §60，以及 docs/05-移植方案.md。

local M = {}

M.LEVELS = {
  {
    id = "t1-pair",
    name = "① 配对",
    short = "配对",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = 12,
    ballBudget = 12,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = true,
    goal = "matchAll",
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = { "球面颜色和字母互为反色 —— 打一颗反色的，就把它「读出」。", "这一关不用凑三颗：把 12 颗全读出来就过关。" },
  },
  {
    id = "t2-multiple",
    name = "② 三的倍数",
    short = "三的倍数",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 9,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = "A1 A1 A1 A1 A0 U0 G0 C0 U0",
    hint = { "这一关开始要消球了：连着读出的球**必须是 3 的倍数**才能消。", "看徽章上的「还差 M」—— 差几颗就再补几颗。" },
  },
  {
    id = "t3-wrong",
    name = "③ 配错的代价",
    short = "配错的代价",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 12,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = "A1 A2 A1 A0 U0 A0 U0 A0 U0 A0 U0 A0",
    hint = { "打错颜色 = 灰球。灰球**不会立刻炸** ——", "要等它左右两颗都已经读出、而且**状态一样**（都配对 / 都配错）时，才连它一起炸掉 3 颗。", "刚才那一炸就是这么来的。不扣分，但那一段白配了。" },
  },
  {
    id = "t4-insert",
    name = "④ 加球",
    short = "加球",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = 12,
    ballBudget = 12,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = { "A", "U" },
    script = nil,
    hint = { "按 Tab（手机点右下角）切到「加球」—— 往链里插一颗，序列的长度就变了。", "凑不成 3 的倍数时，这是除了消球之外的另一种调整手段。", "插错了按 R 重来。" },
  },
  {
    id = "t5-deadball",
    name = "⑤ 死球",
    short = "死球",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 9,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = { "A", "U" },
    script = "A1 A1 U0 A1 A1 A0 A0 A0 A0",
    hint = { "两段各 2 颗，中间夹着 1 颗没读的。", "★ 别急着配中间那颗：配了它，两段会并成 5 颗，反而更远。", "去把后面那几颗凑成一段；真踩了坑，就再补一颗到 6。" },
  },
  {
    id = "t6-cave",
    name = "⑥ 洞穴",
    short = "洞穴",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 22,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = 14,
    startWpFrac = 0.72,
    bases = { "A", "U" },
    script = "A U A U A U A U A U",
    hint = { "★ 到这里才有轨道：球会一直往洞穴爬，队头滚进去就扣一条命。", "它现在离洞口很近 —— 先把最前面那几颗消掉。" },
  },
  {
    id = "t7-mix",
    name = "⑦ 综合",
    short = "综合",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-inner",
    turns = nil,
    innerRatio = nil,
    prefill = 16,
    ballBudget = 36,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = 26,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = { "把前面学的都用上：反色配对、凑 3 的倍数、别去配 1-间隔的那颗。" },
  },
  {
    id = "spiral-outer",
    name = "螺旋 · 出球道在外",
    short = "螺旋·外",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = 14,
    ballBudget = 48,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
  {
    id = "spiral-inner",
    name = "螺旋 · 出球道在内",
    short = "螺旋·内",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-inner",
    turns = nil,
    innerRatio = nil,
    prefill = 14,
    ballBudget = 48,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
  {
    id = "cross-return",
    name = "交叉演示 · 遮挡与桥",
    short = "交叉桥",
    spineKind = 1,
    layersFromJunction = true,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = 16,
    ballBudget = 60,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
  {
    id = "endless",
    name = "无尽 · 无限出球",
    short = "无尽",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = 18,
    ballBudget = 0,
    scoreTarget = 500,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
}

function M.byId(id)
  for i = 1, #M.LEVELS do
    if M.LEVELS[i].id == id then return M.LEVELS[i] end
  end
  return nil
end

return M
end

-- ---------------- ui ----------------
__M["ui"] = function()
-- ui.lua —— 表现层：board 的状态 -> 客户端控件。
--
-- ★★ 这里**不重新实现任何规则**：位置/颜色/显隐全部来自 sc（board.lua 算好的）。
--   ui 的职责只有三件：坐标换算、控件池复用、脏检查。
--
-- 坐标：board 用的是"画布像素、原点左上、y 向下"；控件 anchoredPosition 在父级下
--       是"相对父级中心、y 向上"。所以 y 要翻一次号：uiY = view.cy - y。
--       父级 = 一块铺满画布、居中在画布中心的容器控件。

local CFG = require('config')

local M = {}

local Z = CFG.Z

-- '#rrggbb' -> Color(r,g,b,255)
local function hexColor(s, fallback)
  if type(s) ~= 'string' or #s < 7 then return fallback or Color.FromRGBA(255, 255, 255, 255) end
  local r = tonumber(s:sub(2, 3), 16) or 255
  local g = tonumber(s:sub(4, 5), 16) or 255
  local b = tonumber(s:sub(6, 7), 16) or 255
  return Color.FromRGBA(r, g, b, 255)
end
M.hexColor = hexColor

-- ★★ 控件运行时 ID 的字段名：官方是 **`Id`（首字母大写）**。
--    真机观察（客户端 Lua 运行时契约 §16）：「`Id`（客户端控件运行时ID，首字母大写）/ `prefabIndex`；
--    旧 probe 中的 `control.id` / `prefabId` 是**旧版本接口，不作为兼容口径**」。
--    原来这里写的是小写 `c.id` —— 真机上恒为 nil，于是 `ui.last[nil]` 直接报
--    「table index is nil」，整局在第一帧就崩。本地假宿主提供的是小写 id，所以测试发现不了。
--    两个都认：真机走 Id，本地假宿主走 id。
local function ctrlId(c)
  return c.Id or c.id
end

local function setField(ui, c, key, value)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
  if cache[key] == value then return false end
  cache[key] = value
  c[key] = value
  return true
end

local function setColor(ui, c, hex)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
  if cache.__color == hex then return false end
  cache.__color = hex
  c.imageColor = hexColor(hex)
  return true
end

local function setImage(ui, c, id)
  local key = ctrlId(c)
  local cache = ui.last[key]
  if cache == nil then cache = {}; ui.last[key] = cache end
  if cache.__image == id then return false end
  cache.__image = id
  c:SetImage(Enum.ImageSource.StaticReference, id)
  return true
end

-- ★★ 可见性：官方契约里 `visible` 是**只读**字段 —— 读得到，**写会报**
--    「cannot set visible, no such field」。改可见性必须调方法 SetVisible()。
--    原来这里用 setField(..., 'visible', ...) 直接赋值，真机上一进 sync 就崩。
local function setVisible(ui, c, v)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
  if cache.__visible == v then return false end
  cache.__visible = v
  c:SetVisible(v)
  return true
end

-- ==================== 建池 ====================

-- opts:
--   parent        挂到哪个控件下（一般是铺满画布的容器）
--   canvas        { w, h }
--   ballPrefab    球控件的控件模板索引
--   ballCount     球池大小
--   shotPrefab    弹药控件模板索引
--   shotCount     弹药池大小
--   art           { [base] = 图片id }；缺省用 1..5
--   hudPrefab     文本框控件模板索引
--   hud           { { key=, text=, x=, y=, size=, align= }, ... }  x/y 是**控件坐标**（相对中心，y 向上）
function M.create(opts)
  opts = opts or {}
  local parent = opts.parent
  if not parent then error('ui.create: 需要 parent') end
  local canvas = opts.canvas or { w = 900, h = 900 }

  local ui = {
    canvas = canvas,
    parent = parent,
    last = {},
    balls = {},
    shots = {},
    hud = {},
    stats = { writes = 0, ballWrites = 0, hudWrites = 0 },
  }

  local art = opts.art or {}
  if not next(art) then
    for i = 1, #CFG.BASES do art[CFG.BASES[i]] = i end
  end
  ui.art = art

  -- 球池
  local n = opts.ballCount or 96
  for i = 1, n do
    local c = game.InstantiateClientUIControl(opts.ballPrefab or 1, parent)
    -- ★ 动态创建失败时要**响亮地失败**：不然玩家看到的是空白画面，而错误在日志里
    if not c then
      error('球控件创建失败（第 ' .. i .. ' 个，模板索引 ' .. tostring(opts.ballPrefab or 1)
        .. '）。模板索引可能没填，或这个控件不能动态创建（主屏 / 模板控件的子节点都不行）')
    end
    c:SetActive(true)                       -- 文档：动态创建默认 active=false
    c:SetVisible(false)
    c.canControllerFocus = false
    ui.balls[i] = c
  end

  -- 弹药池
  local sn = opts.shotCount or 8
  for i = 1, sn do
    local c = game.InstantiateClientUIControl(opts.shotPrefab or (opts.ballPrefab or 1), parent)
    c:SetActive(true)
    c:SetVisible(false)
    c.canControllerFocus = false
    ui.shots[i] = c
  end

  -- HUD
  ui.hudOrder = {}
  for i = 1, #(opts.hud or {}) do
    local spec = opts.hud[i]
    local c = game.InstantiateClientUIControl(opts.hudPrefab or 2, parent)
    c:SetActive(true)
    c:SetVisible(true)
    c.canControllerFocus = false
    c:SetAnchoredPosition(spec.x or 0, spec.y or 0)
    c:SetSizeDelta(spec.w or 400, spec.h or 60)
    c.fontSize = spec.size or 28
    c.horizontalAlignment = spec.align == 'right' and Enum.TextHorizontalAlignment.Right
      or (spec.align == 'center' and Enum.TextHorizontalAlignment.Middle or Enum.TextHorizontalAlignment.Left)
    c.verticalAlignment = Enum.TextVerticalAlignment.Middle
    c.enableOutline = true
    c.text = spec.text or ''
    ui.hud[spec.key] = c
    ui.hudOrder[#ui.hudOrder + 1] = spec.key
  end

  return ui
end

-- ==================== 每帧同步 ====================

-- st（可选）: { aim = 弧度, hintLines = {..}, badge = '…', mode = 'match'|'insert' }
function M.sync(ui, sc, st)
  st = st or {}
  local view = sc.view
  local mt = sc.metrics
  local cx, cy = view.cx, view.cy
  ui.stats.writes = 0

  -- ---- 球 ----
  local beads = sc.beads.spawn
  local nb = #beads
  local pool = ui.balls
  for i = 1, #pool do
    local c = pool[i]
    local b = beads[i]
    if b then
      local d = 2 * b.r
      if setField(ui, c, 'anchoredPositionX', b.x - cx) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'anchoredPositionY', cy - b.y) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'sizeDeltaX', d) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'sizeDeltaY', d) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setVisible(ui, c, true) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      -- 配错 = 灰球；已配对但还没定型，用原色（吸附飞行途中）
      local hex = b.wrongMark and CFG.WRONG_COLOR or (CFG.BASE_COLOR[b.base] or '#ffffff')
      setColor(ui, c, hex)
      setImage(ui, c, ui.art[b.base] or 1)
    else
      setVisible(ui, c, false)
    end
  end

  -- ---- 弹药 ----
  local shots = sc.projectiles
  for i = 1, #ui.shots do
    local c = ui.shots[i]
    local p = shots[i]
    if p then
      setField(ui, c, 'anchoredPositionX', p.x - cx)
      setField(ui, c, 'anchoredPositionY', cy - p.y)
      local d = 2 * p.r
      setField(ui, c, 'sizeDeltaX', d)
      setField(ui, c, 'sizeDeltaY', d)
      setVisible(ui, c, true)
      setColor(ui, c, CFG.BASE_COLOR[p.base] or '#ffffff')
      setImage(ui, c, ui.art[p.base] or 1)
    else
      setVisible(ui, c, false)
    end
  end

  -- ---- 核糖体 / 待发球 ----
  if ui.hud.rb then
    setField(ui, ui.hud.rb, 'anchoredPositionX', sc.rb.x - cx)
    setField(ui, ui.hud.rb, 'anchoredPositionY', cy - sc.rb.y)
    setVisible(ui, ui.hud.rb, true)
  end

  -- ---- HUD 文本 ----
  local function text(key, s)
    local c = ui.hud[key]
    if not c then return end
    if c.text ~= s then c.text = s; ui.stats.hudWrites = ui.stats.hudWrites + 1 end
  end
  text('score', '分数 ' .. tostring(sc.score))
  text('lives', '命 ' .. tostring(sc.lives))
  local runs = {}
  for i = 1, #sc.runsInfo do
    local r = sc.runsInfo[i]
    runs[#runs + 1] = tostring(r.len) .. (r.len % 3 == 0 and '✓' or ('(+' .. tostring(3 - r.len % 3) .. ')'))
  end
  text('runs', '连读 ' .. (#runs > 0 and table.concat(runs, ' ') or '—'))
  text('mode', st.mode == 'insert' and '模式：加球' or '模式：配对')
  if ui.hud.hint then
    text('hint', st.hintLines and table.concat(st.hintLines, '\n') or '')
  end
  return ui
end

-- 平台上限自检（《编辑项范围限制》：单控件组 1000 / 单屏 10000）
function M.budget(ui)
  local n = #ui.balls + #ui.shots + #ui.hudOrder
  for _ in pairs(ui.hud) do end
  return n, 1000, 10000
end

return M
end

-- ---------------- input ----------------
__M["input"] = function()
-- input.lua —— 输入层：光标/按键 -> 瞄准角与"要做什么"的意图。
--
-- ★ 这一层**不直接调 board**：它只改 sc.rb.aim（瞄准是输入的事）并留下意图标志，
--   由 game.lua 决定什么时候真的开火/换球/切模式。这样输入层可以单独测。

local CFG = require('config')
local RB = require('ribosome')

local M = {}

-- 画布 UI 坐标（官方：以画布**左下角**为原点，y 向上）
-- -> board 坐标（画布像素、原点左上、y 向下）
function M.toBoard(canvas, x, y)
  return x, canvas.h - y
end

-- opts:
--   area       CursorEventArea 控件（铺满玩区的那块）
--   keyTarget  挂键盘监听的控件（一般是画布根控件）
--   canvas     { w, h }
--   stick      是否也用手柄摇杆瞄准（默认关）
function M.create(opts)
  opts = opts or {}
  local canvas = opts.canvas or { w = 900, h = 900 }
  local inp = {
    canvas = canvas,
    firing = false,        -- 按住 = 连发（冷却由 DESIGN.fireCooldown 管）
    pending = 0,           -- 一次性开火（模拟点击会给一个）
    wantSwap = false,
    wantMode = false,
    wantRestart = false,
    useCursor = true,
    stickX = 0, stickY = 0,
    hold = false,
    stats = { clicks = 0, keys = 0, fires = 0 },
  }

  local area = opts.area
  if area then
    area:AddCursorEventListener(Enum.CursorEventType.CursorDown, function(d)
      inp.hold = true
      inp.stats.clicks = inp.stats.clicks + 1
    end)
    area:AddCursorEventListener(Enum.CursorEventType.CursorUp, function()
      inp.hold = false
    end)
    area:AddCursorEventListener(Enum.CursorEventType.CursorClick, function(d)
      inp.pending = inp.pending + 1
      inp.stats.clicks = inp.stats.clicks + 1
    end)
  end

  local kt = opts.keyTarget
  if kt then
    local KC = Enum.KeyboardKeyCode
    kt:AddKeyEventListener(Enum.KeyEventType.KeyDown, function(code)
      inp.stats.keys = inp.stats.keys + 1
      if code == KC.NormalAttackKey then
        inp.hold = true
        return true
      elseif code == KC.TabKey then
        inp.wantMode = true
        return true
      elseif code == KC.KeyR then
        inp.wantRestart = true
        return true
      elseif code == KC.SpaceJumpKey then
        inp.wantSwap = true
        return true
      end
      return false
    end)
    kt:AddKeyEventListener(Enum.KeyEventType.KeyUp, function(code)
      if code == KC.NormalAttackKey then
        inp.hold = false
        return true
      end
      return false
    end)
  end

  return inp
end

-- 每帧：更新瞄准角，并把意图整理成 inp.firing / wantXxx
function M.update(inp, sc, dt)
  if inp.useCursor then
    local gx, gy = game.GetCursorUIPos()
    local bx, by = M.toBoard(inp.canvas, gx, gy)
    RB.aimAt(sc.rb, bx, by)
  elseif inp.stickX ~= 0 or inp.stickY ~= 0 then
    sc.rb.aim = math.atan(inp.stickY, inp.stickX)
  end

  inp.firing = (inp.hold or inp.pending > 0)
  return inp
end

-- 开火意图被消费掉之后调用
function M.consume(inp)
  inp.pending = 0
end

return M
end

-- ---------------- game ----------------
__M["game"] = function()
-- game.lua —— 宿主胶水：脚本生命周期 + 每帧主循环 + 关卡推进。
--
-- 这就是**最终要上传到千星奇域的那个脚本**的门面（打包器会把它和内核一起打成 out/zuma.lua）。
--
-- 编辑器里要做的事（详见 miliastra/pc/操作手册.html）：
--   1. 建一个**客户端控件容器画布**（不要用主屏）；
--   2. 建 4 个客户端控件模板：图片（球）/ 文本框 / 光标检测区域 / 玩区容器；
--   3. 在这个容器的**脚本页签**里挂上打包后的 zuma.lua；
--   4. 把模板索引填进脚本变量（下面这张表）。
--
-- 脚本变量（编辑期填，运行期用 script:GetParam 读；不填就用括号里的默认值）：
--   levelIndex   从第几关开始（1..11，1 = ① 配对）              [1]
--   ballPrefab   球控件的客户端控件模板索引                      [1]
--   shotPrefab   弹药控件的模板索引（不填则跟球一样）            [= ballPrefab]
--   hudPrefab    文本框控件的模板索引                            [2]
--   cursorPrefab 光标检测区域控件的模板索引                      [3]
--   playPrefab   玩区容器控件的模板索引（不填则跟球一样）        [= ballPrefab]
--   ballCount    球池大小                                        [96]
--   shotCount    弹药池大小                                      [8]
--   seed         随机种子                                        [12345]
--   autoNext     过关后自动进下一关（0 = 不自动）                [1]
--   diag         屏幕左下角显示诊断行（排错用，正式发布再关）    [1]
--
-- ★★ 为什么要 diag：我在手机上**看不到你的电脑屏幕**。
--   出问题时屏幕上那行字就是你转述给我的唯一线索，所以默认开着。

local CFG = require('config')
local BOARD = require('board')
local RB = require('ribosome')
local UI = require('ui')
local INPUT = require('input')
local LEVELS_DATA = require('levels_data')

local G = {}

G.screen = 'boot'          -- boot | playing | won | lost | error
G.resultTimer = 0
G.nextDelay = 2.5
G.loseDelay = 3.0
G.error = nil
G.frames = 0

local function param(name, default)
  local v = script and script:GetParam(name)
  if v == nil then return default end
  return v
end

-- 不依赖控件的日志通道（官方日志 API）。
-- ★ 为什么必须有：真机上控件要等到 OnStart 才建得出来，一旦在那之前失败，
--   屏幕上那行"诊断字"本身也是控件、也建不出来 —— 这时只剩日志能告诉我们死在哪。
local function say(fmt, ...)
  local ok, s = pcall(string.format, fmt, ...)
  if not ok then s = tostring(fmt) end
  if print then pcall(print, '[zuma] ' .. s) end
end

-- 玩区容器的尺寸 = 画布尺寸；它以画布中心为原点
local function buildHudSpecs(w, h)
  local pad = 16
  local halfW, halfH = w / 2, h / 2
  return {
    { key = 'score', x = -halfW + 120 + pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'left' },
    { key = 'lives', x = halfW - 120 - pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'right' },
    { key = 'runs', x = -halfW + 220 + pad, y = halfH - 84 - pad, w = 440, h = 40, size = 26, align = 'left' },
    { key = 'mode', x = -halfW + 120 + pad, y = -halfH + 32 + pad, w = 240, h = 44, size = 26, align = 'left' },
    { key = 'hint', x = 0, y = -halfH + 130, w = math.min(w - 40, 760), h = 130, size = 24, align = 'center' },
    { key = 'result', x = 0, y = 0, w = math.min(w - 40, 640), h = 120, size = 40, align = 'center' },
  }
end

-- ==================== 启动 ====================

function G.OnInit()
  -- ★★ 真机限制（来源：客户端 Lua 运行时真机探针 + 官方《客户端控件 API 文档》）：
  --   1. game.InstantiateClientUIControl 在 **OnInit 阶段返回 nil**，只有 OnStart 及之后成功。
  --      —— 所以这里**一个控件都不建**，全部挪到 OnStart（见 G.tryBoot）。
  --   2. 官方 API 有 script:EnableUpdate(enabled)；真机结论是「EnableUpdate 前无 OnUpdate」。
  --      —— 不打开它，OnUpdate 永远不会被调用，画面就是死的。
  -- 因此 OnInit 里只做**不可能失败**的事。
  local ok0, w, h = pcall(game.GetUICanvasSize)
  if not ok0 then w, h = 900, 900 end
  G.canvas = { w = w, h = h }
  G.view = CFG.viewFor(w, h)
  G.diag = param('diag', 1) ~= 0
  G.error = nil          -- ★ 每次重来都清掉：否则上一次的错误会一直挂在屏幕上（测试抓到的）
  G.booted = false

  say('OnInit：画布 %dx%d', w, h)
  if script and script.EnableUpdate then
    local eok, eerr = pcall(function() script:EnableUpdate(true) end)
    say('EnableUpdate(true) -> %s', eok and 'ok' or tostring(eerr))
  else
    say('警告：没有 script.EnableUpdate，逐帧回调可能不会触发')
  end
  return G
end

-- 真正建控件。**只能在 OnStart 及之后调用**：真机 OnInit 阶段 Instantiate 返回 nil。
function G.tryBoot()
  if G.booted then return end
  G.booted = true
  say('tryBoot：开始建控件')
  local ok, err = pcall(G.boot)
  if ok then
    say('tryBoot：成功')
  else
    G.error = tostring(err)
    G.screen = 'error'
    say('tryBoot 失败：%s', tostring(err))
    if printerr then pcall(printerr, '[zuma] 建控件失败：' .. tostring(err)) end
  end
  G.refreshDiag()
end

-- 真正干活的初始化。任何一步失败都会被 OnInit 的 pcall 接住并显示在屏幕上。
function G.boot()
  local w, h = G.canvas.w, G.canvas.h
  G.seed = param('seed', 12345)
  G.autoNext = param('autoNext', 1) ~= 0

  local root = script.object
  if not root then
    local roots = game.GetClientUIRoots()
    root = roots and roots[1] or nil
  end
  if not root then error('找不到挂载控件：脚本要挂在**客户端控件**上（不能挂主屏）') end
  G.root = root
  root:SetActive(true)
  say('挂载点 = %s', tostring(root))

  -- ★★ 诊断框**第一个建**：万一后面哪一步炸了，屏幕上还有地方显示原因。
  --   （这一条很关键：我在手机上看不到你的屏幕，那行字就是唯一的线索）
  local dok, dc = pcall(game.InstantiateClientUIControl, param('hudPrefab', 2), root)
  if dok and dc then
    G.diagControl = dc
    dc:SetActive(true)
    dc:SetAnchoredPosition(0, -h / 2 + 20)
    dc:SetSizeDelta(math.min(w - 40, 760), 30)
    dc.fontSize = 18
    dc.horizontalAlignment = Enum.TextHorizontalAlignment.Left
    dc.verticalAlignment = Enum.TextVerticalAlignment.Middle
    if not G.diag then dc:SetVisible(false) end
  end

  say('诊断框 = %s', tostring(G.diagControl))

  -- 玩区容器：占满画布、居中
  local playPrefab = param('playPrefab', param('ballPrefab', 1))
  G.area = game.InstantiateClientUIControl(playPrefab, root)
  if not G.area then error('创建玩区容器失败：playPrefab = ' .. tostring(playPrefab)) end
  G.area:SetActive(true)
  G.area:SetAnchoredPosition(0, 0)
  G.area:SetSizeDelta(w, h)

  -- 光标检测区域：铺满画布
  G.cursorArea = game.InstantiateClientUIControl(param('cursorPrefab', 3), G.area)
  if not G.cursorArea then error('创建光标检测区域失败：cursorPrefab = ' .. tostring(param('cursorPrefab', 3))) end
  G.cursorArea:SetActive(true)
  G.cursorArea:SetAnchoredPosition(0, 0)
  G.cursorArea:SetSizeDelta(w, h)
  say('玩区 = %s / 光标区 = %s', tostring(G.area), tostring(G.cursorArea))

  G.ui = UI.create({
    parent = G.area,
    canvas = G.canvas,
    ballPrefab = param('ballPrefab', 1),
    ballCount = param('ballCount', 96),
    shotPrefab = param('shotPrefab', param('ballPrefab', 1)),
    shotCount = param('shotCount', 8),
    hudPrefab = param('hudPrefab', 2),
    hud = buildHudSpecs(w, h),
  })

  G.input = INPUT.create({
    area = G.cursorArea,
    keyTarget = root,
    canvas = G.canvas,
  })


  say('控件池：球 %d / 弹药 %d', #G.ui.balls, #G.ui.shots)

  G.startLevel(param('levelIndex', 1))
  say('关卡 %s 已装配', tostring(G.level and G.level.id or '?'))
  return G
end

-- ==================== 关卡 ====================

function G.startLevel(idx)
  local total = #LEVELS_DATA.LEVELS
  if idx < 1 then idx = 1 end
  if idx > total then idx = total end
  G.levelIndex = idx
  G.level = LEVELS_DATA.LEVELS[idx]
  G.sc = BOARD.assembleScene(G.level, G.view, G.seed + idx)
  G.screen = 'playing'
  G.resultTimer = 0
  -- ★ 立刻同步一次：否则换关后的第一帧里，画面上还留着上一关的球
  if G.ui then UI.sync(G.ui, G.sc, G.syncState()) end
  return G.sc
end

-- ==================== 诊断行 ====================

-- ★ 这一行是"远程排错"的生命线：用户把屏幕上这句话念给我，我就知道卡在哪。
function G.refreshDiag()
  if not G.diag then return end
  local hc = G.diagControl
  if not hc then return end
  local s
  if G.error then
    s = '!! ' .. G.error
  else
    local balls = G.sc and #G.sc.chain.balls or 0
    local pool = G.ui and #G.ui.balls or 0
    local ctrl = 0
    if G.ui then ctrl = pool + #G.ui.shots + 7 end
    s = string.format('帧%d 关%s 球%d/%d 控件%d 状态%s', G.frames,
      tostring(G.level and G.level.id or '?'), balls, pool, ctrl, G.screen)
  end
  if #s > 240 then s = s:sub(1, 240) end
  if hc.text ~= s then hc.text = s end
end

-- ==================== 每帧 ====================

function G.OnUpdate(dt)
  -- 兜底：万一某些版本不调 OnStart，第一帧补建（此时已不在 OnInit 阶段，控件建得出来）
  if not G.booted then
    say('没等到 OnStart，在 OnUpdate 里补建')
    G.tryBoot()
  end
  G.frames = G.frames + 1
  if G.error then
    G.refreshDiag()
    return
  end
  local ok, err = pcall(G.tick, dt)
  if not ok then
    G.error = tostring(err)
    G.screen = 'error'
  end
  G.refreshDiag()
end

function G.tick(dt)
  if not G.sc then return end

  -- 结算画面：只等按键或超时，不再推进盘面
  if G.screen == 'won' or G.screen == 'lost' then
    G.resultTimer = G.resultTimer + dt
    local advance = G.input.wantRestart
    if not advance and G.resultTimer >= ((G.screen == 'won') and G.nextDelay or G.loseDelay) then
      advance = true
    end
    if advance then
      G.input.wantRestart = false
      if G.screen == 'won' and G.autoNext and G.levelIndex < #LEVELS_DATA.LEVELS then
        G.startLevel(G.levelIndex + 1)
      else
        G.startLevel(G.levelIndex)
      end
      return
    end
    UI.sync(G.ui, G.sc, G.syncState())
    return
  end

  if G.input.wantRestart then
    G.input.wantRestart = false
    G.startLevel(G.levelIndex)
    return
  end

  INPUT.update(G.input, G.sc, dt)

  if G.input.wantSwap then
    G.input.wantSwap = false
    RB.swapLoaded(G.sc.rb)
  end
  if G.input.wantMode then
    G.input.wantMode = false
    BOARD.toggleMode(G.sc)
  end

  if G.input.firing then
    -- 冷却由 board/RB 管：没冷却好会返回 nil，这时**不要**消费掉意图
    if BOARD.fireShot(G.sc) then INPUT.consume(G.input) end
  end

  BOARD.advanceScene(G.sc, dt)
  UI.sync(G.ui, G.sc, G.syncState())

  if G.sc.won then
    G.screen = 'won'
    G.resultTimer = 0
  elseif G.sc.gameOver then
    G.screen = 'lost'
    G.resultTimer = 0
  end
end

-- 给 ui.sync 的那一小包"表现层才关心的东西"
function G.syncState()
  local lines = {}
  if G.level and G.level.hint then
    for i = 1, #G.level.hint do lines[#lines + 1] = G.level.hint[i] end
  end
  if G.error then
    lines = { '出错了：' .. G.error }
  elseif G.screen == 'won' then
    lines = { '过关！（' .. tostring(G.sc.winReason) .. '）  按 R 重来' }
  elseif G.screen == 'lost' then
    lines = { '命数用尽  按 R 重来' }
  end
  return {
    mode = G.sc and G.sc.mode or 'match',
    hintLines = lines,
  }
end

function G.OnStart()
  -- 真机上这里是**第一个能建控件**的时机（OnInit 阶段 Instantiate 返回 nil）
  G.tryBoot()
end
function G.OnEnable() end
function G.OnDisable() end
function G.OnLevelUpdate(dt) end   -- OnUpdate 已经不受时停影响，这里不再重复推进
function G.OnDestroy()
  G.sc = nil
  G.ui = nil
  G.input = nil
end

-- 供本地测试/调试用（不改变行为）
function G.info()
  if not G.sc then return { screen = G.screen, error = G.error } end
  local info = BOARD.sceneInfo(G.sc)
  info.screen = G.screen
  info.level = G.level and G.level.id or '?'
  info.mode = G.sc.mode
  info.won = G.sc.won
  info.winReason = G.sc.winReason
  info.gameOver = G.sc.gameOver
  info.error = G.error
  return info
end

return G
end

-- ---------------- 对外门面 ----------------
-- 字段名与 lua/src 的文件名一致。
ZUMA = {
  rng = __require("rng"),
  config = __require("config"),
  elements = __require("elements"),
  geometry = __require("geometry"),
  spines = __require("spines"),
  chain = __require("chain"),
  run = __require("run"),
  projectile = __require("projectile"),
  ribosome = __require("ribosome"),
  board = __require("board"),
  levels_data = __require("levels_data"),
  ui = __require("ui"),
  input = __require("input"),
  game = __require("game"),
}

-- ★ 把生命周期回调暴露成**全局**：运行时是按固定名字查找的。
--   这些函数内部引用的是模块级的 G，不依赖 self，所以裸调用完全等价。
local __LIFECYCLE_NAMES = {
  "OnInit", "OnStart", "OnEnable", "OnDisable", "OnUpdate", "OnLevelUpdate", "OnDestroy"
}
for i = 1, #__LIFECYCLE_NAMES do
  local __n = __LIFECYCLE_NAMES[i]
  local __f = ZUMA.game[__n]
  if type(__f) == "function" then _G[__n] = __f end
end

return ZUMA

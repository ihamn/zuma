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

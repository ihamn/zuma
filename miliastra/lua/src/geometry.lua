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

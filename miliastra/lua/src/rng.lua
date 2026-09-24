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

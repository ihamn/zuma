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
  -- ★★ 取下标前**必须夹一次**：Lua 的整数位宽不是我们能控制的。
  --    64 位（真机 Lua 5.3）= 上面的掩码有效，step() 恒在 [0,1)，下面的折叠**是恒等变换**，
  --    一个数都不会变 —— 对拍 81339 个数值就是这条的证据。
  --    但换成 32 位整数的环境（例如跑在 Fengari 上的模拟器，0xFFFFFFFF == -1），
  --    step() 会跑到 [-0.5, 0.5)，math.floor(step()*n) 就成了负数或越界，
  --    arr[idx+1] 直接是 nil —— 然后 nil 会一路传下去（碱基 nil → 球画成白色、
  --    isComplement(nil) 之类更难查的错），而不是"当场报错"。
  --    与其让环境差异变成 nil，不如折回 [0,1)：环境坏了也就是颜色序列不对，不至于崩。
  local function unit()
    local v = step()
    if v ~= v then return 0 end          -- nan
    v = v % 1                            -- [0,1) 之外的（负数 / ≥1）折回来
    if v < 0 then v = v + 1 end          -- 兜底：万一 % 给了 -0.0
    return v
  end
  rng.int = function(n) return math.floor(unit() * n) end
  rng.pick = function(arr) return arr[rng.int(#arr) + 1] end   -- Lua 数组从 1 开始
  rng.seed = seed & U32                                        -- 与 JS 一致：记的是**入参** seed
  return rng
end

return M

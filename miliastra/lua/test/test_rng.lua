-- rng 的取值域：step() / int() / pick() 都不许越界，更不许返回 nil。
--
-- ★ 为什么单独给 rng 写一份测试：这类错**不会报错**，只会让碱基变成 nil ——
--   画面上是一颗白球，日志里什么都没有。换个 Lua 整数位宽就能复现：
--   模拟器（Fengari，32 位）里实测 rng.pick 有一半返回 nil。
--   64 位整数（真机 Lua 5.3）下 rng.lua 里的掩码有效，折叠是恒等变换 ——
--   等价性由对拍保证（81339 个数值），这里守的是"不许越界"这条底线。

local H = require('harness')
local RNG = require('rng')

H.suite('rng 取值域')

local r = RNG.makeRng(12345)
local bad, mn, mx = 0, 1e9, -1e9
for _ = 1, 20000 do
  local v = r()
  if v < mn then mn = v end
  if v > mx then mx = v end
  if v < 0 or v >= 1 then bad = bad + 1 end
end
H.eq(bad, 0, string.format('20000 次 step() 全在 [0,1)（实测 %.6f..%.6f）', mn, mx))

local r2 = RNG.makeRng(999)
local BASES = { 'A', 'U', 'G', 'C', 'T' }
local outOfRange, nilPick = 0, 0
for _ = 1, 20000 do
  local k = r2.int(5)
  if k < 0 or k >= 5 then outOfRange = outOfRange + 1 end
  if r2.pick(BASES) == nil then nilPick = nilPick + 1 end
end
H.eq(outOfRange, 0, '20000 次 rng.int(5) 全在 [0,5)')
H.eq(nilPick, 0, '20000 次 rng.pick 一次都没取到 nil')

-- 边界：n = 1 时只能是 0；数组只剩一个元素时 pick 必须拿到它
local r3 = RNG.makeRng(7)
local okOne = true
for _ = 1, 500 do if r3.int(1) ~= 0 then okOne = false end end
H.ok(okOne, 'rng.int(1) 恒为 0')
H.eq(r3.pick({ 'X' }), 'X', '只有一个元素时 pick 拿得到它')

-- 种子要真的起作用
local a, b = RNG.makeRng(1), RNG.makeRng(2)
local same = 0
for _ = 1, 100 do if a() == b() then same = same + 1 end end
H.ok(same < 10, '不同种子的序列不同（相同 ' .. same .. '/100）')

-- 同一个种子必须可复现（对拍与关卡装配都依赖这条）
local c1, c2 = RNG.makeRng(4242), RNG.makeRng(4242)
local diff = 0
for _ = 1, 200 do if c1() ~= c2() then diff = diff + 1 end end
H.eq(diff, 0, '同种子 200 次取值完全一致')

H.finish()

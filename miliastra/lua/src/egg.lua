--[[
================================================================================
彩蛋：「璃月黄金交易所」（千星奇域玩法致敬 · 隐藏小游戏）
================================================================================
来源：奇匠提供的玩家自制千星奇域玩法（模拟金融）。规则**照抄**，一条不改：

  · 报价    每 5s 更新一次，初始 100 元/g
  · 波动    单次 ±20，**近似正态**（开发者说不是纯随机，加了限制与算法）
  · 杠杆    可贷款加杠杆；单次只能借 1 万元，或借 100g 黄金去套现
  · 利息    只要欠款（含亏损/借款）就计息：**30 秒一次、每次 10%**，连本带利滚
            ⇒ 指数增长（"高利贷"）⇒ 利息从总资金里抽走 ⇒ **负和游戏**
  · 借款上限 欠款 ≥ 10 万，或黄金欠 > 1000g ⇒ **不能再借**
  · 做空    后期加入（本模块留了 sellShort 的口子）
  · 打工    耗时 30 秒、**仅欠款时可用**、单次还 20% ⇒ 唯一的**正和**出路

★ 本模块是**纯逻辑**（不建控件、不碰画面）：
  ui/game 侧只要读 st 里的字段就能把它画出来 —— 所以它**不占控件预算**，
  也**不影响对拍**（对拍比的是本体规则；彩蛋是移植侧专属）。

确定性：自带 LCG（不用 rng.lua，避免取到 nil 的老坑），同 seed 同结果 ⇒ 可测。
================================================================================
--]]

local M = {}

M.NAME = '璃月黄金交易所'

-- 规则常量（要调就改这里；注释里是玩法来源）
M.PRICE0      = 100      -- 初始价 元/g
M.TICK_SEC    = 3        -- 报价刷新间隔（奇匠："金价每3秒更新价格一次"）
M.VOL         = 20       -- 单次波动上限 ±20
M.INT_SEC     = 30       -- 利息结算间隔
M.INT_RATE    = 0.10     -- 每次 10%
M.BORROW_CASH = 10000    -- 单次能借 1 万元
M.BORROW_GOLD = 100      -- 或借 100g 黄金（套现）
M.CAP_CASH    = 100000   -- 欠款 ≥ 10 万 ⇒ 不能再借
M.CAP_GOLD    = 1000     -- 黄金欠 > 1000g ⇒ 不能再借
M.WORK_SEC    = 30       -- 打工占 30 秒
M.WORK_REPAY  = 0.20     -- 单次还 20%
M.WORK_PAY    = 3000     -- 打工一次的现金收入（用来还债；可调）

-- 自带线性同余，取值 [0,1)。参数取自 Numerical Recipes。
local function lcgNext(s)
  s = (1103515245 * s + 12345) % 2147483648
  return s, s / 2147483648
end

function M.new(seed)
  local st = {
    seed      = math.floor(seed or 20260925) % 2147483648,
    price     = M.PRICE0,
    cash      = 20000,     -- 本钱
    gold      = 0,         -- 持仓 g
    debtCash  = 0,         -- 欠的钱
    debtGold  = 0,         -- 欠的黄金 g
    tPrice    = 0,         -- 报价计时
    tInt      = 0,         -- 计息计时
    tWork     = 0,         -- 打工剩余时间（>0 表示正在打工）
    workDone  = 0,         -- 打工完成次数
    traded    = 0,         -- 成交次数
    interestPaid = 0,      -- 累计付出的利息（用来点题"负和"）
    lastDelta = 0,
    -- ★ 价格历史给界面画折线图。**开局就放一个初始价** ——
    --   否则第一个点是在第一次报价之后才记的，前两个点同值 ⇒ 画出来是零高度的线，看不见（踩过）。
    hist      = { M.PRICE0 },
    log       = {},
  }
  return st
end

local function note(st, s)
  st.log[#st.log + 1] = s
  if #st.log > 40 then table.remove(st.log, 1) end
end

function M.debtTotal(st)
  return st.debtCash + st.debtGold * st.price      -- 黄金欠款按现价折算
end

function M.netWorth(st)
  return st.cash + st.gold * st.price - M.debtTotal(st)
end

function M.canBorrow(st)
  return st.debtCash < M.CAP_CASH and st.debtGold <= M.CAP_GOLD
end

-- ★ 近似正态：三个均匀数之和（Irwin–Hall），再夹到 ±VOL
function M.rollDelta(st)
  local acc = 0
  for _ = 1, 3 do
    local r
    st.seed, r = lcgNext(st.seed)
    acc = acc + r
  end
  local d = (acc / 3 - 0.5) * 2 * M.VOL     -- 大致落在 ±VOL
  if d > M.VOL then d = M.VOL end
  if d < -M.VOL then d = -M.VOL end
  return d
end

-- 推进时间：报价刷新 / 计息 / 打工完成 / 一局限时
function M.tick(st, dt)
  local ev = {}
  -- ★ 局时倒计时（10 分钟）。时间到 ⇒ 不能再交易（结算画面由界面负责）。
  if not st.ended then
    st.left = (st.left or M.SESSION_SEC) - dt
    if st.left <= 0 then
      st.left = 0
      st.ended = true
      note(st, '时间到，收盘')
      ev[#ev + 1] = { type = 'close' }
    end
  end
  if st.ended then return ev end      -- 收盘后不再刷新报价/计息/打工
  -- 打工
  if st.tWork > 0 then
    st.tWork = st.tWork - dt
    if st.tWork <= 0 then
      st.tWork = 0
      local pay = M.WORK_PAY
      -- 先还债（20%），剩下的进现金
      local repay = M.debtTotal(st) * M.WORK_REPAY
      if repay > pay then repay = pay end
      local left = repay
      local fromCash = math.min(left, st.debtCash)
      st.debtCash = st.debtCash - fromCash
      left = left - fromCash
      if left > 0 then
        local g = left / st.price
        st.debtGold = math.max(0, st.debtGold - g)
      end
      st.cash = st.cash + (pay - repay)
      st.workDone = st.workDone + 1
      note(st, '打工完成，还了 ' .. string.format('%.0f', repay))
      ev[#ev + 1] = { type = 'work', repay = repay }
    end
  end
  -- 计息（只在有欠款时）
  st.tInt = st.tInt + dt
  while st.tInt >= M.INT_SEC do
    st.tInt = st.tInt - M.INT_SEC
    if M.debtTotal(st) > 0 then
      local add = st.debtCash * M.INT_RATE + st.debtGold * M.INT_RATE
      st.debtCash = st.debtCash + st.debtCash * M.INT_RATE
      st.debtGold = st.debtGold + st.debtGold * M.INT_RATE
      st.interestPaid = st.interestPaid + add
      note(st, '利息 +' .. string.format('%.0f', add) .. '（10% / 30s）')
      ev[#ev + 1] = { type = 'interest', add = add }
    end
  end
  -- 报价
  st.tPrice = st.tPrice + dt
  while st.tPrice >= M.TICK_SEC do
    st.tPrice = st.tPrice - M.TICK_SEC
    local d = M.rollDelta(st)
    local np = st.price + d
    if np < 1 then np = 1 end
    st.lastDelta = np - st.price
    st.price = np
    st.priceTick = (st.priceTick or 0) + 1    -- ★ 报价序号：还金要等它变过（借金/还金之间必须隔一次波动）
    -- ★ 价格历史（给界面画折线图用）：只留最近 HISTORY 个点
    st.hist = st.hist or { st.price }
    st.hist[#st.hist + 1] = np
    while #st.hist > M.HISTORY do table.remove(st.hist, 1) end
    note(st, string.format('报价 %.0f（%+.1f）', st.price, st.lastDelta))
    ev[#ev + 1] = { type = 'price', price = st.price, delta = st.lastDelta }
  end
  return ev
end

-- 交易
function M.buy(st, grams)
  grams = grams or 1
  local cost = grams * st.price
  if cost > st.cash then return false, '现金不够' end
  st.cash = st.cash - cost
  st.gold = st.gold + grams
  st.traded = st.traded + 1
  return true
end

function M.sell(st, grams)
  grams = grams or 1
  if grams > st.gold then return false, '没这么多黄金' end
  st.gold = st.gold - grams
  st.cash = st.cash + grams * st.price
  st.traded = st.traded + 1
  return true
end

-- 借 1 万元
function M.borrowCash(st)
  if not M.canBorrow(st) then return false, '欠款到顶，借不了了' end
  st.cash = st.cash + M.BORROW_CASH
  st.debtCash = st.debtCash + M.BORROW_CASH
  note(st, '借款 ' .. M.BORROW_CASH)
  return true
end

-- 借 100g 黄金并立刻套现
function M.borrowGold(st)
  if not M.canBorrow(st) then return false, '欠款到顶，借不了了' end
  st.debtGold = st.debtGold + M.BORROW_GOLD
  st.cash = st.cash + M.BORROW_GOLD * st.price
  note(st, '借金 ' .. M.BORROW_GOLD .. 'g 套现')
  return true
end

-- ★ 做空（奇匠："做空每回100啊！"）：每按一次借入 100g 黄金并立刻按现价卖掉
--   ⇒ 手上多一笔现金、同时欠 100g 黄金 ⇒ 金价跌了就赚、涨了就亏。
-- ★ 借金套现（奇匠术语："借金" = 借金套现）：借入 100g 黄金并**立刻按现价卖掉**
--   ⇒ 手上多一笔现金、同时欠 100g 黄金。金价跌了赚、涨了亏。
--   ⚠ 一次一档价：同一档报价里借的，**必须等到下一次报价刷新**才能还金（见下）。
M.SHORT_GOLD = 100
-- ★ 一局 10 分钟（原奇域的限时）。报价 3 秒一档 ⇒ 一局大约 **200 个价格点**。
--   界面不画 200 段折线（控件不够，也不好看），而是**聚合成 40 根 K 线柱**（每根 5 档）：
--   柱高 = 这 5 档里的最高/最低，色 = 收在开盘之上红、之下绿 —— 这才是"现实里的 K 线"观感。
M.SESSION_SEC = 600      -- 一局多久（10 分钟）
M.HISTORY    = 200       -- 保留多少个报价点（10 分钟 ÷ 3 秒 ≈ 200）
function M.short(st)
  if not M.canBorrow(st) then return false, '欠款到顶，借不了金' end
  st.debtGold = st.debtGold + M.SHORT_GOLD
  st.cash = st.cash + M.SHORT_GOLD * st.price
  st.traded = st.traded + 1
  st.shortPrice = st.price          -- ★ 记下借金套现那一档的价格
  st.shortTick = st.priceTick or 0  -- ★ 以及那一档的报价序号
  note(st, '借金套现 ' .. M.SHORT_GOLD .. 'g @ ' .. string.format('%.1f', st.price)
    .. '（欠金 ' .. string.format('%.0f', st.debtGold) .. 'g）')
  return true
end

-- ★ 还金（借金套现的**平仓**）：按**现价**把欠的黄金折成现金还掉（等量黄金价值的现金）。
--   ⚠ 奇匠纠正过：**不需要等波动** —— 玩家完全可以"借完秒还" ✓。
--   我一度加了"必须等下一次报价"的硬约束，那是**错的** ✗（已撤）。
--   秒还的后果天然合理：同一档价借了立刻还 ⇒ 现金原地打转、不赚不赔 ⇒ 想赚就得自己等波动 ✓，
--   这个"等"是玩家自己的选择，不该由系统锁死 ✓。
M.REPAY_GOLD = 100
function M.repayGold(st)
  if (st.debtGold or 0) <= 0 then return false, '没有金欠要还' end
  local grams = math.min(M.REPAY_GOLD, st.debtGold)
  local cost = grams * st.price          -- 等量黄金价值 = 克数 × 现价
  if cost > st.cash then return false, '现金不够还这一笔' end
  st.cash = st.cash - cost
  st.debtGold = st.debtGold - grams
  st.traded = st.traded + 1
  note(st, '还金 ' .. string.format('%.0f', grams) .. 'g @ ' .. string.format('%.1f', st.price)
    .. '（付现金 ' .. string.format('%.0f', cost) .. '）')
  return true
end

-- 打工：30 秒、仅欠款时可用
function M.work(st)
  if M.debtTotal(st) <= 0 then return false, '不欠钱，不用打工' end
  if st.tWork > 0 then return false, '正在打工' end
  st.tWork = M.WORK_SEC
  note(st, '开始打工（30s）')
  return true
end

return M

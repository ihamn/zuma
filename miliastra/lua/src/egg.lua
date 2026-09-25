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
M.TICK_SEC    = 5        -- 报价刷新间隔
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

-- 推进时间：报价刷新 / 计息 / 打工完成
function M.tick(st, dt)
  local ev = {}
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
--   和"借 100g 套现"是同一套账（原玩法里做空就是这么做的），但这里是**独立动作**：
--   有自己的常量、自己的上限判定、自己的日志。
M.SHORT_GOLD = 100
function M.short(st)
  if not M.canBorrow(st) then return false, '欠款到顶，做不了空' end
  st.debtGold = st.debtGold + M.SHORT_GOLD
  st.cash = st.cash + M.SHORT_GOLD * st.price
  st.traded = st.traded + 1
  note(st, '做空 ' .. M.SHORT_GOLD .. 'g（欠金 ' .. string.format('%.0f', st.debtGold) .. 'g）')
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

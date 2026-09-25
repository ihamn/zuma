-- 彩蛋「璃月黄金交易所」规则自检（照奇匠给的玩法一条条验）
local H = require('harness')
local EGG = require('egg')

print('  [彩蛋自检] 开始（这条 print 是为了确认这个文件真的被执行了）')
H.suite('彩蛋：璃月黄金交易所')

-- ① 初始状态：100 元/g
local st = EGG.new(12345)
H.eq(st.price, 100, '初始价 100 元/g')
H.eq(EGG.debtTotal(st), 0, '开局不欠钱')
H.eq(EGG.canBorrow(st), true, '开局可以借')

-- ② 报价：每 5s 一次，波动在 ±20 内
local minD, maxD = 1e9, -1e9
for _ = 1, 200 do
  local d = EGG.rollDelta(st)
  if d < minD then minD = d end
  if d > maxD then maxD = d end
end
H.ok(maxD <= EGG.VOL and minD >= -EGG.VOL, '单次波动落在 ±' .. EGG.VOL .. ' 内（实测 ' ..
  string.format('%.2f', minD) .. '~' .. string.format('%.2f', maxD) .. '）')
local s0 = EGG.new(777)
local evs = EGG.tick(s0, 4.9)
H.eq(#evs, 0, '不到 5s 不刷新报价')
evs = EGG.tick(s0, 0.2)
H.eq(#evs, 1, '满 5s 刷一次报价')
H.ok(s0.price ~= 100, '报价确实变了（' .. string.format('%.1f', s0.price) .. '）')

-- ③ 利息：30s 一次、每次 10%，且只欠款时计
local s1 = EGG.new(1)
s1.debtCash = 10000
EGG.tick(s1, 30)
H.eq(s1.debtCash, 11000, '欠 1 万，30s 后变 1.1 万（+10%）')
EGG.tick(s1, 30)
H.eq(s1.debtCash, 12100, '再 30s 变 1.21 万（复利，不是 1.2 万）')
local s2 = EGG.new(1)
EGG.tick(s2, 30)
H.eq(s2.debtCash, 0, '不欠钱就不计息')

-- ④ 借款规则与上限
local s3 = EGG.new(1)
H.ok(EGG.borrowCash(s3), '借 1 万')
H.eq(s3.cash, 30000, '现金 2 万 + 1 万 = 3 万')
H.eq(s3.debtCash, 10000, '欠款记 1 万')
H.ok(EGG.borrowGold(s3), '借 100g 黄金套现')
H.eq(s3.gold, 0, '借来的黄金立刻套现（不留在手上）')
H.eq(s3.debtGold, 100, '黄金欠款记 100g')
s3.debtCash = 100000
H.eq(EGG.canBorrow(s3), false, '欠款 ≥ 10 万 ⇒ 不能再借')
H.ok(not EGG.borrowCash(s3), '确实借不出来了')
s3.debtCash = 0; s3.debtGold = 1001
H.eq(EGG.canBorrow(s3), false, '黄金欠 > 1000g ⇒ 不能再借')

-- ⑤ 负和：利息真的从总资金里抽走
local s4 = EGG.new(1)
s4.cash = 0; s4.gold = 0; s4.debtCash = 10000
local before = EGG.netWorth(s4)
EGG.tick(s4, 30)
local after = EGG.netWorth(s4)
H.ok(after < before, '光欠着不动，净资产就变少（负和）：' ..
  string.format('%.0f', before) .. ' → ' .. string.format('%.0f', after))

-- ⑥ 打工：唯一的正和出路（30s、仅欠款时、还 20%）
local s5 = EGG.new(1)
H.ok(not EGG.work(s5), '不欠钱不能打工')
s5.debtCash = 10000
H.ok(EGG.work(s5), '欠款时可以打工')
H.ok(not EGG.work(s5), '打工中不能重复点')
EGG.tick(s5, 15)
H.eq(s5.workDone, 0, '15s 还没打完')
EGG.tick(s5, 16)
H.eq(s5.workDone, 1, '满 30s 完成一次')
H.ok(s5.debtCash < 10000, '打工确实还了债（剩 ' .. string.format('%.0f', s5.debtCash) .. '）')

-- ⑦ 买卖
local s6 = EGG.new(1)
H.ok(EGG.buy(s6, 10), '买 10g')
H.eq(s6.gold, 10, '持仓 10g')
H.ok(not EGG.buy(s6, 10000), '钱不够买不了')
H.ok(EGG.sell(s6, 10), '卖 10g')
H.eq(s6.gold, 0, '持仓清空')

-- ⑧ 确定性：同 seed 同结果（可测、可复现）
local a, b = EGG.new(2026), EGG.new(2026)
for _ = 1, 100 do EGG.tick(a, 1); EGG.tick(b, 1) end
H.eq(a.price, b.price, '同 seed 报价完全一致（' .. string.format('%.2f', a.price) .. '）')

-- ⑨ 借金套现 / 还金：**可以秒还**（奇匠纠正："还金不需要等波动再还，玩家完全可以借完秒还"）
local s7 = EGG.new(1)
H.ok(EGG.short(s7), '借金套现 100g')
H.eq(s7.debtGold, 100, '金欠 100g')
H.eq(s7.cash, 20000 + 100 * s7.price, '现金多了 100g 的钱（套现）')
H.ok(EGG.repayGold(s7), '★ 借完**秒还**也允许（系统不要求等波动）')
H.eq(s7.debtGold, 0, '金欠还清')
H.eq(s7.cash, 20000, '秒还后现金回到原样（同一档价 ⇒ 不赚不赔，这是对的）')
-- 换一档价再还，才出现赚赔
local s8 = EGG.new(1)
EGG.short(s8)
EGG.tick(s8, 5.1)
s8.cash = s8.cash + 100000
H.ok(EGG.repayGold(s8), '等过一次报价再还也可以')
H.eq(s8.debtGold, 0, '金欠还清')
H.ok(s8.cash ~= 20000 + 100000, '换了一档价 ⇒ 现金与"秒还"不同（赚赔来自价格波动）')
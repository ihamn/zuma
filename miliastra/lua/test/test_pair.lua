-- test_pair.lua —— 命中判定：互补 = 配对（进三消道），非互补 = 错配（灰球）
--
-- ★ 为什么要单独立一条：真机上用户报"打中以后三消道那颗球是灰的"，
--   而在此之前**没有任何断言直接盯"这一枪算配对还是错配"** —— 对拍覆盖了 stats.pairs /
--   stats.mismatches 的数值，但没有一条"人话"测试说明这条规则。
--   这里就用最直白的方式钉住：把弹丸碱基设成球的互补 → 必须 pairs+1；
--   设成非互补 → 必须 mismatches+1，且球被标记 wrongMark（UI 会画成灰的）。
local H = require('harness')
local MOCK = require('mock')
local CFG = require('config')
local BOARD = require('board')
local RB = require('ribosome')

local host = MOCK.newHost({ w = 900, h = 900 })
MOCK.install(host)

local function freshScene(seed)
  local view = CFG.viewFor(900, 900)
  local mt = CFG.metrics(view.scale)
  local level = require('levels_data').byId('spiral-outer')
  local sc = BOARD.assembleScene(level, view, seed or 20260925)
  return sc, mt
end

-- 朝某颗球打一枪，跑到命中为止（最多 3 秒 = 180 帧）
local function shootAt(sc, ball)
  local before = { pairs = sc.stats.pairs, mis = sc.stats.mismatches }
  local frames = 0
  if not RB.canFire(sc.rb) then
    for _ = 1, 60 do BOARD.advanceScene(sc, 1 / 60) end
  end
  RB.aimAt(sc.rb, ball.x, ball.y)
  BOARD.fireShot(sc)
  for _ = 1, 180 do
    BOARD.advanceScene(sc, 1 / 60)
    frames = frames + 1
    if sc.stats.pairs > before.pairs or sc.stats.mismatches > before.mis then break end
  end
  return frames
end

-- ---------- ① 互补 → 配对 ----------
do
  local sc = freshScene()
  local ball = sc.chain.balls[1]
  H.truthy(ball and ball.base, '第一颗球有碱基：' .. tostring(ball and ball.base))
  local mate = CFG.COMPLEMENT[ball.base] and CFG.COMPLEMENT[ball.base][1]
  H.truthy(mate, ball.base .. ' 有互补碱基')
  sc.rb.loaded[1] = mate
  local f = shootAt(sc, ball)
  H.eq(sc.stats.pairs, 1, '★ 弹丸 ' .. mate .. ' 打中球 ' .. ball.base .. ' → 配对（用了 ' .. f .. ' 帧）')
  H.eq(sc.stats.mismatches, 0, '没有错配')
  H.eq(ball.wrongMark, false, '配对时球**不**标灰')
  H.eq(ball.pairBase, mate, '球的 pairBase 记的是弹丸的碱基（三消道上那颗的身份）')

  -- 三消道上应该**出现一颗绑定球**（用户报"匹配后三消道没有球"，这里钉住它必须有）
  BOARD.syncBeads(sc)
  H.eq(#sc.beads.eliminate, 1, '★ 配对后三消道上有 1 颗绑定球')
  H.eq(sc.beads.eliminate[1].wrong, false, '绑定球不是灰的')
  H.eq(sc.beads.eliminate[1].base, mate, '绑定球的碱基 = 弹丸的碱基（' .. mate .. '）')
end

-- ---------- ② 非互补 → 错配 ----------
do
  local sc = freshScene()
  local ball = sc.chain.balls[1]
  local notMate
  for i = 1, #CFG.BASES do
    local b = CFG.BASES[i]
    if not CFG.isComplement(b, ball.base) then notMate = b; break end
  end
  H.truthy(notMate, '找得到一个非互补的碱基')
  sc.rb.loaded[1] = notMate
  local f = shootAt(sc, ball)
  H.eq(sc.stats.mismatches, 1, '★ 弹丸 ' .. notMate .. ' 打中球 ' .. ball.base .. ' → 错配（用了 ' .. f .. ' 帧）')
  H.eq(sc.stats.pairs, 0, '没有配对')
  H.eq(ball.wrongMark, true, '错配时球被标灰（wrongMark=true）')
  BOARD.syncBeads(sc)
  H.eq(#sc.beads.eliminate, 1, '错配也会在三消道留一颗绑定球')
  H.eq(sc.beads.eliminate[1].wrong, true, '★ 错配的绑定球是**灰的**（UI 用 WRONG_COLOR 画）')
end

-- ---------- ③ 互补表本身：A↔U/T、G↔C，自己配自己一律不算 ----------
H.eq(CFG.isComplement('A', 'U'), true, 'A 配 U')
H.eq(CFG.isComplement('A', 'T'), true, 'A 配 T')
H.eq(CFG.isComplement('U', 'A'), true, 'U 配 A')
H.eq(CFG.isComplement('G', 'C'), true, 'G 配 C')
H.eq(CFG.isComplement('C', 'G'), true, 'C 配 G')
H.eq(CFG.isComplement('A', 'A'), false, '★ 同碱基**不算**配对（A 打 A 是错配）')
H.eq(CFG.isComplement('G', 'G'), false, 'G 打 G 是错配')
H.eq(CFG.isComplement(nil, 'A'), false, '弹丸碱基 nil → 错配（不会崩）')
H.eq(CFG.isComplement('A', nil), false, '球碱基 nil → 错配（不会崩）')

H.finish()

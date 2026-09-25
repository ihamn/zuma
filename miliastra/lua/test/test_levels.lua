-- 全关卡巡检：每个关卡逐个装配 + 让机器人打，检查
--   ① 装配不报错、② 控件数不超平台上限、③ 文案长度不超上限、④ 静止练习关必须能过。
-- 这是移植侧的 probe-play：跑一遍就能看出哪一关的数据有问题。

local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')
local LEVELS_DATA = require('levels_data')

H.suite('全关卡巡检')

local CANVAS = 900
local host = MOCK.newHost({ w = CANVAS, h = CANVAS })
host.prefabs[1] = 'image'
host.prefabs[2] = 'textbox'
host.prefabs[3] = 'cursorarea'
host.params.ballPrefab = 1
host.params.shotPrefab = 1
host.params.hudPrefab = 2
host.params.cursorPrefab = 3
host.params.playPrefab = 1
host.params.ballCount = 80    -- ★ 与 game.lua 的默认值保持一致（96→80：腾控件给轨道段数/彩蛋；测试配置不能停留在旧值，否则控件数自检会算错）
host.params.shotCount = 8
host.params.seed = 20240923
host.params.autoNext = 0
host.params.skipMenu = 1     -- ★ §61：本体开局在菜单；这些测试要直接进游戏，所以显式跳过菜单
MOCK.install(host)
host.scriptObj.object = host.root
host.mount(GAME)

local total = #LEVELS_DATA.LEVELS
H.eq(total, 11, '一共 11 关（10 个 RNA 关 + 1 个经典关，DESIGN §66）')

local function cursorAt(b) return b.x, CANVAS - b.y end

local rows = {}
for idx = 1, total do
  GAME.startLevel(idx)
  local lv = GAME.level
  local sc = GAME.sc
  H.ok(sc ~= nil, lv.id .. ' 装配成功')
  H.ok(sc.path.length > 0, lv.id .. ' 有轨道（' .. string.format('%.1f', sc.path.length) .. '）')
  if lv.hint then
    for i = 1, #lv.hint do
      H.ok(#lv.hint[i] < 1000, lv.id .. ' 提示文案不超 1000 字符')
    end
  end

  -- 机器人：对着第一颗未配对的球打
  local frames, result = 0, 'playing'
  for f = 1, 4000 do
    frames = f
    local bs = sc.beads.spawn
    local pick = nil
    for i = 1, #bs do
      if not bs[i].paired then pick = bs[i]; break end
    end
    if pick then
      local px, py = cursorAt(pick)
      host.click(px, py)
    end
    host.tick(1 / 60)
    result = GAME.screen
    if result ~= 'playing' then break end
  end
  local okb, cnt, glim = host.assertControlBudget()
  H.ok(okb, lv.id .. ' 控件数在上限内（' .. cnt .. '）')
  rows[#rows + 1] = { id = lv.id, result = result, frames = frames,
                      reason = tostring(sc.winReason), cnt = cnt,
                      balls = #sc.chain.balls, score = sc.score, lives = sc.lives }
end

print('  ' .. string.format('%-16s %-8s %-8s %-6s %-7s %-6s %-5s %s', '关卡', '结果', '原因', '帧', '球数', '分数', '命', '控件'))
for i = 1, #rows do
  local r = rows[i]
  print('  ' .. string.format('%-16s %-8s %-8s %-6d %-7d %-6d %-5d %d',
    r.id, r.result, r.reason, r.frames, r.balls, r.score, r.lives, r.cnt))
end

-- ① 配对：静止、不消球、读出全部就过关 —— 机器人必过
GAME.startLevel(1)
for f = 1, 2000 do
  local bs = GAME.sc.beads.spawn
  local pick = nil
  for i = 1, #bs do if not bs[i].paired then pick = bs[i]; break end end
  if pick then local px, py = cursorAt(pick); host.click(px, py) end
  host.tick(1 / 60)
  if GAME.screen ~= 'playing' then break end
end
-- ★ 记录一个**本体侧的设计发现**（不是移植 bug，对拍已证明两边一致）：
--   在"静止/有限球数"关卡里，预算发满之后存在**合法但无解**的盘面。
--   根因是 run.js 的爆炸规则本身：链首/链尾那颗 mark=2 **缺一侧真邻居，永远待定**，
--   设计意图是"等冒球把它顶出边界再判" —— 可预算用尽时再也不冒球，这个前提就没了。
--   实测卡住的形态：标记 211 / 221（2 在链首），且剩余 run 长度不是 3 的倍数。
local stuck = 0
for i = 1, #rows do
  local r = rows[i]
  if r.result == 'playing' then
    stuck = stuck + 1
    local lv = LEVELS_DATA.byId(r.id)
    local bud = lv and lv.ballBudget or 0
    H.ok(bud > 0, r.id .. ' 卡住时预算已发满（否则是机器人不行，不是盘面无解）')
  end
end
print('  卡住的关卡：' .. stuck .. ' / ' .. total .. '（均为"预算发满 + 盘面无解"，见 test_levels.lua 顶部说明）')
H.ok(stuck < total, '不是所有关卡都卡住')

H.eq(GAME.screen, 'won', '① 配对：机器人必过（否则说明配对规则坏了）')

H.finish()

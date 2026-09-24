-- 表现层 + 输入层 + 宿主胶水的联调测试（无头）。
--
-- 这是"在编辑器里跑起来"之前能拿到的最强证据：
-- 同一份 ui.lua / input.lua / game.lua，在假宿主上跑完整的一关。

local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')
local INPUT = require('input')

H.suite('ui + input + game（无头整关）')

local CANVAS = 900
local host = MOCK.newHost({ w = CANVAS, h = CANVAS })
host.prefabs[1] = 'image'
host.prefabs[2] = 'textbox'
host.prefabs[3] = 'cursorarea'
host.params.levelIndex = 1        -- ① 配对：静止、不消球、读出全部就过关
host.params.ballPrefab = 1
host.params.shotPrefab = 1
host.params.hudPrefab = 2
host.params.cursorPrefab = 3
host.params.playPrefab = 1
host.params.ballCount = 32
host.params.shotCount = 4
host.params.seed = 4242
host.params.autoNext = 0
MOCK.install(host)
host.scriptObj.object = host.root

host.mount(GAME)

-- 控件池
H.eq(#GAME.ui.balls, 32, '球池 32 个')
H.eq(#GAME.ui.shots, 4, '弹药池 4 个')
H.eq(GAME.screen, 'playing', '开局就在 playing')
H.eq(GAME.level.id, 't1-pair', '默认第一关是 ① 配对')
local okb, cnt, glim = host.assertControlBudget()
H.ok(okb, '控件数在上限内：' .. cnt .. ' <= ' .. glim)

-- 第一帧：球应该被摆出来了
host.tick(1 / 60)
local visible = 0
for i = 1, #GAME.ui.balls do
  if GAME.ui.balls[i].visible then visible = visible + 1 end
end
H.eq(visible, #GAME.sc.beads.spawn, '可见球数 = 场上球数')
H.near(GAME.ui.balls[1].sizeDeltaX, 2 * GAME.sc.metrics.R, 1e-9, '球的尺寸 = 2R')
H.truthy(GAME.ui.hud.score.text:find('分数'), 'HUD 分数有文字：' .. tostring(GAME.ui.hud.score.text))

-- 坐标换算：把光标放到某颗球的**屏幕位置**上，瞄准则应该对着它
local function cursorAt(b) return b.x, CANVAS - b.y end
local target = GAME.sc.beads.spawn[3]
local cx, cy = cursorAt(target)
host.setCursor(cx, cy)
INPUT.update(GAME.input, GAME.sc, 1 / 60)
local expect = math.atan(target.y - GAME.sc.rb.y, target.x - GAME.sc.rb.x)
H.near(GAME.sc.rb.aim, expect, 1e-6, '瞄准角指向光标所在的那颗球')

-- 点一下 = 打一发
host.click(cx, cy)
host.tick(1 / 60)
H.ok(GAME.sc.stats.fired >= 1, '点击后至少发射了一发（fired=' .. GAME.sc.stats.fired .. '）')

-- 切模式（Tab）：要在 playing 状态下按
local modeBefore = GAME.sc.mode
host.keyEvent(Enum.KeyboardKeyCode.TabKey, true)
host.tick(1 / 60)
H.ok(GAME.sc.mode ~= modeBefore, 'Tab 切了模式：' .. modeBefore .. ' -> ' .. GAME.sc.mode)
host.keyEvent(Enum.KeyboardKeyCode.TabKey, true)
host.tick(1 / 60)
H.eq(GAME.sc.mode, modeBefore, '再按一次切回来')

-- 换球（空格）：不报错且两颗都还在
host.keyEvent(Enum.KeyboardKeyCode.SpaceJumpKey, true)
host.tick(1 / 60)
H.ok(GAME.sc.rb.loaded[1] ~= nil and GAME.sc.rb.loaded[2] ~= nil, '换球后两颗都在')

-- 机器人：每帧把光标放到一颗未配对的球上并点击，直到过关
local frames = 0
for f = 1, 2000 do
  frames = f
  local bs = GAME.sc.beads.spawn
  local pick = nil
  for i = 1, #bs do
    if not bs[i].paired then pick = bs[i]; break end
  end
  if pick then
    local px, py = cursorAt(pick)
    host.click(px, py)
  end
  host.tick(1 / 60)
  if GAME.screen ~= 'playing' then break end
end
H.eq(GAME.screen, 'won', '① 配对关打完了（用了 ' .. frames .. ' 帧）')
H.eq(GAME.sc.winReason, 'match', '过关原因是 match（读出全部）')

-- 过关后 HUD 显示结果
host.tick(1 / 60)
H.truthy(GAME.ui.hud.hint.text:find('过关'), '结算提示：' .. tostring(GAME.ui.hud.hint.text))

-- R 重开
host.keyEvent(Enum.KeyboardKeyCode.KeyR, true)
host.tick(1 / 60)
H.eq(GAME.screen, 'playing', 'R 之后回到 playing')
H.eq(GAME.sc.stats.fired, 0, '重开后备弹计数归零')

-- 换一关（⑥ 洞穴：有轨道、会输）
GAME.startLevel(6)
H.eq(GAME.level.id, 't6-cave', '第 6 关是 ⑥ 洞穴')
H.eq(GAME.sc.still, false, '洞穴关不是静止关')
H.truthy(GAME.sc.path.length > 0, '有轨道')
local cc = 0
for i = 1, #GAME.ui.balls do if GAME.ui.balls[i].visible then cc = cc + 1 end end
H.eq(cc, #GAME.sc.beads.spawn, '换关立刻同步：不会闪过一帧旧盘面（' .. cc .. ' 个）')

-- 一直不开火 -> 队头会被洞穴吞掉，扣光 3 条命 -> gameOver。
-- ⚠ 这里要给足帧数：见下方"链子会先卡住约 1700 帧"的说明（那是本体行为，不是移植 bug）。
local lostAt = nil
for f = 1, 20000 do
  host.tick(1 / 60)
  if GAME.screen == 'lost' then lostAt = f break end
end
H.truthy(lostAt, '放着不管终会输（第 ' .. tostring(lostAt) .. ' 帧）')
H.eq(GAME.sc.gameOver, true, 'gameOver 已置位')

H.finish()

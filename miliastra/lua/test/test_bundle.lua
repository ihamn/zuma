-- 打包产物测试：直接跑 **out/zuma.lua**（要上传的那个文件）。
--
-- 与 test_game.lua 的区别：那个跑的是 require 出来的模块；这个跑的是**单文件、走全局生命周期**
-- 的那一份 —— 也就是千星奇域真正会执行的东西。两层都要过。

local H = require('harness')
local MOCK = require('mock')

H.suite('out/zuma.lua（上传产物的无头整关）')

local chunk, err = loadfile('out/zuma.lua')
H.truthy(chunk, 'out/zuma.lua 能编译：' .. tostring(err))
if not chunk then H.finish() end
local Z = chunk()

H.eq(type(Z), 'table', '返回值是门面表')
local n = 0
for _ in pairs(Z) do n = n + 1 end
H.eq(n, 16, '16 个模块（多了 menu.lua：开始菜单布局；再多了 egg.lua：彩蛋「璃月黄金交易所」）')
H.eq(type(Z.game), 'table', '有 game 模块')
H.eq(type(Z.board), 'table', '有 board 模块')
H.eq(type(Z.ui), 'table', '有 ui 模块')

-- 运行时是**按固定名字**找生命周期回调的，所以必须是全局
for _, name in ipairs({ 'OnInit', 'OnStart', 'OnEnable', 'OnDisable', 'OnUpdate', 'OnLevelUpdate', 'OnDestroy' }) do
  H.eq(type(_G[name]), 'function', '全局回调 ' .. name)
end

-- 装假宿主，然后**像运行时那样**调用全局 OnInit / OnUpdate
local CANVAS = 900
local host = MOCK.newHost({ w = CANVAS, h = CANVAS })
host.prefabs[1] = 'image'
host.prefabs[2] = 'textbox'
host.prefabs[3] = 'cursorarea'
host.params.levelIndex = 1
host.params.ballPrefab = 1
host.params.shotPrefab = 1
host.params.hudPrefab = 2
host.params.cursorPrefab = 3
host.params.playPrefab = 1
host.params.ballCount = 32
host.params.shotCount = 4
host.params.seed = 4242
host.params.autoNext = 0
host.params.skipMenu = 1     -- ★ §61：本体开局在菜单；这些测试要直接进游戏，所以显式跳过菜单
MOCK.install(host)
host.scriptObj.object = host.root

-- ★ 按真机的两段式走：OnInit 阶段建不出控件（Instantiate 返回 nil），OnStart 才建得出来
host.beginInit()
OnInit()
host.enterStart()          -- ← 这一步就是"真机到了 OnStart 才建得出控件"的那条线
OnStart()
host.enterRunning()
local info = Z.game.info()
H.eq(info.level, 't1-pair', 'OnStart 后进了第一关：' .. tostring(info.level))
H.eq(info.screen, 'playing', '屏幕状态 playing')
local okb, cnt, glim = host.assertControlBudget()
H.ok(okb, '控件 ' .. cnt .. ' 个，上限 ' .. glim)

-- 机器人过关
local function cursorAt(b) return b.x, CANVAS - b.y end
local frames = 0
for f = 1, 2000 do
  frames = f
  local sc = Z.game.sc
  local pick = nil
  for i = 1, #sc.beads.spawn do
    if not sc.beads.spawn[i].paired then pick = sc.beads.spawn[i]; break end
  end
  if pick then
    local px, py = cursorAt(pick)
    host.click(px, py)
  end
  OnUpdate(1 / 60)          -- ← 走全局回调，和运行时一致
  if Z.game.info().screen ~= 'playing' then break end
end
local fin = Z.game.info()
H.eq(fin.screen, 'won', '① 配对关通过（' .. frames .. ' 帧）')
H.eq(fin.winReason, 'match', '过关原因 match')
H.ok(fin.balls >= 0, '球数读数正常：' .. fin.balls)

H.finish()

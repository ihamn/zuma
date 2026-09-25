-- 开始菜单（DESIGN.md §61 / 本体 main.js + config.js + render.js 的对应物）。
--
-- 为什么单独一份：这一块**做错了不报错**——玩家只是点不动、或者菜单里链子自己在爬。
-- 断言逐条对着本体的行为写：开局在菜单、菜单态不推进盘面、只判按钮、点别处不发射、
-- 局内左下角按钮能回菜单、skipMenu=1 能直接进游戏。

local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')
local MENU = require('menu')
local LEVELS_DATA = require('levels_data')
local CFG = require('config')

H.suite('开始菜单（§61）')

local CANVAS = 900
local function newHost(extra)
  local host = MOCK.newHost({ w = CANVAS, h = CANVAS })
  host.prefabs[1] = 'image'
  host.prefabs[2] = 'textbox'
  host.prefabs[3] = 'cursorarea'
  host.params.ballPrefab = 1
  host.params.shotPrefab = 1
  host.params.hudPrefab = 2
  host.params.cursorPrefab = 3
  host.params.playPrefab = 1
  host.params.ballCount = 32
  host.params.shotCount = 4
  host.params.seed = 4242
  host.params.autoNext = 0
  host.params.levelIndex = 1
  for k, v in pairs(extra or {}) do host.params[k] = v end
  MOCK.install(host)
  host.scriptObj.object = host.root
  host.mount(GAME)
  return host
end

local function cursorAt(b) return b.x, CANVAS - b.y end

-- ---------- ① 条目表（本体 main.js re build() 里那段 map） ----------
local items = MENU.items(LEVELS_DATA.LEVELS, LEVELS_DATA.TUTORIAL_COUNT)
H.eq(#items, 10, '菜单条目 = 10 关')
H.eq(items[1].index, 0, '条目 index 是 0 基（和本体一致）')
H.eq(items[1].group, '新手关', '第 1 个属于新手关')
H.eq(items[1].label, LEVELS_DATA.LEVELS[1].name, '新手关用关卡全名：' .. tostring(items[1].label))
local tutN = LEVELS_DATA.TUTORIAL_COUNT or 0
H.eq(items[tutN].group, '新手关', '第 ' .. tutN .. ' 个仍是新手关')
H.eq(items[tutN + 1].group, '核心关', '第 ' .. (tutN + 1) .. ' 个是核心关（分组切换点）')
H.ok(items[tutN + 1].label:find('^' .. (tutN + 1) .. ' '), '核心关标签带序号：' .. tostring(items[tutN + 1].label))

-- ---------- ② 布局：按钮都在画面内、不重叠 ----------
for _, wh in ipairs({ { 900, 900 }, { 400, 850 }, { 1280, 720 } }) do
  local v = CFG.viewFor(wh[1], wh[2])
  local mt = CFG.metrics(v.scale)
  local L = MENU.layout(v, mt, items)
  local inside = true
  for _, b in ipairs(L.buttons) do
    if b.x < 0 or b.x + b.w > wh[1] + 0.01 or b.y < 0 or b.y + b.h > wh[2] + 0.01 then inside = false end
  end
  H.ok(inside, wh[1] .. 'x' .. wh[2] .. '：所有按钮都在画面内')
  H.eq(#L.buttons, #items, wh[1] .. 'x' .. wh[2] .. '：按钮数 = 条目数')
  H.eq(#L.groups, 2, wh[1] .. 'x' .. wh[2] .. '：两个分组标题')
  H.eq(L.cols, wh[1] < 640 and 2 or 4, wh[1] .. 'x' .. wh[2] .. '：列数（窄屏 2 列）=' .. L.cols)
end

-- ---------- ③ 命中判定 ----------
local v0 = CFG.viewFor(CANVAS, CANVAS)
local mt0 = CFG.metrics(v0.scale)
local L0 = MENU.layout(v0, mt0, items)
local b3 = L0.buttons[3]
H.eq(MENU.pick(L0, b3.x + b3.w / 2, b3.y + b3.h / 2).index, 2, '点第 3 个按钮正中 → 条目 3')
H.eq(MENU.pick(L0, 5, 5), nil, '点左上角空白 → 不命中任何条目')

-- ---------- ④ 开局在菜单 + 菜单态不推进盘面 ----------
local h1 = newHost()                       -- 不传 skipMenu：应当停在菜单
H.eq(GAME.screen, 'menu', '★ 开局在菜单（本体 main.js 的 screen 初值）')
H.eq(#GAME.menuItems, 10, '菜单条目算好了')
H.ok(GAME.ui.menu and GAME.ui.menu.scrim.visible, '暗幕画出来了')
H.ok(GAME.ui.menu.btn[1].visible, '第 1 个按钮画出来了')

-- 暗幕必须在 HUD **之上**（后建=在上）：拿 Id 比 —— 否则局内 HUD 会从菜单里透出来
local hudFirst = GAME.ui.hud[GAME.ui.hudOrder[1]]
H.ok(GAME.ui.menu.scrim.Id > hudFirst.Id, '★ 菜单图层建在 HUD 之后（z 序在上，HUD 不会透出来）')

-- 菜单态：跑 90 帧，盘面必须一点没动
local s0 = GAME.sc.chain.balls[1] and GAME.sc.chain.balls[1].s or -1
local fired0 = (GAME.sc.stats and GAME.sc.stats.fired) or 0
for _ = 1, 90 do h1.tick(1 / 60) end
local s1 = GAME.sc.chain.balls[1] and GAME.sc.chain.balls[1].s or -1
H.near(s1, s0, 0.001, '★ 菜单态不推进盘面（链子 90 帧没动）')
H.eq(GAME.screen, 'menu', '90 帧后仍在菜单')

-- ---------- ⑤ 点按钮进关；点别处不发射 ----------
h1.click(5, CANVAS - 5)                    -- 左上角空白
h1.tick(1 / 60)
H.eq(GAME.screen, 'menu', '点空白仍在菜单')
H.eq(((GAME.sc.stats and GAME.sc.stats.fired) or 0), 0, '★ 菜单里点空白**不发射**')

local L = MENU.layout(GAME.view, GAME.sc.metrics, GAME.menuItems)
local bt = L.buttons[4]                    -- 第 4 关
h1.click(bt.x + bt.w / 2, CANVAS - (bt.y + bt.h / 2))
h1.tick(1 / 60)
H.eq(GAME.screen, 'playing', '点第 4 个按钮 → 进游戏')
H.eq(GAME.levelIndex, 4, '进的是第 4 关（本体 0 基 index=3 → 移植侧 4）')
H.ok(not GAME.ui.menu.scrim.visible, '进游戏后暗幕收掉')
H.ok(GAME.ui.menu.playBtn.visible, '进游戏后左下角「回菜单」按钮出现')

-- ---------- ⑥ 局内点左下角按钮 → 回菜单 ----------
local pb = MENU.playButtonRect(GAME.view, GAME.sc.metrics)
h1.click(pb.x, CANVAS - pb.y)
h1.tick(1 / 60)
H.eq(GAME.screen, 'menu', '★ 点左下角「回菜单」→ 回菜单')
H.ok(GAME.ui.menu.scrim.visible, '回菜单后暗幕又出现了')

-- ---------- ⑦ skipMenu=1 直接进游戏 ----------
local h2 = newHost({ skipMenu = 1 })
H.eq(GAME.screen, 'playing', 'skipMenu=1 → 直接进游戏（脚本变量仍然有效）')
H.ok(not GAME.ui.menu.scrim.visible, 'skipMenu=1 时暗幕不显示')
H.ok(GAME.ui.menu.playBtn.visible, 'skipMenu=1 时左下角按钮仍在')

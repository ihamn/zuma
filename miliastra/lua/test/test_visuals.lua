-- 表现层"看得见"的测试：核糖体 / 待发球 / 瞄准线 / 配对连线 / 绑定小球 / 洞穴 / 并入球。
--
-- ★ 为什么单独写一份：这些东西**没画也不报错**。这一版之前它们一个都没有 ——
--   本地测试全绿、真机也能跑，只是玩家看不到自己在哪开枪、往哪瞄，也看不出哪两颗配上了
--   （ui.lua 里甚至有个永远为 nil 的 `ui.hud.rb` 死分支）。所以得有断言盯着"画出来了没"。
--
-- 注意分工：**规则**由对拍（parity.mjs）和 board 的测试保证；这里只保证"board 算出来的东西
-- 真的被写进了控件"，断言尽量用 sc 里的值去对，而不是抄一份常量进来。

local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')
local BOARD = require('board')
local UI = require('ui')
local CFG = require('config')

H.suite('表现层：看得见的那些东西')

local function newHost(level)
  local host = MOCK.newHost({ w = 900, h = 900 })
  host.prefabs[1] = 'image'
  host.prefabs[2] = 'textbox'
  host.prefabs[3] = 'cursorarea'
  host.prefabs[4] = 'container'
  host.params = {
    levelIndex = level, ballPrefab = 1, shotPrefab = 1, hudPrefab = 2, cursorPrefab = 3,
    playPrefab = 1, ballCount = 32, shotCount = 4, seed = 4242, autoNext = 0, diag = 1,
  }
  MOCK.install(host)
  host.scriptObj.object = host.root
  host.mount(GAME)
  return host
end

local function redOf(hex) return tonumber(hex:sub(2, 3), 16) end

-- ① 核糖体（发射口）+ 两颗待发球 + 瞄准线
local h1 = newHost(1)
local ui, sc = GAME.ui, GAME.sc
H.truthy(ui.rb, '★ 核糖体控件建出来了（以前压根没有）')
H.eq(ui.rb.visible, true, '核糖体可见')
H.near(ui.rb.anchoredPositionX, sc.rb.x - sc.view.cx, 1e-9, '核糖体 x 跟着 sc.rb')
H.near(ui.rb.anchoredPositionY, sc.view.cy - sc.rb.y, 1e-9, '核糖体 y 跟着 sc.rb')
H.near(ui.rb.sizeDeltaX, 2 * sc.rb.r, 1e-9, '核糖体直径 = 2×rb.r')

H.eq(ui.loaded[1].visible, true, '★ 炮口那颗待发球可见')
H.eq(ui.loaded[2].visible, true, '★ 待命那颗待发球可见')
H.eq(redOf(CFG.BASE_COLOR[sc.rb.loaded[1]]), ui.loaded[1].imageColor.r, '炮口那颗的底色 = 它自己的碱基色')
H.eq(redOf(CFG.BASE_COLOR[sc.rb.loaded[2]]), ui.loaded[2].imageColor.r, '待命那颗的底色 = 它自己的碱基色')
-- 炮口那颗在前（沿 aim 方向 +0.8R），待命那颗在后（−0.7R）
local cx, cy = sc.view.cx, sc.view.cy
local fx = sc.rb.x + math.cos(sc.rb.aim) * sc.rb.r * 0.8
local fy = sc.rb.y + math.sin(sc.rb.aim) * sc.rb.r * 0.8
H.near(ui.loaded[1].anchoredPositionX, fx - cx, 1e-6, '炮口那颗在瞄准方向的前方')
H.near(ui.loaded[1].anchoredPositionY, cy - fy, 1e-6, '炮口那颗 y 正确（y 轴翻号）')

H.near(ui.aim.localRotationZ, -math.deg(sc.rb.aim), 1e-6, '★ 瞄准线角度跟着 rb.aim')
H.near(ui.aim.sizeDeltaX, sc.rb.r + 110 * sc.metrics.scale, 1e-6, '瞄准线长度 = R + 110×scale（本体原式）')

-- ①b 待发球与核糖体是"绕中心"的：pivot 必须是 0.5，否则真机上会绕着角转
H.eq(ui.aim.pivotX, 0.5, '瞄准线的 pivot = 0.5（绕中心旋转）')

-- ② 配对连线 + 副轨上的绑定小球（手动把一颗球标成"已读出"）
local b = sc.chain.balls[2]
b.paired = true
b.wrongMark = false
b.pairBase = CFG.COMPLEMENT[b.base][1]
b.dock = 0
BOARD.syncBeads(sc)
UI.sync(ui, sc, GAME.syncState())
H.eq(ui.elim[1].visible, true, '★ 副轨上出现绑定小球')
H.eq(redOf(CFG.BASE_COLOR[b.pairBase]), ui.elim[1].imageColor.r, '绑定小球的颜色 = 绑定碱基色')
H.near(ui.elim[1].sizeDeltaX, 2 * sc.metrics.r, 1e-9, '绑定小球用的是小球半径 r')
H.eq(ui.links[1].visible, true, '★ 主轨那颗和绑定小球之间画出了连线')
H.ok(ui.links[1].sizeDeltaX > 0, '连线有长度：' .. tostring(ui.links[1].sizeDeltaX))
H.eq(ui.links[2].visible, false, '正确配对只占一段控件')

-- ②b 错配 = 折线"断掉的键"（占两段控件，颜色换成灰）
b.wrongMark = true
BOARD.syncBeads(sc)
UI.sync(ui, sc, GAME.syncState())
H.eq(ui.links[1].visible, true, '错配照样有连线（第一段）')
H.eq(ui.links[2].visible, true, '★ 错配画成两段折线（第二段）')
H.eq(redOf(CFG.WRONG_COLOR), ui.links[1].imageColor.r, '错配连线的颜色 = WRONG_COLOR')

-- ③ 洞穴：静止练习关不画；有轨道的关画在轨道尽头 + 带文字
H.eq(ui.cave.visible, false, '静止练习关没有洞穴（本体：sc.still 时不画）')
H.eq(ui.caveLabel.visible, false, '洞穴文字也跟着隐藏')

local h6 = newHost(6)
local ui6, sc6 = GAME.ui, GAME.sc
H.eq(ui6.cave.visible, true, '★ 有轨道的关画出了洞穴')
local endPt = sc6.path:pointAt(sc6.path.length)
H.near(ui6.cave.anchoredPositionX, endPt.x - sc6.view.cx, 1e-6, '洞穴在轨道尽头')
H.near(ui6.cave.sizeDeltaX, 2 * sc6.metrics.R * 1.5, 1e-6, '洞穴直径 = 2×1.5R（本体原式）')
H.eq(ui6.caveRing.visible, true, '洞穴外圈可见（代替本体的红描边）')
H.eq(ui6.caveLabel.text, '降解洞穴', '洞穴文字')
H.eq(ui6.caveLabel.visible, true, '洞穴文字可见')

-- ④ 并入球（加球模式：正在挤进去的那颗）
BOARD.startMerge(sc6, sc6.chain.balls[2], 'A', nil, nil)
UI.sync(ui6, sc6, GAME.syncState())
H.eq(ui6.merges[1].visible, true, '★ 并入过程中的球画出来了')
H.eq(redOf(CFG.BASE_COLOR['A']), ui6.merges[1].imageColor.r, '并入球的颜色 = 它的碱基色')

-- ⑤ 控件预算（《编辑项范围限制》：单控件组 1000）
local n = UI.count(ui6)
H.ok(n <= 1000, '控件数在上限内：' .. n .. ' <= 1000')

-- ⑥ 换关不该残留：切回"静止 + 无预读球"的第 1 关，洞穴/绑定小球/连线都必须消失
GAME.startLevel(1)
UI.sync(GAME.ui, GAME.sc, GAME.syncState())
H.eq(GAME.ui.cave.visible, false, '切回静止练习关后洞穴消失')
H.eq(GAME.ui.elim[1].visible, false, '上一关的绑定小球不残留')
H.eq(GAME.ui.links[1].visible, false, '上一关的连线不残留')

-- ⑥b 反过来：第 2 关（t2-multiple）的 script 里自带 4 颗**已读出**的球（"A1 A1 …"），
--     所以换过去以后绑定小球和连线**本来就该出现** —— 这条证明上一组断言不是"永远为假"
GAME.startLevel(2)
UI.sync(GAME.ui, GAME.sc, GAME.syncState())
H.ok(#GAME.sc.beads.eliminate > 0, '第 2 关开局就有已读出的球：' .. #GAME.sc.beads.eliminate .. ' 颗')
H.eq(GAME.ui.elim[1].visible, true, '★ 关卡自带的已读球也画出了绑定小球')
H.eq(GAME.ui.links[1].visible, true, '★ 并且画出了连线')

H.finish()

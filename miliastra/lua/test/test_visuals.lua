-- 表现层"看得见"的测试：核糖体 / 待发球 / 瞄准线 / 配对连线 / 绑定小球 / 光晕 / 字母 /
-- 轨道 / 冷却环 / 洞穴 / 并入球 / 动效 / HUD 底板 / 诊断行置顶。
--
-- ★ 为什么单独写一份：这些东西**没画也不报错**。第一版移植里它们一个都没有 ——
--   本地测试全绿、真机也能跑，只是玩家看不到自己在哪开枪、往哪瞄、哪两颗配上了
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

local DT = 1 / 60

local function newHost(level, params)
  local host = MOCK.newHost({ w = 900, h = 900 })
  host.prefabs[1] = 'image'
  host.prefabs[2] = 'textbox'
  host.prefabs[3] = 'cursorarea'
  host.prefabs[4] = 'container'
  host.params = {
    levelIndex = level, ballPrefab = 1, shotPrefab = 1, hudPrefab = 2, cursorPrefab = 3,
    playPrefab = 1, ballCount = 32, shotCount = 4, seed = 4242, autoNext = 0, diag = 1,
  }
  for k, v in pairs(params or {}) do host.params[k] = v end
  MOCK.install(host)
  host.scriptObj.object = host.root
  host.mount(GAME)
  return host
end

local function step(host, n)
  for _ = 1, (n or 1) do host.tick(DT) end
end

local function redOf(hex) return tonumber(hex:sub(2, 3), 16) end

-- ① 核糖体（发射口）+ 两颗待发球 + 瞄准线
local h1 = newHost(1)
local ui, sc = GAME.ui, GAME.sc
H.truthy(ui.rb, '★ 核糖体控件建出来了（第一版压根没有）')
H.eq(ui.rb.visible, true, '核糖体可见')
H.near(ui.rb.anchoredPositionX, sc.rb.x - sc.view.cx, 1e-9, '核糖体 x 跟着 sc.rb')
H.near(ui.rb.anchoredPositionY, sc.view.cy - sc.rb.y, 1e-9, '核糖体 y 跟着 sc.rb')
H.near(ui.rb.sizeDeltaX, 2 * sc.rb.r, 1e-9, '核糖体直径 = 2×rb.r')

H.eq(ui.loaded[1].visible, true, '★ 炮口那颗待发球可见')
H.eq(ui.loaded[2].visible, true, '★ 待命那颗待发球可见')
H.eq(redOf(CFG.BASE_COLOR[sc.rb.loaded[1]]), ui.loaded[1].imageColor.r, '炮口那颗的底色 = 它自己的碱基色')
H.eq(redOf(CFG.BASE_COLOR[sc.rb.loaded[2]]), ui.loaded[2].imageColor.r, '待命那颗的底色 = 它自己的碱基色')
local cx, cy = sc.view.cx, sc.view.cy
local fx = sc.rb.x + math.cos(sc.rb.aim) * sc.rb.r * 0.8
local fy = sc.rb.y + math.sin(sc.rb.aim) * sc.rb.r * 0.8
H.near(ui.loaded[1].anchoredPositionX, fx - cx, 1e-6, '炮口那颗在瞄准方向的前方')
H.near(ui.loaded[1].anchoredPositionY, cy - fy, 1e-6, '炮口那颗 y 正确（y 轴翻号）')

H.near(ui.aim.localRotationZ, -math.deg(sc.rb.aim), 1e-6, '★ 瞄准线角度跟着 rb.aim')
H.near(ui.aim.sizeDeltaX, sc.rb.r + 110 * sc.metrics.scale, 1e-6, '瞄准线长度 = R + 110×scale（本体原式）')
H.eq(ui.aim.pivotX, 0.5, '瞄准线的 pivot = 0.5（绕中心旋转）')
H.eq(ui.aim.imageColor.a, 0x4d, '★ 瞄准线是 30% 透明（照本体 rgba(150,200,255,0.30)）')

-- ② 配对连线 + 副轨上的绑定小球
local b = sc.chain.balls[2]
b.paired = true
b.wrongMark = false
b.pairBase = CFG.COMPLEMENT[b.base][1]
b.dock = 0
BOARD.syncBeads(sc)
UI.sync(ui, sc, GAME.syncState(DT))
H.eq(ui.elim[1].visible, true, '★ 副轨上出现绑定小球')
H.eq(redOf(CFG.BASE_COLOR[b.pairBase]), ui.elim[1].imageColor.r, '绑定小球的颜色 = 绑定碱基色')
H.near(ui.elim[1].sizeDeltaX, 2 * sc.metrics.r, 1e-9, '绑定小球用的是小球半径 r')
H.eq(ui.links[1].visible, true, '★ 主轨那颗和绑定小球之间画出了连线')
H.ok(ui.links[1].sizeDeltaX > 0, '连线有长度：' .. tostring(ui.links[1].sizeDeltaX))
H.eq(ui.links[2].visible, false, '正确配对只占一段控件')

-- ②b 错配 = 折线"断掉的键"（占两段控件，颜色换成灰）
b.wrongMark = true
BOARD.syncBeads(sc)
UI.sync(ui, sc, GAME.syncState(DT))
H.eq(ui.links[2].visible, true, '★ 错配画成两段折线（第二段）')
H.eq(redOf(CFG.WRONG_COLOR), ui.links[1].imageColor.r, '错配连线的颜色 = WRONG_COLOR')

-- ②c 状态光晕：读出的球要亮一圈（本体 drawBead 的 pairGlow）
H.eq(ui.halo[2].visible, true, '★ 读出的球有光晕')
H.ok(ui.letter[2].visible, '读出的球仍有字母')
b.wrongMark = false
BOARD.syncBeads(sc)
UI.sync(ui, sc, GAME.syncState(DT))
H.eq(ui.halo[2].visible, true, '配对正确的球也有光晕')
H.eq(ui.halo[1].visible, false, '没读出的球没有光晕')
H.eq(ui.halo[2].enableSoftEdge, true, '光晕是柔边的（图片控件没有描边，靠柔边做发光）')

-- ②d 球面字母：本体把 label 画在球上；我们叠文本框
local b1 = sc.beads.spawn[3]
H.eq(ui.letter[3].visible, true, '★ 球面字母画出来了')
H.eq(ui.letter[3].text, b1.base, '字母 = 球的碱基：' .. tostring(ui.letter[3].text))
H.near(ui.letter[3].fontSize, math.floor(b1.r * 1.15), 1, '字号 = 半径 × 1.15（本体 drawBead 的比例）')
H.near(ui.letter[3].sizeDeltaX, 2 * b1.r, 1e-9, '字母框跟球一样大（居中显示）')

-- ③ 洞穴：静止练习关不画；有轨道的关画在轨道尽头 + 三层红晕 + 文字
H.eq(ui.cave.visible, false, '静止练习关没有洞穴（本体：sc.still 时不画）')
H.eq(ui.caveLabel.visible, false, '洞穴文字也跟着隐藏')

local h6 = newHost(6)
local ui6, sc6 = GAME.ui, GAME.sc
H.eq(ui6.cave.visible, true, '★ 有轨道的关画出了洞穴')
local endPt = sc6.path:pointAt(sc6.path.length)
H.near(ui6.cave.anchoredPositionX, endPt.x - sc6.view.cx, 1e-6, '洞穴在轨道尽头')
H.near(ui6.cave.sizeDeltaX, 2 * sc6.metrics.R * 1.5, 1e-6, '洞穴直径 = 2×1.5R（本体原式）')
H.eq(ui6.caveGlow[1].visible, true, '★ 洞穴有红晕（本体是径向渐变）')
H.ok(ui6.caveGlow[1].imageColor.a < 255, '红晕是半透明的：a=' .. ui6.caveGlow[1].imageColor.a)
H.eq(ui6.caveLabel.text, '降解洞穴', '洞穴文字')
H.eq(ui6.caveLabel.visible, true, '洞穴文字可见')

-- ③b 轨道：Lua 自己画（一段段棒拼两条轨）
H.eq(ui6.track[1].visible, true, '★ 轨道第一段可见')
H.ok(ui6.track[1].sizeDeltaX > 0, '轨道段有长度：' .. tostring(ui6.track[1].sizeDeltaX))
H.eq(ui6.track[1].enableSoftEdge, true, '轨道路面是柔边的')
local trackKey = ui6.trackKey
step(h6, 3)
H.eq(ui6.trackKey, trackKey, '轨道每帧不重算（换关才算）')
-- 静止练习关也有轨道（本体 drawTrackLayer 是无条件画的）
H.eq(ui.track[1].visible, true, '静止练习关同样画轨道')

-- ④ 并入球（加球模式：正在挤进去的那颗）
BOARD.startMerge(sc6, sc6.chain.balls[2], 'A', nil, nil)
UI.sync(ui6, sc6, GAME.syncState(DT))
H.eq(ui6.merges[1].visible, true, '★ 并入过程中的球画出来了')
H.eq(redOf(CFG.BASE_COLOR['A']), ui6.merges[1].imageColor.r, '并入球的颜色 = 它的碱基色')

-- ⑤ 冷却环：冷却中显示、冷却好了隐藏
sc6.rb.cooldown = (CFG.DESIGN and CFG.DESIGN.fireCooldown or 0.16) * 0.5
UI.sync(ui6, sc6, GAME.syncState(DT))
H.eq(ui6.cd.visible, true, '★ 冷却中显示冷却环')
sc6.rb.cooldown = 0
UI.sync(ui6, sc6, GAME.syncState(DT))
H.eq(ui6.cd.visible, false, '冷却好了冷却环消失')

-- ⑥ HUD：文字要有底板（不然字飘在背景上）
H.ok(ui6.hud.score.bgColor.a > 0, '★ HUD 有半透明底板：a=' .. ui6.hud.score.bgColor.a)
H.eq(ui6.hud.score.text:find('分数') ~= nil, true, 'HUD 文本照旧：' .. ui6.hud.score.text)

-- ⑦ 诊断行必须在最上层（首轮截图里它被提示文字压着）
local root = h6.root
H.eq(root.children[#root.children], GAME.diagControl, '★ 诊断行是根控件下最后一个（画在最上面）')

-- ⑧ 动效：刚读出的绑定小球"弹"一下，被消掉的"炸开淡出"
local h2 = newHost(1)
local ui2, sc2 = GAME.ui, GAME.sc
UI.sync(ui2, sc2, GAME.syncState(DT))            -- 第一帧：记住"都没读出"
local bb = sc2.chain.balls[2]
bb.paired = true
bb.wrongMark = false
bb.pairBase = CFG.COMPLEMENT[bb.base][1]
bb.dock = 0
BOARD.syncBeads(sc2)
UI.sync(ui2, sc2, GAME.syncState(DT))            -- 第二帧：刚读出 -> 起 pop 动效
H.ok(#ui2.fx > 0, '★ 刚读出时起了动效（' .. #ui2.fx .. ' 个）')
H.ok(ui2.elim[1].localScaleX < 1, '弹出起点是缩小的：' .. tostring(ui2.elim[1].localScaleX))
step(h2, 30)                                     -- 0.5 秒后应该回到 1
H.near(ui2.elim[1].localScaleX, 1, 0.05, '动效结束后缩放回到 1')

-- ⑨ fancy=0：动效/光晕/冷却环/轨道都关掉（真机上哪条炸了就靠这个变量兜底）
local h3 = newHost(1, { fancy = 0, track = 0, letters = 0 })
H.eq(#GAME.ui.halo, 0, 'fancy=0：不建光晕池')
H.eq(#GAME.ui.letter, 0, 'letters=0：不建字母池')
H.eq(#GAME.ui.track, 0, 'track=0：不建轨道池')
H.eq(GAME.ui.rb.visible, true, 'fancy=0 也要有核糖体（不然不知道从哪开枪）')
H.eq(GAME.ui.aim.visible, true, 'fancy=0 也保留瞄准线')

-- ⑩ 控件预算（《编辑项范围限制》：单控件组 1000）
local n = UI.count(ui6)
H.ok(n <= 1000, '控件数在上限内：' .. n .. ' <= 1000')

-- ⑪ 换关不该残留：切回"静止 + 无预读球"的第 1 关
GAME.startLevel(1)
UI.sync(GAME.ui, GAME.sc, GAME.syncState(DT))
H.eq(GAME.ui.cave.visible, false, '切回静止练习关后洞穴消失')
H.eq(GAME.ui.elim[1].visible, false, '上一关的绑定小球不残留')
H.eq(GAME.ui.links[1].visible, false, '上一关的连线不残留')

-- ⑪b 反过来：第 2 关（t2-multiple）的 script 自带 4 颗已读出的球（"A1 A1 …"）
GAME.startLevel(2)
UI.sync(GAME.ui, GAME.sc, GAME.syncState(DT))
H.ok(#GAME.sc.beads.eliminate > 0, '第 2 关开局就有已读出的球：' .. #GAME.sc.beads.eliminate .. ' 颗')
H.eq(GAME.ui.elim[1].visible, true, '★ 关卡自带的已读球也画出了绑定小球')
H.eq(GAME.ui.links[1].visible, true, '★ 并且画出了连线')

-- ⑫ ★ 绑定小球**也要有字母**（本体 render.js 用它自己那套 drawBead 画所有珠子，
--    主轨副轨都带字母）。第一版只给主轨画了，用户报"用来匹配的小球没有字母"。
-- ⑬ ★ 配对光晕是**球外一圈细环**，不是"大圆盘"：
--    本体 glow 画在 r+3 处、线宽 max(1.5, r*0.18)；第一版我用 haloScale=2.1 实心圆，
--    看着像"球变大了"（用户一眼看出来不对）。<br>
--    ⚠ 上面 L172 那个 host 是 `letters=0` 的，所以这里自己起一个正常 host。
do
  newHost(2)                                   -- 第 2 关：开局自带已读出的球
  UI.sync(GAME.ui, GAME.sc, GAME.syncState(DT))
  local elim = GAME.sc.beads.eliminate
  H.ok(#elim > 0, '第 2 关有已读出的球：' .. #elim .. ' 颗')

  local lc = GAME.ui.elimLetter[1]
  H.ok(lc ~= nil, '★ 有"绑定球字母"控件池')
  H.eq(lc.visible, true, '★ 绑定小球的字母显示出来了')
  H.eq(lc.text, tostring(elim[1].base), '★ 绑定球字母 = 它的碱基（' .. tostring(elim[1].base) .. '）')
  H.ok(lc.fontSize and lc.fontSize >= 8, '字母有字号：' .. tostring(lc.fontSize))

  local shown = nil
  for i = 1, #GAME.ui.halo do
    if GAME.ui.halo[i].visible then shown = GAME.ui.halo[i]; break end
  end
  H.ok(shown ~= nil, '★ 已读出的球带光晕（可见的光晕控件存在）')
  local ball = GAME.ui.balls[1]
  if shown and ball.sizeDeltaX and shown.sizeDeltaX then
    local ratio = shown.sizeDeltaX / ball.sizeDeltaX
    H.ok(ratio < 1.4, '★ 光晕直径 / 球直径 = ' .. string.format('%.2f', ratio)
      .. '（必须 < 1.4；2.1 就是"球变大了"那个 bug）')
  end
end

H.finish()

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
-- ★ 环上**不该**开柔边：柔边是给实心圆盘做发光用的；换成"空心圆"素材后它会把这圈环糊烂
--   （用户报"有的球描边会突然变坏"）。本体那边 glow 也是硬描边。
H.eq(ui.halo[2].enableSoftEdge, false, '光晕（细环）不开柔边')

-- ②d 球面字母：本体把 label 画在球上；我们叠文本框
local b1 = sc.beads.spawn[3]
H.eq(ui.letter[3].visible, true, '★ 球面字母画出来了')
H.eq(ui.letter[3].text, b1.base, '字母 = 球的碱基：' .. tostring(ui.letter[3].text))
H.near(ui.letter[3].fontSize, math.floor(b1.r * 1.15), 1, '字号 = 半径 × 1.15（本体 drawBead 的比例）')
H.near(ui.letter[3].sizeDeltaX, 2 * b1.r, 1e-9, '字母框跟球一样大（居中显示）')

-- ③ 洞穴：静止练习关不画；有轨道的关画在轨道尽头 + 三层红晕 + 文字
H.eq(ui.cave.visible, false, '静止练习关没有洞穴（本体：sc.still 时不画）')
H.eq(ui.caveLabel.visible, false, '洞穴文字也跟着隐藏')

local h6 = newHost(6, { cd = 1 })   -- 冷却环本体没有（默认关），这条专门测它 → 显式打开
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
H.eq(ui6.cd.visible, true, '★ cd=1 时冷却中显示冷却环')
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
    -- ★★ 本体是"球外**一圈细描边**"：半径 = r + 线宽，线宽 = max(1.5, r*0.18)。
    --    我们拿**实心圆放大一圈垫在球下面**来实现，露出的环宽 = 线宽 → 宽度完全可控。
    --    （用"空心圆素材画环"那条路走不通：环的粗细由素材决定，拉大就跟着变粗 = "球变大了"。）
    local ballR = ball.sizeDeltaX / 2
    local stroke = math.max(1.5, ballR * 0.18)
    local want = (ballR + stroke) * 2
    H.ok(math.abs(shown.sizeDeltaX - want) < 1.0,
      '★ 光晕直径 = (球半径 + 线宽)×2 = ' .. string.format('%.1f', want)
      .. '，实际 ' .. string.format('%.1f', shown.sizeDeltaX))
    H.ok(stroke <= 4,
      '★ 描边线宽 ' .. string.format('%.2f', stroke) .. 'px（细描边；粗了就像"球变大"）')
  end

  -- ★ 副轨绑定球**也要描边**（本体 glowColor 为空 → 白色），同样是"球半径 + 线宽"
  local eh = GAME.ui.halo[GAME.ui.haloHalf + 1]
  H.ok(eh ~= nil, '★ 副轨描边控件存在（halo 池是 2n）')
  H.eq(eh.visible, true, '★ 绑定小球的描边画出来了')
  local e1 = elim[1]
  local eStroke = math.max(1.5, e1.r * 0.18)
  H.ok(math.abs(eh.sizeDeltaX - (e1.r + eStroke) * 2) < 1.0,
    '★ 副轨描边直径 = (r + 线宽)×2 = ' .. string.format('%.1f', (e1.r + eStroke) * 2)
    .. '，实际 ' .. string.format('%.1f', eh.sizeDeltaX))

  -- ★ 核糖体两颗待发球都要字母（本体 lb(1) / lb(0) 都画）
  local rb = GAME.sc.rb
  H.ok(GAME.ui.loadedLetter ~= nil and GAME.ui.loadedLetter[1] ~= nil, '有待发球字母池')
  H.eq(GAME.ui.loadedLetter[1].visible, true, '★ 炮口那颗待发球有字母')
  H.eq(GAME.ui.loadedLetter[1].text, tostring(rb.loaded[1]),
    '★ 炮口球字母 = rb.loaded[1] = ' .. tostring(rb.loaded[1]))
  H.eq(GAME.ui.loadedLetter[2].visible, true, '★ 身后那颗预备球也有字母')
  H.eq(GAME.ui.loadedLetter[2].text, tostring(rb.loaded[2]),
    '★ 预备球字母 = rb.loaded[2] = ' .. tostring(rb.loaded[2]))
  H.eq(GAME.ui.loadedHalo[1].visible, true, '★ 炮口球带白色描边（本体那颗 glow=true）')
  -- ★★ 这两颗待发球字母**不许开描边**：小字号下描边会吃掉笔画（真机上 ④ 就是这么被我改坏的）
  H.eq(GAME.ui.loadedLetter[1].enableOutline, false, '★ 炮口球字母不开描边（开了会把字吃掉）')
  H.eq(GAME.ui.loadedLetter[2].enableOutline, false, '★ 预备球字母不开描边')
  -- ★ z 序：字母必须**晚于**待发球创建（真机后建的盖在上面）
  H.ok(GAME.ui.loadedLetter[1].Id > GAME.ui.loaded[1].Id, '★ 字母建在球之后（z 序更靠上）')
  H.ok(GAME.ui.loadedLetter[2].Id > GAME.ui.loaded[2].Id, '★ 预备球字母也建在球之后')
  -- ★★ 核糖体字母必须与"链珠字母 / 绑定球字母"（真机上显示正常的那两套）**机制完全一致**：
  --    同一个字号公式、同样无描边、同样不调 SetAsLastSibling。
  H.eq(GAME.ui.loadedLetter[1].enableOutline, GAME.ui.letter[1].enableOutline,
    '★ 核糖体字母与链珠字母的描边设置一致（都是 false）')
  -- ⚠ 别拿它跟链珠字母比**数值**：两颗球半径不同（链珠 r=19、待发球 r=13.4），
  --   公式一样但算出来不一样。要比就比**公式**：字号 = max(8, floor(球半径 × 1.15))
  -- 公式 = max(15, floor(半径 × 1.15))：下限 15 只为抬升 ③ 那颗最小的球（半径 10.7 → 12px 看不见），
  -- ④（15px）/ 链珠（21px）/ 绑定球（15px）都不受影响。
  local lr1 = GAME.ui.loaded[1].sizeDeltaX / 2
  local lr2 = GAME.ui.loaded[2].sizeDeltaX / 2
  H.eq(GAME.ui.loadedLetter[1].fontSize, math.max(15, math.floor(lr1 * 1.15)),
    '★ ④ 炮口球字母字号 = max(15, r×1.15) = ' .. tostring(GAME.ui.loadedLetter[1].fontSize))
  if GAME.ui.letterProbe ~= 0 then
    -- 探针模式（默认开）：③ 被改成"大框 + 红底 + 白字 24px"，用来判定真机到底画不画这个控件
    H.eq(GAME.ui.loadedLetter[2].fontSize, 24, '★ 探针：③ 的字号被设成 24（红底白字方块）')
    H.ok(GAME.ui.loadedLetter[2].sizeDeltaX > lr2 * 2, '★ 探针：③ 的框被放大（> 球直径）')
  else
    H.eq(GAME.ui.loadedLetter[2].fontSize, math.max(15, math.floor(lr2 * 1.15)),
      '★ ③ 预备球字母字号（下限 15，真机 scale=1 时从 12 抬到 15）= ' .. tostring(GAME.ui.loadedLetter[2].fontSize))
    H.ok(GAME.ui.loadedLetter[2].fontSize >= 15, '★ ③ 的字号不许低于 15（低于就真机看不见）')
  end
  -- ★★ 真机教训（2026-09-25）：③ 用 2×球半径 = 21.5px 的框时"状态全对却不显示"；
  --    放大后立刻显示。所以待发球字母的框**不许小于链珠字母的框**（2×mt.r = 26.9）。
  -- 基准是**小球**的框（2×mt.r），不是大球的（大球是 2×mt.R = 38，别拿它比）
  local smallBox = 2 * GAME.sc.metrics.r
  H.ok(GAME.ui.loadedLetter[1].sizeDeltaX >= smallBox - 0.01,
    '★ ④ 字母框 ≥ 小球框：' .. tostring(GAME.ui.loadedLetter[1].sizeDeltaX) .. ' vs ' .. tostring(smallBox))
  H.ok(GAME.ui.loadedLetter[2].sizeDeltaX >= smallBox - 0.01,
    '★ ③ 字母框 ≥ 小球框（真机上小于它就不显示）：' .. tostring(GAME.ui.loadedLetter[2].sizeDeltaX) .. ' vs ' .. tostring(smallBox))
  -- ★★ 建法回到"④ 正常"那一版：字母紧跟两颗待发球建（**在 HUD 之前**），
  --    靠"后建=在上"盖住球和描边即可 —— 不再挪到 M.create 末尾（那笔改动把 ④ 弄糊了）。
  H.ok(GAME.ui.loadedLetter[1].Id > GAME.ui.loaded[2].Id, '★ 字母建在两颗待发球之后（z 序在上）')
  if GAME.ui.hudOrder and #GAME.ui.hudOrder > 0 then
    H.ok(GAME.ui.loadedLetter[1].Id < GAME.ui.hud[GAME.ui.hudOrder[1]].Id,
      '★ 字母建在 HUD 文本**之前**（与"④ 正常"那一版的建法一致）')
  end

  -- ★ 大小球配比 = √2（DESIGN 的识别通道：出球道大球 / 三消道小球）
  local mt = GAME.sc.metrics
  local ratio = mt.R / mt.r
  H.ok(math.abs(ratio - math.sqrt(2)) < 1e-6,
    '★ 大小球半径比 R/r = ' .. string.format('%.4f', ratio) .. '（应 = √2 = 1.4142）'
    .. '；画到屏幕上是直径 ' .. string.format('%.1f', mt.R * 2) .. ' : ' .. string.format('%.1f', mt.r * 2))
end

-- ⑭ ★★ **配对消失后要收干净** —— 用户报"没匹配却有一堆白圈"的真凶：
--    隐藏白描边那句写成了 `if eh then ...`，而 eh 是另一个分支里的 local（出了作用域 = nil）
--    → 白圈永久残留。这条断言专门盯"画完要能擦掉"。
do
  newHost(2)                                  -- 第 2 关：开局自带已读出的球（= 有白描边）
  UI.sync(GAME.ui, GAME.sc, GAME.syncState(DT))
  local live = 0
  for i = 1, #GAME.ui.halo do
    if GAME.ui.halo[i].visible then live = live + 1 end
  end
  H.ok(live > 0, '开局有描边亮着：' .. live .. ' 个')

  -- 取消所有配对（模拟"被消掉 / 状态回退"）
  for i = 1, #GAME.sc.chain.balls do
    local b = GAME.sc.chain.balls[i]
    b.paired = false
    b.wrongMark = false
    b.pairBase = nil
  end
  BOARD.syncBeads(GAME.sc)
  UI.sync(GAME.ui, GAME.sc, GAME.syncState(DT))
  local left = 0
  for i = 1, #GAME.ui.halo do
    if GAME.ui.halo[i].visible then left = left + 1 end
  end
  H.eq(left, 0, '★ 取消配对后**一个描边都不许残留**（白圈 bug 就是这条没测）')
  local el = 0
  for i = 1, #GAME.ui.elim do
    if GAME.ui.elim[i].visible then el = el + 1 end
  end
  H.eq(el, 0, '★ 绑定小球也一起收干净')
  local lt = 0
  for i = 1, #GAME.ui.elimLetter do
    if GAME.ui.elimLetter[i].visible then lt = lt + 1 end
  end
  H.eq(lt, 0, '★ 绑定球字母也收干净')
end

H.finish()

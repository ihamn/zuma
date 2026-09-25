-- ui.lua —— 表现层：board 的状态 -> 客户端控件。
--
-- ★★ 这里**不重新实现任何规则**：位置/颜色/显隐全部来自 sc（board.lua 算好的）。
--   ui 的职责只有四件：坐标换算、控件池复用、脏检查、**动效**。
--
-- 坐标：board 用的是"画布像素、原点左上、y 向下"；控件 anchoredPosition 在父级下
--       是"相对父级中心、y 向上"。所以 y 要翻一次号：uiY = view.cy - y。
--       父级 = 一块铺满画布、居中在画布中心的容器控件。
--
-- ★★ 画什么、画多大、什么颜色，全部照网页版 `src/render.js` 搬（百分比/半径/透明度用它的原式）：
--     轨道（双轨路面）              <-  drawTrackLayer（本体用 canvas 描线；我们用一段段"棒"拼）
--     洞穴（降解口）+ 红晕          <-  drawCave
--     配对连线（正确=直棒 / 错配=折线"断掉的键"）<- drawPairLink / drawPairLinks
--     绑定小球（副轨上读出的那一半）<-  drawBeadLayer 的 beads.eliminate
--     球 + 状态光晕 + 碱基字母      <-  drawBead（label / ink / pairGlow）
--     并入过程中的球                <-  drawMergeLayer
--     核糖体 + 两颗待发球 + 瞄准线  <-  drawRibosome
--     开火冷却环                    <-  本体没有（新增）：一眼看出能不能打
--     HUD 文本 + 半透明底板         <-  drawRunBadges / drawStats
--
-- ⚠ 近似之处（图片控件没有描边/渐变，只有填充色 + 柔边 + 径向填充）：
--     - 核糖体：一个暗色圆 + 外圈柔边光晕（本体是填充 + 蓝描边）
--     - 洞穴：中心暗圆 + 三层递减透明度的红晕（本体是径向渐变 + 红描边）
--     - 轨道：一段段带柔边的"棒"（本体是描线；米字路口/自交处会略有接缝）
--     - 球面字母用**文本框**叠在球上（本体是 canvas 文字）；副轨上的绑定小球没叠字母（省控件）
--
-- ★ 控件池的**创建顺序就是绘制顺序**（运行时：同级索引大的在上面，契约 §13）：
--   轨道 -> 洞穴 -> 连线 -> 光晕 -> 绑定小球 -> 球 -> 弹药 -> 并入球 -> 字母
--   -> 瞄准线 -> 冷却环 -> 核糖体 -> 待发球 -> HUD
--
-- ★★ 动效为什么**不用 `game.Tween`** 而是自己算：我们的脏检查缓存按"上一次写进去的值"判断要不要再写，
--   而 Tween 会绕过缓存直接改字段 —— 两条路同时改同一个字段就会互相打架（Tween 刚拉开，下一帧 sync 又写回去）。
--   所以这里：**动画只碰 sync 不碰的字段**（`localScaleX/Y`、以及临时改的 `imageColor` 透明度），
--   用一个短命的效果表 `ui.fx` 自己推进，结束时显式复位并把该控件的颜色缓存作废。
--   （`game.Tween` 仍在假宿主/真机上可用，将来要做"编辑期摆好的动效"再用。）

local CFG = require('config')

local M = {}

-- ==================== 视觉常量（照 src/render.js） ====================

local V = {
  aimLen = 110,        -- drawRibosome：瞄准线长 = R + 110 × scale
  aimWidth = 1.4,      -- drawRibosome：线宽 = max(1, 1.4 × scale)
  linkWidth = 3.4,     -- drawPairLink：连线宽 = max(3, 3.4 × scale)
  linkAmp = 3.4,       -- drawPairLink：错配折线的横向幅度
  caveR = 1.5,         -- drawCave：洞穴半径 = mt.R × 1.5
  linkFrom = 0.26,     -- drawPairLink：连线画在 26%~74% 之间
  linkTo = 0.74,
  haloScale = 1.16,     -- （旧）按比例放大的近似 —— 现在用 haloWidth/glowRadius（绝对值）
  haloPad = 3,          -- （旧）球外 +3 —— 现在按本体线宽算，见 glowRadius
  haloStrokeK = 0.18,   -- 描边线宽 = max(1.5, r × 0.18)（本体 render.js drawBead 的 glow）
  haloStrokeMin = 1.5,
  letterScale = 1.15,  -- 球面字母字号 = 球半径 × 1.15
  trackWidthK = 2.3,   -- 轨道路面宽 = 轨半径 × 2.3（盖住珠子）
}

-- 颜色：网页版用的是 rgba(...)，这里用 '#rrggbbaa'（官方 imageColor 是带 alpha 的 ColorValue）
local C = {
  aim = '#96c8ff4d',        -- rgba(150,200,255,0.30)
  cd = '#96c8ff5c',         -- 冷却环
  roadOuter = '#16202ea6',  -- 出球道路面（大球那条轨）
  roadInner = '#1d2b3ca6',  -- 三消道路面（小球那条轨）
  railLine = '#7f9dc94d',   -- 导轨细线（本体 drawTrackLayer 画的两条细亮线，很提神）
  backdrop = '#0b1119d9',   -- 整块背板（半透明深色）：让画面像个界面，而不是浮在关卡场景上
  caveCore = '#0a060ad9',   -- 洞穴中心
  -- 三层红晕（本体是径向渐变）：**要克制** —— 第一版给太大太红，整个洞口像块红布
  caveGlow = { '#ff5a6e40', '#ff5a6e26', '#ff5a6e14' },
  rbBody = '#22303f',
  rbHalo = '#96c8ff2e',
  panel = '#0a0e12a6',      -- HUD 底板（65%）
  panelLight = '#0a0e1266', -- 提示语那种大块文字用更淡的底板（40%）
  letterOnLight = '#101820',
}

-- '#rrggbb' / '#rrggbbaa' -> Color
local function hexColor(s, fallback)
  if type(s) ~= 'string' or #s < 7 then return fallback or Color.FromRGBA(255, 255, 255, 255) end
  local r = tonumber(s:sub(2, 3), 16) or 255
  local g = tonumber(s:sub(4, 5), 16) or 255
  local b = tonumber(s:sub(6, 7), 16) or 255
  local a = (#s >= 9) and (tonumber(s:sub(8, 9), 16) or 255) or 255
  return Color.FromRGBA(r, g, b, a)
end
M.hexColor = hexColor

-- 取色的 rgb 分量（做"淡出"时要按同一底色改 alpha）
local function rgbOf(hex)
  return tonumber(hex:sub(2, 3), 16) or 255, tonumber(hex:sub(4, 5), 16) or 255, tonumber(hex:sub(6, 7), 16) or 255
end

-- ★★ 控件运行时 ID 的字段名：官方是 **`Id`（首字母大写）**。
--    真机观察（客户端 Lua 运行时契约 §16）：「`Id`（客户端控件运行时ID，首字母大写）/ `prefabIndex`；
--    旧 probe 中的 `control.id` / `prefabId` 是**旧版本接口，不作为兼容口径**」。
--    官方文档的字段表里写的是小写 `id` —— 以真机探针为准，两个都认。
local function ctrlId(c)
  return c.Id or c.id
end

local function cacheOf(ui, c)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
  return cache
end

local function setField(ui, c, key, value)
  local cache = cacheOf(ui, c)
  if cache[key] == value then return false end
  cache[key] = value
  c[key] = value
  return true
end

local function setColor(ui, c, hex)
  local cache = cacheOf(ui, c)
  if cache.__color == hex then return false end
  cache.__color = hex
  c.imageColor = hexColor(hex)
  return true
end

-- 动效直接改过颜色之后，把缓存作废，下一帧才会把底色重新写回去
local function invalidateColor(ui, c)
  local cache = cacheOf(ui, c)
  cache.__color = nil
end

-- 图片素材 id（真机结论，2026-09-25 用户实测）：
--   ★★ **动态创建的图片控件不会继承模板/画布上那张图** —— 必须脚本显式
--      `SetImage(Enum.ImageSource.StaticReference, <资产号>)`。不设 = 每个图片控件画成"?"，
--      球 / 轨道（一堆棒拼的）/ 中央核糖体全能中招（用户就是这么看到的）。
--   ★ 别把两个数字搞混：**图片控件模板索引**（形如 1073741852）不是素材 id；
--      素材 id 是编辑器里那张图的"**资产号**"（当前用 100002 = 一张白圆图）。
--   ui.artAny = 全局兜底资产号（棒/光晕/核糖体等不分碱基的控件用它）；
--   ui.art[base] = 该碱基专属的图（不配就跟 artAny 一样）。
local function artIdOf(ui, base)
  if base == nil then return ui.artAny end
  local a = ui.art
  return (a and a[base]) or ui.artAny
end

local function setImage(ui, c, id)
  if id == nil then return false end
  local cache = cacheOf(ui, c)
  if cache.__image == id then return false end
  cache.__image = id
  c:SetImage(Enum.ImageSource.StaticReference, id)
  return true
end
M.setImageById = setImage

-- ★★ 可见性：官方契约里 `visible` 是**只读**字段 —— 读得到，**写会报**
--    「cannot set visible, no such field」。改可见性必须调方法 SetVisible()。
local function setVisible(ui, c, v)
  local cache = cacheOf(ui, c)
  if cache.__visible == v then return false end
  cache.__visible = v
  c:SetVisible(v)
  return true
end

-- 把一个控件放到游戏坐标 (x, y)、尺寸 w×h、绕中心转 rot 度
local function place(ui, c, cx, cy, x, y, w, h, rot)
  setField(ui, c, 'anchoredPositionX', x - cx)
  setField(ui, c, 'anchoredPositionY', cy - y)
  setField(ui, c, 'sizeDeltaX', w)
  setField(ui, c, 'sizeDeltaY', h)
  setField(ui, c, 'localRotationZ', rot or 0)
  setVisible(ui, c, true)
end

-- ★ 旋转角：board 的 y 向下、控件空间的 y 向上，所以角度要翻号。
local function rotDeg(dx, dy)
  return math.deg(math.atan(-dy, dx))
end

-- 把控件当"一根棒"用：从 (x1,y1) 拉到 (x2,y2)，粗细 w
local function placeSeg(ui, c, cx, cy, x1, y1, x2, y2, w, hex, artId)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then setVisible(ui, c, false); return end
  place(ui, c, cx, cy, (x1 + x2) / 2, (y1 + y2) / 2, len, w, rotDeg(dx, dy))
  setColor(ui, c, hex)
  -- ★ 棒也要设素材：真机上不设就画成"?" —— 轨道/连线/瞄准线全是棒，
  --   用户看到的"轨道是一堆问号拼出来的"就是这里。
  --   ★ 棒优先用 artBar（**方图**；圆图拉成长条会鼓出来，用户已反馈"轨道用圆有点难看"）。
  setImage(ui, c, artId or ui.artBar or ui.artAny)
end

-- 把一个控件当"一颗球"用
local function placeBead(ui, c, cx, cy, x, y, r, hex, artId)
  local d = 2 * r
  place(ui, c, cx, cy, x, y, d, d, 0)
  setColor(ui, c, hex)
  setImage(ui, c, artId or ui.artAny)
end

-- ★★ 描边（本体 drawBead 的 glow）**正确的复刻方式**：
--   本体是 `arc(r + 3)` + `lineWidth = max(1.5, r*0.18)` 的一圈**细描边**。
--   图片控件没有描边能力 —— 一度改成"用空心圆素材画环"，但**环的粗细由素材决定**，
--   放大后那圈跟着变粗，看着就是"匹配以后球变大了"（用户三次反馈的就是这个）。
--   正确做法：**拿实心圆放大一圈、垫在球下面**，露出来的那一圈环宽 = 我们要的线宽。
--   → 宽度完全可控、和我们手里那张实心圆素材的形状无关。
local function glowRadius(r)
  return r + math.max(V.haloStrokeMin, r * V.haloStrokeK)
end

-- 柔边（发光）：图片控件没有描边，靠 enableSoftEdge 做"糊一圈"的效果
local function softEdge(c, on, width)
  c.enableSoftEdge = on and true or false
  if on then
    c.softEdgeMode = Enum.ImageMaskSoftEdgeMode.Percentage
    c.softEdgeWidthX = width or 60
    c.softEdgeWidthY = width or 60
  end
end

-- 动效：直接写 localScale（不进脏检查缓存 —— 这些字段 sync 不碰，不会打架）
local function setScaleRaw(c, s)
  c.localScaleX = s
  c.localScaleY = s
  c.localScaleZ = 1
end

-- 便宜的缓动（够用即可；要 30 种缓动可以换 game.Tween，见文件头说明）
local function easeOut(u) return 1 - (1 - u) * (1 - u) end
local function easeBack(u)
  local s = 1.9
  local v = u - 1
  return 1 + (s + 1) * v * v * v + s * v * v
end

-- ==================== 建池 ====================

-- opts:
--   parent / canvas / ballPrefab / ballCount / shotPrefab / shotCount / art / hudPrefab / hud   —— 同以前
--   linkPrefab / linkCount / cavePrefab / mergeCount                                            —— 同以前
--   track          1 = 轨道也由 Lua 画（0 = 用编辑器里摆的静态图）
--   trackSegments  每条轨画多少段（默认 64；控件预算紧张时调小）
--   letters        1 = 球面上叠碱基字母文本框（0 = 只靠图片素材）
--   fancy          1 = 光晕 / 冷却环 / 动效（0 = 只留静态画面）
function M.create(opts)
  opts = opts or {}
  local parent = opts.parent
  if not parent then error('ui.create: 需要 parent') end
  local canvas = opts.canvas or { w = 900, h = 900 }

  local ui = {
    canvas = canvas,
    parent = parent,
    last = {},
    balls = {}, shots = {}, links = {}, elim = {}, merges = {}, halo = {}, letter = {}, elimLetter = {}, loadedLetter = {}, track = {},
    loaded = {}, hud = {},
    fx = {},                 -- 短命动效表
    elimOwner = {},          -- 球 id -> 正在显示它的绑定小球控件（用来播"被消掉"的动效）
    elimHex = {},            -- 球 id -> 绑定小球的颜色（淡出时要用同一个底色改 alpha）
    wasPaired = {},          -- 球 id -> 上一帧是否已读出
    t = 0,
    stats = { writes = 0, ballWrites = 0, hudWrites = 0 },
  }

  -- ★ 素材 id：**默认不打补丁**（见文件顶部 artIdOf 的注释 —— 写死 1..5 会让真机全画成"?"）
  --   opts.art 给了才用；键是碱基（A/U/G/C/T），值是编辑器里那张图的素材 id。
  ui.art = opts.art or {}
  -- 全局兜底资产号：棒/光晕/核糖体/冷却环这些不分碱基的控件用它（不设就全是"?"）
  ui.artAny = opts.artAny or ui.art['A'] or ui.art[CFG.BASES[1]]
  -- 棒（轨道/连线/瞄准线）专用素材：**方图**最好（圆图拉长会鼓出来）
  ui.artBar = opts.artBar or ui.artAny
  -- 环（洞穴那几圈）专用素材：**空心圆**（实心圆装成环要叠层，效果差）
  ui.artRing = opts.artRing or ui.artAny
  -- 开火冷却环：**本体没有** → 默认关（cd=1 才画）
  -- 球的描边/光晕总开关（默认开；填 glow=0 全关，保留其他美化）
  ui.glowOn = (opts.glow == nil) and 1 or opts.glow
  ui.cdOn = opts.cd or 0
  ui.fancy = (opts.fancy == nil) and 1 or opts.fancy
  ui.letters = (opts.letters == nil) and 1 or opts.letters
  ui.trackOn = (opts.track == nil) and 1 or opts.track
  ui.trackSegments = opts.trackSegments or 64
  ui.trackKey = nil
  ui.letterProbe = opts.letterProbe or 0     -- 临时探针，默认关（2026-09-25 用它定位过 ③ 不显示）

  local ballPrefab = opts.ballPrefab or 1
  local hudPrefab = opts.hudPrefab or 2
  local linkPrefab = opts.linkPrefab or ballPrefab
  local cavePrefab = opts.cavePrefab or ballPrefab

  -- ★ 动态创建失败时要**响亮地失败**：不然玩家看到的是空白画面，而错误在日志里
  local function build(prefab, what, i)
    local c = game.InstantiateClientUIControl(prefab, parent)
    if not c then
      error(what .. '创建失败（第 ' .. i .. ' 个，模板索引 ' .. tostring(prefab)
        .. '）。模板索引可能没填，或这个控件不能动态创建（主屏 / 模板控件的子节点都不行）')
    end
    c:SetActive(true)                       -- 文档：动态创建默认 active=false
    c:SetVisible(false)
    c.canControllerFocus = false
    -- ★★ 兜底：**凡是图片控件，建出来就先把素材设上**。
    --   真机事实：动态创建的图片控件**不继承**模板图，不设素材就画成"?"。
    --   原来靠每个绘制分支自己记得设 —— 漏一处就冒一批问号（用户报了两次）。
    --   放在这里 = 从源头堵住，跟后面怎么画无关。
    if ui.artAny then
      local t = typeof and typeof(c) or nil
      if type(t) == 'string' and t:find('Image', 1, true) then
        setImage(ui, c, ui.artAny)     -- 棒后面会被 placeSeg 改成 ui.artBar（方图）
      end
    end
    return c
  end

  local n = opts.ballCount or 96
  local sn = opts.shotCount or 8

  -- ⓪ "底"：一整块深色背板（用户反馈"没有底"）—— 只花 1 个控件，先建所以画在最底下。
  --    半透明（留一点关卡场景透出来），有它整局才像"一个界面"而不是浮在半空。
  --    backdrop = 0 可关掉（编辑器里自己摆了底图就用 0）。
  if opts.backdrop ~= 0 then
    local bg = build(ballPrefab, '背板控件', 1)
    setColor(ui, bg, C.backdrop or '#0b1119d9')
    softEdge(bg, false, 0)
    ui.backdrop = bg
  end

  -- ① 轨道（最底下）：一段段"棒"拼成两条轨路面
  if ui.trackOn ~= 0 then
    for i = 1, ui.trackSegments * 2 do ui.track[i] = build(linkPrefab, '轨道控件', i) end
  end

  -- ② 洞穴：三层红晕 + 暗心 + 文字
  ui.caveGlow = { build(cavePrefab, '洞穴光晕控件', 1), build(cavePrefab, '洞穴光晕控件', 2),
                  build(cavePrefab, '洞穴光晕控件', 3) }
  ui.cave = build(cavePrefab, '洞穴控件', 1)
  ui.caveLabel = build(hudPrefab, '洞穴文字控件', 1)
  ui.caveLabel.fontSize = 18
  ui.caveLabel.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
  ui.caveLabel.verticalAlignment = Enum.TextVerticalAlignment.Middle
  ui.caveLabel.enableOutline = true
  ui.caveLabel.text = '降解洞穴'
  ui.caveLabel:SetSizeDelta(160, 28)
  for i = 1, #ui.caveGlow do softEdge(ui.caveGlow[i], ui.fancy ~= 0, 70) end
  softEdge(ui.cave, ui.fancy ~= 0, 35)

  -- ③ 连线
  local ln = opts.linkCount or (n * 2)
  for i = 1, ln do ui.links[i] = build(linkPrefab, '连线控件', i) end

  -- ④ 状态光晕（在球下面）
  if ui.fancy ~= 0 then
    -- ★ 光晕池 = **2n**：主轨球用 halo[i]、副轨绑定球用 halo[haloHalf + i]。
    --   本体 render.js 的 drawBeadLayer 把 `['eliminate','spawn']` **两条轨都画一遍**，
    --   两边 paired 时都带 glow（副轨那颗的 glowColor 是空的 → 回落成白色描边）。
    ui.haloHalf = n
    for i = 1, 2 * n do
      ui.halo[i] = build(ballPrefab, '光晕控件', i)
      -- ★★ **环上不开柔边**：柔边（80）是当初给"实心圆盘做发光"调的；
      --    现在这一圈用的是**空心圆素材**，再叠柔边会把环糊成一团 →
      --    用户看到的"有的球描边会突然变坏"就是这个。环要清晰（本体也是硬描边）。
      softEdge(ui.halo[i], false, 0)
    end
  end

  -- ⑤ 绑定小球（副轨上"读出的那一半"）
  for i = 1, n do ui.elim[i] = build(ballPrefab, '绑定小球控件', i) end

  -- ⑥ 球池 / ⑦ 弹药池 / ⑧ 并入球
  for i = 1, n do ui.balls[i] = build(ballPrefab, '球控件', i) end
  for i = 1, sn do ui.shots[i] = build(opts.shotPrefab or ballPrefab, '弹药控件', i) end
  local mn = opts.mergeCount or 8
  for i = 1, mn do ui.merges[i] = build(ballPrefab, '并入球控件', i) end

  -- ⑨ 球面字母（盖在球上面）
  if ui.letters ~= 0 then
    for i = 1, n do
      local c = build(hudPrefab, '字母控件', i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      ui.letter[i] = c
    end
    -- ★ 绑定小球（三消道上那颗）**本体也带字母** —— 本体 render.js 用它自己那套
    --   drawBead(..., b.label || b.base, ...) 画**所有**珠子，主轨副轨都画。
    --   第一版只给主轨画了字母，用户报"用来匹配的小球没有字母"，就是这里漏的。
    for i = 1, n do
      local c = build(hudPrefab, '绑定球字母控件', i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      ui.elimLetter[i] = c
    end
  end

  -- ⑩ 瞄准线 -> 冷却环 -> 核糖体本体 -> 待发球描边 -> 两颗待发球 -> 字母
  -- ★★ **建控件的顺序 = 图层顺序**（后建的盖在上面）。真机上"待发球看不到字母"就是
  --    因为我把描边控件建在了字母**之后** → 描边压在字母上。正确顺序：环 → 球 → 字母。
  ui.aim = build(linkPrefab, '瞄准线控件', 1)
  ui.cd = build(ballPrefab, '冷却环控件', 1)
  ui.rb = build(ballPrefab, '核糖体控件', 1)
  softEdge(ui.rb, ui.fancy ~= 0, 45)
  -- 本体给"炮口那颗"画了 glow（drawBead 第 9 个参数 true）→ 白色描边
  ui.loadedHalo = { build(ballPrefab, '待发球描边控件', 1), build(ballPrefab, '待发球描边控件', 2) }
  for i = 1, 2 do softEdge(ui.loadedHalo[i], false, 0) end   -- 同理：环上不加柔边
  ui.loaded[1] = build(ballPrefab, '待发球控件', 1)
  ui.loaded[2] = build(ballPrefab, '待发球控件', 2)
  -- ★ 待发球也要字母（本体 render.js：`drawBead(..., lb(1), ...)` 和 `lb(0)` —— **两颗都带字**）
  --   放在最后建 → 一定盖在球和描边之上。
  -- ★★ 2026-09-25 【已改回】这一段 + 下面 sync 里的字号，就是"④ 显示正常"那一版的**原文**。
  --    当天 13:10 的提交（43cfc76）把这里做成了"挪到 M.create 最后 + 白描边 + 字号 1.35"，
  --    结果两颗字母全糊（12~19px 小字被描边吃掉）—— 用户报"原本 4 是正常的现在修没了，3 也没好"。
  --    ⚠ 以后别再动这三样：**别挪位置、别加 enableOutline、别改字号公式**。
  if ui.letters ~= 0 then
    for i = 1, 2 do
      local c = build(hudPrefab, '待发球字母控件', i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      ui.loadedLetter[i] = c
    end
  end

  -- ⑪ HUD 文本（加半透明底板，免得字飘在背景上）
  ui.hudOrder = {}
  for i = 1, #(opts.hud or {}) do
    local spec = opts.hud[i]
    local c = build(hudPrefab, '文本框控件', i)
    c:SetVisible(true)
    c:SetAnchoredPosition(spec.x or 0, spec.y or 0)
    c:SetSizeDelta(spec.w or 400, spec.h or 60)
    c.fontSize = spec.size or 28
    c.horizontalAlignment = spec.align == 'right' and Enum.TextHorizontalAlignment.Right
      or (spec.align == 'center' and Enum.TextHorizontalAlignment.Middle or Enum.TextHorizontalAlignment.Left)
    c.verticalAlignment = Enum.TextVerticalAlignment.Middle
    c.enableOutline = true
    -- 底板：默认 65% 半透明；spec.panel == 'light' 更淡一点（提示文字块很大，别做成黑板）
    local panelHex = '#00000000'
    if spec.panel == 'light' then panelHex = C.panelLight
    elseif spec.panel ~= false then panelHex = C.panel end
    c.bgColor = hexColor(panelHex)
    c.text = spec.text or ''
    ui.hud[spec.key] = c
    ui.hudOrder[#ui.hudOrder + 1] = spec.key
  end

  -- 平台上限自检（《编辑项范围限制》：单控件组 1000 / 单屏 10000）
  local total = M.count(ui)
  if total > 900 then
    if print then
      pcall(print, string.format('[zuma] ⚠ 控件数 %d 接近上限 1000：把 ballCount / trackSegments 调小，或把 track / letters 关掉', total))
    end
  end

  return ui
end

-- ==================== 轨道 ====================

-- 轨道用"一段段棒"拼：本体 drawTrackLayer 是 canvas 描线，图片控件只能这样近似。
-- 只在换关时写一次（静态），每帧不碰 —— 所以哪怕 128 个控件也不吃帧预算。
local function placeTrack(ui, sc)
  local cx, cy = sc.view.cx, sc.view.cy
  -- ⓪ 背板：铺满画布的一大块（每次尺寸变了才写）
  if ui.backdrop then
    place(ui, ui.backdrop, cx, cy, cx, cy, sc.view.w, sc.view.h, 0)
    setVisible(ui, ui.backdrop, true)
  end
  if ui.trackOn == 0 or #ui.track == 0 then return end
  local mt = sc.metrics
  local key = tostring(sc.level and sc.level.id) .. '#' .. tostring(math.floor(sc.path.length)) ..
    '#' .. tostring(sc.rails and sc.rails.spawn and sc.rails.spawn.offset or 0)
  if ui.trackKey == key then return end
  ui.trackKey = key

  local N = ui.trackSegments
  local seg = 0
  local function drawRail(poly, radius, hex)
    local m = #poly
    if m < 2 then return end
    local w = V.trackWidthK * radius
    -- ★ 每段两端各伸出去半个宽度：相邻两段**互相压住**，接缝就看不出来了
    --   （不伸的话，圆头"棒"接起来会露出一圈小缺口 —— 第一版出图时能看见一道道的暗痕）
    local ext = w * 0.5
    for k = 0, N - 1 do
      local i0 = 1 + math.floor(k * (m - 1) / N)
      local i1 = 1 + math.floor((k + 1) * (m - 1) / N)
      if i1 > i0 then
        local a, b = poly[i0], poly[i1]
        local dx, dy = b.x - a.x, b.y - a.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1e-6 then
          local ux, uy = dx / len, dy / len
          seg = seg + 1
          placeSeg(ui, ui.track[seg], cx, cy,
            a.x - ux * ext, a.y - uy * ext, b.x + ux * ext, b.y + uy * ext, w, hex)
          softEdge(ui.track[seg], ui.fancy ~= 0, 50)
        end
      end
    end
  end

  if sc.railPolys then
    drawRail(sc.railPolys.spawn, (sc.rails.spawn and sc.rails.spawn.radius) or mt.R, C.roadOuter)
    drawRail(sc.railPolys.eliminate, (sc.rails.eliminate and sc.rails.eliminate.radius) or mt.r, C.roadInner)
  end
  for i = seg + 1, #ui.track do setVisible(ui, ui.track[i], false) end
end

-- ==================== 每帧同步 ====================

-- st（可选）: { dt, events, hintLines = {..}, mode = 'match'|'insert' }
function M.sync(ui, sc, st)
  st = st or {}
  local view = sc.view
  local mt = sc.metrics
  local cx, cy = view.cx, view.cy
  local dt = st.dt or 0
  ui.t = ui.t + dt
  ui.stats.writes = 0

  local function baseColor(b)
    return CFG.BASE_COLOR[b] or '#ffffff'
  end

  -- ---- 动效推进（先推进，再让本帧的静态同步覆盖"非动画字段"）----
  for i = #ui.fx, 1, -1 do
    local fx = ui.fx[i]
    fx.t = fx.t + dt
    local u = fx.dur > 0 and math.min(1, fx.t / fx.dur) or 1
    local c = fx.c
    if fx.kind == 'pop' then
      setScaleRaw(c, 0.25 + (1 - 0.25) * easeBack(u))
    elseif fx.kind == 'fire' then
      local k = (u < 0.4) and (u / 0.4) or (1 - (u - 0.4) / 0.6)
      setScaleRaw(c, 1 + 0.18 * k)
    elseif fx.kind == 'gone' then
      setScaleRaw(c, 1 + 0.9 * easeOut(u))
      local r, g, b = rgbOf(fx.hex)
      c.imageColor = Color.FromRGBA(r, g, b, math.floor(255 * (1 - u) + 0.5))
    end
    if u >= 1 then
      if fx.kind == 'gone' then
        setVisible(ui, c, false)
      else
        setScaleRaw(c, 1)
      end
      if fx.hex then invalidateColor(ui, c) end
      table.remove(ui.fx, i)
    end
  end

  -- ---- 轨道（换关才写）----
  placeTrack(ui, sc)

  -- ---- 洞穴（静止练习关没有轨道，也就没有洞穴）----
  if ui.cave then
    if sc.still or not sc.path then
      setVisible(ui, ui.cave, false)
      setVisible(ui, ui.caveLabel, false)
      for i = 1, #ui.caveGlow do setVisible(ui, ui.caveGlow[i], false) end
    else
      local e = sc.path:pointAt(sc.path.length)
      local R = mt.R * V.caveR
      -- 三层红晕（本体是径向渐变）+ 暗心；fancy 关了就只有暗心
      if ui.fancy ~= 0 then
        for i = 1, #ui.caveGlow do
          local k = 1 + 0.16 * i          -- 1.16 / 1.32 / 1.48：贴着本体那一圈，不要铺开一大片
          local glow = ui.caveGlow[i]
          -- ★ 用**空心圆**素材（ui.artRing）：洞口本来就是"环"，空心圆染红正好；
          --   实心圆在这里得靠叠层+透明度装成环，效果差一截。
          placeBead(ui, glow, cx, cy, e.x, e.y, R * k, C.caveGlow[i] or C.caveGlow[1], ui.artRing)
          -- 呼吸：慢慢放大缩小，让"洞口"看着是活的
          setScaleRaw(glow, 1 + 0.05 * math.sin((ui.t + i * 0.35) * 2.4))
        end
      else
        for i = 1, #ui.caveGlow do setVisible(ui, ui.caveGlow[i], false) end
      end
      placeBead(ui, ui.cave, cx, cy, e.x, e.y, R, C.caveCore)
      place(ui, ui.caveLabel, cx, cy, e.x, e.y + R + 14 * (mt.scale or 1), 160, 28, 0)
    end
  end

  -- ---- 球（+ 状态光晕 + 碱基字母）----
  local beads = sc.beads.spawn
  local pool = ui.balls
  for i = 1, #pool do
    local c = pool[i]
    local b = beads[i]
    if b then
      local d = 2 * b.r
      if setField(ui, c, 'anchoredPositionX', b.x - cx) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'anchoredPositionY', cy - b.y) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'sizeDeltaX', d) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'sizeDeltaY', d) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setVisible(ui, c, true) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      -- 配错 = 灰球；已配对但还没定型，用原色（吸附飞行途中）
      local hex = b.wrongMark and CFG.WRONG_COLOR or baseColor(b.base)
      setColor(ui, c, hex)
      setImage(ui, c, artIdOf(ui, b.base))

      -- 光晕：读出/配错才亮（本体 drawBead 的 glow：球外 r+3 处一圈**描边**，不是大圆盘）
      if ui.halo[i] then
        if ui.fancy ~= 0 and ui.glowOn ~= 0 and b.pairGlow then
          -- ★ 用**空心圆**素材画成细环（实心圆画 2.1× 会像"球变大了" —— 用户一眼看出不对）
        placeBead(ui, ui.halo[i], cx, cy, b.x, b.y, glowRadius(b.r), b.pairGlow, ui.artAny)
        else
          setVisible(ui, ui.halo[i], false)
        end
      end

      -- 字母：本体把 label 画在球面上
      if ui.letter[i] then
        local lc = ui.letter[i]
        local ink = b.wrongMark and (CFG.WRONG_INK or C.letterOnLight) or (CFG.BASE_INK[b.base] or C.letterOnLight)
        place(ui, lc, cx, cy, b.x, b.y, d, d, 0)
        lc.text = tostring(b.label or b.base or '')
        lc.fontSize = math.max(8, math.floor(b.r * V.letterScale))
        lc.fontColor = hexColor(ink)
      end
    else
      setVisible(ui, c, false)
      if ui.halo[i] then setVisible(ui, ui.halo[i], false) end
      if ui.letter[i] then setVisible(ui, ui.letter[i], false) end
    end
  end

  -- ---- 绑定小球 + 配对连线（"读出"这件事的可视化）----
  -- sc.beads.eliminate[i] = 副轨上的那一半；它的 .partner 指向主轨上被读出的球。
  local elim = sc.beads.eliminate
  local li = 0
  local liveElim = {}
  for i = 1, #ui.elim do
    local e = elim[i]
    if e then
      placeBead(ui, ui.elim[i], cx, cy, e.x, e.y, e.r,
        e.wrong and CFG.WRONG_COLOR or baseColor(e.base), artIdOf(ui, e.base))
      -- ★ 副轨绑定球的描边（本体：它的 glow=true 且 glowColor 为空 → 白色描边）
      local eh = ui.halo and ui.haloHalf and ui.halo[ui.haloHalf + i]
      if eh and ui.fancy ~= 0 and ui.glowOn ~= 0 then
        placeBead(ui, eh, cx, cy, e.x, e.y, glowRadius(e.r), '#ffffff80', ui.artAny)  -- 本体是 rgba(255,255,255,0.5)
      elseif eh then
        setVisible(ui, eh, false)
      end
      -- ★ 绑定小球上的字母（本体副轨那颗也画字母）
      local lc = ui.elimLetter and ui.elimLetter[i]
      if lc then
        local d2 = 2 * e.r
        place(ui, lc, cx, cy, e.x, e.y, d2, d2, 0)
        lc.text = tostring(e.base or '')
        lc.fontSize = math.max(8, math.floor(e.r * V.letterScale))
        local ink = e.wrong and (CFG.WRONG_INK or C.letterOnLight) or (CFG.BASE_INK[e.base] or C.letterOnLight)
        lc.fontColor = hexColor(ink)
        setVisible(ui, lc, true)
      end
      local pid = e.partner and e.partner.id
      if pid ~= nil then
        liveElim[pid] = true
        ui.elimOwner[pid] = ui.elim[i]
        ui.elimHex[pid] = e.wrong and CFG.WRONG_COLOR or baseColor(e.base)
        -- 刚被读出：绑定小球"弹"一下（本体 drawPairLink 的 pairGlow 质感）
        if ui.fancy ~= 0 and ui.wasPaired[pid] == false then
          setScaleRaw(ui.elim[i], 0.25)
          ui.fx[#ui.fx + 1] = { c = ui.elim[i], kind = 'pop', t = 0, dur = 0.26 }
        end
      end
    else
      setVisible(ui, ui.elim[i], false)
      if ui.elimLetter and ui.elimLetter[i] then setVisible(ui, ui.elimLetter[i], false) end
      -- ★★ 这里原来写的是 `if eh then setVisible(ui, eh, false) end` —— 而 eh 是上面 if 分支里的
      --    local，**出了作用域**（Lua 不报错，直接是 nil），于是这条隐藏**永远不执行**
      --    → 亮过的白圈永久留在三消道上。用户报"没匹配也有一堆奇怪白圈"就是它。
      --    教训：跨分支用局部变量这种错 Lua 静默通过，只有"配对消失后要收干净"的测试能逮住。
      local stale = ui.halo and ui.haloHalf and ui.halo[ui.haloHalf + i]
      if stale then setVisible(ui, stale, false) end
    end
  end
  -- 读完的球（或整段被消掉）：让它的绑定小球"炸开淡出"再消失
  if ui.fancy ~= 0 then
    for pid, c in pairs(ui.elimOwner) do
      if not liveElim[pid] then
        local wasLive = false
        for i = 1, #elim do
          local e = elim[i]
          if e and e.partner and e.partner.id == pid then wasLive = true; break end
        end
        if not wasLive and ui.wasPaired[pid] == true then
          ui.fx[#ui.fx + 1] = { c = c, kind = 'gone', t = 0, dur = 0.22,
                                hex = ui.elimHex[pid] or '#ffffff' }
          invalidateColor(ui, c)
        end
        ui.elimOwner[pid] = nil
        ui.elimHex[pid] = nil
        ui.wasPaired[pid] = nil
      end
    end
  end
  local barW = math.max(2, V.linkWidth * (mt.scale or 1))
  for i = 1, #elim do
    local e = elim[i]
    local p = e.partner
    if p then
      local hex = e.wrong and CFG.WRONG_COLOR or baseColor(e.base)
      local dx, dy = p.x - e.x, p.y - e.y
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 1e-6 then
        if e.wrong then
          -- 错配：折线（DESIGN §32：主题上就是"氢键接不上"）。两段 = 两个控件。
          local px, py = -dy / len, dx / len
          local amp = math.max(2.5, V.linkAmp * (mt.scale or 1))
          if li + 2 <= #ui.links then
            li = li + 1
            placeSeg(ui, ui.links[li], cx, cy,
              e.x + dx * V.linkFrom, e.y + dy * V.linkFrom,
              e.x + dx * 0.42 + px * amp, e.y + dy * 0.42 + py * amp, barW, hex)
            li = li + 1
            placeSeg(ui, ui.links[li], cx, cy,
              e.x + dx * 0.58 - px * amp, e.y + dy * 0.58 - py * amp,
              e.x + dx * V.linkTo, e.y + dy * V.linkTo, barW, hex)
          end
        elseif li + 1 <= #ui.links then
          li = li + 1
          placeSeg(ui, ui.links[li], cx, cy,
            e.x + dx * V.linkFrom, e.y + dy * V.linkFrom,
            e.x + dx * V.linkTo, e.y + dy * V.linkTo, barW, hex)
        end
      end
    end
  end
  for i = li + 1, #ui.links do setVisible(ui, ui.links[i], false) end

  -- ---- 状态记忆（给下一帧判断"刚读出/刚消失"）----
  for i = 1, #beads do
    local b = beads[i]
    if b.id ~= nil then ui.wasPaired[b.id] = b.paired and true or false end
  end

  -- ---- 弹药 ----
  local shots = sc.projectiles
  for i = 1, #ui.shots do
    local c = ui.shots[i]
    local p = shots[i]
    if p then
      placeBead(ui, c, cx, cy, p.x, p.y, p.r, baseColor(p.base), artIdOf(ui, p.base))
    else
      setVisible(ui, c, false)
    end
  end

  -- ---- 并入球（U12：正在挤进去的那颗，画在同层链珠之上）----
  local merges = sc.merges or {}
  for i = 1, #ui.merges do
    local m = merges[i]
    if m then
      placeBead(ui, ui.merges[i], cx, cy, m.x, m.y, m.r, baseColor(m.base), artIdOf(ui, m.base))
    else
      setVisible(ui, ui.merges[i], false)
    end
  end

  -- ---- 核糖体（发射口）+ 两颗待发球 + 瞄准线 + 冷却环 ----
  local rb = sc.rb
  if rb then
    local R = rb.r
    local ax, ay = math.cos(rb.aim), math.sin(rb.aim)
    -- 瞄准线：从炮口沿 aim 方向，长度 R + 110×scale（本体 drawRibosome 原式），30% 透明
    placeSeg(ui, ui.aim, cx, cy, rb.x, rb.y,
      rb.x + ax * (R + V.aimLen * (mt.scale or 1)), rb.y + ay * (R + V.aimLen * (mt.scale or 1)),
      math.max(1, V.aimWidth * (mt.scale or 1)), C.aim)
    -- 核糖体本体
    placeBead(ui, ui.rb, cx, cy, rb.x, rb.y, R, C.rbBody)
    -- 开火冷却环：径向填充，满了就该能打了。
    -- ★★ **本体没有这个东西**（`src/render.js` 里根本没有 cooldown 的绘制，它只是规则值）。
    --    按"屏幕上默认不许出现本体没有的东西"这条规矩（HANDOFF §19），**默认关**；
    --    想看就填脚本变量 cd=1。
    if ui.cd then
      if ui.fancy ~= 0 and ui.cdOn == 1 and rb.cooldown and rb.cooldown > 0.001 then
        local total = (CFG.DESIGN and CFG.DESIGN.fireCooldown) or 0.16
        local p = 1 - math.min(1, rb.cooldown / total)
        placeBead(ui, ui.cd, cx, cy, rb.x, rb.y, R * 1.45, C.cd)
        ui.cd:SetFillRadial360(Enum.ImageFillRadialType.Top, p)
      else
        setVisible(ui, ui.cd, false)
      end
    end
    -- 两颗待发球：炮口那颗在前（+0.8R，半径 ×1.0）、待命那颗在后（−0.7R，半径 ×0.8）
    -- （本体 render.js drawRibosome 原文：`bR = (mode==='insert') ? mt.R : mt.r`）
    local bR = (sc.mode == 'insert') and mt.R or mt.r
    local b1, b2 = rb.loaded and rb.loaded[1], rb.loaded and rb.loaded[2]
    local lx1, ly1 = rb.x + ax * R * 0.8, rb.y + ay * R * 0.8
    local lx2, ly2 = rb.x - ax * R * 0.7, rb.y - ay * R * 0.7
    placeBead(ui, ui.loaded[1], cx, cy, lx1, ly1, bR, baseColor(b1), artIdOf(ui, b1))
    placeBead(ui, ui.loaded[2], cx, cy, lx2, ly2, bR * 0.8, baseColor(b2), artIdOf(ui, b2))
    -- ★★ 两颗待发球的字母（本体 lb(1) / lb(0) 都画）。
    -- ★★★ 2026-09-25 **临时探针**（定位"③ 的字母设好了却不显示"）：
    --   真机日志已证明 ③ 的文本框「文字=G 可见=true 字号=15 位置=(0,-21)」全都正常，
    --   屏幕上却没有 —— 只剩两种可能，探针一次判定：
    --     · 看到"红底方块 + 白字 G" → 控件会被绘制，是尺寸/颜色问题 → 据此收窄；
    --     · 什么都看不到            → 这个控件不在绘制列表里 → 改用**链珠字母那套池子**画。
    --   探针只动 ③（k=2），④ 全程不动；`letterProbe=0` 可关掉。
    for k = 1, 2 do
      local lc = ui.loadedLetter and ui.loadedLetter[k]
      if lc then
        local base = (k == 1) and b1 or b2
        local rr = (k == 1) and bR or bR * 0.8
        local xx = (k == 1) and lx1 or lx2
        local yy = (k == 1) and ly1 or ly2
        local probe = (ui.letterProbe ~= 0) and (k == 2)
        -- ★★ 框尺寸：**不小于链珠字母的框**（2×mt.r）。
        --   真机事实（2026-09-25）：③ 原来用 2×rr = 21.5px 的框，状态全对（文字/可见/字号/位置
        --   都对）却**不显示**；探针把框放大 + 换红底白字后立刻显示。而链珠字母的框是 26.9px，
        --   一直显示正常 ⇒ 取 max(2×球半径, 2×链珠半径)，即"用已被证明能显示的尺寸"。
        local box = math.max(2 * rr, 2 * mt.r)
        local d2 = probe and (rr * 5.6) or box
        place(ui, lc, cx, cy, xx, yy, d2, d2, 0)
        if probe then
          lc.text = 'G'
          lc.fontSize = 24
          lc.fontColor = hexColor('#ffffff')
          lc.bgColor = hexColor('#ff0000cc')
        else
          lc.text = tostring(base or '')
          -- 字号 = 半径 × V.letterScale，**下限 15**：4/链珠/绑定球的自然值都 ≥15，
          -- 所以这个下限只抬升 ③ 那颗最小的球（10.7 → 12 抬到 15）。别改成整体放大，更别加描边。
          lc.fontSize = math.max(15, math.floor(rr * V.letterScale))
          lc.fontColor = hexColor(CFG.BASE_INK[base] or C.letterOnLight)
          lc.bgColor = hexColor('#00000000')
        end
        setVisible(ui, lc, true)
      end
    end
    -- ★ 炮口那颗的白色描边（本体那次 drawBead 的 glow 参数是 true）
    local lh = ui.loadedHalo
    if lh and ui.fancy ~= 0 and ui.glowOn ~= 0 then
      placeBead(ui, lh[1], cx, cy, lx1, ly1, glowRadius(bR), '#ffffff80', ui.artAny)  -- 本体同样 50%
      setVisible(ui, lh[2], false)
    elseif lh then
      setVisible(ui, lh[1], false)
      setVisible(ui, lh[2], false)
    end
  end

  -- ---- 开火后坐（stats.fired 涨了就弹一下）----
  if ui.fancy ~= 0 and ui.rb then
    local fired = (sc.stats and sc.stats.fired) or 0
    if ui.lastFired == nil then ui.lastFired = fired end
    if fired > ui.lastFired then
      ui.fx[#ui.fx + 1] = { c = ui.rb, kind = 'fire', t = 0, dur = 0.16 }
    end
    ui.lastFired = fired
  end

  -- ---- HUD 文本 ----
  -- ★ 没文字的文本框要**连底板一起藏起来**：首轮美化里"结果"文本框一直是空的，
  --   却把 640×120 的半透明黑板画在正中央，把核糖体整个盖住了。
  local function text(key, s)
    local c = ui.hud[key]
    if not c then return end
    if c.text ~= s then c.text = s; ui.stats.hudWrites = ui.stats.hudWrites + 1 end
    if s and s ~= '' then
      setVisible(ui, c, true)
    else
      setVisible(ui, c, false)
    end
  end
  text('score', '分数 ' .. tostring(sc.score))
  text('lives', '命 ' .. tostring(sc.lives))
  local runs = {}
  for i = 1, #sc.runsInfo do
    local r = sc.runsInfo[i]
    runs[#runs + 1] = tostring(r.len) .. (r.len % 3 == 0 and '✓' or ('(+' .. tostring(3 - r.len % 3) .. ')'))
  end
  text('runs', '连读 ' .. (#runs > 0 and table.concat(runs, ' ') or '—'))
  text('mode', st.mode == 'insert' and '模式：加球' or '模式：配对')
  -- 判定诊断行（st.lastHit / st.mate 由 game.lua 填）：屏幕上直接看得到"这次算配对还是错配"
  if ui.hud.hit then text('hit', st.lastHit or '') end
  if ui.hud.mate then text('mate', st.mate or '') end
  if ui.hud.hint then
    text('hint', st.hintLines and table.concat(st.hintLines, '\n') or '')
  end
  return ui
end

-- ui 一共建了多少个控件（诊断行 + 预算自检用）
function M.count(ui)
  local n = #ui.balls + #ui.shots + #ui.links + #ui.elim + #ui.merges
    + #ui.track + #ui.halo + #ui.letter + #ui.loaded
    + (ui.rb and 1 or 0) + (ui.aim and 1 or 0) + (ui.cd and 1 or 0)
    + (ui.cave and 1 or 0) + (ui.caveLabel and 1 or 0) + #ui.caveGlow
    + #ui.hudOrder
  return n
end

-- 平台上限自检（《编辑项范围限制》：单控件组 1000 / 单屏 10000）
function M.budget(ui)
  return M.count(ui), 1000, 10000
end

return M

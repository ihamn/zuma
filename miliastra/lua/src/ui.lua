-- ui.lua —— 表现层：board 的状态 -> 客户端控件。
--
-- ★★ 这里**不重新实现任何规则**：位置/颜色/显隐全部来自 sc（board.lua 算好的）。
--   ui 的职责只有三件：坐标换算、控件池复用、脏检查。
--
-- 坐标：board 用的是"画布像素、原点左上、y 向下"；控件 anchoredPosition 在父级下
--       是"相对父级中心、y 向上"。所以 y 要翻一次号：uiY = view.cy - y。
--       父级 = 一块铺满画布、居中在画布中心的容器控件。
--
-- ★★ 画什么、画多大，照着网页版 `src/render.js` 搬（百分比/半径/偏移都用它的原式）：
--     核糖体 + 两颗待发球 + 瞄准线   <-  drawRibosome
--     配对连线（正确 = 一根直棒；错配 = 折线"断掉的键"）<- drawPairLink / drawPairLinks
--     副轨上的绑定小球（读出的那一半）<- drawBeadLayer 的 beads.eliminate
--     并入过程里正在挤进去的球        <- drawMergeLayer
--     洞穴（降解口）                  <- drawCave
--   ★ 这是"表现层缺口"的修复：这一版之前，上面这些东西**一个都没画** ——
--     玩家看不到自己在哪开枪、往哪瞄，也看不出哪两颗配上了（只有颜色变化）。
--
-- ⚠ 画不出来的部分（原因写在代码里，不靠人记）：图片控件**只有填充色，没有描边/渐变**。
--     - 核糖体本体只画填充 #22303f（本体还有一圈蓝色描边）
--     - 洞穴画成"红圈 + 暗心"两个控件（本体是径向渐变 + 红描边）
--     - 瞄准线用不透明蓝 #4a6a90（本体是 rgba(150,200,255,0.30)，图片控件没有 alpha）
--     - 洞穴标签"降解洞穴"用**文本框**控件（本体是 canvas 文字）
--   这些都是"能看出是什么"的下限，真机上看着不对再调数值。
--
-- ★ 控件池的**创建顺序就是绘制顺序**（运行时：同级索引大的在上面，契约 §13）：
--   洞穴 -> 连线 -> 绑定小球 -> 球 -> 弹药 -> 并入球 -> 瞄准线 -> 核糖体 -> 待发球 -> HUD

local CFG = require('config')

local M = {}

local Z = CFG.Z

-- '#rrggbb' -> Color(r,g,b,255)
local function hexColor(s, fallback)
  if type(s) ~= 'string' or #s < 7 then return fallback or Color.FromRGBA(255, 255, 255, 255) end
  local r = tonumber(s:sub(2, 3), 16) or 255
  local g = tonumber(s:sub(4, 5), 16) or 255
  local b = tonumber(s:sub(6, 7), 16) or 255
  return Color.FromRGBA(r, g, b, 255)
end
M.hexColor = hexColor

-- ★★ 控件运行时 ID 的字段名：官方是 **`Id`（首字母大写）**。
--    真机观察（客户端 Lua 运行时契约 §16）：「`Id`（客户端控件运行时ID，首字母大写）/ `prefabIndex`；
--    旧 probe 中的 `control.id` / `prefabId` 是**旧版本接口，不作为兼容口径**」。
--    原来这里写的是小写 `c.id` —— 真机上恒为 nil，于是 `ui.last[nil]` 直接报
--    「table index is nil」，整局在第一帧就崩。本地假宿主提供的是小写 id，所以测试发现不了。
--    两个都认：真机走 Id，本地假宿主走 id。
local function ctrlId(c)
  return c.Id or c.id
end

local function setField(ui, c, key, value)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
  if cache[key] == value then return false end
  cache[key] = value
  c[key] = value
  return true
end

local function setColor(ui, c, hex)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
  if cache.__color == hex then return false end
  cache.__color = hex
  c.imageColor = hexColor(hex)
  return true
end

local function setImage(ui, c, id)
  local key = ctrlId(c)
  local cache = ui.last[key]
  if cache == nil then cache = {}; ui.last[key] = cache end
  if cache.__image == id then return false end
  cache.__image = id
  c:SetImage(Enum.ImageSource.StaticReference, id)
  return true
end

-- ★★ 可见性：官方契约里 `visible` 是**只读**字段 —— 读得到，**写会报**
--    「cannot set visible, no such field」。改可见性必须调方法 SetVisible()。
--    原来这里用 setField(..., 'visible', ...) 直接赋值，真机上一进 sync 就崩。
local function setVisible(ui, c, v)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
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
--   （两根连线/瞄准线都靠这个把"一根棒"摆到正确方向）
local function rotDeg(dx, dy)
  return math.deg(math.atan(-dy, dx))
end

-- 把控件当"一根棒"用：从 (x1,y1) 拉到 (x2,y2)，粗细 w
local function placeSeg(ui, c, cx, cy, x1, y1, x2, y2, w, hex)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then setVisible(ui, c, false); return end
  place(ui, c, cx, cy, (x1 + x2) / 2, (y1 + y2) / 2, len, w, rotDeg(dx, dy))
  setColor(ui, c, hex)
  setImage(ui, c, 1)
end

-- 把一个控件当"一颗球"用
local function placeBead(ui, c, cx, cy, x, y, r, hex, artId)
  local d = 2 * r
  place(ui, c, cx, cy, x, y, d, d, 0)
  setColor(ui, c, hex)
  setImage(ui, c, artId or 1)
end

-- ==================== 建池 ====================

-- opts:
--   parent        挂到哪个控件下（一般是铺满画布的容器）
--   canvas        { w, h }
--   ballPrefab    球控件的控件模板索引
--   ballCount     球池大小（同时也是绑定小球池的大小）
--   shotPrefab    弹药控件模板索引
--   shotCount     弹药池大小
--   linkPrefab    连线的模板索引（默认与球同一个模板：拉长就是一根棒）
--   linkCount     连线池大小（默认 ballCount × 2 —— 错配的折线要占两段）
--   mergeCount    并入球池大小（默认 8）
--   cavePrefab    洞穴的模板索引（默认与球同一个模板）
--   art           { [base] = 图片id }；缺省用 1..5
--   hudPrefab     文本框控件模板索引
--   hud           { { key=, text=, x=, y=, size=, align= }, ... }  x/y 是**控件坐标**（相对中心，y 向上）
function M.create(opts)
  opts = opts or {}
  local parent = opts.parent
  if not parent then error('ui.create: 需要 parent') end
  local canvas = opts.canvas or { w = 900, h = 900 }

  local ui = {
    canvas = canvas,
    parent = parent,
    last = {},
    balls = {},
    shots = {},
    links = {},
    elim = {},
    merges = {},
    loaded = {},
    hud = {},
    stats = { writes = 0, ballWrites = 0, hudWrites = 0 },
  }

  local art = opts.art or {}
  if not next(art) then
    for i = 1, #CFG.BASES do art[CFG.BASES[i]] = i end
  end
  ui.art = art

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
    return c
  end

  local n = opts.ballCount or 96
  local sn = opts.shotCount or 8

  -- ① 洞穴（最底下：球要能从它前面滚进去）
  ui.caveRing = build(cavePrefab, '洞穴外圈控件', 1)
  ui.cave = build(cavePrefab, '洞穴控件', 1)
  ui.caveLabel = build(hudPrefab, '洞穴文字控件', 1)
  ui.caveLabel.fontSize = 18
  ui.caveLabel.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
  ui.caveLabel.verticalAlignment = Enum.TextVerticalAlignment.Middle
  ui.caveLabel.enableOutline = true
  ui.caveLabel.text = '降解洞穴'
  ui.caveLabel:SetSizeDelta(160, 28)

  -- ② 配对连线（在球下面：连线不该盖住球面）
  local ln = opts.linkCount or (n * 2)
  for i = 1, ln do ui.links[i] = build(linkPrefab, '连线控件', i) end

  -- ③ 绑定小球（副轨上"读出的那一半"）
  for i = 1, n do ui.elim[i] = build(ballPrefab, '绑定小球控件', i) end

  -- ④ 球池
  for i = 1, n do ui.balls[i] = build(ballPrefab, '球控件', i) end

  -- ⑤ 弹药池
  for i = 1, sn do ui.shots[i] = build(opts.shotPrefab or ballPrefab, '弹药控件', i) end

  -- ⑥ 并入球（加球模式里正在挤进去的那颗）
  local mn = opts.mergeCount or 8
  for i = 1, mn do ui.merges[i] = build(ballPrefab, '并入球控件', i) end

  -- ⑦ 瞄准线 -> 核糖体本体 -> 两颗待发球（本体在最上，压住瞄准线的起点）
  ui.aim = build(linkPrefab, '瞄准线控件', 1)
  ui.rb = build(ballPrefab, '核糖体控件', 1)
  ui.loaded[1] = build(ballPrefab, '待发球控件', 1)
  ui.loaded[2] = build(ballPrefab, '待发球控件', 2)

  -- ⑧ HUD 文本
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
    c.text = spec.text or ''
    ui.hud[spec.key] = c
    ui.hudOrder[#ui.hudOrder + 1] = spec.key
  end

  return ui
end

-- ==================== 每帧同步 ====================

-- st（可选）: { aim = 弧度, hintLines = {..}, badge = '…', mode = 'match'|'insert' }
function M.sync(ui, sc, st)
  st = st or {}
  local view = sc.view
  local mt = sc.metrics
  local cx, cy = view.cx, view.cy
  ui.stats.writes = 0

  local function baseColor(b)
    return CFG.BASE_COLOR[b] or '#ffffff'
  end

  -- ---- 球 ----
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
      setImage(ui, c, ui.art[b.base] or 1)
    else
      setVisible(ui, c, false)
    end
  end

  -- ---- 绑定小球 + 配对连线（"读出"这件事的可视化）----
  -- sc.beads.eliminate[i] = 副轨上的那一半；它的 .partner 指向主轨上被读出的球。
  -- 连线画在两者之间（本体 drawPairLink：26%~74% 一段；错配画成折线 = "断掉的键"）。
  local elim = sc.beads.eliminate
  local li = 0
  for i = 1, #ui.elim do
    local e = elim[i]
    if e then
      placeBead(ui, ui.elim[i], cx, cy, e.x, e.y, e.r,
        e.wrong and CFG.WRONG_COLOR or baseColor(e.base), ui.art[e.base] or 1)
    else
      setVisible(ui, ui.elim[i], false)
    end
  end
  local barW = math.max(2, 3.4 * (mt.scale or 1))
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
          local amp = math.max(2.5, 3.4 * (mt.scale or 1))
          if li + 2 <= #ui.links then
            li = li + 1
            placeSeg(ui, ui.links[li], cx, cy,
              e.x + dx * 0.26, e.y + dy * 0.26,
              e.x + dx * 0.42 + px * amp, e.y + dy * 0.42 + py * amp, barW, hex)
            li = li + 1
            placeSeg(ui, ui.links[li], cx, cy,
              e.x + dx * 0.58 - px * amp, e.y + dy * 0.58 - py * amp,
              e.x + dx * 0.74, e.y + dy * 0.74, barW, hex)
          end
        elseif li + 1 <= #ui.links then
          li = li + 1
          placeSeg(ui, ui.links[li], cx, cy,
            e.x + dx * 0.26, e.y + dy * 0.26,
            e.x + dx * 0.74, e.y + dy * 0.74, barW, hex)
        end
      end
    end
  end
  for i = li + 1, #ui.links do setVisible(ui, ui.links[i], false) end

  -- ---- 弹药 ----
  local shots = sc.projectiles
  for i = 1, #ui.shots do
    local c = ui.shots[i]
    local p = shots[i]
    if p then
      placeBead(ui, c, cx, cy, p.x, p.y, p.r, baseColor(p.base), ui.art[p.base] or 1)
    else
      setVisible(ui, c, false)
    end
  end

  -- ---- 并入球（U12：正在挤进去的那颗，画在同层链珠之上）----
  local merges = sc.merges or {}
  for i = 1, #ui.merges do
    local m = merges[i]
    if m then
      placeBead(ui, ui.merges[i], cx, cy, m.x, m.y, m.r, baseColor(m.base), ui.art[m.base] or 1)
    else
      setVisible(ui, ui.merges[i], false)
    end
  end

  -- ---- 核糖体（发射口）+ 两颗待发球 + 瞄准线 ----
  local rb = sc.rb
  if rb then
    local R = rb.r
    local ax, ay = math.cos(rb.aim), math.sin(rb.aim)
    -- 瞄准线：从炮口沿 aim 方向，长度 R + 110×scale（本体 drawRibosome 原式）
    placeSeg(ui, ui.aim, cx, cy, rb.x, rb.y,
      rb.x + ax * (R + 110 * (mt.scale or 1)), rb.y + ay * (R + 110 * (mt.scale or 1)),
      math.max(1, 1.4 * (mt.scale or 1)), '#4a6a90')
    -- 本体
    placeBead(ui, ui.rb, cx, cy, rb.x, rb.y, R, '#22303f', 1)
    -- 两颗待发球：炮口那颗在前（+0.8R，半径 ×1.0）、待命那颗在后（−0.7R，半径 ×0.8）
    local bR = (sc.mode == 'insert') and mt.R or mt.r
    local b1, b2 = rb.loaded and rb.loaded[1], rb.loaded and rb.loaded[2]
    placeBead(ui, ui.loaded[1], cx, cy,
      rb.x + ax * R * 0.8, rb.y + ay * R * 0.8, bR, baseColor(b1), ui.art[b1] or 1)
    placeBead(ui, ui.loaded[2], cx, cy,
      rb.x - ax * R * 0.7, rb.y - ay * R * 0.7, bR * 0.8, baseColor(b2), ui.art[b2] or 1)
  end

  -- ---- 洞穴（静止练习关没有轨道，也就没有洞穴）----
  if ui.cave then
    if sc.still or not sc.path then
      setVisible(ui, ui.cave, false)
      setVisible(ui, ui.caveRing, false)
      setVisible(ui, ui.caveLabel, false)
    else
      local e = sc.path:pointAt(sc.path.length)
      local R = mt.R * 1.5
      placeBead(ui, ui.caveRing, cx, cy, e.x, e.y, R * 1.15, '#ff5a6e', 1)
      placeBead(ui, ui.cave, cx, cy, e.x, e.y, R, '#1a0a12', 1)
      place(ui, ui.caveLabel, cx, cy, e.x, e.y + R + 14 * (mt.scale or 1), 160, 28, 0)
    end
  end

  -- ---- HUD 文本 ----
  local function text(key, s)
    local c = ui.hud[key]
    if not c then return end
    if c.text ~= s then c.text = s; ui.stats.hudWrites = ui.stats.hudWrites + 1 end
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
  if ui.hud.hint then
    text('hint', st.hintLines and table.concat(st.hintLines, '\n') or '')
  end
  return ui
end

-- ui 一共建了多少个控件（诊断行 + 预算自检用）
function M.count(ui)
  return #ui.balls + #ui.shots + #ui.links + #ui.elim + #ui.merges + #ui.loaded
    + (ui.rb and 1 or 0) + (ui.aim and 1 or 0)
    + (ui.cave and 1 or 0) + (ui.caveRing and 1 or 0) + (ui.caveLabel and 1 or 0)
    + #ui.hudOrder
end

-- 平台上限自检（《编辑项范围限制》：单控件组 1000 / 单屏 10000）
function M.budget(ui)
  return M.count(ui), 1000, 10000
end

return M

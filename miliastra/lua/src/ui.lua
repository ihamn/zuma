-- ui.lua —— 表现层：board 的状态 -> 客户端控件。
--
-- ★★ 这里**不重新实现任何规则**：位置/颜色/显隐全部来自 sc（board.lua 算好的）。
--   ui 的职责只有三件：坐标换算、控件池复用、脏检查。
--
-- 坐标：board 用的是"画布像素、原点左上、y 向下"；控件 anchoredPosition 在父级下
--       是"相对父级中心、y 向上"。所以 y 要翻一次号：uiY = view.cy - y。
--       父级 = 一块铺满画布、居中在画布中心的容器控件。

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

-- 每颗球要写进去的东西（脏检查的键）
local BALL_KEYS = { 'anchoredPositionX', 'anchoredPositionY', 'sizeDeltaX', 'sizeDeltaY', 'visible' }

local function setField(ui, c, key, value)
  local cache = ui.last[c.id]
  if cache == nil then cache = {}; ui.last[c.id] = cache end
  if cache[key] == value then return false end
  cache[key] = value
  c[key] = value
  return true
end

local function setColor(ui, c, hex)
  local cache = ui.last[c.id]
  if cache == nil then cache = {}; ui.last[c.id] = cache end
  if cache.__color == hex then return false end
  cache.__color = hex
  c.imageColor = hexColor(hex)
  return true
end

local function setImage(ui, c, id)
  local cache = ui.last[c.id]
  if cache == nil then cache = {}; ui.last[c.id] = cache end
  if cache.__image == id then return false end
  cache.__image = id
  c:SetImage(Enum.ImageSource.StaticReference, id)
  return true
end

-- ==================== 建池 ====================

-- opts:
--   parent        挂到哪个控件下（一般是铺满画布的容器）
--   canvas        { w, h }
--   ballPrefab    球控件的控件模板索引
--   ballCount     球池大小
--   shotPrefab    弹药控件模板索引
--   shotCount     弹药池大小
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
    hud = {},
    stats = { writes = 0, ballWrites = 0, hudWrites = 0 },
  }

  local art = opts.art or {}
  if not next(art) then
    for i = 1, #CFG.BASES do art[CFG.BASES[i]] = i end
  end
  ui.art = art

  -- 球池
  local n = opts.ballCount or 96
  for i = 1, n do
    local c = game.InstantiateClientUIControl(opts.ballPrefab or 1, parent)
    -- ★ 动态创建失败时要**响亮地失败**：不然玩家看到的是空白画面，而错误在日志里
    if not c then
      error('球控件创建失败（第 ' .. i .. ' 个，模板索引 ' .. tostring(opts.ballPrefab or 1)
        .. '）。模板索引可能没填，或这个控件不能动态创建（主屏 / 模板控件的子节点都不行）')
    end
    c:SetActive(true)                       -- 文档：动态创建默认 active=false
    c:SetVisible(false)
    c.canControllerFocus = false
    ui.balls[i] = c
  end

  -- 弹药池
  local sn = opts.shotCount or 8
  for i = 1, sn do
    local c = game.InstantiateClientUIControl(opts.shotPrefab or (opts.ballPrefab or 1), parent)
    c:SetActive(true)
    c:SetVisible(false)
    c.canControllerFocus = false
    ui.shots[i] = c
  end

  -- HUD
  ui.hudOrder = {}
  for i = 1, #(opts.hud or {}) do
    local spec = opts.hud[i]
    local c = game.InstantiateClientUIControl(opts.hudPrefab or 2, parent)
    c:SetActive(true)
    c:SetVisible(true)
    c.canControllerFocus = false
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

  -- ---- 球 ----
  local beads = sc.beads.spawn
  local nb = #beads
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
      if setField(ui, c, 'visible', true) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      -- 配错 = 灰球；已配对但还没定型，用原色（吸附飞行途中）
      local hex = b.wrongMark and CFG.WRONG_COLOR or (CFG.BASE_COLOR[b.base] or '#ffffff')
      setColor(ui, c, hex)
      setImage(ui, c, ui.art[b.base] or 1)
    else
      setField(ui, c, 'visible', false)
    end
  end

  -- ---- 弹药 ----
  local shots = sc.projectiles
  for i = 1, #ui.shots do
    local c = ui.shots[i]
    local p = shots[i]
    if p then
      setField(ui, c, 'anchoredPositionX', p.x - cx)
      setField(ui, c, 'anchoredPositionY', cy - p.y)
      local d = 2 * p.r
      setField(ui, c, 'sizeDeltaX', d)
      setField(ui, c, 'sizeDeltaY', d)
      setField(ui, c, 'visible', true)
      setColor(ui, c, CFG.BASE_COLOR[p.base] or '#ffffff')
      setImage(ui, c, ui.art[p.base] or 1)
    else
      setField(ui, c, 'visible', false)
    end
  end

  -- ---- 核糖体 / 待发球 ----
  if ui.hud.rb then
    setField(ui, ui.hud.rb, 'anchoredPositionX', sc.rb.x - cx)
    setField(ui, ui.hud.rb, 'anchoredPositionY', cy - sc.rb.y)
    setField(ui, ui.hud.rb, 'visible', true)
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

-- 平台上限自检（《编辑项范围限制》：单控件组 1000 / 单屏 10000）
function M.budget(ui)
  local n = #ui.balls + #ui.shots + #ui.hudOrder
  for _ in pairs(ui.hud) do end
  return n, 1000, 10000
end

return M

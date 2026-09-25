-- host/mock.lua —— 千星奇域**客户端脚本 API 的无头假宿主**。
--
-- 存在的理由：表现层（ui.lua）与输入层（input.lua）不能"传上去看效果"才有反馈。
-- 这个假宿主照官方 API 文档（mhtakr07vej4_客户端控件API文档.md）实现同一套接口，
-- 于是**同一份 ui.lua / input.lua / game.lua 可以在这里无头跑起来并断言**。
--
-- ★★ 关键设计：假宿主把 game / Enum / script / Color 装成**全局**，
--   与真环境完全一致 —— 所以业务代码里写的就是 `game.GetCursorUIPos()`、
--   `Enum.CursorEventType.CursorClick`，不需要任何"为了测试而做的适配层"。
--
-- ⚠ 这是**本地工具**，不进 out/zuma.lua（打包器只打 lua/src/）。

local M = {}

-- ==================== Color ====================

local function makeColor(r, g, b, a)
  return { r = r, g = g, b = b, a = a == nil and 255 or a }
end

local Color = {}
function Color.new(r, g, b, a) return makeColor(r, g, b, a) end
function Color.FromRGB(r, g, b) return makeColor(r, g, b, 255) end
function Color.FromRGBA(r, g, b, a) return makeColor(r, g, b, a) end
function Color.ToRGBA(c) return c.r, c.g, c.b, c.a end
setmetatable(Color, { __call = function(_, r, g, b, a) return makeColor(r, g, b, a) end })

-- ==================== Enum ====================

local function enumOf(names)
  local t = {}
  for i = 1, #names do t[names[i]] = i - 1 end
  return t
end

local Enum = {
  EaseType = enumOf({ 'Linear', 'InSine', 'OutSine', 'InOutSine', 'InQuad', 'OutQuad', 'InOutQuad',
                      'OutBack', 'OutElastic', 'OutBounce' }),
  CustomVariableEntityType = { Level = 0, PlayerSelf = 1, AvatarSelf = 2 },
  Device = { KeyboardAndMouse = 0, Mobile = 1, Controller = 2, MobileController = 3 },
  StageMode = { Beyond = 0, Classic = 1 },
  LanguageType = { LanguageNone = 0, LanguageChs = 2, LanguageEng = 1 },
  ParamType = enumOf({ 'Entity', 'EntityList', 'Int', 'IntList', 'Bool', 'BoolList', 'Float',
                       'FloatList', 'String', 'StringList', 'Vector3', 'Vector3List', 'Guid',
                       'GuidList', 'ConfigId', 'PrefabId', 'ConfigIdList', 'PrefabIdList' }),
  CursorEventType = enumOf({ 'CursorDown', 'CursorUp', 'CursorEnter', 'CursorExit', 'CursorDrag',
                             'CursorBeginDrag', 'CursorEndDrag', 'CursorClick' }),
  KeyEventType = enumOf({ 'KeyDown', 'KeyUp', 'KeyHold' }),
  TextHorizontalAlignment = { Left = 0, Middle = 1, Right = 2 },
  TextVerticalAlignment = { Top = 0, Middle = 1, Bottom = 2 },
  ImageSource = enumOf({ 'StaticReference', 'Item', 'Equipment', 'Skill', 'UnitStatus',
                         'Faction', 'Currency', 'Prefab' }),
  ImageType = { Basic = 0, Stretch = 1 },
  ImageFillType = enumOf({ 'Unused', 'Horizontal', 'Vertical', 'Radial90', 'Radial180', 'Radial360' }),
  -- 下面两个照官方《客户端控件 API 文档》§22/§23 补（原先漏了，于是"边缘羽化/径向填充"在本地没法用）
  ImageFillRadialType = enumOf({ 'Bottom', 'Left', 'Top', 'Right' }),
  ImageMaskSoftEdgeMode = enumOf({ 'Percentage', 'Pixel' }),
  ControllerNavigationDir = { Up = 0, Down = 1, Left = 2, Right = 3 },
  ControllerNavigationEventType = enumOf({ 'Confirm', 'Cancel', 'Focus', 'LostFocus' }),
  ScrollDirection = { Horizontal = 0, Vertical = 1 },
  UIAnimationLayer = { AboveAllControls = 0, BelowAllControls = 1 },
  KeyboardKeyCode = {},   -- 下面按奇匠按键 1..43 填充
}
-- 奇匠按键 1..43（官方是"默认物理键"编号，这里只保证名字存在且各不相同）
for i = 1, 43 do Enum.KeyboardKeyCode['CraftspersonKey' .. i] = i end
Enum.KeyboardKeyCode.NormalAttackKey = 100      -- 鼠标左键
Enum.KeyboardKeyCode.SpaceJumpKey = 101
Enum.KeyboardKeyCode.TabKey = 102
Enum.KeyboardKeyCode.KeyR = 103
Enum.KeyboardKeyCode.CharacterSkill1Key = 104
Enum.KeyboardKeyCode.MoveForwardKey = 105
Enum.KeyboardKeyCode.MoveBackwardKey = 106
Enum.KeyboardKeyCode.MoveLeftKey = 107
Enum.KeyboardKeyCode.MoveRightKey = 108

M.Color = Color
M.Enum = Enum

-- ==================== 控件 ====================

-- ★★ 真机契约①：控件 userdata 是**按类型封死**的 —— 不在白名单里的字段，
--     读 -> nil，写 -> 报 `cannot set <字段>, no such field`（官方契约 §12）。
--   来源：模拟器客户端运行时 `client/lua-runtime/src/scene.js` 的
--     BASE_RO / BASE_RW / KIND_RO / KIND_RW（那几张表是照着官方《客户端控件 API 文档》的字段面做的）。
--
--   ★ 为什么本地要照抄这张表：真机上写错一个字段名**不会报错、也不生效**（或者当场崩），
--     而本假宿主原来"什么字段都收"。ui.lua 里的 `c.id`（真机是 `Id`）就是这么漏过 546 项本体的。
--     契约写在代码里，导出/测试时才拦得住。
local BASE_RO = { 'alive', 'Id', 'prefabIndex', 'active', 'activeInHierarchy', 'visible' }
local BASE_RW = {
  'name', 'parent',
  'anchoredPositionX', 'anchoredPositionY', 'sizeDeltaX', 'sizeDeltaY',
  'anchorMinX', 'anchorMinY', 'anchorMaxX', 'anchorMaxY', 'pivotX', 'pivotY',
  'localScaleX', 'localScaleY', 'localScaleZ',
  'localRotationX', 'localRotationY', 'localRotationZ', 'canControllerFocus',
}
local KIND_RO = {
  image = { 'imageSource', 'imageId' },
  grid = { 'itemCount', 'scrollDirection', 'layoutConstraint', 'layoutConstraintFixedCount' },
  reference = { 'referencedPrefabIndex' },
}
-- ⚠ 这里的 kind 名是本假宿主自己的（cursorarea / root），与 scene.js 的 cursor / container 对应
local KIND_RW = {
  root = { 'isolateNavigation', 'disableKeyEventPassthrough', 'disableCursorEventPassthrough', 'showCursor' },
  container = { 'isolateNavigation', 'disableKeyEventPassthrough', 'disableCursorEventPassthrough', 'showCursor' },
  textbox = { 'text', 'fontSize', 'fontColor', 'bgColor', 'enableOutline', 'outlineColor',
              'horizontalAlignment', 'verticalAlignment', 'adaptiveFontSize', 'minimumFontSize' },
  textwindow = { 'interactable', 'showScrollBar', 'text', 'fontSize', 'fontColor', 'bgColor',
                 'enableOutline', 'outlineColor', 'horizontalAlignment', 'verticalAlignment',
                 'adaptiveFontSize', 'minimumFontSize' },
  -- 文档写了 imageType 可写，但真机赋值报 "cannot set imageType"（官方契约 §14）—— 本地照样封死
  image = { 'imageColor', 'enableMask', 'enableSoftEdge', 'softEdgeMode', 'softEdgeWidthX',
            'softEdgeWidthY', 'horizontalSoftRange', 'verticalSoftRange', 'reverseMaskArea',
            'fillType', 'fillHorizontalType', 'fillVerticalType', 'fillRadial90Type',
            'fillRadialType', 'fillAmount' },
  button = { 'interactable', 'clickAudioId', 'raycastTarget' },
  cursorarea = { 'raycastTarget' },
  cursor = { 'raycastTarget' },
  grid = { 'itemPrefabIndex', 'raycastTarget', 'showScrollBar', 'interactable', 'scrollProgress' },
  keyhint = { 'keyboardKeyCode', 'controllerKeyCode' },
  animation = { 'animationId', 'playSoundEffect', 'layer' },
  fullscreen = { 'animationId', 'playSoundEffect' },
}

local function setOf(list, into)
  into = into or {}
  for i = 1, #list do into[list[i]] = true end
  return into
end
local BASE_RO_SET = setOf(BASE_RO)
local BASE_RW_SET = setOf(BASE_RW)
local KIND_SETS = {}
local function setsFor(kind)
  local s = KIND_SETS[kind]
  if not s then
    s = { ro = setOf(KIND_RO[kind] or {}), rw = setOf(KIND_RW[kind] or {}) }
    KIND_SETS[kind] = s
  end
  return s
end

local nextControlId = 0

local function newControl(kind, prefabIndex, name)
  nextControlId = nextControlId + 1
  local c = {
    __kind = kind,
    -- ★ 只读字段一律存在 `__` 内部名下面：Lua 的 __newindex 只在"键不存在"时触发，
    --   要是直接把 active/Id 存成同名字段，外面 `c.active = true` 会**绕过**只读检查。
    __alive = true,
    __Id = nextControlId,               -- ★ 真机字段名是 `Id`（首字母大写）；小写 id 真机读出来是 nil
    __prefabIndex = prefabIndex or 0,
    __active = (kind == 'root'),        -- 文档：默认 false，只有激活的才跑脚本逻辑
    __visible = true,                   -- 真机 visible 是**只读**字段：只能读，改要走 SetVisible()
    name = name or (kind .. '#' .. nextControlId),
    parent = nil,
    children = {},
    canControllerFocus = false,
    keyListeners = {},                  -- eventType -> {cb, ...}
    cursorListeners = {},
    navListeners = {},
  }
  c.anchoredPositionX, c.anchoredPositionY = 0, 0
  -- ★ 锚点/pivot 默认 0.5（= 相对父级中心）：真机运行时就是这个默认值
  --   （scene.js 的 Control：anchorMin/Max 0.5、pivot 0.5）。ui.lua 靠"绕中心旋转"画
  --   瞄准线和连线，pivot 不对的话真机上那两根会绕着角转 —— 这里照真机给对。
  c.anchorMinX, c.anchorMinY, c.anchorMaxX, c.anchorMaxY = 0.5, 0.5, 0.5, 0.5
  c.pivotX, c.pivotY = 0.5, 0.5
  c.localScaleX, c.localScaleY, c.localScaleZ = 1, 1, 1
  c.localRotationX, c.localRotationY, c.localRotationZ = 0, 0, 0
  c.sizeDeltaX, c.sizeDeltaY = 100, 100
  if kind == 'image' then
    c.imageSource = Enum.ImageSource.StaticReference
    c.imageId = 0
    c.imageColor = Color.FromRGBA(255, 255, 255, 255)
    c.enableMask, c.enableSoftEdge, c.reverseMaskArea = false, false, false
    c.fillType, c.fillAmount = Enum.ImageFillType.Unused, 1
  elseif kind == 'textbox' then
    c.text = ''
    c.fontSize = 24
    c.fontColor = Color.FromRGBA(255, 255, 255, 255)
    c.bgColor = Color.FromRGBA(0, 0, 0, 0)
    c.enableOutline, c.adaptiveFontSize = false, false
    c.outlineColor = Color.FromRGBA(0, 0, 0, 255)
    c.minimumFontSize = 12
    c.horizontalAlignment = Enum.TextHorizontalAlignment.Left
    c.verticalAlignment = Enum.TextVerticalAlignment.Top
  elseif kind == 'cursorarea' or kind == 'cursor' then
    c.raycastTarget = true
  end
  return c
end
M.newControl = newControl

-- ==================== 控件方法 ====================

local METHODS = {}

local function rootOf(c)
  while c.parent do c = c.parent end
  return c
end

function METHODS:GetChildren() return self.children end
function METHODS:GetChild(name)
  for i = 1, #self.children do if self.children[i].name == name then return self.children[i] end end
  return nil
end
function METHODS:FindChild(path)
  local cur = self
  for seg in tostring(path):gmatch('[^/]+') do
    cur = cur and cur:GetChild(seg) or nil
  end
  return cur
end
function METHODS:SetActive(active)
  rawset(self, '__active', active and true or false)    -- active 是只读字段，只能由宿主自己改
  return self
end
function METHODS:SetVisible(visible)
  rawset(self, '__visible', visible and true or false)  -- 同理：visible 只读，改走这个方法
  return self
end
function METHODS:GetSiblingIndex()
  if not self.parent then return 0 end
  for i = 1, #self.parent.children do if self.parent.children[i] == self then return i - 1 end end
  return 0
end
function METHODS:SetSiblingIndex(index)
  local p = self.parent
  if not p then return false end
  local cur = self:GetSiblingIndex()
  if index < 0 or index >= #p.children or index == cur then return index == cur end
  table.remove(p.children, cur + 1)
  table.insert(p.children, index + 1, self)
  return true
end
function METHODS:SetAsFirstSibling() return self:SetSiblingIndex(0) end
function METHODS:SetAsLastSibling() return self:SetSiblingIndex(#(self.parent and self.parent.children or {}) - 1) end

function METHODS:GetAnchoredPosition() return self.anchoredPositionX, self.anchoredPositionY end
function METHODS:SetAnchoredPosition(x, y)
  self.anchoredPositionX, self.anchoredPositionY = x, y
  return self
end
function METHODS:GetSizeDelta() return self.sizeDeltaX, self.sizeDeltaY end
function METHODS:SetSizeDelta(x, y) self.sizeDeltaX, self.sizeDeltaY = x, y; return self end
function METHODS:GetAnchorMin() return self.anchorMinX, self.anchorMinY end
function METHODS:SetAnchorMin(x, y) self.anchorMinX, self.anchorMinY = x, y; return self end
function METHODS:GetAnchorMax() return self.anchorMaxX, self.anchorMaxY end
function METHODS:SetAnchorMax(x, y) self.anchorMaxX, self.anchorMaxY = x, y; return self end
function METHODS:GetPivot() return self.pivotX, self.pivotY end
function METHODS:SetPivot(x, y) self.pivotX, self.pivotY = x, y; return self end
function METHODS:GetLocalScale() return self.localScaleX, self.localScaleY, self.localScaleZ end
function METHODS:SetLocalScale(x, y, z) self.localScaleX, self.localScaleY, self.localScaleZ = x, y, z or self.localScaleZ; return self end
function METHODS:GetLocalRotation() return self.localRotationX, self.localRotationY, self.localRotationZ end
function METHODS:SetLocalRotation(x, y, z) self.localRotationX, self.localRotationY, self.localRotationZ = x, y, z; return self end

function METHODS:GetScripts() return self.scripts or {} end
function METHODS:GetScript() return nil end
function METHODS:GetScriptByPath() return nil end

function METHODS:AddKeyEventListener(eventType, cb)
  self.keyListeners[eventType] = self.keyListeners[eventType] or {}
  table.insert(self.keyListeners[eventType], cb)
  return self
end
function METHODS:RemoveKeyEventListener(eventType, cb)
  local l = self.keyListeners[eventType]
  if not l then return self end
  for i = #l, 1, -1 do if l[i] == cb then table.remove(l, i) end end
  return self
end
function METHODS:RemoveKeyEventListeners(eventType) self.keyListeners[eventType] = nil; return self end
function METHODS:RemoveAllKeyEventListeners() self.keyListeners = {}; return self end
function METHODS:AddNavigationEventListener(eventType, cb)
  self.navListeners[eventType] = self.navListeners[eventType] or {}
  table.insert(self.navListeners[eventType], cb)
  return self
end
function METHODS:RemoveNavigationEventListener(eventType, cb)
  local l = self.navListeners[eventType]
  if not l then return self end
  for i = #l, 1, -1 do if l[i] == cb then table.remove(l, i) end end
  return self
end
function METHODS:RemoveNavigationEventListeners(eventType) self.navListeners[eventType] = nil; return self end

-- 图片
function METHODS:SetImage(imageSource, imageId)
  rawset(self, 'imageSource', imageSource)   -- imageSource/imageId 是只读字段
  rawset(self, 'imageId', imageId)
  return self
end
function METHODS:SetSoftEdgeWidth(wx, wy) self.softEdgeWidthX, self.softEdgeWidthY = wx, wy; return self end
function METHODS:SetFillUnused() self.fillType, self.fillAmount = Enum.ImageFillType.Unused, 0; return self end
function METHODS:SetFillHorizontal(t, amt) self.fillType, self.fillHorizontalType, self.fillAmount = Enum.ImageFillType.Horizontal, t, amt; return self end
function METHODS:SetFillVertical(t, amt) self.fillType, self.fillVerticalType, self.fillAmount = Enum.ImageFillType.Vertical, t, amt; return self end
function METHODS:SetFillRadial90(t, amt) self.fillType, self.fillRadial90Type, self.fillAmount = Enum.ImageFillType.Radial90, t, amt; return self end
function METHODS:SetFillRadial180(t, amt) self.fillType, self.fillRadialType, self.fillAmount = Enum.ImageFillType.Radial180, t, amt; return self end
function METHODS:SetFillRadial360(t, amt) self.fillType, self.fillRadialType, self.fillAmount = Enum.ImageFillType.Radial360, t, amt; return self end

-- 光标检测区域
function METHODS:AddCursorEventListener(eventType, cb)
  self.cursorListeners[eventType] = self.cursorListeners[eventType] or {}
  table.insert(self.cursorListeners[eventType], cb)
  return self
end
function METHODS:RemoveCursorEventListener(eventType, cb)
  local l = self.cursorListeners[eventType]
  if not l then return self end
  for i = #l, 1, -1 do if l[i] == cb then table.remove(l, i) end end
  return self
end
function METHODS:RemoveCursorEventListeners(eventType) self.cursorListeners[eventType] = nil; return self end
function METHODS:RemoveAllCursorEventListeners() self.cursorListeners = {}; return self end
function METHODS:SimulateCursorClick()
  local host = self.__host
  if host then host:dispatchCursor(self, 'CursorDown'); host:dispatchCursor(self, 'CursorUp'); host:dispatchCursor(self, 'CursorClick') end
  return self
end

local CONTROL_MT = {}

-- 只读字段 -> 内部存储名（存在内部名下，写同名字段才会撞上 __newindex）
local RO_STORE = {
  alive = '__alive', Id = '__Id', prefabIndex = '__prefabIndex',
  active = '__active', visible = '__visible',
}

CONTROL_MT.__index = function(t, k)
  if k == 'activeInHierarchy' then
    local c = t
    while c do
      if not c.active then return false end
      c = c.parent
    end
    return true
  end
  local store = RO_STORE[k]
  if store then return rawget(t, store) end
  if BASE_RW_SET[k] then return rawget(t, k) end
  local s = setsFor(t.__kind)
  if s.ro[k] or s.rw[k] then return rawget(t, k) end
  local m = METHODS[k]
  if m then return m end
  return nil            -- ★ 真机：不在白名单里的字段**读为 nil**（不是报错）
end

CONTROL_MT.__newindex = function(t, k, v)
  if type(k) == 'string' and k:sub(1, 2) == '__' then return rawset(t, k, v) end   -- 假宿主内部字段
  if BASE_RO_SET[k] then
    error('cannot set ' .. tostring(k) .. ', no such field', 2)                    -- ★ 真机原话
  end
  local s = setsFor(t.__kind)
  if s.ro[k] then error('cannot set ' .. tostring(k) .. ', no such field', 2) end
  if BASE_RW_SET[k] or s.rw[k] then return rawset(t, k, v) end
  error('cannot set ' .. tostring(k) .. ', no such field', 2)
end

local function attachControl(host, kind, prefabIndex, name)
  local c = newControl(kind, prefabIndex, name)
  c.__host = host
  return setmetatable(c, CONTROL_MT)
end
M.attachControl = attachControl

-- ==================== Tween ====================

local TweenMT = {}
TweenMT.__index = TweenMT
function TweenMT:SetEase(e) self.ease = e; return self end
function TweenMT:SetRelative(b) self.relative = b and true or false; return self end
function TweenMT:Play() self.playing, self.done = true, false; return self end
function TweenMT:Pause() self.paused = true; return self end
function TweenMT:Resume() self.paused = false; return self end
function TweenMT:Restart() self.t, self.done, self.paused = 0, false, false; self:snap(0); return self end
function TweenMT:Complete() self.t = self.duration; self:snap(1); self.done = true; self.playing = false; return self end
function TweenMT:Kill(complete_) if complete_ then self:Complete() end; self.killed = true; self.playing = false; return self end
function TweenMT:SetLoops(n) self.loops = n; return self end
function TweenMT:SetOnComplete(f) self.onComplete = f; return self end
function TweenMT:SetOnStepComplete(f) self.onStep = f; return self end

-- 线性插值（不实现 30 种缓动：本地验证只关心"值到没到位"）
local function eased(self, u)
  if self.ease == Enum.EaseType.Linear then return u end
  return u * u * (3 - 2 * u)     -- smoothstep：单调、端点精确
end
function TweenMT:snap(u)
  local e = eased(self, u)
  for k, target in pairs(self.data) do
    local from = self.from[k]
    local to = self.relative and (from + target) or target
    self.object[k] = from + (to - from) * e
  end
end
function TweenMT:step(dt)
  if self.killed or self.done or not self.playing or self.paused then return end
  self.t = self.t + dt
  local u = self.duration > 0 and math.min(1, self.t / self.duration) or 1
  self:snap(u)
  if self.onStep then self.onStep() end
  if u >= 1 then
    self.done = true
    self.playing = false
    if self.onComplete then self.onComplete() end
  end
end

local SeqMT = {}
SeqMT.__index = SeqMT
function SeqMT:Append(tw) self.steps[#self.steps + 1] = { kind = 'tween', tween = tw }; return self end
function SeqMT:AppendInterval(sec) self.steps[#self.steps + 1] = { kind = 'wait', sec = sec }; return self end
function SeqMT:AppendCallback(fn) self.steps[#self.steps + 1] = { kind = 'cb', fn = fn }; return self end
function SeqMT:Join(tw) self.steps[#self.steps + 1] = { kind = 'tween', tween = tw }; return self end
function SeqMT:Insert(t, tw) self.steps[#self.steps + 1] = { kind = 'tween', tween = tw, at = t }; return self end
function SeqMT:InsertCallback(t, fn) self.steps[#self.steps + 1] = { kind = 'cb', fn = fn, at = t }; return self end
function SeqMT:Play() self.playing, self.i, self.wait = true, 1, 0; return self end
function SeqMT:Pause() self.playing = false; return self end
function SeqMT:Resume() self.playing = true; return self end
function SeqMT:Restart() self.i, self.wait, self.playing = 1, 0, true; return self end
function SeqMT:Kill() self.killed, self.playing = true, false; return self end
function SeqMT:Complete() while self.playing do self:step(1e9) end; return self end
function SeqMT:SetOnComplete(f) self.onComplete = f; return self end
function SeqMT:SetOnStepComplete(f) self.onStep = f; return self end
function SeqMT:SetLoops(n) self.loops = n; return self end
function SeqMT:step(dt)
  if self.killed or not self.playing then return end
  local budget = dt
  while budget > 0 and self.playing do
    local s = self.steps[self.i]
    if not s then
      self.playing = false
      if self.onComplete then self.onComplete() end
      return
    end
    if s.kind == 'cb' then
      self.i = self.i + 1
      if s.fn then s.fn() end
    elseif s.kind == 'wait' then
      local use = math.min(budget, (s.sec or 0) - self.wait)
      self.wait = self.wait + use
      budget = budget - use
      if self.wait >= (s.sec or 0) - 1e-12 then self.i = self.i + 1; self.wait = 0 end
    else
      s.tween.playing = true
      s.tween:step(budget)
      if s.tween.done then
        self.i = self.i + 1
      else
        budget = 0
      end
    end
  end
end

-- ==================== 宿主 ====================

local CURSOR_ORDER = { 'CursorDown', 'CursorUp', 'CursorEnter', 'CursorExit',
                       'CursorDrag', 'CursorBeginDrag', 'CursorEndDrag', 'CursorClick' }

function M.newHost(opts)
  opts = opts or {}
  local host = {
    canvas = { w = opts.w or 900, h = opts.h or 900 },
    cursor = { x = 0, y = 0, pressX = 0, pressY = 0, down = false, touchId = 1, lastX = 0, lastY = 0 },
    controls = {},
    roots = {},
    tweens = {},
    seqs = {},
    params = opts.params or {},
    prefabs = opts.prefabs or {},
    globals = opts.globals or {},
    texts = opts.texts or {},
    signals = {},
    serverHandlers = {},
    logs = {},
    audio = {},
    time = 0,
    paused = false,
    -- ★★ 真机契约②：「EnableUpdate 前无 OnUpdate」。所以默认是**关**的，
    --    脚本必须在 OnInit 里调 script:EnableUpdate(true) 才会收到每帧回调。
    updateEnabled = false,
    -- ★★ 真机契约③：生命周期阶段决定 Instantiate 能不能成功。
    --    OnInit / OnDestroy 阶段 -> 返回 nil（真机探针）；OnStart 及之后 -> 控件。
    --    默认 'running'：直接调 API 的测试（不走 mount）当宿主已经起来了。
    phase = 'running',
    mounted = nil,
    stats = { instantiated = 0, destroyed = 0, cursorEvents = 0, keyEvents = 0, tweens = 0, seqs = 0 },
  }

  -- 阶段切换（给不走 mount 的测试用；mount 会自动走一遍）
  function host.beginInit() host.phase = 'init' end
  function host.enterStart() host.phase = 'start' end
  function host.enterRunning() host.phase = 'running' end

  -- ---------- 控件树 ----------
  function host.newControl(kind, prefabIndex, name, parent)
    local c = attachControl(host, kind, prefabIndex, name)
    host.controls[c.Id] = c
    parent = parent or host.root
    if parent then
      c.parent = parent
      parent.children[#parent.children + 1] = c
    end
    return c
  end

  -- 文档：无父层级时以画布左下为原点；有父层级时是相对父级中心的偏移
  local function absPos(c)
    if not c.parent then return c.anchoredPositionX, c.anchoredPositionY end
    local px, py = absPos(c.parent)
    return px + c.anchoredPositionX, py + c.anchoredPositionY
  end
  function host.absPos(c) return absPos(c) end

  function host.containsPoint(c, x, y)
    local ax, ay = absPos(c)
    local hw, hh = c.sizeDeltaX / 2, c.sizeDeltaY / 2
    return x >= ax - hw and x <= ax + hw and y >= ay - hh and y <= ay + hh
  end

  function host.visibleChain(c)
    while c do
      if not (c.active and c.visible) then return false end
      c = c.parent
    end
    return true
  end

  -- ---------- 光标事件 ----------
  local function makeEventData(host_)
    return {
      dragging = host_.cursor.down,
      touchId = host_.cursor.touchId,
      GetUIPos = function() return host_.cursor.x, host_.cursor.y end,
      GetPressUIPos = function() return host_.cursor.pressX, host_.cursor.pressY end,
      GetUIPosDelta = function() return host_.cursor.x - host_.cursor.lastX, host_.cursor.y - host_.cursor.lastY end,
    }
  end

  function host.dispatchCursor(c, eventName)
    local listeners = c.cursorListeners[Enum.CursorEventType[eventName]]
    if not listeners then return 0 end
    local data = makeEventData(host)
    local n = 0
    for i = 1, #listeners do
      host.stats.cursorEvents = host.stats.cursorEvents + 1
      listeners[i](data)
      n = n + 1
    end
    return n
  end

  local function topCursorArea(host_, x, y)
    local best = nil
    for i = 1, #host_.roots do
      local stack = { host_.roots[i] }
      while #stack > 0 do
        local c = table.remove(stack)
        if c.__kind == 'cursorarea' and c.raycastTarget and host_.visibleChain(c)
           and host_.containsPoint(c, x, y) then
          best = c
        end
        for k = 1, #c.children do stack[#stack + 1] = c.children[k] end
      end
    end
    return best
  end
  host.topCursorArea = topCursorArea

  function host.setCursor(x, y)
    host.cursor.lastX, host.cursor.lastY = host.cursor.x, host.cursor.y
    host.cursor.x, host.cursor.y = x, y
    local top = topCursorArea(host, x, y)
    if top ~= host.__hover then
      if host.__hover then host.dispatchCursor(host.__hover, 'CursorExit') end
      host.__hover = top
      if top then host.dispatchCursor(top, 'CursorEnter') end
    elseif top and host.cursor.down then
      host.dispatchCursor(top, 'CursorDrag')
    end
    return top
  end

  function host.click(x, y)
    if x then host.setCursor(x, y) end
    local top = topCursorArea(host, host.cursor.x, host.cursor.y)
    if not top then return nil end
    host.cursor.pressX, host.cursor.pressY = host.cursor.x, host.cursor.y
    host.cursor.down = true
    host.dispatchCursor(top, 'CursorDown')
    host.cursor.down = false
    host.dispatchCursor(top, 'CursorUp')
    host.dispatchCursor(top, 'CursorClick')
    return top
  end

  -- ---------- 键盘 ----------
  function host.keyEvent(code, down)
    host.stats.keyEvents = host.stats.keyEvents + 1
    local et = down and Enum.KeyEventType.KeyDown or Enum.KeyEventType.KeyUp
    for _, c in pairs(host.controls) do
      local l = c.keyListeners[et]
      if l and c.activeInHierarchy then
        for i = 1, #l do
          if l[i](code) == true then return true end     -- 返回 true = 已处理，停止传播
        end
      end
    end
    return false
  end

  -- ---------- 脚本生命周期 ----------
  -- ★★ 照真机的顺序走：OnInit -> OnEnable -> OnStart（退出 OnDisable -> OnDestroy），
  --   并且**阶段可见**：
  --     OnInit  阶段 Instantiate 返回 nil（真机探针）
  --     OnStart 阶段才行
  --   所以 mount 出来的宿主和真机行为一致，测试才拦得住"在 OnInit 里建控件"这种错。
  function host.mount(tbl)
    host.mounted = tbl
    host.scriptObj.object = host.scriptObj.object or host.root
    host.phase = 'init'
    if tbl.OnInit then tbl.OnInit() end
    host.phase = 'enable'
    if tbl.OnEnable then tbl.OnEnable() end
    host.phase = 'start'
    if tbl.OnStart then tbl.OnStart() end
    host.phase = 'running'
    return tbl
  end
  function host.unmount()
    host.phase = 'destroy'
    if host.mounted and host.mounted.OnDisable then host.mounted.OnDisable() end
    if host.mounted and host.mounted.OnDestroy then host.mounted.OnDestroy() end
    host.mounted = nil
    host.phase = 'idle'
  end

  function host.tick(dt)
    host.time = host.time + dt
    for i = #host.tweens, 1, -1 do
      host.tweens[i]:step(dt)
      if host.tweens[i].killed then table.remove(host.tweens, i) end
    end
    for i = #host.seqs, 1, -1 do
      host.seqs[i]:step(dt)
      if host.seqs[i].killed then table.remove(host.seqs, i) end
    end
    if host.mounted and host.updateEnabled and not host.paused then
      if host.mounted.OnUpdate then host.mounted.OnUpdate(dt) end
    end
    if host.mounted and host.mounted.OnLevelUpdate and not host.paused then
      host.mounted.OnLevelUpdate(dt)
    end
  end

  -- 服务端 -> 客户端信号
  function host.fireServerSignal(name, params)
    local h = host.serverHandlers[name]
    if h then h(name, params or {}) end
  end

  -- ---------- 假 game 表 ----------
  local game = {}

  function game.GetUICanvasSize() return host.canvas.w, host.canvas.h end
  function game.GetCursorUIPos() return host.cursor.x, host.cursor.y end
  function game.GetDevice() return Enum.Device.KeyboardAndMouse end
  function game.SetControllerFocus(c) host.focus = c end
  function game.GetControllerFocus() return host.focus end
  function game.GetControllerLeftStickAxis() return host.stickLX or 0, host.stickLY or 0 end
  function game.GetControllerRightStickAxis() return host.stickRX or 0, host.stickRY or 0 end

  function game.InstantiateClientUIControl(prefabIndex, parent)
    -- ★ 真机契约：OnInit / OnDestroy 阶段返回 nil（探针：OnInit/OnDestroy -> nil；OnStart -> 控件）
    if host.phase == 'init' or host.phase == 'destroy' then return nil end
    -- 测试用：把某个模板索引标成"创建必定失败"，用来验证错误能不能显示到屏幕上
    if host.failPrefabs and host.failPrefabs[prefabIndex] then return nil end
    local kind = host.prefabs[prefabIndex] or 'image'
    local c = host.newControl(kind, prefabIndex, nil, parent)
    host.stats.instantiated = host.stats.instantiated + 1
    return c
  end
  function game.DestroyClientUIControl(c)
    if not c then return end
    rawset(c, '__alive', false)            -- alive 是只读字段
    host.controls[c.Id] = nil
    host.stats.destroyed = host.stats.destroyed + 1
    if c.parent then
      for i = #c.parent.children, 1, -1 do
        if c.parent.children[i] == c then table.remove(c.parent.children, i) end
      end
    end
  end
  function game.GetClientUIControl(id) return host.controls[id] end
  function game.FindClientUIRoot(name)
    for i = 1, #host.roots do if host.roots[i].name == name then return host.roots[i] end end
    return nil
  end
  function game.GetClientUIRoots() return host.roots end

  function game.Tween(object, data, duration)
    local from = {}
    for k in pairs(data) do from[k] = object[k] or 0 end
    local tw = setmetatable({
      object = object, data = data, from = from, duration = duration,
      t = 0, playing = false, paused = false, done = false, killed = false,
      ease = Enum.EaseType.Linear, relative = false,
    }, TweenMT)
    host.tweens[#host.tweens + 1] = tw
    host.stats.tweens = host.stats.tweens + 1
    return tw
  end
  function game.TweenSequence()
    local sq = setmetatable({ steps = {}, i = 1, wait = 0, playing = false, killed = false }, SeqMT)
    host.seqs[#host.seqs + 1] = sq
    host.stats.seqs = host.stats.seqs + 1
    return sq
  end

  function game.ServerSignal(name)
    local sig = { name = name, params = {} }
    local function add(t, v) sig.params[#sig.params + 1] = { type = t, value = v } end
    function sig:AddParam(t, v) add(t, v) end
    function sig:AddInt(v) add(Enum.ParamType.Int, v) end
    function sig:AddIntList(v) add(Enum.ParamType.IntList, v) end
    function sig:AddFloat(v) add(Enum.ParamType.Float, v) end
    function sig:AddFloatList(v) add(Enum.ParamType.FloatList, v) end
    function sig:AddString(v) add(Enum.ParamType.String, v) end
    function sig:AddStringList(v) add(Enum.ParamType.StringList, v) end
    function sig:AddBool(v) add(Enum.ParamType.Bool, v) end
    function sig:AddVector3(v) add(Enum.ParamType.Vector3, v) end
    function sig:AddEntity(v) add(Enum.ParamType.Entity, v) end
    function sig:AddEntityList(v) add(Enum.ParamType.EntityList, v) end
    function sig:AddGuid(v) add(Enum.ParamType.Guid, v) end
    function sig:AddPrefabId(v) add(Enum.ParamType.PrefabId, v) end
    function sig:AddConfigId(v) add(Enum.ParamType.ConfigId, v) end
    function sig:SendSignal()
      host.signals[#host.signals + 1] = { name = sig.name, params = sig.params }
      return true
    end
    return sig
  end

  function game.GetGlobalCustomVariableValue(entityType, name)
    local v = host.globals[entityType .. ':' .. name]
    if v == nil then v = host.globals[name] end
    return v
  end
  function game.PauseLevelTime(p) host.paused = p and true or false end
  function game.IsLevelTimePaused() return host.paused end
  function game.PlayAudio2D(id) host.audio[#host.audio + 1] = id; return #host.audio end
  function game.StopAudio() end
  function game.IsAudioAlive() return false end
  function game.GetLanguageType() return Enum.LanguageType.LanguageChs end
  function game.GetStageMode() return Enum.StageMode.Classic end
  function game.IsTestPlay() return true end
  function game.GetText(id) return host.texts[id] or id end
  function game.PrintClientUITree()
    local function walk(c, d)
      host.logs[#host.logs + 1] = string.rep('  ', d) .. c.name
      for i = 1, #c.children do walk(c.children[i], d + 1) end
    end
    for i = 1, #host.roots do walk(host.roots[i], 0) end
    return #host.logs
  end

  -- ★★ 真机契约④：game 的函数是**点号调用**的（`game.GetUICanvasSize()`）。
  --   写成冒号（`game:GetUICanvasSize()`）会把 game 自己当成第一个实参塞进去，
  --   真机报 `bad argument count ... (0 expected, got 1)`（2026-09-25 真机回传）。
  --   这里照做：冒号调用当场报错，别让它在本地"看着没事"。
  do
    local names = {}
    for k, v in pairs(game) do if type(v) == 'function' then names[#names + 1] = k end end
    for i = 1, #names do
      local k, f = names[i], game[names[i]]
      game[k] = function(...)
        local a = { ... }
        if a[1] == game then
          error('bad argument count to ' .. k .. ' (点号调用，别用冒号：game.' .. k .. '(...))', 2)
        end
        return f(...)
      end
    end
  end

  host.game = game

  -- ---------- 假 script 对象 ----------
  local scriptObj = {
    alive = true,
    scriptMappingId = opts.scriptMappingId or 1,
    object = nil,
    path = opts.scriptPath or 'zuma.lua',
    enabled = true,
    __serverHandlers = {},
    __varHandlers = {},
  }
  function scriptObj:GetParam(paramName) return host.params[paramName] end
  function scriptObj:EnableUpdate(enabled)
    host.updateEnabled = enabled and true or false
    self.enabled = host.updateEnabled
  end
  function scriptObj:Invoke(fnName, ...)
    local f = host.mounted and host.mounted[fnName]
    if type(f) == 'function' then return f(...) end
    return nil
  end
  function scriptObj:RegisterServerSignalHandler(signalName, callback)
    host.serverHandlers[signalName] = callback
    self.__serverHandlers[signalName] = callback
  end
  function scriptObj:UnregisterServerSignalHandler(signalName)
    host.serverHandlers[signalName] = nil
    self.__serverHandlers[signalName] = nil
  end
  function scriptObj:RegisterCustomVariableChangedHandler(entityType, name, callback)
    self.__varHandlers[entityType .. ':' .. name] = callback
  end
  function scriptObj:UnregisterCustomVariableChangedHandler(entityType, name)
    self.__varHandlers[entityType .. ':' .. name] = nil
  end
  host.scriptObj = scriptObj

  -- ---------- 根节点 ----------
  function host.createRoot(name, w, h)
    local r = host.newControl('root', 0, name or 'Canvas', nil)
    r.anchoredPositionX, r.anchoredPositionY = (w or host.canvas.w) / 2, (h or host.canvas.h) / 2
    r.sizeDeltaX, r.sizeDeltaY = w or host.canvas.w, h or host.canvas.h
    rawset(r, '__active', true)
    host.roots[#host.roots + 1] = r
    host.root = host.root or r
    return r
  end
  host.createRoot('Canvas')

  -- ---------- 平台限制自检 ----------
  function host.countControls()
    local n = 0
    for _ in pairs(host.controls) do n = n + 1 end
    return n
  end
  function host.assertControlBudget()
    local n = host.countControls()
    local PER_GROUP, PER_SCREEN = 1000, 10000      -- 《编辑项范围限制》
    return n <= PER_GROUP, n, PER_GROUP, PER_SCREEN
  end

  return host
end

-- 把假宿主装成**全局**，与真环境一致
function M.install(host)
  _G.game = host.game
  _G.Enum = Enum
  _G.Color = Color
  _G.script = host.scriptObj
  return host
end

return M

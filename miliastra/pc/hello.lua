-- hello.lua —— 最小验证脚本：确认「脚本映射 -> 挂到控件 -> 试玩」这条管线是通的。
--
-- 只依赖官方 API，**不依赖 zuma.lua 的任何东西**。所以它能把问题一刀切开：
--   · hello 能跑  -> 管线没问题，那是 zuma.lua 的事
--   · hello 也不跑 -> 是"文件没进去 / 映射没建 / 没挂到控件"这类管线问题
--
-- 期望现象：试玩后屏幕上 8 颗彩色小球绕中心转圈，上方一行状态字。
-- 出错时那行字会变成 "!! 具体原因"。
--
-- 用到的脚本变量（不填就用默认值）：
--   ballPrefab  球控件模板索引 [1]
--   hudPrefab   文本框模板索引 [2]

local t = 0
local balls = {}
local info = nil
local err = nil
local W, H = 900, 900

local function param(name, d)
  local v = script and script:GetParam(name)
  if v == nil then return d end
  return v
end

local function build()
  local w, h = game.GetUICanvasSize()
  local root = script.object
  if not root then
    local rs = game.GetClientUIRoots()
    root = rs and rs[1]
  end
  if not root then error('找不到挂载控件：脚本要挂在**客户端控件**上（不能挂主屏）') end
  root:SetActive(true)

  local ballPrefab = param('ballPrefab', 1)
  local hudPrefab = param('hudPrefab', 2)

  info = game.InstantiateClientUIControl(hudPrefab, root)
  if info then
    info:SetActive(true)
    info:SetAnchoredPosition(0, h / 2 - 40)
    info:SetSizeDelta(math.min(w - 40, 700), 40)
    info.fontSize = 22
    info.text = 'hello: 正在创建球…'
  end

  for i = 1, 8 do
    local c = game.InstantiateClientUIControl(ballPrefab, root)
    if not c then
      error('球控件创建失败（ballPrefab = ' .. tostring(ballPrefab)
        .. '）：模板索引可能没填，或这个控件不能动态创建（主屏 / 模板控件的子节点都不行）')
    end
    c:SetActive(true)
    c:SetSizeDelta(60, 60)
    c.imageColor = Color.FromRGBA(80 + i * 20, 220 - i * 15, 255, 255)
    balls[i] = c
  end
  return w, h
end

function OnInit()
  local ok, e = pcall(function() W, H = build() end)
  if not ok then err = tostring(e) end
end

function OnUpdate(dt)
  t = t + dt
  if err then
    if info then info.text = '!! ' .. err end
    return
  end
  local n = #balls
  for i = 1, n do
    local a = t * 0.8 + (i - 1) / n * math.pi * 2
    balls[i]:SetAnchoredPosition(math.cos(a) * 160, math.sin(a) * 160)
    balls[i]:SetLocalRotation(0, 0, math.deg(a))
  end
  if info then
    info.text = string.format('hello 跑起来了 · 已运行 %.1f 秒 · 球 %d 个 · 画布 %dx%d', t, n, W, H)
  end
end

function OnStart() end
function OnLevelUpdate(dt) end
function OnDestroy() end

return { OnInit = OnInit, OnUpdate = OnUpdate, OnStart = OnStart, OnDestroy = OnDestroy }

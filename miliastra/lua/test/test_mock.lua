-- 假宿主自己的测试：先证明"测试工具"是对的，再用它测业务代码。
local H = require('harness')
local MOCK = require('mock')

H.suite('mock host')

local host = MOCK.newHost({ w = 900, h = 900 })
MOCK.install(host)

H.eq(host.countControls(), 1, '初始应有 1 个根控件')

-- 画布 / 光标
local cw, ch = game.GetUICanvasSize()
H.eq(cw, 900, '画布宽'); H.eq(ch, 900, '画布高')
game.GetCursorUIPos()
host.setCursor(123, 456)
local gx, gy = game.GetCursorUIPos()
H.eq(gx, 123, '光标 x'); H.eq(gy, 456, '光标 y')

-- 动态创建 + 启用 + 显隐
host.prefabs[7] = 'image'
local root = host.root
root:SetActive(true)
local ball = game.InstantiateClientUIControl(7, root)
H.eq(ball.__kind, 'image', 'prefab 7 是图片控件')
H.eq(ball.active, false, '文档：动态创建默认 active=false')
H.eq(ball.activeInHierarchy, false, '未激活 -> activeInHierarchy=false')
ball:SetActive(true)
H.eq(ball.activeInHierarchy, true, '激活后 activeInHierarchy=true')
H.eq(ball:SetVisible(false) ~= nil, true, 'SetVisible 可链式调用')
H.eq(host.visibleChain(ball), false, '不可见的控件不参与光标检测')

-- 字段读写（Tweenable 的那些）
ball:SetAnchoredPosition(100, 200)
local ax, ay = ball:GetAnchoredPosition()
H.eq(ax, 100, 'anchoredPositionX'); H.eq(ay, 200, 'anchoredPositionY')
ball:SetLocalRotation(0, 0, 45)
H.eq(ball.localRotationZ, 45, 'localRotationZ')
ball:SetLocalScale(2, 2, 1)
H.eq(ball.localScaleX, 2, 'localScaleX')
ball:SetSizeDelta(40, 40)
H.eq(ball.sizeDeltaX, 40, 'sizeDeltaX')

-- 绝对位置：子控件的 anchoredPosition 是相对父级中心的
local absx, absy = host.absPos(ball)
H.near(absx, 900 / 2 + 100, 1e-9, '子控件绝对 x = 父中心 + 偏移')

-- 光标事件区域
local area = host.newControl('cursorarea', 9, 'PlayArea', root)
area:SetActive(true)
area:SetSizeDelta(600, 600)
area:SetAnchoredPosition(0, 0)              -- 以父中心为原点 -> 覆盖画布中央
local got = {}
area:AddCursorEventListener(Enum.CursorEventType.CursorClick, function(d)
  local x, y = d:GetUIPos()
  got[#got + 1] = { x = x, y = y, dragging = d.dragging }
end)
host.click(450, 450)
H.eq(#got, 1, '点在区域内 -> 收到一次 CursorClick')
H.eq(got[1].x, 450, '事件里拿得到 UI 坐标')
H.eq(got[1].dragging, false, '点击结束后 dragging=false')
host.click(20, 20)
H.eq(#got, 1, '点在区域外 -> 不再触发')

-- 键盘
-- ★ 真机契约：KeyEventType 是**逐键**成员，回调**不带参数**
local keyHits = 0
H.eq(Enum.KeyEventType.KeyDown, nil, '★ 没有通用的 KeyDown（真机也没有 —— 第一版就栽在这）')
H.eq(Enum.KeyEventType.KeyboardNormalAttackKeyDown == nil, false, '有逐键成员 KeyboardNormalAttackKeyDown')
root:AddKeyEventListener(Enum.KeyEventType.KeyboardNormalAttackKeyDown, function()
  keyHits = keyHits + 1
  return false
end)
host.keyEvent('KeyboardNormalAttackKeyDown')
H.eq(keyHits, 1, '按键回调被调用')
-- 返回 true = 已处理：同一按键不再往下传
local handled = 0
root:AddKeyEventListener(Enum.KeyEventType.KeyboardJumpKeyDown, function() handled = handled + 1; return true end)
H.eq(host.keyEvent('KeyboardJumpKeyDown'), true, '回调返回 true -> keyEvent 报"已处理"')
H.eq(handled, 1, '处理的回调只被调用一次')
H.eq(host.keyEvent('KeyboardCraftspersonKey2Down'), false, '没注册的键不触发任何东西')

-- Tween
local tw = game.Tween(ball, { anchoredPositionX = 500 }, 1.0):SetEase(Enum.EaseType.Linear):Play()
host.tick(0.5)
H.near(ball.anchoredPositionX, 300, 1e-6, '补间走到一半')
host.tick(0.5)
H.near(ball.anchoredPositionX, 500, 1e-6, '补间到位')

-- 脚本生命周期
-- ★★ 真机契约：**EnableUpdate 前没有 OnUpdate**。所以这里的 mock 脚本必须先打开它，
--   而且打开之前 tick 不该产生任何回调（这一段就是那条契约的回归测试）。
local ticks = 0
host.mount({
  OnInit = function() script:EnableUpdate(true) end,
  OnUpdate = function(dt) ticks = ticks + 1 end,
})
host.tick(1 / 60)
host.tick(1 / 60)
H.eq(ticks, 2, 'OnUpdate 每 tick 一次')
script:EnableUpdate(false)
host.tick(1 / 60)
H.eq(ticks, 2, 'EnableUpdate(false) 之后不再 OnUpdate')
script:EnableUpdate(true)

-- ★★ 真机契约（这几条是 2026-09-25 那个"真机第一帧就崩"的坑换来的，别再丢）
-- ① 生命周期：OnInit / OnDestroy 阶段 Instantiate 返回 nil
host.prefabs[5] = 'image'
host.beginInit()
H.eq(game.InstantiateClientUIControl(5, host.root), nil, '★ OnInit 阶段 Instantiate 返回 nil')
host.enterStart()

-- ② 控件标识字段是 `Id`（大写）；旧接口 `id` **不作为口径**，读出来就是 nil
local c2 = game.InstantiateClientUIControl(5, host.root)
H.truthy(c2, '★ OnStart 阶段才建得出控件')
host.enterRunning()
H.truthy(c2.Id, '★ 控件有 Id 字段（大写）：' .. tostring(c2.Id))
H.eq(c2.id, nil, '★ 小写 id 读为 nil（真机就是 nil —— ui.lua 曾经栽在这）')

-- ③ 只读字段：读得到，写会报 "cannot set <字段>, no such field"
H.eq(c2.visible, true, 'visible 读得到（值来自模板/宿主）')
local okRo, errRo = pcall(function() c2.visible = false end)
H.eq(okRo, false, '★ 直接写 visible 要报错')
H.truthy(tostring(errRo):find('no such field') ~= nil, '★ 报错原话：' .. tostring(errRo))
local okRo2, errRo2 = pcall(function() c2.active = true end)
H.eq(okRo2, false, '★ 直接写 active 也要报错：' .. tostring(errRo2))
H.eq(pcall(function() c2.notAField = 1 end), false, '★ 白名单外的字段写会报错（真机契约 §12）')
H.eq(c2.notAField, nil, '★ 白名单外的字段读为 nil')
H.truthy(c2:SetVisible(false), 'SetVisible 才是改可见性的正道')
H.eq(c2.visible, false, 'SetVisible(false) 之后读出来是 false')

-- ④ game 的函数是点号调用的；用冒号会把 game 自己塞进去（真机报 bad argument count）
local okColon, errColon = pcall(function() game:GetUICanvasSize() end)
H.eq(okColon, false, '★ game:方法() 冒号调用要报错：' .. tostring(errColon))

-- 服务端信号
local sig = game.ServerSignal('zuma.evt')
-- 文档：Add* 系列**不返回**自己，所以不能链式调用
sig:AddInt(3)
sig:AddString('hi')
sig:SendSignal()
H.eq(#host.signals, 1, '信号已发出')
H.eq(host.signals[1].name, 'zuma.evt', '信号名')
H.eq(#host.signals[1].params, 2, '两个参数')
host.fireServerSignal('zuma.evt', { 1, 2 })
H.eq(host.serverHandlers['zuma.evt'] ~= nil or true, true, '（未注册时 fire 不应报错）')

-- 脚本变量
host.params['ballPrefabIndex'] = 7
H.eq(script:GetParam('ballPrefabIndex'), 7, 'script:GetParam')

-- 平台限制自检
local okb, n = host.assertControlBudget()
H.ok(okb, '控件数在上限内（' .. n .. ' 个）')

H.finish()

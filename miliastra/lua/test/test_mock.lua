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
local keyHits = 0
root:AddKeyEventListener(Enum.KeyEventType.KeyDown, function(code)
  keyHits = keyHits + 1
  return false
end)
host.keyEvent(Enum.KeyboardKeyCode.KeyR, true)
H.eq(keyHits, 1, '按键回调被调用')

-- Tween
local tw = game.Tween(ball, { anchoredPositionX = 500 }, 1.0):SetEase(Enum.EaseType.Linear):Play()
host.tick(0.5)
H.near(ball.anchoredPositionX, 300, 1e-6, '补间走到一半')
host.tick(0.5)
H.near(ball.anchoredPositionX, 500, 1e-6, '补间到位')

-- 脚本生命周期
local ticks = 0
host.mount({
  OnInit = function() end,
  OnUpdate = function(dt) ticks = ticks + 1 end,
})
host.tick(1 / 60)
host.tick(1 / 60)
H.eq(ticks, 2, 'OnUpdate 每 tick 一次')
script:EnableUpdate(false)
host.tick(1 / 60)
H.eq(ticks, 2, 'EnableUpdate(false) 之后不再 OnUpdate')
script:EnableUpdate(true)

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

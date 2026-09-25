-- 诊断能力的测试：**出错时屏幕上必须看得见**。
-- 这一条很重要 —— 我在手机上看不到用户的电脑屏幕，那行字是唯一的线索。
--
-- ★★ 2026-09-25 改：真机上「控件只能在 OnStart 建」（OnInit 阶段 Instantiate 返回 nil），
--   所以这里**按真机的两段式**驱动：beginInit/OnInit -> enterStart/OnStart。
--   顺带就把"哪天有人把建控件挪回 OnInit"这件事钉死在这条测试里。

local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')

H.suite('诊断行 / 出错可见')

local function newHost(opts)
  opts = opts or {}
  local host = MOCK.newHost({ w = 900, h = 900 })
  host.prefabs[1] = 'image'
  host.prefabs[2] = 'textbox'
  host.prefabs[3] = 'cursorarea'
  host.params.ballPrefab = 1
  host.params.shotPrefab = 1
  host.params.hudPrefab = 2
  host.params.cursorPrefab = 3
  host.params.playPrefab = 1
  host.params.ballCount = 8
  host.params.shotCount = 2
  host.params.autoNext = 0
  -- ★ 诊断行现在**默认关**（屏幕上要和本体一致）；这条测试是专门测它的，所以显式打开
  host.params.diag = 1
  if opts.failCursor then host.failPrefabs = { [3] = true } end
  MOCK.install(host)
  if not opts.noRoot then host.scriptObj.object = host.root else host.roots = {}; host.scriptObj.object = nil end
  return host
end

-- 像真机那样走一遍生命周期：OnInit（建不出控件）-> OnStart（才建得出来）
local function lifecycle(host)
  host.beginInit()
  GAME.OnInit()
  host.enterStart()
  GAME.OnStart()
  host.enterRunning()
end

-- ① 正常：OnInit 只登记不建控件；OnStart 之后才有控件和诊断行
local h1 = newHost()
h1.beginInit()
GAME.OnInit()
H.eq(GAME.error, nil, 'OnInit 不报错')
H.eq(h1.stats.instantiated, 0, '★ OnInit 阶段一个控件都不建（真机：Instantiate 返回 nil）')
H.eq(GAME.diagControl, nil, '★ OnInit 阶段还没有诊断控件')
h1.enterStart()
GAME.OnStart()
H.eq(GAME.error, nil, '正常启动没有错误')
H.truthy(GAME.diagControl, 'OnStart 之后诊断控件建出来了')
H.truthy(GAME.diagControl.text:find('帧'), '诊断行有内容：' .. tostring(GAME.diagControl.text))
H.truthy(GAME.diagControl.text:find('t1%-pair') ~= nil, '诊断行含关卡 id')
GAME.OnUpdate(1 / 60)
H.truthy(GAME.diagControl.text:find('帧'), '每帧刷新')

-- ② 光标检测区域创建失败：不能抛出去，要显示在屏幕上
local h2 = newHost({ failCursor = true })
lifecycle(h2)
H.truthy(GAME.error, '捕获到了错误')
H.truthy(GAME.error:find('光标检测区域') ~= nil, '错误信息指明了是哪一步：' .. tostring(GAME.error))
H.eq(GAME.screen, 'error', '屏幕状态变成 error')
H.truthy(GAME.diagControl and GAME.diagControl.text:sub(1, 2) == '!!', '诊断行以 !! 开头：' .. tostring(GAME.diagControl and GAME.diagControl.text))
GAME.OnUpdate(1 / 60)
H.truthy(GAME.diagControl.text:sub(1, 2) == '!!', '出错后每帧仍然显示，不刷没')

-- ③ 连挂载控件都找不到：也要被 pcall 接住（只是屏幕上没地方显示）
local h3 = newHost({ noRoot = true })
lifecycle(h3)
H.truthy(GAME.error, '没有挂载控件时也捕获到错误')
H.truthy(GAME.error:find('找不到挂载控件') ~= nil, '错误信息可读：' .. tostring(GAME.error))

-- ④ 恢复：还能正常再来一次（不要卡死在 error 状态）
local h4 = newHost()
lifecycle(h4)
H.eq(GAME.error, nil, '重新初始化后错误被清掉')
H.eq(GAME.screen, 'playing', '回到 playing')
GAME.OnUpdate(1 / 60)
H.eq(GAME.screen, 'playing', '继续跑一帧没问题')

-- ★ 默认（不填 diag）时屏幕上不该有诊断文字 —— "移植版默认要和本体一样"
do
  local h = newHost()
  h.params.diag = nil                     -- 显式不填 = 用脚本默认值
  lifecycle(h)
  GAME.frames = 3
  GAME.refreshDiag()
  H.eq(GAME.diag, false, '★ diag 默认关（屏幕上不多一个字）')
  H.eq(GAME.diagControl.text, '', '默认时诊断框文字为空（空文字会被隐藏）')
end

-- ★ 但**出错**时必须显示，哪怕没开 diag（这是救命的那行，不属于辅助线）
do
  local h = newHost()
  h.params.diag = nil
  lifecycle(h)
  GAME.error = '测试用的错误'
  GAME.refreshDiag()
  H.truthy(GAME.diagControl.text:find('测试用的错误') ~= nil,
    '★ 出错时诊断框照样显示：' .. tostring(GAME.diagControl.text))
end

H.finish()

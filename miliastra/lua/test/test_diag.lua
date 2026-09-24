-- 诊断能力的测试：**出错时屏幕上必须看得见**。
-- 这一条很重要 —— 我在手机上看不到用户的电脑屏幕，那行字是唯一的线索。

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
  if opts.failCursor then host.failPrefabs = { [3] = true } end
  MOCK.install(host)
  if not opts.noRoot then host.scriptObj.object = host.root else host.roots = {}; host.scriptObj.object = nil end
  return host
end

-- ① 正常：诊断行显示状态
local h1 = newHost()
GAME.OnInit()
H.eq(GAME.error, nil, '正常启动没有错误')
H.truthy(GAME.diagControl, '诊断控件建出来了')
H.truthy(GAME.diagControl.text:find('帧'), '诊断行有内容：' .. tostring(GAME.diagControl.text))
H.truthy(GAME.diagControl.text:find('t1%-pair') ~= nil, '诊断行含关卡 id')
GAME.OnUpdate(1 / 60)
H.truthy(GAME.diagControl.text:find('帧'), '每帧刷新')

-- ② 光标检测区域创建失败：不能抛出去，要显示在屏幕上
local h2 = newHost({ failCursor = true })
GAME.OnInit()
H.truthy(GAME.error, '捕获到了错误')
H.truthy(GAME.error:find('光标检测区域') ~= nil, '错误信息指明了是哪一步：' .. tostring(GAME.error))
H.eq(GAME.screen, 'error', '屏幕状态变成 error')
H.truthy(GAME.diagControl and GAME.diagControl.text:sub(1, 2) == '!!', '诊断行以 !! 开头：' .. tostring(GAME.diagControl and GAME.diagControl.text))
GAME.OnUpdate(1 / 60)
H.truthy(GAME.diagControl.text:sub(1, 2) == '!!', '出错后每帧仍然显示，不刷没')

-- ③ 连挂载控件都找不到：也要被 pcall 接住（只是屏幕上没地方显示）
local h3 = newHost({ noRoot = true })
GAME.OnInit()
H.truthy(GAME.error, '没有挂载控件时也捕获到错误')
H.truthy(GAME.error:find('找不到挂载控件') ~= nil, '错误信息可读：' .. tostring(GAME.error))

-- ④ 恢复：还能正常再来一次（不要卡死在 error 状态）
local h4 = newHost()
GAME.OnInit()
H.eq(GAME.error, nil, '重新初始化后错误被清掉')
H.eq(GAME.screen, 'playing', '回到 playing')
GAME.OnUpdate(1 / 60)
H.eq(GAME.screen, 'playing', '继续跑一帧没问题')

H.finish()

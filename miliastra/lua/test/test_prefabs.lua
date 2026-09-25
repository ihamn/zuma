-- 自动认控件模板：**一个脚本变量都不填**也要能跑起来。
--
-- 为什么单独测：这一步就是为了消灭"让用户去编辑器里点开控件抄 4 个数字"这件事 ——
-- 抄错的后果是"球建不出来"或"点击没反应"，而且报错信息不会告诉你抄错了。
-- 官方给了 typeof()（"返回运行时类型名称；用于识别宿主对象"），脚本可以自己问。
--
-- 这个测试模拟"用户什么都没填"的情形：只给 4 个模板、不给任何 prefab 变量。

local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')

H.suite('自动认控件模板')

local function host(fillParams)
  local h = MOCK.newHost({ w = 900, h = 900 })
  h.prefabs[1] = 'image'
  h.prefabs[2] = 'textbox'
  h.prefabs[3] = 'cursorarea'
  h.prefabs[4] = 'container'
  h.params = { levelIndex = 1, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0, diag = 1 }
  if fillParams then
    for k, v in pairs(fillParams) do h.params[k] = v end
  end
  MOCK.install(h)
  h.scriptObj.object = h.root
  h.mount(GAME)
  return h
end

-- ① 什么都不填：脚本自己认出 球=1 文本=2 光标=3 容器=4
local h = host()
H.eq(GAME.error, nil, '一个变量都不填也能启动：' .. tostring(GAME.error))
H.eq(GAME.prefabs.ball, 1, '自动认出球模板 = 图片控件那个（索引 1）')
H.eq(GAME.prefabs.hud, 2, '自动认出文本框模板 = 索引 2')
H.eq(GAME.prefabs.cursor, 3, '自动认出光标检测区域模板 = 索引 3')
H.eq(GAME.prefabs.play, 4, '自动认出容器模板 = 索引 4')
H.eq(GAME.prefabs.shot, 1, '没单独给弹药模板时跟球一样')
H.truthy(GAME.ui and #GAME.ui.balls > 0, '球池建出来了：' .. tostring(GAME.ui and #GAME.ui.balls))
H.truthy(GAME.ui.rb and GAME.ui.rb.visible, '核糖体也画出来了（说明整条链子都通了）')

-- ② 探针不留痕：探测用的控件必须被销毁，不能占着控件预算
local budget, lim = require('ui').count(GAME.ui), 1000
H.ok(budget <= lim, '控件数在上限内：' .. budget .. ' <= ' .. lim)

-- ③ 顺序打乱也能认出来（不靠"第 1 个就是球"这种假设）
local h2 = MOCK.newHost({ w = 900, h = 900 })
h2.prefabs[7] = 'container'
h2.prefabs[9] = 'cursorarea'
h2.prefabs[12] = 'textbox'
h2.prefabs[15] = 'image'
h2.params = { levelIndex = 1, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0, diag = 1 }
MOCK.install(h2)
h2.scriptObj.object = h2.root
h2.mount(GAME)
H.eq(GAME.error, nil, '模板索引不是 1/2/3/4 也能跑：' .. tostring(GAME.error))
H.eq(GAME.prefabs.ball, 15, '认出球模板 = 15')
H.eq(GAME.prefabs.hud, 12, '认出文本框模板 = 12')
H.eq(GAME.prefabs.cursor, 9, '认出光标模板 = 9')
H.eq(GAME.prefabs.play, 7, '认出容器模板 = 7')

-- ④ 填了变量就以变量为准（自动认只是"没填时的兜底"）
local h3 = host({ ballPrefab = 1, hudPrefab = 2, cursorPrefab = 3, playPrefab = 1 })
H.eq(GAME.prefabs.play, 1, '填了 playPrefab 就用填的（不覆盖用户的意图）')

-- ⑤ 关掉自动认（autoPrefabs=0）时回到老行为：按 1/2/3/4 默认值
local h4 = host({ autoPrefabs = 0 })
H.eq(GAME.prefabs.ball, 1, 'autoPrefabs=0：球用默认值 1')
H.eq(GAME.prefabs.cursor, 3, 'autoPrefabs=0：光标用默认值 3')

-- ⑥ 容器节点模板可以**不建**：没有容器模板时直接用画布自带的默认容器节点
local h5 = MOCK.newHost({ w = 900, h = 900 })
h5.prefabs[2] = 'textbox'
h5.prefabs[3] = 'cursorarea'
h5.prefabs[1] = 'image'
h5.params = { levelIndex = 1, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0, diag = 1 }
MOCK.install(h5)
h5.scriptObj.object = h5.root
h5.mount(GAME)
H.eq(GAME.error, nil, '只建 3 个模板（图片/文本框/光标区）也能跑：' .. tostring(GAME.error))
H.eq(GAME.prefabs.play, nil, '没找到容器模板 → playPrefab 为空')
H.eq(GAME.ui.parent, h5.root, '★ 玩区父节点直接用了画布的默认容器节点')
H.truthy(GAME.ui.rb and GAME.ui.rb.visible, '照样把核糖体画出来了')

-- ⑦ 类型不对要**当场报错**，而不是到真机才崩在"调用 nil"上
--    （真机：图片控件没有 AddCursorEventListener / 文本框没有 SetImage）
local h6 = host({ cursorPrefab = 1, hudPrefab = 2 })   -- 光标指到"图片"模板上
H.truthy(GAME.error, '光标模板类型不对时报错')
H.truthy(tostring(GAME.error):find('不是"光标检测区域"控件') ~= nil, '错误信息说得清：' .. tostring(GAME.error))

local h7 = host({ hudPrefab = 1 })                     -- HUD 指到"图片"模板上
H.truthy(GAME.error, 'HUD 模板类型不对时报错')
H.truthy(tostring(GAME.error):find('不是%*%*文本框控件%*%*') ~= nil or tostring(GAME.error):find('文本框') ~= nil,
  '错误信息说得清：' .. tostring(GAME.error))

-- 假宿主本身也照真机封死：类型专属方法在别的类型上读出来是 nil
local probe = MOCK.newHost({ w = 900, h = 900 })
probe.prefabs[1] = 'image'
probe.prefabs[3] = 'cursorarea'
MOCK.install(probe)
local img = game.InstantiateClientUIControl(1, probe.root)
local cur = game.InstantiateClientUIControl(3, probe.root)
H.eq(img.AddCursorEventListener, nil, '★ 图片控件没有 AddCursorEventListener（真机也没有）')
H.eq(img.SetImage == nil, false, '图片控件有 SetImage')
H.eq(cur.SetImage, nil, '★ 光标检测区域没有 SetImage（真机也没有）')
H.eq(cur.AddCursorEventListener == nil, false, '光标检测区域有 AddCursorEventListener')

H.finish()

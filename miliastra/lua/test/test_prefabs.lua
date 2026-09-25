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

-- ⑧ ★★ 真机的模板索引是**大数字**（2^30 起）：用户实测点开模板看到 1073741846。
--    第一版只扫 1..32，于是"明明存了模板"却全报 nil —— 这条就是那个 bug 的回归测试。
local h8 = MOCK.newHost({ w = 900, h = 900 })
h8.prefabs[1073741846] = 'image'
h8.prefabs[1073741850] = 'textbox'
h8.prefabs[1073741860] = 'cursorarea'
h8.params = { levelIndex = 1, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0, diag = 1 }
MOCK.install(h8)
h8.scriptObj.object = h8.root
h8.mount(GAME)
H.eq(GAME.error, nil, '大数字索引也能跑起来：' .. tostring(GAME.error))
H.eq(GAME.prefabs.ball, 1073741846, '★ 认出球模板 = 1073741846（真机就是这个量级）')
H.eq(GAME.prefabs.hud, 1073741850, '认出文本框模板 = 1073741850')
H.eq(GAME.prefabs.cursor, 1073741860, '认出光标检测区域模板 = 1073741860')
H.truthy(GAME.ui and #GAME.ui.balls > 0, '球池照常建出来：' .. tostring(GAME.ui and #GAME.ui.balls))

-- ⑨ ★★ 素材：真机上**动态创建的图片控件不继承模板图** → 必须显式 SetImage(资产号)，
--    否则球/轨道/中央核糖体全画成"?"（用户就是这样看到的）。
--    所以现在的规则反过来：**不配也要设**，用默认资产号 100002。
do
  local h9 = MOCK.newHost({ w = 900, h = 900 })
  h9.prefabs[1] = 'image'
  h9.prefabs[2] = 'textbox'
  h9.prefabs[3] = 'cursorarea'
  h9.params = { levelIndex = 8, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0, diag = 0 }
  MOCK.install(h9)
  h9.scriptObj.object = h9.root
  h9.mount(GAME)
  H.eq(GAME.error, nil, '不配素材也能跑：' .. tostring(GAME.error))
  H.eq(GAME.ui.art['A'], 100002, '★ 不配 art → 用默认资产号 100002（实心圆）')
  H.eq(GAME.ui.artBar, 100001, '★ 棒默认用方块 100001（用户给的资产号）')
  H.eq(GAME.ui.artRing, 100006, '★ 环默认用空心圆 100006')
  H.eq(GAME.ui.artAny, 100002, '兜底资产号也设上了（棒/光晕/核糖体用它）')
  H.truthy((h9.stats.setImage or 0) > 0, '★ 必须真的调了 SetImage（真机不设就全是"?"）')
end

-- ⑩ 配了 art 时才按碱基换图（这时候才该调 SetImage）
do
  local h10 = MOCK.newHost({ w = 900, h = 900 })
  h10.prefabs[1] = 'image'
  h10.prefabs[2] = 'textbox'
  h10.prefabs[3] = 'cursorarea'
  h10.params = { levelIndex = 8, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0,
                 art = 'A:1001,U:1002,G:1003,C:1004,T:1005' }
  MOCK.install(h10)
  h10.scriptObj.object = h10.root
  h10.mount(GAME)
  H.eq(GAME.error, nil, '配了素材能跑：' .. tostring(GAME.error))
  H.truthy((h10.stats.setImage or 0) > 0, '配了 art → 会调 SetImage（次数 ' .. tostring(h10.stats.setImage) .. '）')
  H.truthy(GAME.ui.art and GAME.ui.art['A'] == 1001, 'art 参数被解析进 ui.art：A=1001')
end

-- ⑪ ★ 自动"借图"：画布里放了一个配好图的图片控件 → 脚本把它那张图的 id 拿来给全部碱基
do
  local h11 = MOCK.newHost({ w = 900, h = 900 })
  h11.prefabs[1] = 'image'
  h11.prefabs[2] = 'textbox'
  h11.prefabs[3] = 'cursorarea'
  h11.params = { levelIndex = 8, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0 }
  MOCK.install(h11)
  -- 画布上摆一个"配好图"的图片控件（imageId 是只读字段）
  local deco = game.InstantiateClientUIControl(1, h11.root)
  deco.name = '球素材'
  deco.imageId = 1073741900
  h11.scriptObj.object = h11.root
  h11.mount(GAME)
  H.eq(GAME.error, nil, '借图后能跑：' .. tostring(GAME.error))
  H.eq(GAME.ui.art['A'], 1073741900, '★ 从画布上借到素材 id = 1073741900，并套给了全部碱基')
  H.eq(GAME.ui.art['T'], 1073741900, 'T 也用同一个素材')
  H.truthy((h11.stats.setImage or 0) > 0, '借到图之后才会调 SetImage')
end

-- ⑫ artImage 变量可以直接指定（不用在画布里摆控件）
do
  local h12 = MOCK.newHost({ w = 900, h = 900 })
  h12.prefabs[1] = 'image'
  h12.prefabs[2] = 'textbox'
  h12.prefabs[3] = 'cursorarea'
  h12.params = { levelIndex = 8, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0, artImage = 1073741999 }
  MOCK.install(h12)
  h12.scriptObj.object = h12.root
  h12.mount(GAME)
  H.eq(GAME.ui.art['G'], 1073741999, 'artImage=1073741999 直接生效')
end

-- ⑮ ★★ 光标常驻：官方 API §24 说 ClientUIContainerControl.showCursor = "是否显示常驻光标；
--    **CursorEvent 相关方法都需设置该参数为真后才可正常使用**"。
--    用户真机现象：不设就得**按住 Alt** 才看得见光标。所以脚本必须在启动时打开它。
do
  local h15 = MOCK.newHost({ w = 900, h = 900 })
  h15.prefabs[1] = 'image'
  h15.prefabs[2] = 'textbox'
  h15.prefabs[3] = 'cursorarea'
  h15.params = { levelIndex = 8, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0 }
  MOCK.install(h15)
  h15.scriptObj.object = h15.root
  h15.mount(GAME)
  H.eq(GAME.error, nil, '能跑起来：' .. tostring(GAME.error))
  H.eq(h15.root.showCursor, true, '★ 挂载点（容器节点）的 showCursor 被脚本打开了 → 光标常驻')
end

-- ⑬ ★★ 铁律：整局建完之后，**每一个图片控件都必须有素材**（imageId 非 nil）。
--    真机上"没设素材的图片控件"就是画成"?"；用户报过两次（球那批、轨道那批），
--    根因都是"某个绘制分支忘了设"。这条断言把整个类别的 bug 一次钉死。
do
  local h13 = MOCK.newHost({ w = 900, h = 900 })
  h13.prefabs[1] = 'image'
  h13.prefabs[2] = 'textbox'
  h13.prefabs[3] = 'cursorarea'
  h13.params = { levelIndex = 8, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0 }
  MOCK.install(h13)
  h13.scriptObj.object = h13.root
  h13.mount(GAME)
  local imgs, missing, sample = 0, 0, nil
  for _, c in pairs(h13.controls) do
    local t = typeof and typeof(c) or nil
    if type(t) == 'string' and t:find('Image', 1, true) then
      imgs = imgs + 1
      if c.imageId == nil then
        missing = missing + 1
        sample = sample or tostring(c.name)
      end
    end
  end
  H.truthy(imgs > 100, '图片控件有一大堆（' .. tostring(imgs) .. ' 个）')
  H.eq(missing, 0, '★ 每个图片控件都设了素材（漏一个真机就是"?"）；共 ' .. tostring(imgs)
    .. ' 个图片控件，缺 ' .. tostring(missing) .. ' 个' .. (sample and ('，例如 ' .. sample) or ''))
end

-- ⑭ 棒可以用单独的"方图"资产号（artBar）—— 圆图拉成长条会鼓出来
do
  local h14 = MOCK.newHost({ w = 900, h = 900 })
  h14.prefabs[1] = 'image'
  h14.prefabs[2] = 'textbox'
  h14.prefabs[3] = 'cursorarea'
  h14.params = { levelIndex = 8, ballCount = 16, shotCount = 4, seed = 4242, autoNext = 0,
                 artImage = 100002, artBar = 100003 }
  MOCK.install(h14)
  h14.scriptObj.object = h14.root
  h14.mount(GAME)
  H.eq(GAME.ui.artAny, 100002, '球面用 artImage=100002（实心圆）')
  H.eq(GAME.ui.artRing, 100006, '★ 洞穴那几圈用默认空心圆 100006')
  H.eq(GAME.ui.artBar, 100003, '★ 棒用 artBar=100003（方图）覆盖默认 100001')
end

H.finish()

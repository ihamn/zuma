-- game.lua —— 宿主胶水：脚本生命周期 + 每帧主循环 + 关卡推进。
--
-- 这就是**最终要上传到千星奇域的那个脚本**的门面（打包器会把它和内核一起打成 out/zuma.lua）。
--
-- 编辑器里要做的事（详见 miliastra/pc/操作手册.html）：
--   1. 建一个**客户端控件容器画布**（不要用主屏）；
--   2. 建 4 个客户端控件模板：图片（球）/ 文本框 / 光标检测区域 / 玩区容器；
--   3. 在这个容器的**脚本页签**里挂上打包后的 zuma.lua；
--   4. 把模板索引填进脚本变量（下面这张表）。
--
-- 脚本变量（编辑期填，运行期用 script:GetParam 读；不填就用括号里的默认值）：
--   levelIndex   从第几关开始（1..11，1 = ① 配对）              [1]
--   ballPrefab   球控件的客户端控件模板索引                      [1]
--   shotPrefab   弹药控件的模板索引（不填则跟球一样）            [= ballPrefab]
--   hudPrefab    文本框控件的模板索引                            [2]
--   cursorPrefab 光标检测区域控件的模板索引                      [3]
--   playPrefab   玩区容器控件的模板索引（不填则跟球一样）        [= ballPrefab]
--   ballCount    球池大小                                        [96]
--   shotCount    弹药池大小                                      [8]
--   seed         随机种子                                        [12345]
--   autoNext     过关后自动进下一关（0 = 不自动）                [1]
--   diag         屏幕左下角显示诊断行（排错用，正式发布再关）    [1]
--
-- ★★ 为什么要 diag：我在手机上**看不到你的电脑屏幕**。
--   出问题时屏幕上那行字就是你转述给我的唯一线索，所以默认开着。

local CFG = require('config')
local BOARD = require('board')
local RB = require('ribosome')
local UI = require('ui')
local INPUT = require('input')
local LEVELS_DATA = require('levels_data')

local G = {}

G.screen = 'boot'          -- boot | playing | won | lost | error
G.resultTimer = 0
G.nextDelay = 2.5
G.loseDelay = 3.0
G.error = nil
G.frames = 0

local function param(name, default)
  local v = script and script:GetParam(name)
  if v == nil then return default end
  return v
end

-- 玩区容器的尺寸 = 画布尺寸；它以画布中心为原点
local function buildHudSpecs(w, h)
  local pad = 16
  local halfW, halfH = w / 2, h / 2
  return {
    { key = 'score', x = -halfW + 120 + pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'left' },
    { key = 'lives', x = halfW - 120 - pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'right' },
    { key = 'runs', x = -halfW + 220 + pad, y = halfH - 84 - pad, w = 440, h = 40, size = 26, align = 'left' },
    { key = 'mode', x = -halfW + 120 + pad, y = -halfH + 32 + pad, w = 240, h = 44, size = 26, align = 'left' },
    { key = 'hint', x = 0, y = -halfH + 130, w = math.min(w - 40, 760), h = 130, size = 24, align = 'center' },
    { key = 'result', x = 0, y = 0, w = math.min(w - 40, 640), h = 120, size = 40, align = 'center' },
  }
end

-- ==================== 启动 ====================

function G.OnInit()
  -- 最外层不做任何可能失败的事：先把画布尺寸和诊断显示准备好
  local ok0, w, h = pcall(game.GetUICanvasSize)
  if not ok0 then w, h = 900, 900 end
  G.canvas = { w = w, h = h }
  G.view = CFG.viewFor(w, h)
  G.diag = param('diag', 1) ~= 0
  G.error = nil          -- ★ 每次重来都清掉：否则上一次的错误会一直挂在屏幕上（测试抓到的）

  local ok, err = pcall(G.boot)
  if not ok then
    G.error = tostring(err)
    G.screen = 'error'
  end
  G.refreshDiag()
  return G
end

-- 真正干活的初始化。任何一步失败都会被 OnInit 的 pcall 接住并显示在屏幕上。
function G.boot()
  local w, h = G.canvas.w, G.canvas.h
  G.seed = param('seed', 12345)
  G.autoNext = param('autoNext', 1) ~= 0

  local root = script.object
  if not root then
    local roots = game.GetClientUIRoots()
    root = roots and roots[1] or nil
  end
  if not root then error('找不到挂载控件：脚本要挂在**客户端控件**上（不能挂主屏）') end
  G.root = root
  root:SetActive(true)

  -- ★★ 诊断框**第一个建**：万一后面哪一步炸了，屏幕上还有地方显示原因。
  --   （这一条很关键：我在手机上看不到你的屏幕，那行字就是唯一的线索）
  local dok, dc = pcall(game.InstantiateClientUIControl, param('hudPrefab', 2), root)
  if dok and dc then
    G.diagControl = dc
    dc:SetActive(true)
    dc:SetAnchoredPosition(0, -h / 2 + 20)
    dc:SetSizeDelta(math.min(w - 40, 760), 30)
    dc.fontSize = 18
    dc.horizontalAlignment = Enum.TextHorizontalAlignment.Left
    dc.verticalAlignment = Enum.TextVerticalAlignment.Middle
    if not G.diag then dc:SetVisible(false) end
  end

  -- 玩区容器：占满画布、居中
  local playPrefab = param('playPrefab', param('ballPrefab', 1))
  G.area = game.InstantiateClientUIControl(playPrefab, root)
  if not G.area then error('创建玩区容器失败：playPrefab = ' .. tostring(playPrefab)) end
  G.area:SetActive(true)
  G.area:SetAnchoredPosition(0, 0)
  G.area:SetSizeDelta(w, h)

  -- 光标检测区域：铺满画布
  G.cursorArea = game.InstantiateClientUIControl(param('cursorPrefab', 3), G.area)
  if not G.cursorArea then error('创建光标检测区域失败：cursorPrefab = ' .. tostring(param('cursorPrefab', 3))) end
  G.cursorArea:SetActive(true)
  G.cursorArea:SetAnchoredPosition(0, 0)
  G.cursorArea:SetSizeDelta(w, h)

  G.ui = UI.create({
    parent = G.area,
    canvas = G.canvas,
    ballPrefab = param('ballPrefab', 1),
    ballCount = param('ballCount', 96),
    shotPrefab = param('shotPrefab', param('ballPrefab', 1)),
    shotCount = param('shotCount', 8),
    hudPrefab = param('hudPrefab', 2),
    hud = buildHudSpecs(w, h),
  })

  G.input = INPUT.create({
    area = G.cursorArea,
    keyTarget = root,
    canvas = G.canvas,
  })


  G.startLevel(param('levelIndex', 1))
  return G
end

-- ==================== 关卡 ====================

function G.startLevel(idx)
  local total = #LEVELS_DATA.LEVELS
  if idx < 1 then idx = 1 end
  if idx > total then idx = total end
  G.levelIndex = idx
  G.level = LEVELS_DATA.LEVELS[idx]
  G.sc = BOARD.assembleScene(G.level, G.view, G.seed + idx)
  G.screen = 'playing'
  G.resultTimer = 0
  -- ★ 立刻同步一次：否则换关后的第一帧里，画面上还留着上一关的球
  if G.ui then UI.sync(G.ui, G.sc, G.syncState()) end
  return G.sc
end

-- ==================== 诊断行 ====================

-- ★ 这一行是"远程排错"的生命线：用户把屏幕上这句话念给我，我就知道卡在哪。
function G.refreshDiag()
  if not G.diag then return end
  local hc = G.diagControl
  if not hc then return end
  local s
  if G.error then
    s = '!! ' .. G.error
  else
    local balls = G.sc and #G.sc.chain.balls or 0
    local pool = G.ui and #G.ui.balls or 0
    local ctrl = 0
    if G.ui then ctrl = pool + #G.ui.shots + 7 end
    s = string.format('帧%d 关%s 球%d/%d 控件%d 状态%s', G.frames,
      tostring(G.level and G.level.id or '?'), balls, pool, ctrl, G.screen)
  end
  if #s > 240 then s = s:sub(1, 240) end
  if hc.text ~= s then hc.text = s end
end

-- ==================== 每帧 ====================

function G.OnUpdate(dt)
  G.frames = G.frames + 1
  if G.error then
    G.refreshDiag()
    return
  end
  local ok, err = pcall(G.tick, dt)
  if not ok then
    G.error = tostring(err)
    G.screen = 'error'
  end
  G.refreshDiag()
end

function G.tick(dt)
  if not G.sc then return end

  -- 结算画面：只等按键或超时，不再推进盘面
  if G.screen == 'won' or G.screen == 'lost' then
    G.resultTimer = G.resultTimer + dt
    local advance = G.input.wantRestart
    if not advance and G.resultTimer >= ((G.screen == 'won') and G.nextDelay or G.loseDelay) then
      advance = true
    end
    if advance then
      G.input.wantRestart = false
      if G.screen == 'won' and G.autoNext and G.levelIndex < #LEVELS_DATA.LEVELS then
        G.startLevel(G.levelIndex + 1)
      else
        G.startLevel(G.levelIndex)
      end
      return
    end
    UI.sync(G.ui, G.sc, G.syncState())
    return
  end

  if G.input.wantRestart then
    G.input.wantRestart = false
    G.startLevel(G.levelIndex)
    return
  end

  INPUT.update(G.input, G.sc, dt)

  if G.input.wantSwap then
    G.input.wantSwap = false
    RB.swapLoaded(G.sc.rb)
  end
  if G.input.wantMode then
    G.input.wantMode = false
    BOARD.toggleMode(G.sc)
  end

  if G.input.firing then
    -- 冷却由 board/RB 管：没冷却好会返回 nil，这时**不要**消费掉意图
    if BOARD.fireShot(G.sc) then INPUT.consume(G.input) end
  end

  BOARD.advanceScene(G.sc, dt)
  UI.sync(G.ui, G.sc, G.syncState())

  if G.sc.won then
    G.screen = 'won'
    G.resultTimer = 0
  elseif G.sc.gameOver then
    G.screen = 'lost'
    G.resultTimer = 0
  end
end

-- 给 ui.sync 的那一小包"表现层才关心的东西"
function G.syncState()
  local lines = {}
  if G.level and G.level.hint then
    for i = 1, #G.level.hint do lines[#lines + 1] = G.level.hint[i] end
  end
  if G.error then
    lines = { '出错了：' .. G.error }
  elseif G.screen == 'won' then
    lines = { '过关！（' .. tostring(G.sc.winReason) .. '）  按 R 重来' }
  elseif G.screen == 'lost' then
    lines = { '命数用尽  按 R 重来' }
  end
  return {
    mode = G.sc and G.sc.mode or 'match',
    hintLines = lines,
  }
end

function G.OnStart() end
function G.OnEnable() end
function G.OnDisable() end
function G.OnLevelUpdate(dt) end   -- OnUpdate 已经不受时停影响，这里不再重复推进
function G.OnDestroy()
  G.sc = nil
  G.ui = nil
  G.input = nil
end

-- 供本地测试/调试用（不改变行为）
function G.info()
  if not G.sc then return { screen = G.screen, error = G.error } end
  local info = BOARD.sceneInfo(G.sc)
  info.screen = G.screen
  info.level = G.level and G.level.id or '?'
  info.mode = G.sc.mode
  info.won = G.sc.won
  info.winReason = G.sc.winReason
  info.gameOver = G.sc.gameOver
  info.error = G.error
  return info
end

return G

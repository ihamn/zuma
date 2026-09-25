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
--   autoPrefabs  自动认控件模板（下面的索引**一个都不用填**）      [1]
--   ballPrefab   球控件的客户端控件模板索引（填了就不用自动认）    [自动]
--   shotPrefab   弹药控件的模板索引（不填则跟球一样）              [= ballPrefab]
--   hudPrefab    文本框控件的模板索引                              [自动]
--   cursorPrefab 光标检测区域控件的模板索引                        [自动]
--   playPrefab   玩区容器控件的模板索引（不填则跟球一样）          [自动]
--   ballCount    球池大小                                        [96]
--   shotCount    弹药池大小                                      [8]
--   fancy        光晕 / 冷却环 / 动效（0 = 只留静态画面）          [1]
--   track        轨道也由 Lua 画（0 = 用编辑器里摆的静态图）      [1]
--   trackSegments 每条轨画多少段（控件紧张时调小）                [64]
--   letters      球面叠碱基字母（0 = 只靠图片素材）               [1]
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

-- 不依赖控件的日志通道（官方日志 API）。
-- ★ 为什么必须有：真机上控件要等到 OnStart 才建得出来，一旦在那之前失败，
--   屏幕上那行"诊断字"本身也是控件、也建不出来 —— 这时只剩日志能告诉我们死在哪。
-- ★★ 为什么格式化失败也要把值打出来：第一次真机试玩时这行打成了字面量 `画布 %dx%d` ——
--   `%d` 遇到非整数（真机 canvas 尺寸是浮点）会抛错，pcall 一接住就只剩格式串，
--   等于**把最想看的信息吞了**。现在退回"格式串 + 值"，丑但有用。
local function say(fmt, ...)
  local ok, s = pcall(string.format, fmt, ...)
  if not ok then
    local n = select('#', ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    s = tostring(fmt) .. '   [' .. table.concat(parts, ' ') .. ']'
  end
  if print then pcall(print, '[zuma] ' .. s) end
end

-- 玩区容器的尺寸 = 画布尺寸；它以画布中心为原点
-- panel: 'solid'（默认，65% 底板）/ 'light'（40%，给大块文字）/ false（不画底板）
local function buildHudSpecs(w, h)
  local pad = 16
  local halfW, halfH = w / 2, h / 2
  return {
    { key = 'score', x = -halfW + 120 + pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'left' },
    { key = 'lives', x = halfW - 120 - pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'right' },
    { key = 'runs', x = -halfW + 220 + pad, y = halfH - 84 - pad, w = 440, h = 40, size = 26, align = 'left' },
    { key = 'mode', x = -halfW + 120 + pad, y = -halfH + 32 + pad, w = 240, h = 44, size = 26, align = 'left' },
    { key = 'hint', x = 0, y = -halfH + 130, w = math.min(w - 40, 760), h = 130, size = 24, align = 'center', panel = 'light' },
    -- 结果框在正中央：**平时没有文字**，所以不给底板（给了就是一块盖住核糖体的黑板）
    { key = 'result', x = 0, y = 0, w = math.min(w - 40, 640), h = 120, size = 40, align = 'center', panel = false },
  }
end

-- ==================== 启动 ====================

function G.OnInit()
  -- ★★ 第一行就要说话：**日志里看不到这行 = 脚本根本没跑起来**（映射没挂上 / 容器不可见）。
  --   这是排错的第一分叉点，所以放在所有可能失败的动作之前，而且用不依赖控件的 print。
  say('★ zuma 脚本已启动（日志里能看到这行 = 脚本挂上了）')
  -- ★★ 真机限制（来源：客户端 Lua 运行时真机探针 + 官方《客户端控件 API 文档》）：
  --   1. game.InstantiateClientUIControl 在 **OnInit 阶段返回 nil**，只有 OnStart 及之后成功。
  --      —— 所以这里**一个控件都不建**，全部挪到 OnStart（见 G.tryBoot）。
  --   2. 官方 API 有 script:EnableUpdate(enabled)；真机结论是「EnableUpdate 前无 OnUpdate」。
  --      —— 不打开它，OnUpdate 永远不会被调用，画面就是死的。
  -- 因此 OnInit 里只做**不可能失败**的事。
  local ok0, w, h = pcall(game.GetUICanvasSize)
  if not ok0 then w, h = 900, 900 end
  G.canvas = { w = w, h = h }
  G.view = CFG.viewFor(w, h)
  G.diag = param('diag', 1) ~= 0
  G.error = nil          -- ★ 每次重来都清掉：否则上一次的错误会一直挂在屏幕上（测试抓到的）
  G.booted = false

  say('OnInit：画布 %s x %s', tostring(w), tostring(h))
  if script and script.EnableUpdate then
    local eok, eerr = pcall(function() script:EnableUpdate(true) end)
    say('EnableUpdate(true) -> %s', eok and 'ok' or tostring(eerr))
  else
    say('警告：没有 script.EnableUpdate，逐帧回调可能不会触发')
  end
  return G
end

-- 真正建控件。**只能在 OnStart 及之后调用**：真机 OnInit 阶段 Instantiate 返回 nil。
function G.tryBoot()
  if G.booted then return end
  G.booted = true
  say('tryBoot：开始建控件')
  local ok, err = pcall(G.boot)
  if ok then
    say('tryBoot：成功')
  else
    G.error = tostring(err)
    G.screen = 'error'
    say('tryBoot 失败：%s', tostring(err))
    -- ★ 失败在"建控件之前"（多半是挂载点/模板/容器的问题）→ 把**真实控件树**打进日志。
    --   官方 API：game.PrintClientUITree() "将当前客户端控件树按父子层级写入日志"。
    --   只在 ui 还没建起来时打（那时树很小）；建了一半就别打了，几百个控件会刷屏。
    if not G.ui and game.PrintClientUITree then
      pcall(game.PrintClientUITree)
      say('已把客户端控件树打进日志（用来确认容器/挂载点到底存不存在）')
    end
    if printerr then pcall(printerr, '[zuma] 建控件失败：' .. tostring(err)) end
  end
  G.refreshDiag()
end

-- ★★ 自动认控件模板：**用户一个变量都不用填**。
--
-- 官方文档《客户端控件和客户端脚本》§八：「编辑时，可以通过点击客户端控件查看对应的控件模板索引ID」
-- —— 也就是说索引是编辑器给的数字，要人去点开看、再抄进脚本变量表。这一步既枯燥又容易抄错
-- （抄错的后果是"球建不出来"或"点击没反应"）。
--
-- 但官方同时提供了 `typeof(value)`（"返回运行时类型名称；用于识别宿主对象"），
-- 于是可以**自己问**：从索引 1 开始挨个尝试建一个控件，看它的运行时类型名是什么，是图片就是球、
-- 是文本框就是 HUD、是光标检测区域就是点击区、是容器就是玩区。探针用完立刻销毁（不占控件数）。
-- 填了脚本变量的以变量为准；没填的用自动认出来的；自动认不出才退回 1/2/3/4。
local function detectPrefabs(root)
  local want = {          -- 变量名 -> 类型名里必须出现的关键词
    ballPrefab = 'Image',
    hudPrefab = 'TextBox',
    cursorPrefab = 'Cursor',
    playPrefab = 'Container',
  }
  local found = {}
  local probe = {}        -- 诊断用：前几个索引到底"建出来了"还是"报什么错"
  if not (typeof and game.InstantiateClientUIControl and game.DestroyClientUIControl) then
    return found, probe
  end
  for i = 1, 32 do
    local ok, c = pcall(game.InstantiateClientUIControl, i, root)
    if i <= 8 then
      local desc
      if not ok then desc = '报错 ' .. tostring(c)
      elseif c == nil then desc = 'nil（没有这个模板）'
      else desc = '建出 ' .. tostring(typeof(c)) end
      probe[#probe + 1] = '索引 ' .. tostring(i) .. '：' .. desc
    end
    if ok and c then
      local t = typeof(c)
      for k, word in pairs(want) do
        if found[k] == nil and type(t) == 'string' and t:find(word, 1, true) then found[k] = i end
      end
      pcall(game.DestroyClientUIControl, c)      -- 探针不留痕
    end
  end
  return found, probe
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
  say('挂载点 = %s', tostring(root))

  -- ★ 模板索引定下来：填了变量的用变量，没填的**自动认**（见 detectPrefabs 注释）
  local useAuto = param('autoPrefabs', 1) ~= 0
  local auto, probe = {}, {}
  if useAuto then
    auto, probe = detectPrefabs(root)
    say('自动认模板：球=%s 文本=%s 光标=%s 容器=%s', tostring(auto.ballPrefab), tostring(auto.hudPrefab),
      tostring(auto.cursorPrefab), tostring(auto.playPrefab))
    if not (auto.ballPrefab or auto.hudPrefab or auto.cursorPrefab or auto.playPrefab) then
      -- 一个模板都没有 = 动态创建无从谈起。把"该怎么建"和"探针看到了什么"一起打出来。
      say('⚠ 索引 1~32 里没找到任何客户端控件模板 —— 这就是屏幕空白的原因')
      say('   建法：界面控件组库 → 客户端控件模板 → 【添加客户端控件】→ 选类型 → **存为模板**')
      say('   （注意是"存为模板"，不是"在画布里摆一个控件"；摆出来的实例没有模板索引）')
      for i = 1, #probe do say('   探针 %s', probe[i]) end
    end
  end
  G.prefabs = {
    ball = param('ballPrefab', auto.ballPrefab or 1),
    hud = param('hudPrefab', auto.hudPrefab or 2),
    -- 光标必须真的有（类型不对就没有点击事件）；容器没有就用画布默认容器节点
    -- 关掉自动认时，按手册建议的顺序建的话模板③就是光标检测区域 → 兜底成 3
    cursor = param('cursorPrefab', auto.cursorPrefab or (not useAuto and 3 or nil)),
    play = param('playPrefab', auto.playPrefab),
  }
  G.prefabs.shot = param('shotPrefab', G.prefabs.ball)
  say('用这套模板索引：球=%s 弹药=%s 文本=%s 光标=%s 玩区=%s', tostring(G.prefabs.ball), tostring(G.prefabs.shot),
    tostring(G.prefabs.hud), tostring(G.prefabs.cursor), tostring(G.prefabs.play))

  -- ★★ 诊断框**第一个建**：万一后面哪一步炸了，屏幕上还有地方显示原因。
  --   （这一条很关键：我在手机上看不到你的屏幕，那行字就是唯一的线索）
  local dok, dc = pcall(game.InstantiateClientUIControl, G.prefabs.hud, root)
  if dok and dc then
    -- 文本框类型要是不对（比如拿图片模板当 HUD），真机上写 .text / .fontSize 会直接报"字段不存在"
    local ht = typeof and typeof(dc) or nil
    if type(ht) == 'string' and not ht:find('TextBox', 1, true) then
      error('模板 ' .. tostring(G.prefabs.hud) .. ' 是 ' .. ht .. '，不是**文本框控件** —— ' ..
        '分数/提示/球面字母都靠它，请到 界面控件组库 → 客户端控件模板 里建一个文本框并存为模板')
    end
    G.diagControl = dc
    dc:SetActive(true)
    dc:SetAnchoredPosition(0, -h / 2 + 20)
    dc:SetSizeDelta(math.min(w - 40, 760), 30)
    dc.fontSize = 18
    dc.horizontalAlignment = Enum.TextHorizontalAlignment.Left
    dc.verticalAlignment = Enum.TextVerticalAlignment.Middle
    if not G.diag then dc:SetVisible(false) end
    dc.bgColor = Color.FromRGBA(8, 12, 18, 170)     -- 半透明底板，压着字也看得清
  end

  say('诊断框 = %s', tostring(G.diagControl))

  -- 玩区容器：**有就用，没有就直接挂在画布自带的默认容器节点下**（省掉模板④）。
  -- ★ 为什么这样设计：千星奇域里有两个名字很像的"容器"——
  --   ① 客户端控件容器 = 画布本身（服务器控件，必须有，客户端控件靠它显示、脚本靠它挂）
  --   ② 容器节点控件   = 普通控件模板（ClientUIContainerControl），只是我们拿来当"玩区父节点"
  --   ② 完全可以省掉：画布的默认容器节点（game.GetClientUIRoots 返回的那个）就能当父节点。
  local playPrefab = param('playPrefab', auto.playPrefab)
  if playPrefab then
    G.area = game.InstantiateClientUIControl(playPrefab, root)
    if not G.area then
      error('创建玩区容器失败：模板索引 = ' .. tostring(playPrefab) .. '（可以不填 —— 留空就用画布默认容器）')
    end
    G.area:SetActive(true)
    G.area:SetAnchoredPosition(0, 0)
    G.area:SetSizeDelta(w, h)
    -- 如果用户拿图片模板当玩区（省一个模板），它默认是块白图，会把整屏糊住 → 调成全透明
    local at = typeof and typeof(G.area) or nil
    if type(at) == 'string' and not at:find('Container', 1, true) then
      pcall(function() G.area.imageColor = Color.FromRGBA(0, 0, 0, 0) end)
      say('玩区容器用的是 %s（不是容器节点控件）→ 已调成全透明，免得糊住屏幕', tostring(at))
    end
  else
    G.area = root
    say('没建容器节点模板 → 直接用画布的默认容器节点当玩区（少建一个模板）')
  end

  -- 光标检测区域：**必须是"光标检测区域"控件**（类型不对则根本没有 AddCursorEventListener，
  -- 真机上会以"调用 nil"崩掉，而假宿主什么方法都有、本地发现不了 → 这里用 typeof 当场拦下）
  local cursorPrefab = param('cursorPrefab', auto.cursorPrefab)
  if not cursorPrefab then
    error('没找到"光标检测区域"控件模板：请到 界面控件组库 → 客户端控件模板 → 添加客户端控件 → 选"光标检测区域" → 存为模板')
  end
  G.cursorArea = game.InstantiateClientUIControl(cursorPrefab, G.area)
  if not G.cursorArea then
    error('创建光标检测区域失败：模板索引 = ' .. tostring(cursorPrefab) .. '（要建一个"光标检测区域"控件并存为模板）')
  end
  local ct = typeof and typeof(G.cursorArea) or nil
  if type(ct) == 'string' and not ct:find('Cursor', 1, true) then
    error('模板 ' .. tostring(cursorPrefab) .. ' 是 ' .. ct .. '，不是"光标检测区域"控件 —— ' ..
      '类型不对就没有点击事件，必须建一个光标检测区域并存为模板')
  end
  G.cursorArea:SetActive(true)
  G.cursorArea:SetAnchoredPosition(0, 0)
  G.cursorArea:SetSizeDelta(w, h)
  say('玩区 = %s / 光标区 = %s', tostring(G.area), tostring(G.cursorArea))

  G.ui = UI.create({
    parent = G.area,
    canvas = G.canvas,
    ballPrefab = G.prefabs.ball,
    ballCount = param('ballCount', 96),
    shotPrefab = G.prefabs.shot,
    shotCount = param('shotCount', 8),
    -- 连线 / 轨道 / 洞穴都用**球的模板**（拉长就是一根棒、放大就是一个洞）—— 编辑器里不用多建模板
    linkPrefab = param('linkPrefab', G.prefabs.ball),
    linkCount = param('linkCount', param('ballCount', 96) * 2),
    cavePrefab = param('cavePrefab', G.prefabs.ball),
    mergeCount = param('mergeCount', 8),
    -- 三档"美化"开关（真机上哪条炸了就改脚本变量关掉，不用重新打包逻辑）
    fancy = param('fancy', 1),               -- 光晕 / 冷却环 / 动效
    track = param('track', 1),               -- 轨道也由 Lua 画（0 = 用编辑器摆的静态图）
    trackSegments = param('trackSegments', 64),
    letters = param('letters', 1),           -- 球面叠碱基字母（0 = 只靠图片素材）
    hudPrefab = G.prefabs.hud,
    hud = buildHudSpecs(w, h),
  })

  G.input = INPUT.create({
    area = G.cursorArea,
    keyTarget = root,
    canvas = G.canvas,
  })


  say('控件池：球 %s / 弹药 %s', tostring(#G.ui.balls), tostring(#G.ui.shots))

  -- ★ 诊断行要**画在所有东西上面**（排错的生命线，被压住就等于没有）：
  --   必须在**所有控件都建完之后**再提到最上层 —— 早了会被后建的玩区/HUD 盖回去。
  if G.diagControl and G.diagControl.SetAsLastSibling then
    pcall(function() G.diagControl:SetAsLastSibling() end)
  end

  G.startLevel(param('levelIndex', 1))
  say('关卡 %s 已装配', tostring(G.level and G.level.id or '?'))
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
    -- 控件总数 = ui 建的 + 脚本自己建的 3 个（诊断框 / 玩区 / 光标区）
    local ctrl = G.ui and (UI.count(G.ui) + 3) or 0
    s = string.format('帧%d 关%s 球%d/%d 控件%d 状态%s', G.frames,
      tostring(G.level and G.level.id or '?'), balls, pool, ctrl, G.screen)
  end
  if #s > 240 then s = s:sub(1, 240) end
  if hc.text ~= s then hc.text = s end
end

-- ==================== 每帧 ====================

function G.OnUpdate(dt)
  -- 兜底：万一某些版本不调 OnStart，第一帧补建（此时已不在 OnInit 阶段，控件建得出来）
  if not G.booted then
    say('没等到 OnStart，在 OnUpdate 里补建')
    G.tryBoot()
  end
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
    UI.sync(G.ui, G.sc, G.syncState(dt))
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
  UI.sync(G.ui, G.sc, G.syncState(dt))

  if G.sc.won then
    G.screen = 'won'
    G.resultTimer = 0
  elseif G.sc.gameOver then
    G.screen = 'lost'
    G.resultTimer = 0
  end
end

-- 给 ui.sync 的那一小包"表现层才关心的东西"
-- dt：动效要按时间推进；events：board 攒的事件（清段/爆炸/命中），表现层拿去播一次性动效
function G.syncState(dt)
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
    dt = dt,
    events = G.sc and BOARD.drainEvents(G.sc) or nil,   -- ★ 只有一个消费者：这里取走，别处再取就没了
    mode = G.sc and G.sc.mode or 'match',
    hintLines = lines,
  }
end

function G.OnStart()
  -- 真机上这里是**第一个能建控件**的时机（OnInit 阶段 Instantiate 返回 nil）
  G.tryBoot()
end
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

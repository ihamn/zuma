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
-- ★★ 规则：移植版**默认要和本体长得一样**。
--   下面这两条是移植期加的"辅助线"，本体没有 —— 所以**默认关**，要排查时填脚本变量开：
--     diag=1  → 左下角那行状态（帧/关卡/球数/控件数/状态）
--     teach=1 → 左上角两行教学（手里该打谁 + 上次命中判定）
--   默认全关时，屏幕上的东西和网页版一一对应，不多一个字。
local function buildHudSpecs(w, h, teach)
  local pad = 16
  local halfW, halfH = w / 2, h / 2
  local specs = {
    { key = 'score', x = -halfW + 120 + pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'left' },
    { key = 'lives', x = halfW - 120 - pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'right' },
    { key = 'runs', x = -halfW + 220 + pad, y = halfH - 84 - pad, w = 440, h = 40, size = 26, align = 'left' },
    { key = 'mode', x = -halfW + 120 + pad, y = -halfH + 32 + pad, w = 240, h = 44, size = 26, align = 'left' },
    { key = 'hint', x = 0, y = -halfH + 130, w = math.min(w - 40, 760), h = 130, size = 24, align = 'center', panel = 'light' },
    -- 结果框在正中央：**平时没有文字**，所以不给底板（给了就是一块盖住核糖体的黑板）
    { key = 'result', x = 0, y = 0, w = math.min(w - 40, 640), h = 120, size = 40, align = 'center', panel = false },
  }
  -- teach=1 才加那两行辅助（本体没有）：手里该打谁 + 上次命中判定
  if teach then
    specs[#specs + 1] = { key = 'mate', x = -halfW + 120 + pad, y = halfH - 178 - pad, w = 640, h = 36, size = 22, align = 'left' }
    specs[#specs + 1] = { key = 'hit', x = -halfW + 120 + pad, y = halfH - 136 - pad, w = 640, h = 36, size = 22, align = 'left' }
  end
  return specs
end

-- ★★ 自动"借"一张图：真机上图片控件没配图就画成"?"（用户实测：球、轨道、中央全是"?"）。
--   素材 id 在编辑器里是大数字，抄起来烦 —— 所以让脚本自己在**画布里找**：
--   官方 ClientUIBaseControl:GetChildren() 能拿到直接子控件，图片控件的 imageId 是**只读**字段。
--   只要你**在画布里放一个配好图的图片控件**（哪怕是个装饰图标），脚本就把它那张图的 id
--   拿来当所有球/轨道/光晕的素材，一个数字都不用抄。
--   （也可以直接填 `artImage=1073741860` 指定；或按碱基分别填 `art=A:id,U:id,...`）
local function adoptImageId(root)
  local found = {}
  local seen = {}
  local function walk(ctrl, depth)
    if not ctrl or depth > 4 or #found >= 12 or seen[ctrl] then return end
    seen[ctrl] = true
    local ok, kids = pcall(function() return ctrl:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local ch = kids[i]
      local id = ch and ch.imageId
      local t = typeof and typeof(ch) or nil
      -- ★ 只认**正整数**：0 表示"没配图"（真机/假宿主都会这么给），捡了 0 等于没设 → 全画成"?"
      if type(id) == 'number' and id > 0 and type(t) == 'string' and t:find('Image', 1, true) then
        found[#found + 1] = { id = id, name = tostring(ch.name), t = t }
      end
      walk(ch, depth + 1)
    end
  end
  -- ① 挂载点往下；② 挂载点往上的三层（用户可能把"配好图的控件"摆在画布别处）；
  -- ③ 官方 game.GetClientUIRoots()（"实际显示的画布默认容器节点"）各自的子树。
  walk(root, 1)
  local up = root
  for _ = 1, 3 do
    if not up then break end
    up = up.parent
    walk(up, 1)
  end
  local okr, roots = pcall(function() return game.GetClientUIRoots() end)
  if okr and type(roots) == 'table' then
    for i = 1, #roots do walk(roots[i], 1) end
  end
  return found
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
  -- ★★ 显示缩放 zoom（**移植侧旋钮，本体没有** → 默认 1 = 完全照本体）。
  --   用途：只想让整个画面（球/轨道/洞穴）大一点，又不想去编辑器改画布尺寸时，
  --   填 zoom=1.2 就行。做法是把 rx/ry/scale **一起**乘 —— 于是所有尺寸等比放大，
  --   R/r 仍是 √2、规则数值一个没动（碰撞/间距都由 mt 推导，等比缩放不改变行为）。
  --   ★ 更"正统"的做法是改画布：画布 1280×1280 时 base=1280 → scale=1.4222，
  --     大球 R 19→27.0、小球 r 13.4→19.1（正好就是"2 : √2"），且本体同样视口算出来一模一样。
  local zoom = tonumber(tostring(param('zoom', '')))
  if zoom and zoom > 0 and zoom ~= 1 then
    G.view.rx, G.view.ry, G.view.scale =
      G.view.rx * zoom, G.view.ry * zoom, G.view.scale * zoom
    G.zoom = zoom
  end
  G.diag = param('diag', 0) ~= 0        -- ★ 默认关：屏幕上要和本体一样，不多一个字
  G.teach = param('teach', 0) ~= 0      -- ★ 默认关：教学辅助行（手里该打谁 / 上次命中判定）
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
  local probe = {}        -- 诊断用：建出来的/报错的都记一笔
  if not (typeof and game.InstantiateClientUIControl and game.DestroyClientUIControl) then
    return found, probe
  end

  -- ★★ 索引空间（这是第一版踩的坑）：真机上"客户端控件模板索引"是**大数字**，
  --   不是 1/2/3/4。实测数据点：用户点开模板看到 1073741846，关卡目录是 1073741825
  --   —— 都从 2^30 起（同一个 ID 空间）。只扫 1..32 的话，"明明存了模板"也会全报 nil。
  local BASE = 1073741824          -- 2^30
  local RANGES = {
    { 1, 32 },                     -- 有些环境/子控件确实用小索引
    { BASE + 1, BASE + 192 },      -- 客户端控件模板的真实空间（覆盖 1073741846 这种）
  }

  local built = 0
  for r = 1, #RANGES do
    local lo, hi = RANGES[r][1], RANGES[r][2]
    local madeHere = 0
    for i = lo, hi do
      -- 小范围（1~32）要**扫完**，否则会漏掉容器模板（它常常排在最后）；
      -- 大范围（2^30 起，192 个索引）只要三个必需的认出来就收工，省得白试两百次。
      if r > 1 and found.ballPrefab and found.hudPrefab and found.cursorPrefab then break end
      local ok, c = pcall(game.InstantiateClientUIControl, i, root)
      if ok and c then
        madeHere = madeHere + 1
        built = built + 1
        local t = typeof(c)
        if #probe < 12 then
          -- ★ 顺带把"这张图控件自带什么图"读出来（官方：imageSource / imageId 是**只读**字段）。
          --   真机上如果这里打出 id=nil，就是"模板根本没配图" → 每个实例都会画成"?"。
          local src, iid = c.imageSource, c.imageId
          probe[#probe + 1] = '索引 ' .. tostring(i) .. '：建出 ' .. tostring(t) ..
            '（自带图 source=' .. tostring(src) .. ' id=' .. tostring(iid) .. '）'
          -- ★★ 图片类型（基础 / 拉伸）：**真机上只读**（我们自己的契约 §14：赋值报
          --    "cannot set imageType"）→ 脚本改不了，只能读出来提醒。
          --    若模板是"拉伸"且素材是三宫格/九宫格，我们放大控件时**四角不变、中间被拉**，
          --    球与光晕各自形变 → 看上去就是"球变大了 / 描边变形"（用户反复反馈的那个）。
          local it = c.imageType
          if it ~= nil then
            local okE, basicVal = pcall(function() return Enum.ImageType.Basic end)
            local isBasic = okE and (it == basicVal)
            probe[#probe + 1] = '图片类型 = ' .. tostring(it) ..
              (isBasic and '（基础 ✓ 正确）'
                or '（★ 拉伸 —— 请到图片模板里把「图片类型」改成基础，素材也别用三宫格/九宫格）')
          end
        end
        for k, word in pairs(want) do
          if found[k] == nil and type(t) == 'string' and t:find(word, 1, true) then found[k] = i end
        end
        pcall(game.DestroyClientUIControl, c)      -- 探针不留痕
      elseif not ok and #probe < 12 then
        probe[#probe + 1] = '索引 ' .. tostring(i) .. '：报错 ' .. tostring(c)
      end
    end
    if madeHere == 0 and #probe < 12 then
      probe[#probe + 1] = '范围 ' .. tostring(lo) .. '~' .. tostring(hi) .. '：一个都建不出来'
    end
  end
  return found, probe, built
end

-- 真正干活的初始化。任何一步失败都会被 OnInit 的 pcall 接住并显示在屏幕上。
function G.boot()
  local w, h = G.canvas.w, G.canvas.h
  G.seed = param('seed', 12345)
  G.autoNext = param('autoNext', 1) ~= 0

  local root = script.object
  local roots = game.GetClientUIRoots and game.GetClientUIRoots() or nil
  local rootCount = (roots and #roots) or 0
  -- ★ 官方定义：GetClientUIRoots() = "实际显示的客户端控件容器画布中的默认容器节点"。
  --   0 = 关卡运行时**没有显示中的画布**（容器没加进界面布局 / 初始可见没勾 / 玩家应用的布局不对）
  --   —— 这种情况下就算模板建好了也什么都看不见，所以单独报一声。
  say('客户端控件根控件数 = %s', tostring(rootCount))
  if rootCount == 0 then
    say('   ⚠ 运行时看不到任何 UI 根控件：请确认那个"客户端控件容器"是加在')
    say('      【界面控件组管理 → 界面布局】里、勾了【初始可见】，且参数配置窗口里玩家应用的就是这个布局')
  end
  if not root then
    root = roots and roots[1] or nil
  end
  if not root then error('找不到挂载控件：脚本要挂在**客户端控件**上（不能挂主屏）') end
  G.root = root
  root:SetActive(true)
  -- ★★ 光标常驻 + CursorEvent 的前置条件（官方 API 文档 §24 ClientUIContainerControl）：
  --     showCursor  boolean 读写 —— "是否显示常驻光标；**CursorEvent 相关方法都需设置该参数为真后
  --     才可正常使用**"。
  --   也就是说：不设它，玩家得**按住 Alt** 才能看见光标（用户实测就是这个），
  --   而且点击/光标事件也可能不生效。设上 = 光标常驻 + 事件正常。
  --   （编辑器里等价开关：容器节点控件 → 功能设置 → 【显示常驻光标】）
  do
    local targets = { root }
    if G.area and G.area ~= root then targets[#targets + 1] = G.area end
    local done = {}
    for i = 1, #targets do
      local c = targets[i]
      local ok, err = pcall(function() c.showCursor = true end)
      if ok then
        done[#done + 1] = tostring(c)
      else
        say('⚠ 设 showCursor 失败（%s）：%s', tostring(c), tostring(err))
      end
    end
    say('★ 已开"显示常驻光标" showCursor=true（%s）—— 不用再按住 Alt', table.concat(done, ' '))
  end
  -- ★ 挂载点（客户端控件容器）自己也要**有尺寸**：它在编辑器里如果是 0×0，
  --   我们挂进去的所有控件都会被裁掉 —— 表现就是"脚本全跑通了、屏幕上什么都没有"。
  --   ⚠ 只设尺寸、**不动位置**：位置由编辑器/布局决定，乱设会让整盘偏移。
  do
    local ok, err = pcall(function() root:SetSizeDelta(w, h) end)
    if G.zoom then say('显示缩放 zoom=%s（等比放大，规则数值未动）', tostring(G.zoom)) end
  say('把挂载点尺寸设成画布尺寸（%s x %s）：%s', tostring(w), tostring(h), ok and 'ok' or ('失败 ' .. tostring(err)))
  end
  say('挂载点 = %s', tostring(root))

  -- ★ 模板索引定下来：填了变量的用变量，没填的**自动认**（见 detectPrefabs 注释）
  local useAuto = param('autoPrefabs', 1) ~= 0
  local auto, probe, built = {}, {}, 0
  if useAuto then
    auto, probe, built = detectPrefabs(root)
    say('自动认模板：球=%s 文本=%s 光标=%s 容器=%s（探测共建出 %s 个控件）',
      tostring(auto.ballPrefab), tostring(auto.hudPrefab),
      tostring(auto.cursorPrefab), tostring(auto.playPrefab), tostring(built))
    for i = 1, #probe do say('   %s', probe[i]) end
    if not (auto.ballPrefab or auto.hudPrefab or auto.cursorPrefab or auto.playPrefab) then
      say('⚠ 两个索引空间都没找到客户端控件模板 —— 这就是屏幕空白的原因')
      say('   ① 模板要"存为模板"：界面控件组库 → 客户端控件模板 → 【添加客户端控件】→ 选类型 → 存为模板')
      say('   ② 实在找不到就把编辑器里点开控件看到的那个大数字（形如 1073741xxx）填进脚本变量：')
      say('      ballPrefab / hudPrefab / cursorPrefab（填了就优先用你填的）')
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

  -- ★★ 球面素材 id。
  --   真机事实（2026-09-25 用户实测）：**动态创建的图片控件不会继承模板/画布上那张图**，
  --   必须脚本自己 `SetImage(Enum.ImageSource.StaticReference, <资产号>)`，
  --   否则每个图片控件都画成"?"（球、轨道、中央核糖体全中招）。
  --   优先级：art=A:id,U:id,...（按碱基分别指定）> artImage=<id> > 画布里借一张 > 默认值。
  --   ⚠ 注意区分两个数字：**图片控件模板索引**（形如 1073741852）不是素材 id；
  --     素材 id 是编辑器里那张图的"**资产号**"。
  --   ★ 用户在编辑器里的三张图（2026-09-25 报的资产号）：
  --       100002 实心圆 → 球面/光晕/核糖体本体/背板
  --       100001 方块   → 轨道 / 配对连线 / 瞄准线（拉成长条，圆图会鼓出来）
  --       100006 空心圆 → 洞穴那几圈红环（本来就是"环"）
  local DEFAULT_ART = 100002       -- 实心圆
  local DEFAULT_BAR = 100001       -- 方块
  local DEFAULT_RING = 100006      -- 空心圆
  local art = {}
  local artAny = nil          -- 全局兜底资产号（光晕/核糖体/背板等不分碱基的控件用它）
  local artBar = tonumber(tostring(param('artBar', ''))) or DEFAULT_BAR    -- 棒（轨道/连线/瞄准线）
  local artRing = tonumber(tostring(param('artRing', ''))) or DEFAULT_RING -- 环（洞穴）
  do
    local spec = param('art', '')
    if type(spec) == 'string' and spec ~= '' then
      for pair in string.gmatch(spec, '[^,;%s]+') do
        local k, v = string.match(pair, '([AUGC]):(%d+)')
        if k and v then art[k] = tonumber(v) end
      end
    end
    if not next(art) then
      local one = tonumber(tostring(param('artImage', '')))
      if not one then
        local cand = adoptImageId(root)
        for i = 1, #cand do
          say('画布里发现一张配好图的控件：%s（%s）id=%s', cand[i].name, cand[i].t, tostring(cand[i].id))
        end
        if cand[1] then one = tonumber(tostring(cand[1].id)) end
      end
      if not one then
        one = DEFAULT_ART
        say('没在画布里借到图 → 用默认资产号 %s（要换就填 artImage=<资产号>）', tostring(DEFAULT_ART))
      end
      if one then
        artAny = one
        for i = 1, #CFG.BASES do art[CFG.BASES[i]] = one end
        say('★ 球面素材资产号 = %s（全部碱基共用；想分别指定就填 art=A:id,U:id,...）', tostring(one))
      say('★ 素材：实心圆=%s 方块(轨道/连线)=%s 空心圆(洞穴)=%s', tostring(one), tostring(artBar), tostring(artRing))
      end
    end
    if next(art) then
      local parts = {}
      for i = 1, #CFG.BASES do
        local b = CFG.BASES[i]
        if art[b] then parts[#parts + 1] = b .. '=' .. tostring(art[b]) end
      end
      say('球面素材 id：%s', table.concat(parts, ' '))
    else
      say('球面素材：没找到任何可用素材 id → 会画成"?"。请在画布里放一个配好图的图片控件，或填 artImage=<素材id>')
    end
  end

  -- ★★ imgTest=1：画一排"候选素材 id"格子（每格一个图片控件，下面一行小字写编号）。
  --   为什么需要它：真机上**动态创建的图片控件不会继承模板/画布上那张图**，必须脚本用
  --   SetImage(素材id) 指定；而"素材 id"在编辑器里是大数字，抄起来烦。
  --   做法：把 2^30 起的一段候选 id 挨个试一遍，用户**看一眼哪格是白圆图**，报编号即可。
  --   日志里同时打印"编号 -> id"的对应表（1 = 1073741825 …）。
  if param('imgTest', 0) ~= 0 then
    local base = tonumber(tostring(param('imgTestBase', ''))) or 1073741824
    local n = tonumber(tostring(param('imgTestCount', ''))) or 24
    local map = {}
    for i = 1, n do
      local id = base + i
      local x = -w / 2 + 36 + (i - 1) * 66
      local cell = game.InstantiateClientUIControl(G.prefabs.ball, G.area)
      if cell then
        cell:SetActive(true)
        cell:SetVisible(true)
        cell:SetSizeDelta(56, 56)
        cell:SetAnchoredPosition(x, h / 2 - 44)
        local ok = pcall(function() cell:SetImage(Enum.ImageSource.StaticReference, id) end)
        if not ok then say('  imgTest %s：SetImage 报错', tostring(id)) end
        local lab = game.InstantiateClientUIControl(G.prefabs.hud, G.area)
        if lab then
          lab:SetActive(true)
          lab:SetVisible(true)
          lab.text = tostring(i)
          lab.fontSize = 16
          lab.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
          lab:SetSizeDelta(60, 20)
          lab:SetAnchoredPosition(x, h / 2 - 82)
        end
        map[#map + 1] = tostring(i) .. '=' .. tostring(id)
      end
    end
    say('imgTest：上面那排格子的编号对应表 —— %s', table.concat(map, ' '))
    say('imgTest：哪一格是白圆图，就把格子编号（或那个 id）填进 artImage=…')
  end

  G.ui = UI.create({
    parent = G.area,
    canvas = G.canvas,
    art = art,
    artAny = artAny,
    artBar = artBar,
    artRing = artRing,
    cd = tonumber(tostring(param('cd', ''))) or 0,   -- 开火冷却环（本体没有 → 默认关）
    glow = tonumber(tostring(param('glow', ''))),    -- 球的描边/光晕总开关（默认开；0 = 全关）
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
    hud = buildHudSpecs(w, h, G.teach),
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

  -- ★ 洞穴状态（回答"洞穴看不到"这类问题：是本体规则、还是位置/图层）
  --   本体 render.js：`if (!(G.sc && G.sc.still)) drawCave(...)` —— **静止关本来就不画洞穴**。
  do
    local still = G.sc and G.sc.still
    local e = (G.sc and G.sc.path) and G.sc.path:pointAt(G.sc.path.length) or nil
    say('洞穴：静止关=%s 可见=%s 位置=%s,%s（静止关按本体规则不画）',
      tostring(still), tostring(not still),
      e and string.format('%.0f', e.x) or '?', e and string.format('%.0f', e.y) or '?')
    if e then
      say('  画布中心=%s,%s 洞穴离中心 %s,%s（画布 %sx%s）',
        string.format('%.0f', w / 2), string.format('%.0f', h / 2),
        string.format('%.0f', e.x - w / 2), string.format('%.0f', e.y - h / 2),
        string.format('%.0f', w), string.format('%.0f', h))
    end
  end

  -- ★★ 碱基抽样（排"打中全变灰 / 球发白"这类问题用）：
  --   若这里打出 nil，说明真机上**碱基没生成出来** → 球会是白的、且每次命中都判"错配"。
  --   若碱基正常而命中仍判错配，那就是"打中的是旁边那颗"（碰撞/瞄准）问题。
  do
    local balls = G.sc and G.sc.chain and G.sc.chain.balls or {}
    local sample = {}
    for i = 1, math.min(#balls, 8) do sample[#sample + 1] = tostring(balls[i].base) end
    say('球碱基抽样（共 %s 颗，前 8）：%s', tostring(#balls), table.concat(sample, ' '))
    local rb = G.sc and G.sc.rb or nil
    if rb and rb.loaded then
      say('核糖体待发碱基：%s / %s', tostring(rb.loaded[1]), tostring(rb.loaded[2]))
    end
    say('本关允许的碱基：%s', table.concat(G.sc and G.sc.bases or {}, ' '))
    -- ★ 待发球自检放到**第一次 UI.sync 之后**（见下面的 ⑨）—— 原来写在这里，
    --   而字母的 .text 是在 UI.sync 里才写进去的 ⇒ 这行**永远报"文字=空"**，
    --   测的不是真状态（用户就是这样被我误导了一轮）。
  end
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
  -- ⑨ ★ 待发球自检：**必须在上面这次 sync 之后**（字母的 .text 是 sync 里写的）。
  --   三项一起报，才能分清到底是哪一环：源碱基有没有 → 文字写进去没 → 可见/字号对不对。
  do
    local rb = G.sc and G.sc.rb
    local ui = G.ui
    local names = { '④炮口球', '③预备球' }     -- k=1 是炮口那颗、k=2 是身后那颗（本体 lb(1)/lb(0)）
    for k = 1, 2 do
      local src = rb and rb.loaded and rb.loaded[k]
      local lc = ui and ui.loadedLetter and ui.loadedLetter[k]
      -- ★ 一行里给出**完整对照**：源碱基 → 球颜色 → 控件文字/可见/字号/位置/控件尺寸
      --   缺哪一环一眼可见（源=nil → 球会是白的；文字=空 → 没写进去；可见=false → 被藏了）
      local ballHex = (src == nil) and '（源碱基 nil → 球会被画成白色！）' or '（有源）'
      say('%s：源碱基=%s %s 球半径=%.1f', names[k], tostring(src), ballHex,
        (k == 1) and ((G.sc.mode == 'insert') and G.sc.metrics.R or G.sc.metrics.r)
          or (((G.sc.mode == 'insert') and G.sc.metrics.R or G.sc.metrics.r) * 0.8))
      if lc then
        say('   控件：文字=[%s] 可见=%s 字号=%s 框尺寸=%.1fx%.1f 位置=(%.0f,%.0f)',
          tostring(lc.text), tostring(lc.visible), tostring(lc.fontSize),
          lc.sizeDeltaX or -1, lc.sizeDeltaY or -1,
          lc.anchoredPositionX or -999, lc.anchoredPositionY or -999)
      else
        say('   控件：**不存在**（ui.loadedLetter[%d] = nil，letters 关了？）', k)
      end
    end
  end
  return G.sc
end

-- ==================== 诊断行 ====================

-- ★ 这一行是"远程排错"的生命线：用户把屏幕上这句话念给我，我就知道卡在哪。
--   ⚠ 但出**错**时必须永远显示（那不属于"辅助线"，是救命的）—— 只有"正常状态那行"受 diag 开关控制。
function G.refreshDiag()
  local hc = G.diagControl
  if not hc then return end
  if not G.diag and not G.error then
    -- 没开辅助线、也没出错 → 这一格留空（空文字会被隐藏，屏幕上和本体一致）
    if hc.text ~= '' then hc.text = '' end
    return
  end
  local s
  if G.error then
    s = '!! ' .. G.error
  else
    local balls = G.sc and #G.sc.chain.balls or 0
    local pool = G.ui and #G.ui.balls or 0
    -- 控件总数 = ui 建的 + 脚本自己建的 3 个（诊断框 / 玩区 / 光标区）
    local ctrl = G.ui and (UI.count(G.ui) + 3) or 0
    -- ★ 诊断行里带上**轨道朝向**（出球道在内/在外）：这类"内外"的争论看一眼这行就有结论，
    --   不用再靠猜或互相描述（2026-09-25 为"内外"来回了好几轮，根因就是当时没这个信息）。
    local rail = G.level and G.level.railOrder
    local railTxt = (rail == 'spawn-outer') and '外' or (rail == 'spawn-inner') and '内' or '?'
    s = string.format('帧%d 关%s(出球道在%s) 球%d/%d 控件%d 状态%s', G.frames,
      tostring(G.level and G.level.id or '?'), railTxt, balls, pool, ctrl, G.screen)
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
-- ★★ 教玩家怎么打：手里这颗该打谁。
--   这是本作最容易误解的一点 —— 它是 **RNA 互补配对**（A↔U/T、G↔C），
--   **不是**祖玛那种"同色三消"。真机上用户"打中了却变灰"，九成就是打了同字母的球。
function G.mateText()
  if not G.sc or G.sc.mode ~= 'match' then return '' end
  local rb = G.sc.rb
  local b = rb and rb.loaded and rb.loaded[1]
  if not b then return '' end
  local c = CFG.COMPLEMENT[b] or {}
  if #c == 0 then return '手里 ' .. tostring(b) end
  -- ⚠ 文本框宽度有限（640），太长会被裁掉 —— 规则说明放在关卡提示里，这里只给结论
  return '手里 ' .. tostring(b) .. ' → 打 ' .. table.concat(c, '/') .. ' 的球'
end

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
  -- ★★ 判定诊断：每次命中都打一行「弹丸碱基 vs 目标球碱基 → 配对/错配」。
  --   真机第一次试玩"打中全变灰、也不进三消道"就只能靠这种行定位
  --   （要么碱基是 nil，要么判定反了，要么命中的是旁边那颗）。
  local events = G.sc and BOARD.drainEvents(G.sc) or nil
  if events then
    for i = 1, #events do
      local e = events[i]
      -- 事件的字段（见 board.resolveHit）：base = **弹丸**的碱基，target = **被打中那颗球**的碱基
      if e.type == 'pair' then
        G.lastHit = '上次命中：弹丸 ' .. tostring(e.base) .. ' 打中球 ' .. tostring(e.target) .. ' → 配对 ✅'
        say('%s', G.lastHit)
      elseif e.type == 'mismatch' then
        G.lastHit = '上次命中：弹丸 ' .. tostring(e.base) .. ' 打中球 ' .. tostring(e.target)
          .. ' → 错配 ❌（球变灰、绑定球也是灰的）'
        say('%s', G.lastHit)
      elseif e.type == 'insert' then
        G.lastHit = '上次命中：弹丸 ' .. tostring(e.base) .. ' 并入球 ' .. tostring(e.target) .. '（加球模式）'
        say('%s', G.lastHit)
      end
    end
  end
  return {
    dt = dt,
    events = events,   -- ★ 只有一个消费者：这里取走，别处再取就没了
    mode = G.sc and G.sc.mode or 'match',
    hintLines = lines,
    lastHit = G.lastHit,
    mate = G.mateText and G.mateText() or nil,
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

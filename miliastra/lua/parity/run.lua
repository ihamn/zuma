-- parity/run.lua —— 对拍的 **Lua 侧**解释器。
--
-- 设计要点：**命令表只写一次**（由 tools/parity.mjs 生成），JS 侧和 Lua 侧各写一个
-- 解释器去执行同一份命令表。这样"场景本身"不会两边各写一遍、各自漂移。
--
-- ⚠ 本文件是**本地验证工具**，允许用 io（千星奇域里 io 不可用）。
--   lua/src/ 下的任何文件都**不许**碰 io —— 那条约束由 tools/check-lua-sandbox.mjs 盯。
--
-- 用法：lua run.lua <命令文件>

local rngM = require('rng')
local CFG = require('config')
local MENU = { m = require('menu') }
local LEVELS_DATA = require('levels_data')
local GEO = require('geometry')
local SP = require('spines')
local RUN = require('run')
local CH = require('chain')
local PJ = require('projectile')

local function fmt(v)
  if v == nil then return 'nil' end
  if type(v) == 'boolean' then return v and 'true' or 'false' end
  if type(v) == 'string' then return v end
  if v ~= v then return 'nan' end
  if v == math.huge then return 'inf' end
  if v == -math.huge then return '-inf' end
  if math.type(v) == 'integer' then return tostring(v) end
  return string.format('%.12g', v)
end

local out = {}
local function emit(...)
  local parts = {}
  local n = select('#', ...)
  for i = 1, n do parts[i] = fmt((select(i, ...))) end
  out[#out + 1] = table.concat(parts, ' ')
end

-- level 参数：-1 表示"该字段不设"（对应 JS 的 undefined / null）
local function makeLevel(turns, budget, inner)
  if turns < 0 and budget < 0 and inner < 0 then return nil end
  local lv = {}
  if turns >= 0 then lv.turns = turns end
  if budget >= 0 then lv.ballBudget = budget end
  if inner >= 0 then lv.innerRatio = inner end
  return lv
end

local function makeSpine(kind, view, level)
  if kind == 1 then return SP.crossReturnSpine(view, level) end
  return SP.spiralSpine(view, level)
end

local handlers = {}

handlers.mark = function(a) emit('mark', a[1]) end

handlers.rng = function(a)
  local r = rngM.makeRng(a[1])
  local n = a[2]
  local vals = {}
  for i = 1, n do vals[i] = r() end
  emit('rng', a[1], table.unpack(vals))
end

handlers.rngint = function(a)
  local r = rngM.makeRng(a[1])
  local n, mod = a[2], a[3]
  local vals = {}
  for i = 1, n do vals[i] = r.int(mod) end
  emit('rngint', a[1], table.unpack(vals))
end

handlers.metrics = function(a)
  local m = CFG.metrics(a[1])
  emit('metrics', a[1], m.p, m.R, m.r, m.d, m.linkGap, m.diameterRatio, m.areaRatio)
end

-- 开始菜单（§61）：和 JS 侧 parity-js.mjs 的 'menu' 分支一一对应。
--   布局用的是**移植侧** menu.lua（本体 config.js 的 1:1 移植），对拍就是证明它没抄错。
--   mode: 0 = 条目表、1 = 布局、其它 = 局内按钮 + 命中判定（a[5..] 是坐标对）
handlers.menu = function(a)
  local w, h, scale, mode = a[1], a[2], a[3], a[4]
  local v = CFG.viewFor(w, h)
  local mt = CFG.metrics(scale)
  local items = MENU.m.items(LEVELS_DATA.LEVELS, LEVELS_DATA.TUTORIAL_COUNT)
  if mode == 0 then
    emit('menu.items', #items, LEVELS_DATA.TUTORIAL_COUNT or 0)
    for i = 1, #items do
      emit('menu.item', items[i].index + 1, (items[i].group == '新手关') and 1 or 0, items[i].label)
    end
  elseif mode == 1 then
    local L = MENU.m.layout(v, mt, items)
    emit('menu.layout', L.x0, L.innerW, L.cols, L.bw, L.bh, L.titleY, L.footerY, #L.buttons, #L.groups)
    for i = 1, #L.buttons do
      local b = L.buttons[i]
      emit('menu.btn', b.x, b.y, b.w, b.h, b.item.index + 1)
    end
    for i = 1, #L.groups do emit('menu.group', L.groups[i].name, L.groups[i].y) end
  else
    local pb = MENU.m.playButtonRect(v, mt)
    emit('menu.playbtn', pb.x, pb.y, pb.r)
    local L = MENU.m.layout(v, mt, items)
    for i = 5, #a, 2 do
      local px, py = a[i], a[i + 1]
      local it = MENU.m.pick(L, px, py)
      emit('menu.pick', px, py, it and (it.index + 1) or 0)
    end
  end
end

handlers.view = function(a)
  local v = CFG.viewFor(a[1], a[2])
  emit('view', a[1], a[2], v.cx, v.cy, v.rx, v.ry, v.scale, v.portrait and 1 or 0)
end

handlers.turns = function(a)
  local v = CFG.viewFor(a[2], a[3])
  emit('turns', a[1], SP.turnsForBudget(v, a[1]))
end

handlers.spine = function(a)
  local kind, turns, budget, inner = a[1], a[2], a[3], a[4]
  local v = CFG.viewFor(a[5], a[6])
  local fn = makeSpine(kind, v, makeLevel(turns, budget, inner))
  local n = a[7]
  local vals = {}
  for i = 0, n do
    local q = fn(i / n)
    vals[#vals + 1] = q.x
    vals[#vals + 1] = q.y
  end
  emit('spine', kind, turns, budget, inner, table.unpack(vals))
  if fn.junctionU then emit('spine.junction', kind, fn.junctionU) end
end

handlers.path = function(a)
  local kind, turns, budget, inner = a[1], a[2], a[3], a[4]
  local v = CFG.viewFor(a[5], a[6])
  local samples = a[7]
  local fn = makeSpine(kind, v, makeLevel(turns, budget, inner))
  local path = GEO.buildPath(fn, { samples = samples, center = { x = v.cx, y = v.cy } })
  emit('path.head', kind, path.length, path:samples())
  for i = 8, #a do
    local u = a[i]
    local s = path:sAtU(u)
    local p = path:pointAt(s)
    local nn = path:normalAt(s)
    emit('path', u, s, p.x, p.y, nn.x, nn.y, path:zAt(s))
  end
end

handlers.curv = function(a)
  local kind, turns, budget, inner = a[1], a[2], a[3], a[4]
  local v = CFG.viewFor(a[5], a[6])
  local samples = a[7]
  local fn = makeSpine(kind, v, makeLevel(turns, budget, inner))
  local path = GEO.buildPath(fn, { samples = samples, center = { x = v.cx, y = v.cy } })
  local vals = {}
  for i = 8, #a do
    local k = a[i]           -- 0 基采样下标
    vals[#vals + 1] = GEO.curvatureAt(path.pts, k + 1)
  end
  emit('curv', table.unpack(vals))
end

-- marks：数字串，0=空 1=正确配对 2=错误配对 3=已配对但未定型(dock<1)
handlers.marks = function(a, raw)
  local s = raw[1]   -- ★ 必须用原始 token：'0110' 当数字会变成 110
  local chain = { balls = {} }
  for i = 1, #s do
    local c = tonumber(s:sub(i, i))
    local b = { id = i, wp = 0, r = 19 }
    if c == 1 or c == 2 or c == 3 then b.paired = true end
    if c == 2 then b.wrongMark = true end
    if c == 3 then b.dock = 0.5 end
    chain.balls[i] = b
  end
  local finals, docked = {}, {}
  for i = 1, #chain.balls do
    finals[i] = RUN.markFinal(chain.balls[i])
    docked[i] = RUN.isDocked(chain.balls[i]) and 1 or 0
  end
  emit('marks.final', table.unpack(finals))
  emit('marks.docked', table.unpack(docked))
  emit('marks.explosion', RUN.findExplosion(chain))
  local runs = RUN.computeRuns(chain)
  local flat = {}
  for i = 1, #runs do
    flat[#flat + 1] = runs[i].i0
    flat[#flat + 1] = runs[i].i1
    flat[#flat + 1] = runs[i].len
  end
  emit('marks.runs', #runs, table.unpack(flat))
  emit('marks.clearable', #RUN.clearableRuns(chain))
end

-- chain：确定性操作序列，两侧共用同一套 op 选择规则（rng 已先被 rng 用例证明一致）
handlers.chain = function(a)
  local seed, steps, dt = a[1], a[2], a[3]
  local curveLength = a[4]
  if curveLength < 0 then curveLength = nil end
  local prefill = a[5]
  local r = rngM.makeRng(seed)
  local mt = CFG.metrics(1)
  local ch = CH.makeChain(mt, {})
  if prefill > 0 then
    CH.prefillChain(ch, prefill, function(i) return CFG.BASES[(i % 5) + 1] end)
  end
  for step = 1, steps do
    local op = r.int(12)
    if op <= 5 then
      CH.advanceChain(ch, dt, curveLength)
    elseif op == 6 then
      ch.freezeTime = 0.3
      CH.advanceChain(ch, dt, curveLength)
    elseif op == 7 then
      CH.spawnBall(ch, CFG.BASES[r.int(5) + 1], nil)
    elseif op == 8 then
      local idx = r.int(#ch.balls + 1) + 1
      local dist = r() * 120
      CH.applyBackward(ch, idx, 30, dist)
      CH.advanceChain(ch, dt, curveLength)
    elseif op == 9 then
      CH.drainHead(ch, curveLength and (curveLength * 0.9) or 0)
    elseif op == 10 then
      if #ch.balls >= 2 then
        local i0 = r.int(#ch.balls) + 1
        local i1 = r.int(#ch.balls - i0 + 1) + i0
        CH.removeRange(ch, i0, i1)
      end
    else
      CH.recycleFront(ch)
    end
    local parts = { 'ch', step, #ch.balls, ch.speed, ch.stopTime, ch.freezeTime,
                    ch.stats.spawned, ch.stats.drained, ch.stats.removed, ch.stats.leftField or 0,
                    #CH.chainRuns(ch) }
    for i = 1, #ch.balls do
      local b = ch.balls[i]
      parts[#parts + 1] = string.format('%s:%s:%s:%s', fmt(b.wp), b.base or '-', b.id,
                                        b.backLeft and b.backLeft or -1)
    end
    emit(table.unpack(parts))
  end
end

-- sweep：弹丸扫掠命中
handlers.sweep = function(a)
  local seed, n = a[1], a[2]
  local r = rngM.makeRng(seed)
  local balls = {}
  for i = 1, n do
    balls[i] = { x = r() * 800, y = r() * 800, r = 10 + r() * 12, paired = (r() < 0.3) }
  end
  local mt = CFG.metrics(1)
  for k = 1, 12 do
    local x0, y0 = r() * 800, r() * 800
    local x1, y1 = r() * 800, r() * 800
    local pr = 8 + r() * 10
    local hit = PJ.sweepHit(balls, x0, y0, x1, y1, pr, true)
    if hit then
      emit('sweep', k, hit.index, hit.t, hit.x, hit.y)
    else
      emit('sweep', k, -1)
    end
  end
  emit('sweep.metrics', mt.p)
end

-- ==================== level / board：整局对拍 ====================
--
-- ★ 关卡数据来自**命令文件里的 level 行**（由 tools/parity.mjs 生成），
--   JS 侧和 Lua 侧各自把它还原成自己的 level 结构。数据只写一次，两边不会漂。

local BOARD = require('board')
local RB = require('ribosome')

local LEVELS = {}

local FLAG_STILL, FLAG_CENTER, FLAG_NOCLEAR, FLAG_MATCHALL, FLAG_LAYERS =
  1, 2, 4, 8, 16

handlers.level = function(a, raw)
  local idx = a[1]
  local sig, turnsv, budget, inner = a[2], a[3], a[4], a[5]
  local prefill, flags, startFrac, speedv, railSign, sTgt, basesMask = a[6], a[7], a[8], a[9], a[10], a[11], a[12]
  local script = raw[13]
  if script == '-' then script = nil end
  local lv = {
    id = 'L' .. idx,
    spineKind = sig,
    railOrder = railSign > 0 and 'spawn-outer' or 'spawn-inner',
  }
  if turnsv >= 0 then lv.turns = turnsv end
  if inner >= 0 then lv.innerRatio = inner end
  lv.ballBudget = budget
  lv.prefill = prefill
  lv.still = (flags % 2 >= 1)
  lv.centerChain = ((math.floor(flags / FLAG_CENTER)) % 2 == 1)
  lv.noClear = ((math.floor(flags / FLAG_NOCLEAR)) % 2 == 1)
  if ((math.floor(flags / FLAG_MATCHALL)) % 2 == 1) then lv.goal = 'matchAll' end
  lv.layersFromJunction = ((math.floor(flags / FLAG_LAYERS)) % 2 == 1)
  if startFrac >= 0 then lv.startWpFrac = startFrac end
  if speedv >= 0 then lv.speed = speedv end
  lv.scoreTarget = (sTgt < 0) and math.huge or sTgt
  if basesMask > 0 then
    local b = {}
    for i = 1, #CFG.BASES do
      if math.floor(basesMask / (2 ^ (i - 1))) % 2 == 1 then b[#b + 1] = CFG.BASES[i] end
    end
    lv.bases = b
  end
  if script then lv.script = script end
  lv.insertMode = ((math.floor(flags / 32)) % 2 == 1)   -- flags bit5 = 加球模式
  LEVELS[idx] = lv
end

handlers.board = function(a)
  local lvIdx, seed, frames, dt, firePct, fireMode, dumpEvery = a[1], a[2], a[3], a[4], a[5], a[6], a[7]
  local lv = LEVELS[lvIdx]
  if not lv then error('level not defined: ' .. tostring(lvIdx)) end
  local view = CFG.viewFor(900, 900)
  local sc = BOARD.assembleScene(lv, view, seed)
  if lv.insertMode then BOARD.setMode(sc, 'insert') end
  local drv = rngM.makeRng(seed * 7919 + 13)

  local function dump(tag, frame)
    local parts = { tag, frame, #sc.chain.balls,
      string.format('%.12g', sc.score), sc.lives, sc.spawnCount,
      sc.won and 1 or 0, sc.winReason or '-', sc.gameOver and 1 or 0, sc.losing and 1 or 0,
      sc.stats.fired, sc.stats.pairs, sc.stats.mismatches, sc.stats.merges,
      sc.stats.cleared, sc.stats.codons, sc.stats.lost, sc.stats.explosions,
      string.format('%.12g', sc.chain.speed), string.format('%.12g', #sc.chain.balls > 0 and sc.chain.balls[1].wp or 0) }
    for i = 1, #sc.chain.balls do
      local b = sc.chain.balls[i]
      parts[#parts + 1] = string.format('%s:%s:%s:%s:%s:%s',
        fmt(b.wp), b.base, RUN.markFinal(b), b.pairBase or '-',
        b.dock and fmt(b.dock) or '-', b.backLeft and b.backLeft or -1)
    end
    emit(table.unpack(parts))
  end

  dump('b0', 0)
  for f = 1, frames do
    if fireMode > 0 and drv() < firePct / 100 then
      local bs = sc.chain.balls
      if #bs > 0 then
        local pick = drv.int(#bs) + 1
        if fireMode == 2 then
          local found = 0
          for k = 0, #bs - 1 do
            local j = ((pick - 1 + k) % #bs) + 1
            if not bs[j].paired then found = j; break end
          end
          pick = found
        end
        if pick > 0 then
          RB.aimAt(sc.rb, bs[pick].x, bs[pick].y)
          BOARD.fireShot(sc)
        end
      end
    end
    BOARD.advanceScene(sc, dt)
    if dumpEvery > 0 and f % dumpEvery == 0 then dump('b', f) end
  end
  dump('bend', frames)
end

-- 主循环
local file = arg[1]
for line in io.lines(file) do
  line = line:gsub('^%s+', ''):gsub('%s+$', '')
  if line ~= '' and line:sub(1, 1) ~= '#' then
    local toks = {}
    for t in line:gmatch('%S+') do toks[#toks + 1] = t end
    local cmd = table.remove(toks, 1)
    local h = handlers[cmd]
    if not h then error('unknown command: ' .. cmd) end
    local args = {}
    for i = 1, #toks do args[i] = tonumber(toks[i]) end
    h(args, toks)   -- 原始 token 也传进去（marks 这类命令要的是字符串）
  end
end

io.write(table.concat(out, '\n'), '\n')

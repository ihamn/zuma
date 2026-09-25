-- input.lua —— 输入层：光标/按键 -> 瞄准角与"要做什么"的意图。
--
-- ★ 这一层**不直接调 board**：它只改 sc.rb.aim（瞄准是输入的事）并留下意图标志，
--   由 game.lua 决定什么时候真的开火/换球/切模式。这样输入层可以单独测。

local CFG = require('config')
local RB = require('ribosome')

local M = {}

-- 画布 UI 坐标（官方：以画布**左下角**为原点，y 向上）
-- -> board 坐标（画布像素、原点左上、y 向下）
function M.toBoard(canvas, x, y)
  return x, canvas.h - y
end

-- opts:
--   area       CursorEventArea 控件（铺满玩区的那块）
--   keyTarget  挂键盘监听的控件（一般是画布根控件）
--   canvas     { w, h }
--   stick      是否也用手柄摇杆瞄准（默认关）
function M.create(opts)
  opts = opts or {}
  local canvas = opts.canvas or { w = 900, h = 900 }
  local inp = {
    canvas = canvas,
    firing = false,        -- 按住 = 连发（冷却由 DESIGN.fireCooldown 管）
    pending = 0,           -- 一次性开火（模拟点击会给一个）
    wantSwap = false,
    wantMode = false,
    wantRestart = false,
    useCursor = true,
    stickX = 0, stickY = 0,
    hold = false,
    stats = { clicks = 0, keys = 0, fires = 0 },
  }

  local area = opts.area
  if area then
    area:AddCursorEventListener(Enum.CursorEventType.CursorDown, function(d)
      inp.hold = true
      inp.stats.clicks = inp.stats.clicks + 1
    end)
    area:AddCursorEventListener(Enum.CursorEventType.CursorUp, function()
      inp.hold = false
    end)
    area:AddCursorEventListener(Enum.CursorEventType.CursorClick, function(d)
      inp.pending = inp.pending + 1
      inp.stats.clicks = inp.stats.clicks + 1
      -- ★ 菜单/按钮要用"点在哪"。官方 API 直接给光标坐标（左下原点、y 向上），
      --   这里立刻换算成**棋盘坐标**存下来 —— 不依赖回调参数 d 的形状（那个没文档保证）。
      local ok, gx, gy = pcall(game.GetCursorUIPos)
      if ok and type(gx) == 'number' and type(gy) == 'number' then
        local bx, by = M.toBoard(inp.canvas, gx, gy)
        inp.clickX, inp.clickY = bx, by
      end
    end)
  end

  local kt = opts.keyTarget
  if kt then
    -- ★★ 真机契约（2026-09-25 真机日志）：
    --   1. `Enum.KeyEventType` 是**逐键**成员 —— `KeyboardNormalAttackKeyDown`、
    --      `KeyboardCharacterSkill3KeyDown`、`KeyboardJumpKeyDown` …（官方文档里 164 个），
    --      **没有** `KeyDown` / `KeyUp` 这种通用成员。第一版按通用名写，真机直接报
    --      `bad argument #2 to 'AddKeyEventListener' (KeyEventType expected, got nil)`。
    --   2. 回调**没有参数**（不是"给你一个键码让你自己比"），注册哪个键就代表哪个键；
    --      返回 true = 已处理（容器内其他控件不再响应这次按键）。
    --   3. 成员名在不同版本可能微调 → 这里按候选名**探测**，缺哪个就在日志里点名，
    --      而不是让整局崩在这一行。
    local KEYMAP = {
      { 'fireDown', { 'KeyboardNormalAttackKeyDown', 'ControllerNormalAttackKeyDown' } },
      { 'fireUp', { 'KeyboardNormalAttackKeyUp', 'ControllerNormalAttackKeyUp' } },
      { 'modeDown', { 'KeyboardOpenShortcutWheelKeyDown' } },          -- Tab：切模式
      { 'swapDown', { 'KeyboardJumpKeyDown', 'ControllerJumpKeyDown' } }, -- 空格：换手里那颗
      { 'restartDown', { 'KeyboardCharacterSkill3KeyDown' } },         -- R：重开本关
    }

    local function pick(cands)
      for i = 1, #cands do
        local v = Enum.KeyEventType[cands[i]]
        if v ~= nil then return v, cands[i] end
      end
      return nil, cands[1]
    end

    -- 不依赖控件的日志通道（和 game.lua 一样：挂了也要说清是哪个键没注册上）
    local function log(fmt, a, b)
      if not print then return end
      local ok, s = pcall(string.format, fmt, a, b)
      if not ok then s = tostring(fmt) end
      pcall(print, '[zuma] ' .. s)
    end

    local handlers = {
      fireDown = function()
        inp.hold = true
        inp.stats.keys = inp.stats.keys + 1
        return true
      end,
      fireUp = function()
        inp.hold = false
        return true
      end,
      modeDown = function() inp.wantMode = true; return true end,
      swapDown = function() inp.wantSwap = true; return true end,
      restartDown = function() inp.wantRestart = true; return true end,
    }

    local bound = {}
    for i = 1, #KEYMAP do
      local act, cands = KEYMAP[i][1], KEYMAP[i][2]
      local et, name = pick(cands)
      if et == nil then
        log('⚠ 按键事件 %s 在这台机器上不存在（试过：%s）—— 这个操作暂时用不了', act, name)
      else
        local ok, err = pcall(function() kt:AddKeyEventListener(et, handlers[act]) end)
        if ok then
          bound[#bound + 1] = act .. '=' .. name
        else
          log('⚠ 注册按键事件 %s 失败：%s', name, tostring(err))
        end
      end
    end
    log('按键绑定：%s', table.concat(bound, ' '), nil)
  end

  return inp
end

-- 每帧：更新瞄准角，并把意图整理成 inp.firing / wantXxx
function M.update(inp, sc, dt)
  if inp.useCursor then
    local gx, gy = game.GetCursorUIPos()
    local bx, by = M.toBoard(inp.canvas, gx, gy)
    RB.aimAt(sc.rb, bx, by)
  elseif inp.stickX ~= 0 or inp.stickY ~= 0 then
    sc.rb.aim = math.atan(inp.stickY, inp.stickX)
  end

  inp.firing = (inp.hold or inp.pending > 0)
  return inp
end

-- 开火意图被消费掉之后调用
function M.consume(inp)
  inp.pending = 0
  inp.clickX, inp.clickY = nil, nil
end

return M

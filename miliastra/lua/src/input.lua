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
    end)
  end

  local kt = opts.keyTarget
  if kt then
    local KC = Enum.KeyboardKeyCode
    kt:AddKeyEventListener(Enum.KeyEventType.KeyDown, function(code)
      inp.stats.keys = inp.stats.keys + 1
      if code == KC.NormalAttackKey then
        inp.hold = true
        return true
      elseif code == KC.TabKey then
        inp.wantMode = true
        return true
      elseif code == KC.KeyR then
        inp.wantRestart = true
        return true
      elseif code == KC.SpaceJumpKey then
        inp.wantSwap = true
        return true
      end
      return false
    end)
    kt:AddKeyEventListener(Enum.KeyEventType.KeyUp, function(code)
      if code == KC.NormalAttackKey then
        inp.hold = false
        return true
      end
      return false
    end)
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
end

return M

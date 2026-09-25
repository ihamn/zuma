-- 开始菜单（DESIGN.md §61）—— src/config.js 的 menuItems / menuLayout / menuButtonRect 的 Lua 移植。
--
-- 为什么单独一个模块：这三样是**纯计算**（条目表、按钮矩形、命中判定），
--   JS 侧和 Lua 侧必须一模一样 —— 所以它们进对拍（parity）当证据，而不是"看着差不多"。
--   ★ 与本体一一对应：
--     menuItems      = main.js  rebuild() 里那段 ALL_LEVELS.map(...)
--     menuLayout     = config.js  menuLayout(view, mt, items)
--     menuButtonRect = config.js  menuButtonRect(view, mt)   （局内左下角"菜单"按钮）

local CFG = require('config')

local M = {}

-- 菜单条目：新手关用关卡全名，核心关带序号（本体 main.js 原文）
--   label: tut ? (l.name || l.short) : ((i + 1) + ' ' + (l.short || l.name))
function M.items(levels, tutorialCount)
  local out = {}
  for i = 1, #levels do
    local l = levels[i]
    local tut = i <= (tutorialCount or 0)
    local label
    if tut then
      label = l.name or l.short
    else
      label = tostring(i) .. ' ' .. (l.short or l.name)
    end
    out[i] = {
      index = i - 1,                       -- 本体是 0 基；这里保留 0 基，方便和本体逐值对拍
      group = tut and '新手关' or '核心关',
      label = label,
    }
  end
  return out
end

-- 菜单布局：竖屏（窄）2 列、横屏/桌面 4 列（本体 config.js 原文，逐式照搬）
--   view: { w, h, cx, cy }   mt: { scale }
function M.layout(view, mt, items)
  local s = (mt and mt.scale) or 1
  local W, H = view.w, view.h
  local narrow = W < 640
  local cols = narrow and 2 or 4
  local pad = math.max(10, 18 * s)
  local gapX, gapY = 9 * s, 8 * s
  local innerW = math.min(W - pad * 2, narrow and (440 * s) or (760 * s))
  local x0 = (W - innerW) / 2
  local bh = math.max(36, 50 * s)
  local bw = (innerW - gapX * (cols - 1)) / cols
  local buttons, groups = {}, {}
  local y = math.max(76 * s, H * 0.26)
  local col, last = 0, nil
  for i = 1, #items do
    local it = items[i]
    if it.group ~= last then
      if last ~= nil then y = y + bh + gapY + 24 * s end   -- 换组：留出组标题的位置
      groups[#groups + 1] = { name = it.group, y = y }
      y = y + 20 * s
      col = 0
      last = it.group
    end
    buttons[#buttons + 1] = {
      x = x0 + col * (bw + gapX), y = y, w = bw, h = bh, item = it, index = i - 1,
    }
    col = col + 1
    if col >= cols then col = 0; y = y + bh + gapY end
  end
  return {
    x0 = x0, innerW = innerW, cols = cols, bw = bw, bh = bh,
    buttons = buttons, groups = groups,
    titleY = math.max(40 * s, H * 0.14),
    footerY = H - math.max(22 * s, 30 * s),
  }
end

-- 命中的是哪个条目（本体 main.js onPointerDown 里那段矩形判定）
--   返回 item（含 index），点空处返回 nil
function M.pick(layout, x, y)
  for i = 1, #layout.buttons do
    local b = layout.buttons[i]
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      return b.item
    end
  end
  return nil
end

-- 局内左下角「回菜单」按钮（本体 config.js menuButtonRect）
function M.playButtonRect(view, mt)
  local s = (mt and mt.scale) or 1
  local r = 22 * s
  local pad = 26 * s
  return { x = r + pad, y = view.h - r - pad, r = r }
end

-- 点是否落在按钮的判定圈里（本体用 r*1.3 的宽松判定：手指友好）
function M.hitButton(btn, x, y, k)
  k = k or 1.3
  local dx, dy = x - btn.x, y - btn.y
  return (dx * dx + dy * dy) <= (btn.r * k) * (btn.r * k)
end

return M

-- config.lua —— src/config.js 的 Lua 5.3 移植。
-- 数值一律与 config.js 逐字对应；改数值只改这里（对应本体的"只改一个文件"约定）。

local M = {}

M.BASES = { 'A', 'U', 'G', 'C', 'T' }

-- 互补配对表（不对称：A 是唯一的双配碱基）
M.COMPLEMENT = {
  A = { 'U', 'T' },
  U = { 'A' },
  T = { 'A' },
  G = { 'C' },
  C = { 'G' },
}

-- 颜色（第二通道）。互补碱基的颜色互为反色。
M.BASE_COLOR = {
  A = '#e05cff', T = '#5cc93f', U = '#9dff7a', G = '#33b8ff', C = '#ff6b33',
}
M.BASE_INK = {
  A = '#1c0a24', T = '#0d2205', U = '#132a08', G = '#04203a', C = '#2b0f04',
}
M.WRONG_COLOR = '#6b7280'
M.WRONG_INK = '#0b1220'
M.WRONG_GLOW = '#ff5555'

function M.complementColor(base)
  local c = M.COMPLEMENT[base]
  if c then return M.BASE_COLOR[c[1]] end
  return '#ffffff'
end

M.DESIGN = {
  base = 900,
  spawnRadius = 19,
  smallDiameterRatio = 1 / math.sqrt(2),
  railClearance = 9.0,
  beadGap = 1.5,
  pathSamples = 2400,
  outerFit = 0.45,
  outerFitWide = 0.62,
  outerFitTall = 0.86,
  minScale = 0.82,
  innerRatio = 0.32,
  turns = 1.9,

  chainSpeed = 42,
  chainAccel = 30,
  chainDecel = 620,
  slowDistance = 0,
  slowFactor = 2.6,

  ribosomeRadius = 30,
  fireCooldown = 0.16,
  shotSpeed = 1150,
  shotRadiusRatio = 0.9,
  shotMaxLife = 3.0,
  dockTime = 0.30,
  readWindow = 0.30,

  startLives = 3,
  ballBudget = 0,
  scoreTarget = 500,
  winOnClear = true,
  scorePerBall = 10,
  losingSpeed = 1500,

  mergeTime = 0.26,
  defaultMode = 'match',

  elemFreezeTime = 3.0,
  elemAutoPairCount = 3,
  elemSwirlRange = 2,
  elemBurnTime = 3.0,
  elemBurnTick = 0.25,
  elemCoreLife = 6.0,
  elemCoreMax = 5,
  elemReactionDepth = 4,
  elemShieldMax = 3,
  elemScorePerReaction = 10,
  reactionFlashTime = 1.2,
  elemHints = true,
  hintMaxCount = 4,
  modeFlashTime = 0.28,

  bagBias = 1.0,
  retreatTime = 0.22,
  backFrames = 30,
  backStopFrames = 20,
  insertPairs = false,
}

M.Z = { projectile = 50, actor = 60, fx = 70, hud = 100 }

function M.metrics(scale)
  local D = M.DESIGN
  local R = D.spawnRadius * scale
  local r = R * D.smallDiameterRatio
  local d = R + r + D.railClearance * scale
  local linkGap = D.beadGap * scale
  local p = 2 * R + linkGap
  return {
    scale = scale,
    R = R,
    r = r,
    d = d,
    p = p,
    linkGap = linkGap,
    diameterRatio = R / r,
    areaRatio = (R * R) / (r * r),
  }
end

function M.viewFor(w, h)
  local D = M.DESIGN
  local base = math.min(w, h)
  local scale = math.max(base / D.base, math.min(D.minScale, base / 450))
  local portrait = h > w * 1.25
  local capX = base * D.outerFitWide
  local capY = base * (portrait and D.outerFitTall or D.outerFitWide)
  return {
    w = w, h = h, dpr = 1,
    cx = w / 2, cy = h / 2,
    rx = math.min(w * D.outerFit, capX),
    ry = math.min(h * D.outerFit, capY),
    base = base, scale = scale, portrait = portrait,
  }
end

-- 模式按钮矩形（render / main 共用一份）
function M.modeButtonRect(view, mt)
  local r = 40 * mt.scale
  local pad = 26 * mt.scale
  return { x = view.w - r - pad, y = view.h - r - pad, r = r }
end

function M.menuButtonRect(view, mt)
  local r = 22 * mt.scale
  local pad = 26 * mt.scale
  return { x = r + pad, y = view.h - r - pad, r = r }
end

function M.isComplement(tRNA, mRNA)
  local c = M.COMPLEMENT[mRNA]
  if not c then return false end
  for i = 1, #c do if c[i] == tRNA then return true end end
  return false
end

-- ==================== 经典祖玛专用配色（DESIGN.md §66.6）====================
-- 奇匠要求："原版球的颜色不要沿用，重新搞"。
-- ★ 内部 token 仍是 A/U/C/G/T（规则/对拍/控件池一律不动），只换**显示颜色**。
M.CLASSIC_COLOR = {
  A = '#e8453c',   -- 红
  U = '#f2c53d',   -- 黄
  G = '#3b7ddd',   -- 蓝
  C = '#3fbf6f',   -- 绿
  T = '#9a5bd6',   -- 紫
}
M.CLASSIC_INK = {
  A = '#2a0705', U = '#2b2205', G = '#04122b', C = '#052a12', T = '#1b0733',
}

-- 按 ruleset 取色：'classic' 用经典那套，其它（含缺省）用 RNA 碱基色
function M.colorOf(base, rules)
  local t = (rules == 'classic') and M.CLASSIC_COLOR or M.BASE_COLOR
  return t[base] or '#ffffff'
end
function M.inkOf(base, rules)
  local t = (rules == 'classic') and M.CLASSIC_INK or M.BASE_INK
  return t[base] or '#101820'
end

return M

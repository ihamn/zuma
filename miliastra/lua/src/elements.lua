-- elements.lua —— src/elements.js 的 Lua 5.3 移植（**部分**）。
--
-- ⚠ 只移植了"匹配/加球模式跑得起来"所需的部分：七元素表 + canAttach / elemName / elemColor。
--   **反应表（REACTIONS / sevenReaction / beadElemsFor）没有移植** ——
--   七球模式已被用户明确搁置（§65「先不管」），移植它没有意义。
--   如果以后要做，照 elements.js 逐条抄数据即可（它是考证结论，不是平衡数值）。
--
-- 为什么必须先有 canAttach：核糖体的 loadedElem 初始化要抽两次元素，
-- **这会消耗确定性随机数**（rng 的调用次数必须与 JS 完全一致，否则整条链全错位）。

local M = {}

M.ELEMENTS = { 'pyro', 'hydro', 'cryo', 'electro', 'dendro', 'geo', 'anemo' }

M.ELEM = {
  pyro    = { name = '火', color = '#ff7a45', ink = '#3a1204', attachable = true },
  hydro   = { name = '水', color = '#49b6ff', ink = '#04223a', attachable = true },
  cryo    = { name = '冰', color = '#a8ecff', ink = '#0b2b38', attachable = true },
  electro = { name = '雷', color = '#c08cff', ink = '#220b3a', attachable = true },
  dendro  = { name = '草', color = '#8ede52', ink = '#10300a', attachable = true },
  geo     = { name = '岩', color = '#ffc94d', ink = '#3a2604', attachable = false },
  anemo   = { name = '风', color = '#6fe8c8', ink = '#0a332a', attachable = false },
}

M.QUICK = 'quick'

function M.canAttach(elem)
  local e = M.ELEM[elem]
  return (e ~= nil) and (e.attachable == true)
end

function M.elemName(elem)
  if elem == M.QUICK then return '激' end
  local e = M.ELEM[elem]
  return e and e.name or '—'
end

function M.elemColor(elem)
  if elem == M.QUICK then return '#d9f24a' end
  local e = M.ELEM[elem]
  return e and e.color or '#8899aa'
end

return M

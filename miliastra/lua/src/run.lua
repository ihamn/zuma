-- run.lua —— src/run.js 的 Lua 5.3 移植。三消道的 3N 消除。纯逻辑。
--
-- 记号：x_i ∈ {0,1} 表示序列里第 i 颗主链球是否"已被读出"。
-- ★ 这里的"序列"就是 chain.balls 的顺序：balls[1] = 洞端，balls[#balls] = 出球端。

local M = {}

-- 标记是否已"定型"（吸附飞行结束）。1 和 2 都算标记，只是含义不同。
function M.isMarked(b)
  return b.paired == true and (b.dock == nil or b.dock >= 1)
end

-- 定型后的状态值：0 = 空、1 = 正确配对、2 = 错误配对。
function M.markFinal(b)
  if not M.isMarked(b) then return 0 end
  return b.wrongMark == true and 2 or 1
end

-- 一颗球是否"已被读出"（x=1）：**正确**配对，且吸附飞行已完成。
-- 注意：错误配对（2）在这里和 0 一样返回 false —— 所以 2 会像 0 一样断开 run。
function M.isDocked(b)
  return M.isMarked(b) and b.wrongMark ~= true
end

-- ★ 爆炸判定（DESIGN.md §32 / §34）。返回下标（1 基），无则返回 -1。
function M.findExplosion(chain)
  local balls = chain.balls
  for i = 2, #balls - 1 do
    if M.markFinal(balls[i]) == 2 then
      local l = M.markFinal(balls[i - 1])
      local r = M.markFinal(balls[i + 1])
      if l ~= 0 and r ~= 0 then
        if (l == 1) == (r == 1) then return i end
      end
    end
  end
  return -1
end

-- run = 标记序列上的极大连续区间（只看序列相邻，与出球道的物理空隙无关）
function M.computeRuns(chain)
  local balls = chain.balls
  local runs = {}
  local cur = nil
  for i = 1, #balls do
    local b = balls[i]
    if not M.isDocked(b) then
      cur = nil
    else
      if cur == nil then
        cur = { i0 = i, i1 = i, len = 1, key = b.id }
        runs[#runs + 1] = cur
      else
        cur.i1 = i
        cur.len = cur.len + 1
      end
    end
  end
  return runs
end

-- 当前所有"该消"的段：长度是 3 的倍数且 >= 3
function M.clearableRuns(chain)
  local out = {}
  local runs = M.computeRuns(chain)
  for i = 1, #runs do
    local r = runs[i]
    if r.len >= 3 and r.len % 3 == 0 then out[#out + 1] = r end
  end
  return out
end

-- 给渲染用的读数
function M.runStatus(run)
  local mod = run.len % 3 == 0
  return {
    len = run.len,
    mod = mod,
    toNext = mod and 0 or (3 - (run.len % 3)),
  }
end

return M

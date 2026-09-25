-- 复现探针：绑定小球（3n 道）控件被回收时，是否带着上一颗球的"炸开"缩放出现？
-- 用户线索：新手第 1 关没有、第 2 关开始有（第 2 关起会发生"消除"）。
local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')

H.suite('绑定小球复位')

local CANVAS = 900
local host = MOCK.newHost({ w = CANVAS, h = CANVAS })
host.prefabs[1] = 'image'
host.prefabs[2] = 'textbox'
host.prefabs[3] = 'cursorarea'
host.params.ballPrefab = 1
host.params.shotPrefab = 1
host.params.hudPrefab = 2
host.params.cursorPrefab = 3
host.params.playPrefab = 1
host.params.ballCount = 96
host.params.shotCount = 8
host.params.seed = 20240923
host.params.autoNext = 0
MOCK.install(host)
host.scriptObj.object = host.root
host.mount(GAME)

local function cursorAt(b) return b.x, CANVAS - b.y end

for _, name in ipairs({ 't1-pair', 't2-multiple', 't3-wrong' }) do
  local idx
  for i = 1, #require('levels_data').LEVELS do
    if require('levels_data').LEVELS[i].id == name then idx = i end
  end
  GAME.startLevel(idx)
  local sc = GAME.sc
  local worst, worstFrame, worstIdx = 1, 0, 0
  local gone = 0
  for f = 1, 4000 do
    local bs = sc.beads.spawn
    local pick = nil
    for i = 1, #bs do
      if not bs[i].paired then pick = bs[i]; break end
    end
    if pick then host.click(cursorAt(pick)) end
    host.tick(1 / 60)
    -- 统计还在跑的 'gone' 动效 + 扫所有可见绑定小球的缩放
    for i = 1, #GAME.ui.fx do
      if GAME.ui.fx[i].kind == 'gone' then gone = gone + 1 end
    end
    for i = 1, #GAME.ui.elim do
      local c = GAME.ui.elim[i]
      if c and c.visible and (c.localScaleX or 1) > worst then
        worst, worstFrame, worstIdx = c.localScaleX, f, i
      end
    end
    if GAME.screen ~= 'playing' then break end
  end
  print(string.format('  【%s】可见绑定小球最大缩放 = %.3f（第 %d 帧，控件 #%d）；gone 动效累计 %d 次；结束时场上球 %d',
    name, worst, worstFrame, worstIdx, gone, #sc.beads.eliminate))
  H.ok(worst <= 1.15, string.format('★ %s：可见的绑定小球缩放必须 ≈1（>1.15 就是"异常增大"）实际 %.3f', name, worst))
end

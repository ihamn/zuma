-- 性能/预算基线：每帧的"引擎调用次数"（真机上每一调用都是成本）+ 控件数。
-- 用 level 8（最忙的一关：96 球池 + 128 轨道段 + 洞穴）跑 600 帧统计。
local H = require('harness')
local MOCK = require('mock')
local GAME = require('game')
local UI = require('ui')

H.suite('性能基线')

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
host.params.seed = 4242
host.params.autoNext = 0
host.params.skipMenu = 1
host.params.diag = 1
MOCK.install(host)
host.scriptObj.object = host.root
host.mount(GAME)

local function level8()
  for i = 1, #require('levels_data').LEVELS do
    if require('levels_data').LEVELS[i].id == 'spiral-outer' then return i end
  end
  return 8
end
GAME.startLevel(level8())
host.tick(1 / 60)

local ctrl = UI.count(GAME.ui) + 3
local N = 600
local t0 = os.clock()
for _ = 1, N do host.tick(1 / 60) end
local ms = (os.clock() - t0) * 1000 / N

print(string.format('  控件数 = %d（平台上限 1000）', ctrl))
print(string.format('  每帧：UI 字段写入 %d 次（球 %d / HUD %d），引擎 SetImage %d 次',
  GAME.ui.stats.writes, GAME.ui.stats.ballWrites, GAME.ui.stats.hudWrites, host.stats.setImage or -1))
print(string.format('  %d 帧耗时 %.0f ms/帧（⚠ 这是 Fengari 解释器的速度，不代表真机；只用来看"相对变化"）', N, ms))

-- ---------- 优化项钉成断言（免得以后悄悄退化）----------
-- ① 控件预算：轨道段数 64→40 之后应当 ≤ 820（省下 48 个给以后用；平台硬上限 1000）
H.ok(ctrl <= 820, '★ 控件数 ≤ 820（当前 ' .. ctrl .. '；轨道段数 40 省了 48 个）')
-- ② 菜单布局必须**缓存复用**（原来是每帧新分配十几张表 → 真机 GC 抖动）
local L1 = GAME.menuLayoutCached()
local L2 = GAME.menuLayoutCached()
H.ok(L1 == L2, '★ 菜单布局是同一张表（缓存生效，没有每帧重建）')
-- ③ 游玩时根本不算菜单布局（syncMenu 只在菜单态读它）
GAME.screen = 'playing'
H.eq(GAME.syncState(1 / 60).menuLayout, nil, '★ 游玩时 syncState 不带菜单布局（零成本）')
GAME.screen = 'menu'
H.ok(GAME.syncState(1 / 60).menuLayout ~= nil, '菜单态才带菜单布局')

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
host.params.ballCount = 80
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

local tree = 0
for _ in pairs(host.controls or {}) do tree = tree + 1 end
print(string.format('  控件总数 = %d（平台上限：单控件组 1000）；假宿主实际建出 %d 个', ctrl, tree))
local u = GAME.ui
print(string.format('    球池 %d ｜ 弹药 %d ｜ 并入球 %d ｜ 连线 %d ｜ 绑定小球 %d',
  #u.balls, #u.shots, #u.merges, #u.links, #u.elim))
print(string.format('    轨道 %d ｜ 光晕 %d ｜ 球面字母 %d ｜ 绑定球字母 %d ｜ 待发球字母 %d',
  #u.track, #u.halo, #u.letter, #u.elimLetter, #(u.loadedLetter or {})))
print(string.format('    洞穴 %d ｜ 核糖体/瞄准/冷却 3 ｜ HUD %d ｜ 菜单 %d',
  #u.caveGlow + 2, #u.hudOrder, 6 + #u.menu.groups + #u.menu.btn * 2 + 2))
print(string.format('    画布/玩区/光标区/诊断框 4 个由脚本另建 → 合计 %d', ctrl))
print(string.format('  每帧：UI 字段写入 %d 次（球 %d / HUD %d），引擎 SetImage %d 次',
  GAME.ui.stats.writes, GAME.ui.stats.ballWrites, GAME.ui.stats.hudWrites, host.stats.setImage or -1))
print(string.format('  %d 帧耗时 %.0f ms/帧（⚠ 这是 Fengari 解释器的速度，不代表真机；只用来看"相对变化"）', N, ms))

-- ---------- 优化项钉成断言（免得以后悄悄退化）----------
-- ① 控件预算：轨道段数 64→40 之后应当 ≤ 820（省下 48 个给以后用；平台硬上限 1000）
-- ① M.count 必须**跟着真机建出来的控件数**（原来漏算 101：绑定球字母池 96 + 背板 + 待发球描边/字母 4）。
--   脚本自己建的 3~4 个（画布/光标区/诊断框…）不在 ui.count 里，所以允许 ≤3 的差。
H.ok(math.abs(ctrl - tree) <= 3,
  '★ ui.count 必须对得上真机建出的控件数：脚本报 ' .. ctrl .. ' / 假宿主实际 ' .. tree)
-- ② 平台硬上限（《编辑项范围限制》：单控件组 1000）
H.ok(tree <= 1000, '★ 控件数在平台上限内：' .. tree .. ' / 1000（余量 ' .. (1000 - tree) .. '）')
-- ② 菜单布局必须**缓存复用**（原来是每帧新分配十几张表 → 真机 GC 抖动）
local L1 = GAME.menuLayoutCached()
local L2 = GAME.menuLayoutCached()
H.ok(L1 == L2, '★ 菜单布局是同一张表（缓存生效，没有每帧重建）')
-- ③ 游玩时根本不算菜单布局（syncMenu 只在菜单态读它）
GAME.screen = 'playing'
H.eq(GAME.syncState(1 / 60).menuLayout, nil, '★ 游玩时 syncState 不带菜单布局（零成本）')
GAME.screen = 'menu'
H.ok(GAME.syncState(1 / 60).menuLayout ~= nil, '菜单态才带菜单布局')

import io, sys
def sub(path, old, new, tag, cnt=1):
    s = io.open(path, encoding='utf-8').read()
    n = s.count(old)
    if n != cnt: print('!! ' + tag + ' 命中 ' + str(n)); sys.exit(1)
    io.open(path, 'w', encoding='utf-8').write(s.replace(old, new)); print('ok  ' + tag)

# ---- render.js：删掉局内关卡按钮行 ----
s = io.open('src/render.js', encoding='utf-8').read()
i0 = s.index('// 关卡按钮（右上角一排）')
i1 = s.index('// 按顺序画所有珠子')
io.open('src/render.js', 'w', encoding='utf-8').write(s[:i0] + s[i1:])
print('ok  render.js 删掉 drawLevelButtons')
sub('src/render.js', "  drawModeButton(ctx, G);\n  drawMenuButton(ctx, G);\n  drawLevelButtons(ctx, G);\n  drawRunBadges(ctx, G);",
"  drawModeButton(ctx, G);\n  drawMenuButton(ctx, G);\n  drawRunBadges(ctx, G);", 'render 去掉调用')
sub('src/render.js', "modeButtonRect, levelButtonRect, menuLayout, menuButtonRect } from './config.js';",
"modeButtonRect, menuLayout, menuButtonRect } from './config.js';", 'render 去掉导入')

# ---- main.js：删掉点击分支与导入 ----
sub('src/main.js', "import { metrics, viewFor, modeButtonRect, levelButtonRect, menuLayout, menuButtonRect, DESIGN } from './config.js';",
"import { metrics, viewFor, modeButtonRect, menuLayout, menuButtonRect, DESIGN } from './config.js';", 'main 去掉导入')
sub('src/main.js', """  // 右上角关卡按钮：点它换关，不发射（键盘 1-9 在手机上是按不到的）
  const nLv = ALL_LEVELS.length;
  if (nLv > 1) {
    for (let i = 0; i < nLv; i++) {
      const lb = levelButtonRect(G.view, G.metrics, i, nLv);
      if (Math.hypot(p.x - lb.x, p.y - lb.y) <= lb.r * 1.3) {
        if (i !== G.levelIndex) setLevel(i);
        return;
      }
    }
  }
  // 右下角模式按钮""",
"""  // 换关走左下角「菜单」（§61）—— 原来右上角那排 12 个小圆点是"没有菜单时的权宜之计"，
  // 现在有两个换关入口反而更乱，删掉。
  // 右下角模式按钮""", 'main 去掉关卡按钮分支')

# ---- config.js：删掉 levelButtonRect ----
s = io.open('src/config.js', encoding='utf-8').read()
i0 = s.index('// 关卡按钮的矩形（render 画、main 判点击，共用一份）。')
i1 = s.index('// 固定层级带（DESIGN.md §3.2）')
io.open('src/config.js', 'w', encoding='utf-8').write(s[:i0] + s[i1:])
print('ok  config.js 删掉 levelButtonRect')

# ---- smoke：把关卡按钮那组换成菜单按钮 ----
sub('tools/smoke.mjs', "import { modeButtonRect, levelButtonRect } from '../src/config.js';",
"import { modeButtonRect, menuButtonRect, menuLayout } from '../src/config.js';", 'smoke 导入')

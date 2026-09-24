import io, sys
def sub(path, old, new, tag):
    s = io.open(path, encoding='utf-8').read()
    n = s.count(old)
    if n != 1: print('!! ' + tag + ' 命中 ' + str(n)); sys.exit(1)
    io.open(path, 'w', encoding='utf-8').write(s.replace(old, new)); print('ok  ' + tag)

# 删掉 lineSpine（结构上不可用）
s = io.open('src/spines.js', encoding='utf-8').read()
i0 = s.index('// ★ §63 直线骨架')
i1 = s.index('// ★★ §62 轨道长度')
io.open('src/spines.js', 'w', encoding='utf-8').write(s[:i0] + s[i1:])
print('ok  删掉 lineSpine')

# 在 §62 的注释里补上"为什么至少要一段弧"
sub('src/spines.js', """//   ⚠ 无尽关（ballBudget = 0）不套这条 —— 它的球数没有上限，轨道要按最长的来。""",
"""//   ⚠ 无尽关（ballBudget = 0）不套这条 —— 它的球数没有上限，轨道要按最长的来。
//
// ★★ §63 但**不能短到没有弧度**（曾经想把练习关做成一条直线，做不到）：
//   球距 39.5、球半径 19 —— 球几乎是挨着的，所以**在任何距离上，相邻两颗的视角都几乎重叠**
//   （垂直距离 h 处，相邻球夹角 atan(39.5/h)，而一颗球的视角宽 2·asin(19/dist)，
//   两者在任何 h 下都只差不到 1°）。直线排布实测：12 发里 5 发擦到隔壁那颗。
//   螺旋/弧线不一样 —— 球分布在不同半径上，每一颗都有独立的角度，所以打得准。
//   结论：练习关用 0.75 圈的小弧（球正好铺满），而不是直线，也不是 1.9 圈的大螺旋。""", '补注释')

# levels.js：练习关改用小弧
L = 'src/levels.js'
sub(L, "import { spiralSpine, crossReturnSpine, lineSpine } from './spines.js';",
"import { spiralSpine, crossReturnSpine } from './spines.js';", '去掉 lineSpine 导入')
for tag in ['① 反色', '② 三的倍数', '③ 五色球', '④ 配错的代价']:
    pass
s = io.open(L, encoding='utf-8').read()
n = s.count("    makeSpine: lineSpine,      // ★ 直线：这一课不需要轨道") + \
    s.count("    makeSpine: lineSpine,")
s = s.replace("    makeSpine: lineSpine,      // ★ 直线：这一课不需要轨道\n", "    makeSpine: spiralSpine,\n    turns: 0.75,               // ★ 一小段弧：球正好铺满，没有多余的空轨道\n")
s = s.replace("    makeSpine: lineSpine,\n", "    makeSpine: spiralSpine,\n    turns: 0.75,\n")
io.open(L, 'w', encoding='utf-8').write(s)
print('ok  四关改用 0.75 圈小弧（替换了 ' + str(n) + ' 处）')

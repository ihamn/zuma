import io, sys
def sub(path, old, new, tag):
    s = io.open(path, encoding='utf-8').read()
    n = s.count(old)
    if n != 1: print('!! ' + tag + ' 命中 ' + str(n)); sys.exit(1)
    io.open(path, 'w', encoding='utf-8').write(s.replace(old, new)); print('ok  ' + tag)

# ---------- A. scene.js：静止 = 速度归零，而不是跳过推进 ----------
sub('src/scene.js', """  // ★ §63 静止练习关：链子**一点都不动**。
  //   只挡住冒球和失败是不够的 —— 那样链子还会以 42/s 往洞口爬，
  //   "静止"就名不副实（测试里的"60 秒后队头没动"当场抓到了这一条）。
  if (!sc.still) advanceChain(ch, dt, sc.path.length);""",
"""  // ★ §65 静止练习关：**速度归零**，但绳模型照常跑。
  //   ⚠ 不能整个跳过 advanceChain —— 那样"插入一颗把珠串顶开"就不工作了，
  //     ④ 加球那一关会直接叠在一起（绳模型的推动就在 advanceChain 里）。
  //   速度 0 的效果是：队尾不前进，但推动/缝合照旧 —— 这正是"静止"要的东西。
  advanceChain(ch, dt, sc.path.length);""", '静止=速度归零')

sub('src/scene.js', "  if (level.speed != null) chain.targetSpeed = level.speed * mt.scale;",
"""  // ★ §65 静止关速度归零（但绳模型继续跑，见 advanceScene 里的注释）
  if (level.still) chain.targetSpeed = 0;
  else if (level.speed != null) chain.targetSpeed = level.speed * mt.scale;""", '静止关速度 0')

sub('src/scene.js', "  if (sc.level.speed != null) chain.targetSpeed = sc.level.speed * sc.metrics.scale;",
"  if (sc.level.still) chain.targetSpeed = 0;\n  else if (sc.level.speed != null) chain.targetSpeed = sc.level.speed * sc.metrics.scale;", '重开也归零')

# ---------- B. main.js：模式按钮只切 匹配 <-> 加球 ----------
sub('src/main.js', """// 模式：改场景 + 记在 G 上（rebuild 时贴回去）
// §57：三种模式 —— 匹配（RNA 碱基）/ 加球 / 七球（元素）。
// ★ 七球模式是**一层**：球的身份就是元素，**匹配本身就是元素反应**
//   （用户原话「直接来个七球模式，匹配相当于元素反应」）。
function applyMode(m) {
  G.mode = (m === 'insert') ? 'insert' : ((m === 'seven') ? 'seven' : 'match');
  if (G.sc) setMode(G.sc, G.mode);
  return G.mode;
}
function cycleMode() {
  const order = ['match', 'insert', 'seven'];
  return applyMode(order[(order.indexOf(G.mode) + 1) % order.length]);
}""",
"""// 模式：改场景 + 记在 G 上（rebuild 时贴回去）
// ★ §65 右下角按钮**只在 匹配 <-> 加球 之间切**。
//   用户：「七球模式请不要加入右下角的切换按钮，我们先不管」——
//   七球（元素）那套代码留着，但不上按钮：它现在是个没定型的试验，
//   摆在玩家的模式循环里只会让人误以为它是个正式玩法。
//   需要它时用 __ZUMA__.setMode('seven')（测试与探针就是这么用的）。
function applyMode(m) {
  G.mode = (m === 'seven') ? 'seven' : ((m === 'insert') ? 'insert' : 'match');
  if (G.sc) setMode(G.sc, G.mode);
  return G.mode;
}
function cycleMode() {
  return applyMode(G.mode === 'insert' ? 'match' : 'insert');
}""", '模式按钮只剩两态')

# ---------- C. render.js：按钮不再画七球 ----------
sub('src/render.js', """  // §57：三态循环 匹配 -> 加球 -> 元素。颜色和缩略珠子都跟着模式变，
  // 玩家不用读字也知道现在这一发是干什么的。
  const isIns = sc.mode === 'insert';
  const isElem = sc.mode === 'seven';
  const accent = isIns ? '#ff9a3c' : (isElem ? '#c08cff' : '#2fd6c6');""",
"""  // ★ §65 按钮只表示 匹配 <-> 加球 两态（七球不上按钮，见 main.js 的注释）。
  //   颜色和缩略珠子都跟着模式变，玩家不用读字也知道这一发是干什么的。
  const isIns = sc.mode === 'insert';
  const isElem = false;
  const accent = isIns ? '#ff9a3c' : '#2fd6c6';""", '按钮两态')
io.open('src/render.js', 'w', encoding='utf-8').write(io.open('src/render.js', encoding='utf-8').read())
print('render 按钮注释已改')

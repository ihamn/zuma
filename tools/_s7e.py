import io, sys
R = 'src/render.js'
s = io.open(R, encoding='utf-8').read()
def sub(old, new, tag):
    global s
    n = s.count(old)
    if n != 1: print('!! ' + tag + ' 命中 ' + str(n)); sys.exit(1)
    s = s.replace(old, new); print('ok  ' + tag)

sub("""function drawBead(ctx, x, y, r, base, glow, color, ink, glowColor, elem, frozen) {
  const fill = color || BASE_COLOR[base];
  const textInk = ink || BASE_INK[base];""",
"""// label = 球面上的字（匹配模式是碱基字母，七球模式是元素汉字：火水冰雷草岩风）
function drawBead(ctx, x, y, r, label, glow, color, ink, glowColor, frozen) {
  const fill = color || BASE_COLOR[label] || '#8899aa';
  const textInk = ink || BASE_INK[label] || '#101820';""", 'drawBead 签名简化')

sub("""  // ★ §57 元素附着：内圈一道元素色环。
  //   半径取 0.80r、环宽 0.28r（覆盖 0.66r~0.94r）—— 碱基字母最宽约 ±0.30r，
  //   所以两者不会打架。外面那圈留给 pairGlow（互补碱基色），两套信息互不遮挡。
  if (elem) {
    // ⚠ 先画一道**深色隔离环**：元素色可能和碱基色同色相（绿碱基 + 草附着、
    //   蓝碱基 + 水附着），没有隔离环的话那一圈看起来只是"球的明暗"，玩家读不出"有没有附着"。
    ctx.beginPath();
    ctx.arc(x, y, r * 0.92, 0, TAU);
    ctx.strokeStyle = 'rgba(6,10,18,0.92)';
    ctx.lineWidth = Math.max(2, r * 0.16);
    ctx.stroke();
    // ★ 元素带画成 **4 段断开的弧**，不是整圈。
    //   理由：元素色和碱基色会撞色相（橙碱基 C + 火 #ff7a45、蓝碱基 G + 水 #49b6ff、
    //   绿碱基 U + 草 #8ede52）—— 画成整圈时那一圈会被读成"球的明暗渐变"，
    //   玩家分不出"有没有附着"。断开之后用**形状**通道说话，撞色也不影响判断。
    ctx.strokeStyle = elemColor(elem);
    ctx.lineWidth = Math.max(2.4, r * 0.30);
    const seg = TAU / 4;
    for (let k = 0; k < 4; k++) {
      ctx.beginPath();
      ctx.arc(x, y, r * 0.78, k * seg + 0.24, (k + 1) * seg - 0.24);
      ctx.stroke();
    }
  }

""", "", '移除元素附着带')

sub("  ctx.fillText(base, x, y + r * 0.06);", "  ctx.fillText(label, x, y + r * 0.06);", 'drawBead 画 label')

sub("""      drawBead(ctx, b.x, b.y, b.r, b.base, b.paired === true,
        b.wrong ? WRONG_COLOR : null, b.wrong ? WRONG_INK : null, b.pairGlow,
        b.elem, b.frozen);""",
"""      drawBead(ctx, b.x, b.y, b.r, b.label || b.base, b.paired === true,
        b.wrong ? WRONG_COLOR : (b.col || null), b.wrong ? WRONG_INK : (b.ink || null),
        b.pairGlow, b.frozen);""", '链上球画 label')

sub("    drawBead(ctx, m.x, m.y, m.r, m.base, true, null, null, null, m.elem, 0);",
"    drawBead(ctx, m.x, m.y, m.r, m.base, true, null, null, null, 0);", '并入球调用')

sub("""  const le = rb.loadedElem || [null, null];
  drawBead(ctx, rb.x - Math.cos(rb.aim) * R * 0.7, rb.y - Math.sin(rb.aim) * R * 0.7,
    bR * 0.8, rb.loaded[1], false, null, null, null, le[1], 0);
  drawBead(ctx, rb.x + Math.cos(rb.aim) * R * 0.8, rb.y + Math.sin(rb.aim) * R * 0.8,
    bR * 1.0, rb.loaded[0], true, null, null, null, le[0], 0);""",
"""  // 七球模式下手里装的就是元素 -> 直接按元素配色 + 汉字画；匹配模式仍是碱基字母
  const sv = sc.mode === 'seven';
  const tk = function (k) { return sv ? elemColor(rb.loaded[k]) : null; };
  const ik = function (k) { return sv && ELEM[rb.loaded[k]] ? ELEM[rb.loaded[k]].ink : null; };
  const lb = function (k) { return sv ? elemGlyph(rb.loaded[k]) : rb.loaded[k]; };
  drawBead(ctx, rb.x - Math.cos(rb.aim) * R * 0.7, rb.y - Math.sin(rb.aim) * R * 0.7,
    bR * 0.8, lb(1), false, tk(1), ik(1), null, 0);
  drawBead(ctx, rb.x + Math.cos(rb.aim) * R * 0.8, rb.y + Math.sin(rb.aim) * R * 0.8,
    bR * 1.0, lb(0), true, tk(0), ik(0), null, 0);""", '核糖体七球配色')

sub("    drawBead(ctx, p.x, p.y, p.r, p.base, false, null, null, null, p.elem, 0);",
"""    const svp = sc.mode === 'seven';
    drawBead(ctx, p.x, p.y, p.r, svp ? elemGlyph(p.base) : p.base, false,
      svp ? elemColor(p.base) : null, null, null, 0);""", '弹丸七球配色')

sub("import { findReaction } from './scene.js';", "import { findSevenReaction } from './scene.js';", 'render 导入 findSevenReaction')
sub("import { elemColor, elemName, ELEM } from './elements.js';",
"import { elemColor, elemName, elemGlyph, ELEM } from './elements.js';", 'render 导入 elemGlyph')

sub("""  if (!sc || sc.mode !== 'element' || !DESIGN.elemHints) return;
  const rb = sc.rb;
  if (!rb || !rb.loaded || !rb.loadedElem) return;
  const bead = rb.loaded[0], trig = rb.loadedElem[0];
  if (!bead || !trig) return;""",
"""  if (!sc || sc.mode !== 'seven' || !DESIGN.elemHints) return;
  const rb = sc.rb;
  if (!rb || !rb.loaded) return;
  const bead = rb.loaded[0];
  if (!bead) return;""", '提示改七球')

sub("""    if (b.paired) continue;                       // 已占用的球打不中
    if (!isComplement(bead, b.base)) continue;    // 碱基配不上 = 废弹，不提示
    const hit = findReaction(sc, i, trig);
    if (!hit) continue;                           // 不会反应就别标，保持画面干净
    const r = hit.reaction;""",
"""    if (b.paired) continue;                       // 已占用的球打不中
    const r = findSevenReaction(sc, i, bead);     // 没反应 = 打上去是废弹，不提示
    if (!r) continue;""", '提示判定改七球')

sub("""    ctx.fillStyle = elemColor(trig);
    ctx.fillText(txt, b.x, by + bh - 2);""",
"""    ctx.fillStyle = elemColor(bead);
    ctx.fillText(txt, b.x, by + bh - 2);""", '提示配色')

# HUD：七球模式显示手里两颗元素
sub("""  if (G.sc && G.sc.mode === 'element' && ii0) {
    ctx.font = '600 ' + Math.max(11, Math.round(14 * mt.scale)) + 'px system-ui, sans-serif';
    ctx.fillStyle = 'rgba(225,235,255,0.92)';
    const le = G.sc.rb && G.sc.rb.loadedElem ? G.sc.rb.loadedElem : [null, null];
    ctx.fillText('盾 ' + ii0.shields + '   核 ' + ii0.cores + '   反应 ' + ii0.reactions +
      '   装载 ' + elemName(le[0]) + '/' + elemName(le[1]), 16, 14 + 58 * mt.scale);""",
"""  if (G.sc && G.sc.mode === 'seven' && ii0) {
    ctx.font = '600 ' + Math.max(11, Math.round(14 * mt.scale)) + 'px system-ui, sans-serif';
    ctx.fillStyle = 'rgba(225,235,255,0.92)';
    const le = ii0.loaded || [null, null];
    ctx.fillText('盾 ' + ii0.shields + '   核 ' + ii0.cores + '   反应 ' + ii0.reactions +
      '   装载 ' + elemName(le[0]) + '/' + elemName(le[1]), 16, 14 + 58 * mt.scale);""", 'HUD 七球')

# 模式按钮：元素 -> 七球
sub("""  const isIns = sc.mode === 'insert';
  const isElem = sc.mode === 'element';""",
"""  const isIns = sc.mode === 'insert';
  const isElem = sc.mode === 'seven';""", '模式按钮七球')

sub("  ctx.fillText(isIns ? '加球' : (isElem ? '元素' : '匹配'), btn.x, btn.y + btn.r * 0.52);",
"  ctx.fillText(isIns ? '加球' : (isElem ? '七球' : '匹配'), btn.x, btn.y + btn.r * 0.52);", '模式按钮文案')

io.open(R, 'w', encoding='utf-8').write(s)
print('render.js 完成')

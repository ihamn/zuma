// 设计常量：全部长度都是"设计单位"，运行时乘 scale 得到像素。
// 依据 DESIGN.md §2.3。任何数值调整只改这一个文件。

export const BASES = ['A', 'U', 'G', 'C', 'T'];

// 互补配对表（不对称：A 是唯一的双配碱基）。唯一真源，U8 直接使用。
export const COMPLEMENT = {
  A: ['U', 'T'],
  U: ['A'],
  T: ['A'],
  G: ['C'],
  C: ['G'],
};

// 颜色（第二通道）。★ 设计原则：**互补碱基的颜色必须互为反色**。
//   这样玩家不需要背配对表：发跟它颜色相反的那颗就是配对，纯知觉操作。
//   GC 一族：G 青蓝(201度) <-> C 橙(17度)    ATU 一族：A 紫红(288度) <-> T 绿(107度) / U 亮绿(104度)
//   T 与 U 同色相、不同明度：既能分辨，又都近似 A 的反色（两者都是 A 的配对对象）。
export const BASE_COLOR = {
  A: '#e05cff',   // 288度 紫红 —— 反色是绿色系
  T: '#5cc93f',   // 107度 绿
  U: '#9dff7a',   // 104度 亮绿（与 T 同族，明度更高）
  G: '#33b8ff',   // 201度 青蓝 —— 反色是橙色
  C: '#ff6b33'    //  17度 橙
};
export const BASE_INK = {
  A: '#1c0a24',
  T: '#0d2205',
  U: '#132a08',
  G: '#04203a',
  C: '#2b0f04'
};

// 错误配对（mark = 2）的配色：低饱和灰 + 警示红 —— 不抢眼，但一眼能看出"坏了"
export const WRONG_COLOR = '#6b7280';
export const WRONG_INK = '#0b1220';
export const WRONG_GLOW = '#ff5555';

// 某碱基的配对对象应显示的颜色（用于给大球描一圈「该发什么色」的提示）
export function complementColor(base) {
  const c = COMPLEMENT[base];
  return c && c.length ? BASE_COLOR[c[0]] : '#ffffff';
}

export const DESIGN = {
  base: 900,                          // 短边设计基准
  spawnRadius: 19,                    // 出球道大球半径 R
  smallDiameterRatio: 1 / Math.SQRT2, // 三消道直径 / 出球道直径 = 1/√2 -> 直径比 √2:1、面积比 2:1
  railClearance: 9.0,                 // 两轨之间的净空。原来 3.2，球边缘只剩 2px 缝，配对连线没地方画                 // 两轨之间的净空
  beadGap: 1.5,                       // 同轨相邻球净空（= 绳模型的 linkGap）
  pathSamples: 2400,
  outerFit: 0.45,
  outerFitWide: 0.62,   // 横向拉伸上限
  outerFitTall: 0.86,   // 竖屏时纵向拉伸上限（用满手机高度）
  minScale: 0.82,       // scale 下限（自适应，见 viewFor）：手机竖屏上球要够大、能瞄
  innerRatio: 0.32,
  turns: 1.9,

  // 珠串推进（U3）：手感沿用原版——加速慢、减速快（约 20:1）
  chainSpeed: 42,     // 目标速度（设计单位/秒）
  chainAccel: 30,     // 加速（设计单位/秒²）
  chainDecel: 620,    // 减速（设计单位/秒²）
  slowDistance: 0,    // B7 冻结：减速带关掉（置 0 即禁用；原版是 340）
  slowFactor: 2.6,    // 减速带末端的速度分母

  // U6/U7/U8 发射与配对
  ribosomeRadius: 30,     // 核糖体半径（设计单位）
  fireCooldown: 0.16,     // 两发之间的最小间隔（秒）
  shotSpeed: 1150,        // 弹丸速度（设计单位/秒）
  shotRadiusRatio: 0.9,   // 弹丸半径 = 三消道小球半径 × 该系数
  shotMaxLife: 3.0,       // 弹丸存活上限（秒）
  dockTime: 0.30,         // 配对吸附飞行时长（秒）
  readWindow: 0.30,       // U9 识别窗口（A14 的加码容错），纯手感参数

  // U11 生命与计分（A15：失败条件与祖玛一致）
  startLives: 3,
  // ★ 过关条件（DESIGN.md §50）：照原版 Board.cpp:620-644 —— 原版是**分数达标**过关，
  //   不是"清空场上球"（清空只是暂时，链子会从出球口继续补）。
  //   达到目标后：停冒球 + 台上剩下的球引爆（原版 DetonateBalls）。
  // ★★ 每关的球数预算。**0 = 无限出球**（对应原版 CurveDesc::mNumBalls == 0，
  //   原版把它叫 endless）。要有限关卡就写正数。
  //
  //   历史：我一度把它当"让清零过关可达"的手段 -> 那是**治标**。
  //   真正的病是"手里那颗珠子过期了没人换"（见下方 scoreTarget 附近的说明），
  //   修好之后无限出球本来就撑得住（清球 1.23 颗/秒 > 冒球 1.06 颗/秒），预算可以撤。
  ballBudget: 0,
  // 分数目标。>0 时达标过关（原版 Board::mScoreTarget 的同构，endless 也是靠它升级）。
  //   500 分 ≈ 清 50 颗 ≈ 41 秒（按 1.23 颗/秒），是个合适的关卡长度。
  scoreTarget: 500,
  // 另一个过关条件：**场上清空**。正常玩法里链子会立刻从出球口补上，所以「空」只可能
  // 来自「你把整场清光了」（比如只剩 3 颗 mark=2，一次爆炸全带走）。模糊测试会关掉它。
  winOnClear: true,          // 原版 Board::mLives = 3
  scorePerBall: 10,       // 最小计分：每消除一颗
  losingSpeed: 1500,      // 失败时珠子被吸入洞穴的速度（设计单位/秒）

  // U12 加球（只发生在出球道）
  mergeTime: 0.26,        // 并入动画时长（秒）
  // ⏸ 加球默认关闭。原因见 DESIGN.md §17：它当前**没有给玩家任何增益**（链 +1、不产生新配对），
  // 是纯惩罚，且与用户最初「配对错误不会直接带来负反馈」相冲突。
  // 机制本身（并入动画 + 自动顶开）已完整实现并有 15 项单测，改回 true 即恢复。
  // ★ 切换轨道机制（DESIGN.md §46）：一发子弹要么去匹配（三消道留标记），要么去加球（并入出球道）。
  //   原版是"一发两用"（子弹必然并入，然后 CheckSet 自动判同色三消，见 CurveMgr.cpp:1860）——
  //   它的并入是中性的（球变长而已，消除会清掉）。我们的并入会**改变 0/1/2 序列的结构**，
  //   而且要解"卡死的连续区段"（§28 的 1-间隔死球），需要玩家主动选时机，所以分模式。
  defaultMode: 'match',   // 'match'（RNA 碱基配对）| 'insert'（加球）| 'seven'（七球·元素）

  // ---- §57 元素反应模式 ----
  // 反应表本身在 elements.js（那是考证结论）；这里只放**本作的**数值旋钮。
  elemFreezeTime: 3.0,      // 冻结：整链停止前进的秒数（原神里冻结 = 无法行动）
  elemAutoPairCount: 3,     // 超导：自动「读出」（配对）的颗数上限
  elemSwirlRange: 2,        // 扩散：把元素往两侧传播几颗
  elemBurnTime: 3.0,        // 燃烧持续时间（秒）
  elemBurnTick: 0.25,       // 燃烧频率：原神 0.25 秒跳一次，即每秒 4 次
  elemCoreLife: 6.0,        // 草原核存活时长（原神 6 秒）
  elemCoreMax: 5,           // 场上最多几个草原核（原神上限 5 个，超出的立即爆炸）
  elemReactionDepth: 4,     // 反应连锁深度上限（扩散/传导可能引发二次反应）
  elemShieldMax: 3,         // 晶片护盾上限（每片抵挡一次洞穴吞噬）
  // 每次反应的基础分：对应原神「剧变反应是一次独立显示的伤害」。
  // ⚠ 一开始给 20，实测元素模式下**分数过关的无尽关 7.7 秒就通关了**（匹配模式 30 秒）——
  //   因为反应分盖过了"消一颗 10 分"这条主线（14 次反应 280 分 vs 消 24 颗 240 分）。
  //   降到 10：反应是加成，不该成为主要得分手段。
  elemScorePerReaction: 10,
  reactionFlashTime: 1.2,   // 反应名在屏幕上停留的秒数（纯渲染）
  // ★ 瞄准提示（§57.11 的对策①）：发球前，在"这一发真能打中的球"上标出会触发什么反应。
  //   元素层不像碱基那样有直觉通道（"发反色的那颗"就完事了），玩家得背反应表 ——
  //   这个提示是成本最低的解法：不改任何规则，只把已经算出来的结果说出来。
  elemHints: true,
  hintMaxCount: 4,          // 同屏最多标几个（多了反而糊）
  modeFlashTime: 0.28,    // 按模式按钮后按钮高亮的时长（秒）—— 给「点到了」一个确认


  // 珠子袋：从「场上未配对大球的互补碱基」里抽（原版 GetRandomPendingBallColor 的同族机制）。
  // 1.0 = 永远抽可用的；0 = 纯均匀。纯均匀时随机一发配上的概率只有 6/25 = 24%，是手忙脚乱的主因。
  bagBias: 1.0,

  // 视觉过渡（纯渲染，不参与任何判定）：消除后前段往出球口方向后退、插入时前段被顶开，
  // 这两处逻辑上是当帧到位的（所以 λ≡1、级联不被阻断），但画面上要缓动一下才好看。
  retreatTime: 0.22,

  // 原版式后退冲量（CurveMgr::AdvanceBackwardBalls / Ball::mBackwardsCount）：
  // 消除后整链沿轨道往冒球口方向渐进后退，而不是瞬移。原版是 BackwardsCount=30、速度=combo*1.5。
  backFrames: 30,
  backStopFrames: 20,   // 后退期间暂停推进/喂入的帧数（对应原版 AdvanceBackwardBalls 末尾的 mStopTime = 20）


  // 加球的正反馈：插入后若与邻居互补，这颗新球自己获得绑定小球（进入 run）。
  // 账：链 +1，若因此凑满 3n -> 消掉 -> 净 -2。详见 DESIGN.md §18。
  // ★ 默认 false：让两种模式语义彻底分离 —— 加球模式只改链结构、完全不碰标记，
  //   玩家不用猜「加球时会不会顺手配上一颗」。想要 §18 那个正反馈就改回 true。
  insertPairs: false
};

// 模式按钮的屏幕矩形（render 画、main 判点击，共用一份）
export function modeButtonRect(view, mt) {
  const r = 40 * mt.scale;          // 手指友好
  const pad = 26 * mt.scale;        // 离底边留远一点，免得被手机浏览器自己的 UI 盖住
  return { x: view.w - r - pad, y: view.h - r - pad, r: r };
}

// ★ §61 开始菜单的布局（render 画、main.js 判点击，共用一份 —— 和 modeButtonRect 一个套路）。
//   返回的 buttons 里带着**原始 item**，所以点中之后不需要再按下标去猜是哪个关卡。
//
//   竖屏（窄）2 列、横屏/桌面 4 列：手机上一行塞 4 个按钮会小到点不准。
export function menuLayout(view, mt, items) {
  const s = mt.scale || 1;
  const W = view.w, H = view.h;
  const narrow = W < 640;
  const cols = narrow ? 2 : 4;
  const pad = Math.max(10, 18 * s);
  const gapX = 9 * s, gapY = 8 * s;
  const innerW = Math.min(W - pad * 2, narrow ? 440 * s : 760 * s);
  const x0 = (W - innerW) / 2;
  const bh = Math.max(36, 50 * s);
  const bw = (innerW - gapX * (cols - 1)) / cols;
  const buttons = [];
  const groups = [];
  let y = Math.max(76 * s, H * 0.26);
  let col = 0, last = null;
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    if (it.group !== last) {
      if (last !== null) y += bh + gapY + 24 * s;   // 换组：留出组标题的位置
      groups.push({ name: it.group, y: y });
      y += 20 * s;
      col = 0;
      last = it.group;
    }
    buttons.push({ x: x0 + col * (bw + gapX), y: y, w: bw, h: bh, item: it, index: i });
    col += 1;
    if (col >= cols) { col = 0; y += bh + gapY; }
  }
  return {
    x0: x0, innerW: innerW, cols: cols, bw: bw, bh: bh,
    buttons: buttons, groups: groups,
    titleY: Math.max(40 * s, H * 0.14),
    footerY: H - Math.max(22 * s, 30 * s)
  };
}

// 局内的「回菜单」按钮（左下角，和右下角的模式按钮对称）
export function menuButtonRect(view, mt) {
  const r = 22 * mt.scale;
  const pad = 26 * mt.scale;
  return { x: r + pad, y: view.h - r - pad, r: r };
}

// 固定层级带（DESIGN.md §3.2）
export const Z = {
  projectile: 50,
  actor: 60,
  fx: 70,
  hud: 100
};

export function metrics(scale) {
  const R = DESIGN.spawnRadius * scale;
  const r = R * DESIGN.smallDiameterRatio;
  const d = R + r + DESIGN.railClearance * scale;
  const linkGap = DESIGN.beadGap * scale;
  const p = 2 * R + linkGap;
  return {
    scale: scale,
    R: R,                        // 出球道球半径
    r: r,                        // 三消道球半径
    d: d,                        // 两轨中心距
    p: p,                        // 同轨相邻球心距（= touchDist(大,大)）
    linkGap: linkGap,            // 绳模型相邻球的额外净空
    diameterRatio: R / r,        // === √2
    areaRatio: (R * R) / (r * r) // === 2
  };
}

// 视口布局。两个要点：
//   1) scale 有**下限**：手机竖屏 (400x850) 上 min/900 只有 0.44，球直径 17px，手指根本瞄不准。
//   2) 竖屏时纵向放开上限：圆形棋盘在 400x850 上只占中间一小块，上下全是空的。
export function viewFor(w, h) {
  const base = Math.min(w, h);
  // scale 下限不能是绝对常量：小屏（320）上再大就把棋盘挤爆了。
  // 所以取 min(0.82, base/450)：400 宽 -> 0.82；320 宽 -> 0.71；900 宽 -> 仍是 min/900 = 1.0
  const scale = Math.max(base / DESIGN.base, Math.min(DESIGN.minScale, base / 450));
  const portrait = h > w * 1.25;
  const capX = base * (portrait ? DESIGN.outerFitWide : DESIGN.outerFitWide);
  const capY = base * (portrait ? DESIGN.outerFitTall : DESIGN.outerFitWide);
  return {
    w: w,
    h: h,
    dpr: 1,
    cx: w / 2,
    cy: h / 2,
    rx: Math.min(w * DESIGN.outerFit, capX),
    ry: Math.min(h * DESIGN.outerFit, capY),
    base: base,
    scale: scale,
    portrait: portrait
  };
}


// 真实碱基配对：A-U / A-T / G≡C。参数顺序无所谓（表是对称的，单测会断言）。
export function isComplement(tRNA, mRNA) {
  const c = COMPLEMENT[mRNA];
  return !!c && c.indexOf(tRNA) >= 0;
}

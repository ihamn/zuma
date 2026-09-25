// 关卡配方（DESIGN.md §5.3 / §55）。三个"清空过关"的有限球数关 + 一个无尽关。
//
// ★ 为什么关卡必须带球数（DESIGN.md §55）—— 用户报的 bug 的根因：
//   用户要的「把场上清光 = 胜利」和「无限出球」在逻辑上**互斥**：无限出球时链子
//   下一帧就从出球口补上一颗，「场上为空」只是清球后的一瞬间 —— 拿它判赢就会秒过关。
//   原版 Zuma 的解法是每关给定球数（CurveDesc::mNumBalls）：**发完 + 清光**才算通关。
//   于是本作分两类关卡：
//     · 有限球数关（ballBudget > 0）—— 过关 = 预算发满 + 场上清空（3n 消清光或爆炸炸光都算）
//     · 无尽关（ballBudget === 0）—— 过关 = 分数达标，无限出球保留在这
//   之前三个关都没写 ballBudget，全都退回 DESIGN.ballBudget = 0，
//   于是 scene.js 里那条"清空过关"分支**从来没被执行过**（死规则），
//   用户看到的正是"炸光了却不过关"。

import { spiralSpine, crossReturnSpine } from './spines.js';

export const LEVELS = [
  // ★ 2026-09-25 关卡表变更（奇匠先说反了一次，这是更正后的最终状态）：
  //   **删掉 'spiral-inner'（螺旋 · 出球道在内）**，保留 'spiral-outer'（出球道在外）。
  //   同时把新手关里唯一用"内"的那一关（t7-mix）也换成"外" ——
  //   于是**整个游戏不再出现 `railOrder: 'spawn-inner'`**。
  //   影响面（已同步）：本体测试 test-tutorial.mjs 的 LEVELS 断言、tools/smoke.mjs 的核心关下标、
  //   tools/test-{geometry,insert}.mjs 里按数字下标取"交叉关"的三处（改成按 id 查）、
  //   导出物 miliastra/lua/src/levels_data.lua、DESIGN.md 数值表、手册里的关卡编号。
  //   ⚠ 教训：测试里**别按数字下标取关卡**（`LEVELS[2]` 删一关就静默指向别的关）。
  {
    id: 'spiral-outer',
    name: '螺旋 · 出球道在外',
    short: '螺旋·外',
    makeSpine: spiralSpine,
    railOrder: 'spawn-outer',
    layers: null,
    prefill: 14,
    ballBudget: 48,
    scoreTarget: Infinity,
  },
  {
    id: 'cross-return',
    name: '交叉演示 · 遮挡与桥',
    short: '交叉桥',
    makeSpine: crossReturnSpine,
    railOrder: 'spawn-outer',
    // 回程段放在上层：跨层相交 = 合法桥；同层自交 = 报错
    layers: function (path, spine) {
      const cut = path.sAtU(spine.junctionU != null ? spine.junctionU : 0.64);
      return [
        { from: 0, to: cut, z: 0 },
        { from: cut, to: path.length, z: 1 }
      ];
    },
    prefill: 16,
    ballBudget: 60,
    scoreTarget: Infinity,
  },
  {
    // ★ 无尽关：把"原本的无限出球"原样保留在这里。
    //   它没有"打完"的概念，所以过关只能靠分数 —— 见 config.js DESIGN.scoreTarget。
    id: 'endless',
    name: '无尽 · 无限出球',
    short: '无尽',
    makeSpine: spiralSpine,
    railOrder: 'spawn-outer',
    layers: null,
    prefill: 18,
    ballBudget: 0,
    scoreTarget: 500,
  }
];

// ==================== §60 新手关：逐步拆分 ====================
//
// 用户："给我们的 RNA 灵感祖玛写几个新手关卡，逐步拆分。"
//
// ★★ ①~④ 是**静止练习关**（§63）：连轨道都没有。
//   起因（用户）：「新手关如果说只是为了让你看看匹配什么球，没必要再来一个长长的轨道吧？
//   或者说其实普遍不需要吧？」—— 上一版我把轨道缩短了，但那是治标：
//   ①~④ 教的全是"配对规则"，而轨道、洞穴、会前进的链子**跟这一课毫无关系** ✗
//   所以这四关用的是直线骨架 + 不前进 + 无洞穴：一排静止的球 + 旁边平行的三消道，
//   "配对 = 小球落到旁边那条道上"一眼就懂，别的什么都不出现。
//   ⑤「洞穴」才是**第一次出现轨道**的那一关 —— 它教的正好就是轨道带来的东西。
//
// 原则：**一关只教一件事，而且必须能"看得见"。** 所以要这几个字段：
//   still    静止练习关：不前进、不出球、没有洞穴 -> 也就没有失败
//
// ★★ 静止关有一条**硬约束：场上球数必须是 3 的倍数。**
//   原因是吸附飞行要 0.3 秒 —— 玩家连打几发时，那几颗小球会**同时落位**，
//   于是 run 从 0 直接跳到 4（跳过了 3）。真实关卡里链子还在冒球，补一颗到 6 就解了；
//   但静止关没有新球也没有洞穴，一旦出现 3n+1 就是死局。
//   实测 t4（爆炸后剩 7 颗）就卡在这里：配对全部 -> run=7 -> 永远消不掉。
//   test-tutorial 里有一条断言专门盯这个不变量。
//   bases    本关只出现哪几种碱基 —— 信息量是最贵的资源，第一关只给 A/U 两色
//   script   固定开局序列 —— 有些课（尤其 §28 的死球）必须摆出**确定的局面**，
//            随机是碰不到的；写法 "A1 U1 A0"，1 = 开局就已配对
//   speed    珠串推进速度 —— 前两关要慢到玩家有余裕看
//   hint     这一关在教什么（HUD 直接显示，不写"请点击此处"那种废话）
//   startWpFrac  开局把整链往前挪（占轨道全长的比例）—— 教"被洞穴吞"时得让危险近在眼前
//
// 每条 hint 都对应 DESIGN.md 里一条已经成立的规则，不是临时编的话术：
//   ① 反色        §23 调色板：互补碱基必须互为反色 -> 玩家不用背配对表
//   ② 三的倍数    §19/§4.6 3n 消；「N 颗 · 还差 M」的徽章已经在 HUD 上
//   ③ 五色球      §4.4 配对表 A–U / A–T / G≡C（A 是唯一的双配碱基）
//   ④ 配错的代价  §29/§30 2 态：错误配对 -> mark 2 -> 爆炸，**且不扣分**
//   ⑤ 洞穴        §A15 失败条件与祖玛一致：队头滚进洞穴被吞，扣命
//   ⑥ 加球        §46 一发要么匹配要么并入；§28.5 加球用来调"序列长度"
//   ⑦ 死球        §28 ★ 1-间隔死球：11 0 11 里配对中间那颗 = 陷阱（变成 5）
//   ⑧ 综合        前面全用上

export const TUTORIALS = [
  {
    id: 't1-pair',
    name: '① 配对',
    short: '配对',
    makeSpine: spiralSpine,
    turns: 0.75,
    railOrder: 'spawn-outer',
    layers: null,
    still: true,
    centerChain: true,
    // ★★ §64 这一关**只教配对**：不消球、不爆炸、不用凑三颗。
    //   用户：「第一关融入了三的倍数，不太对」—— 对。① 名义上教"看颜色发反色"，
    //   可玩家一配对就碰上 3n 消，两条规则同时压上来，第一关就不干净了。
    noClear: true,
    goal: 'matchAll',
    prefill: 12,
    ballBudget: 12,
    scoreTarget: Infinity,
    hint: [
      '球面颜色和字母互为反色 —— 打一颗反色的，就把它「读出」。',
      '这一关不用凑三颗：把 12 颗全读出来就过关。'
    ],
  },
  {
    id: 't2-multiple',
    name: '② 三的倍数',
    short: '三的倍数',
    makeSpine: spiralSpine,
    turns: 0.75,
    railOrder: 'spawn-outer',
    layers: null,
    still: true,
    centerChain: true,
    // 4 已读 + 5 未读 = 9。正确走法：补 2 颗 -> run=6 消掉 -> 剩 3 颗 -> 再补 3 颗 -> 过关。
    script: 'A1 A1 A1 A1 A0 U0 G0 C0 U0',
    ballBudget: 9,
    scoreTarget: Infinity,
    hint: [
      '这一关开始要消球了：连着读出的球**必须是 3 的倍数**才能消。',
      '看徽章上的「还差 M」—— 差几颗就再补几颗。'
    ],
  },
  {
    id: 't3-wrong',
    name: '③ 配错的代价',
    short: '配错的代价',
    makeSpine: spiralSpine,
    turns: 0.75,
    railOrder: 'spawn-outer',
    layers: null,
    still: true,
    centerChain: true,
    // 12 颗：第一帧 A1/A2/A1 一起炸掉 3 颗 -> 剩下 9 颗（3 的倍数，见 §63.3 的硬约束）。
    script: 'A1 A2 A1 A0 U0 A0 U0 A0 U0 A0 U0 A0',
    ballBudget: 12,
    scoreTarget: Infinity,
    // ★ §64 用户：「第 4 关没有讲具体啥时候爆炸。需要合适的文字说明。」
    //   规则就是 run.js 的 findExplosion：灰球左右两颗都已读出、且**状态相同**（都 1 或都 2）才炸。
    hint: [
      '打错颜色 = 灰球。灰球**不会立刻炸** ——',
      '要等它左右两颗都已经读出、而且**状态一样**（都配对 / 都配错）时，才连它一起炸掉 3 颗。',
      '刚才那一炸就是这么来的。不扣分，但那一段白配了。'
    ],
  },
  {
    id: 't4-insert',
    name: '④ 加球',
    short: '加球',
    makeSpine: spiralSpine,
    turns: 0.75,
    railOrder: 'spawn-outer',
    layers: null,
    // ★ §65 加球也放在静止练习里（用户：「洞穴往后放放」）——
    //   插入靠的是绳模型的"顶开"，而静止关**速度归零但绳模型照跑**，
    //   所以插一颗照样会把前面那截顶开，不需要轨道、更不需要洞穴。
    still: true,
    centerChain: true,
    bases: ['A', 'U'],
    prefill: 12,
    ballBudget: 12,
    scoreTarget: Infinity,
    hint: [
      '按 Tab（手机点右下角）切到「加球」—— 往链里插一颗，序列的长度就变了。',
      '凑不成 3 的倍数时，这是除了消球之外的另一种调整手段。',
      '插错了按 R 重来。'
    ],
  },
  {
    id: 't5-deadball',
    name: '⑤ 死球',
    short: '死球',
    makeSpine: spiralSpine,
    turns: 0.75,
    railOrder: 'spawn-outer',
    layers: null,
    still: true,
    centerChain: true,
    bases: ['A', 'U'],
    // ★★ §28 的 1-间隔死球：11 0 11。两段各 2 颗，中间夹 1 颗没读的。
    //   最自然的操作就是"把中间那颗也读了" —— 于是两段并成 5，反而更远。
    //   9 颗（3 的倍数）：配上中间那颗 = 5，再补 1 颗 = 6 消掉，剩 3 颗 -> 再消 -> 过关。
    script: 'A1 A1 U0 A1 A1 A0 A0 A0 A0',
    ballBudget: 9,
    scoreTarget: Infinity,
    hint: [
      '两段各 2 颗，中间夹着 1 颗没读的。',
      '★ 别急着配中间那颗：配了它，两段会并成 5 颗，反而更远。',
      '去把后面那几颗凑成一段；真踩了坑，就再补一颗到 6。'
    ],
  },
  {
    id: 't6-cave',
    name: '⑥ 洞穴',
    short: '洞穴',
    makeSpine: spiralSpine,
    railOrder: 'spawn-outer',
    layers: null,
    bases: ['A', 'U'],
    script: 'A U A U A U A U A U',
    // 开局把队头摆到轨道 72% 处：危险要看得见，玩家才会在意
    startWpFrac: 0.72,
    ballBudget: 22,
    scoreTarget: Infinity,
    speed: 14,
    hint: [
      '★ 到这里才有轨道：球会一直往洞穴爬，队头滚进去就扣一条命。',
      '它现在离洞口很近 —— 先把最前面那几颗消掉。'
    ],
  },
  {
    id: 't7-mix',
    name: '⑦ 综合',
    short: '综合',
    makeSpine: spiralSpine,
    railOrder: 'spawn-outer',
    layers: null,
    ballBudget: 36,
    prefill: 16,
    scoreTarget: Infinity,
    speed: 26,
    hint: [
      '把前面学的都用上：反色配对、凑 3 的倍数、别去配 1-间隔的那颗。'
    ],
  }
];

// 游戏里实际用的关卡表：新手关在前，正式关（原来的核心关）在后。
// ⚠ 不把新手关塞进 LEVELS 本身 —— 测试与探针大量拿 LEVELS[0] 当夹具，
//   混进去会把几十条断言的含义悄悄改掉（这类"改测试含义"的坑本轮已经踩过）。
//   ★ 2026-09-25：LEVELS 删掉了 spiral-outer，所以 LEVELS[0] 现在是 spiral-inner。
export const ALL_LEVELS = TUTORIALS.concat(LEVELS);

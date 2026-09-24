// 元素与元素反应（DESIGN.md §57/§58）。纯数据 + 纯函数，不碰场景。
//
// ★ 为什么单开一个文件：反应表是**从官方 WIKI 逐条抄下来的**（见 §58 的来源对照），
//   它是"考证结论"而不是"平衡数值"，把它和场景逻辑混在一起以后就没法核对来源了。
//
// 数据来源：https://wiki.biligame.com/ys/元素反应 （2026-08 抓取的 wikitext）
//   21 种反应分六类：增幅 / 剧变 / 结晶 / 激化 / 月曜 / 星烁。
//   本作实现**基础 12 种**；月曜（月感电/月绽放/月结晶）与星烁（星超导/星扩散/星辉风旋）
//   是"需要特定角色天赋才能转化"的亚种，和祖玛玩法无关，**不实现**（§57.6 有说明）。

// ---------- 七元素 ----------
// ★ attachable = 能否作为"附着元素"（先手）。
//   风、岩**不能附着**：官方 WIKI 里扩散永远写作「风元素触及火/水/雷/冰」、
//   结晶永远写作「岩元素触及火/水/雷/冰」—— 从来没有反过来的写法。
//   所以风/岩只能做**触发元素**（后手），场上不会留着风/岩的附着。
export const ELEMENTS = ['pyro', 'hydro', 'cryo', 'electro', 'dendro', 'geo', 'anemo'];
export const ELEM = {
  pyro:    { name: '火', color: '#ff7a45', ink: '#3a1204', attachable: true },
  hydro:   { name: '水', color: '#49b6ff', ink: '#04223a', attachable: true },
  cryo:    { name: '冰', color: '#a8ecff', ink: '#0b2b38', attachable: true },
  electro: { name: '雷', color: '#c08cff', ink: '#220b3a', attachable: true },
  dendro:  { name: '草', color: '#8ede52', ink: '#10300a', attachable: true },
  geo:     { name: '岩', color: '#ffc94d', ink: '#3a2604', attachable: false },
  anemo:   { name: '风', color: '#6fe8c8', ink: '#0a332a', attachable: false }
};
// 「激元素」不是七元素之一，是原激化留下的状态元素（原神：施加激元素附着）
export const QUICK = 'quick';

export function canAttach(elem) {
  return !!(ELEM[elem] && ELEM[elem].attachable);
}
export function elemName(elem) {
  return elem === QUICK ? '激' : (ELEM[elem] ? ELEM[elem].name : '—');
}
export function elemColor(elem) {
  return elem === QUICK ? '#d9f24a' : (ELEM[elem] ? ELEM[elem].color : '#8899aa');
}

// ---------- 反应表 ----------
// key = 先手(场上已有的附着) + '|' + 后手(本次触发的元素)
//
// ★ 倍率的不对称性直接来自 WIKI 的备注：
//   「正克制」= 水打火、火打冰  -> 2
//   「逆克制」= 冰打火、火打水  -> 1.5
//   注意是**后手（触发方）**吃倍率 —— 水打火 2.0 而 火打水 1.5，
//   所以同一个反应在表里是两条，不能合并。
//
// effect = 交给 scene.js 执行的效果名（§57.3 的映射表）：
//   amp      增幅：该球被消掉时分数乘 mult（对应原神"增幅基于技能伤害倍率"）
//   explode  剧变：就地移除 3 颗 + 后退（复用爆炸的路径，保持"移除必是 3 的倍数"）
//   autoPair 自动配对（帮助凑 3n 段）
//   chain    感电传导：向所有带水附着的球放电
//   freeze   冻结：该段停止前进
//   swirl    扩散：把该元素复制到周围
//   shield   结晶：获得一枚晶片护盾
//   burn     燃烧：持续自动配对相邻球
//   core     绽放：生成草原核
//   quicken  原激化：施加激元素
export const REACTIONS = {
  // ---- 增幅反应（2 种）----
  'pyro|hydro':    { id: 'vaporize',   name: '蒸发',   mult: 2.0,  effect: 'amp' },
  'hydro|pyro':    { id: 'vaporize',   name: '蒸发',   mult: 1.5,  effect: 'amp' },
  'cryo|pyro':     { id: 'melt',       name: '融化',   mult: 2.0,  effect: 'amp' },
  'pyro|cryo':     { id: 'melt',       name: '融化',   mult: 1.5,  effect: 'amp' },
  // ---- 剧变反应（8 种，含碎冰单列）----
  'electro|pyro':  { id: 'overload',   name: '超载',   mult: 2.75, effect: 'explode' },
  'pyro|electro':  { id: 'overload',   name: '超载',   mult: 2.75, effect: 'explode' },
  'electro|cryo':  { id: 'superconduct', name: '超导', mult: 1.5,  effect: 'autoPair' },
  'cryo|electro':  { id: 'superconduct', name: '超导', mult: 1.5,  effect: 'autoPair' },
  'electro|hydro': { id: 'electroCharged', name: '感电', mult: 2.0, effect: 'chain' },
  'hydro|electro': { id: 'electroCharged', name: '感电', mult: 2.0, effect: 'chain' },
  'cryo|hydro':    { id: 'frozen',     name: '冻结',   mult: 0,    effect: 'freeze' },
  'hydro|cryo':    { id: 'frozen',     name: '冻结',   mult: 0,    effect: 'freeze' },
  'dendro|pyro':   { id: 'burning',    name: '燃烧',   mult: 0.25, effect: 'burn' },
  'pyro|dendro':   { id: 'burning',    name: '燃烧',   mult: 0.25, effect: 'burn' },
  'dendro|hydro':  { id: 'bloom',      name: '绽放',   mult: 2.0,  effect: 'core' },
  'hydro|dendro':  { id: 'bloom',      name: '绽放',   mult: 2.0,  effect: 'core' },
  'dendro|electro':{ id: 'quicken',    name: '原激化', mult: 0,    effect: 'quicken' },
  'electro|dendro':{ id: 'quicken',    name: '原激化', mult: 0,    effect: 'quicken' },
  // ---- 风 / 岩：只能当后手 ----
  'pyro|anemo':    { id: 'swirl',      name: '扩散',   mult: 0.6,  effect: 'swirl' },
  'hydro|anemo':   { id: 'swirl',      name: '扩散',   mult: 0.6,  effect: 'swirl' },
  'cryo|anemo':    { id: 'swirl',      name: '扩散',   mult: 0.6,  effect: 'swirl' },
  'electro|anemo': { id: 'swirl',      name: '扩散',   mult: 0.6,  effect: 'swirl' },
  'pyro|geo':      { id: 'crystallize', name: '结晶',  mult: 0,    effect: 'shield' },
  'hydro|geo':     { id: 'crystallize', name: '结晶',  mult: 0,    effect: 'shield' },
  'cryo|geo':      { id: 'crystallize', name: '结晶',  mult: 0,    effect: 'shield' },
  'electro|geo':   { id: 'crystallize', name: '结晶',  mult: 0,    effect: 'shield' },
  // ---- 激化反应的续接（激元素作先手）----
  'quick|electro': { id: 'aggravate',  name: '超激化', mult: 1.15, effect: 'amp' },
  'quick|dendro':  { id: 'spread',     name: '蔓激化', mult: 1.25, effect: 'amp' }
};

// 碎冰：不是"两元素相遇"，而是「冻结状态 + 岩元素/钝击」—— 所以单列，不进上面的表
export const SHATTER = { id: 'shatter', name: '碎冰', mult: 3.0, effect: 'explode' };

export function reactionFor(aura, trigger) {
  if (!aura || !trigger) return null;
  return REACTIONS[aura + '|' + trigger] || null;
}

// ==================== 七球模式（§57 改版）====================
//
// 用户的定调：「直接来个七球模式，匹配相当于元素反应」。
// 所以这里**不再是"碱基配对 + 元素附着"两层**，而是一层：
//
//   球的身份 = 元素（七种之一）      珠子的身份 = 元素
//   匹配成功 = 这两个元素之间**有反应**（反应表就是匹配表）
//   匹配失败 = 两者之间没有反应 -> 走原有的"错误配对 -> 爆炸"
//
// 玩家因此不是在找"唯一能配上的那颗"，而是在选"我想要哪个反应"——
// 这才是"匹配相当于元素反应"这句话真正的玩法含义。

// 球（先手）与珠子（后手）之间有没有反应。
// quickened = 这颗球身上有激元素（原激化的后续：超激化/蔓激化）。
export function sevenReaction(ballElem, beadElem, quickened) {
  if (!ballElem || !beadElem) return null;
  // 激元素优先：原神里带激元素的目标被雷/草触及时走超激化/蔓激化
  if (quickened) {
    const q = REACTIONS[QUICK + '|' + beadElem];
    if (q) return q;
  }
  // 球当先手（绝大多数元素都能附着）
  const a = REACTIONS[ballElem + '|' + beadElem];
  if (a) return a;
  // ★ 球是风/岩时**不能作先手**（§57.3），这时反过来查：珠子才是先手、球上的风/岩才是后手。
  //   倍率仍旧由后手吃，所以"风球 + 火珠 -> 扩散"这样查出来的方向是对的。
  const b = REACTIONS[beadElem + '|' + ballElem];
  if (b) return b;
  return null;
}

// 能跟这颗球反应的珠子元素（给珠袋池用）。空数组 = 这颗球打不动（理论上不会发生）。
export function beadElemsFor(ballElem, quickened) {
  const out = [];
  for (let i = 0; i < ELEMENTS.length; i++) {
    const e = ELEMENTS[i];
    if (e === ballElem) continue;                     // 同元素只刷新，不反应 -> 打上去就是废弹
    if (sevenReaction(ballElem, e, quickened)) out.push(e);
  }
  return out;
}

// 元素在球面上显示的字（一个汉字，直接当"字母"用）

// 元素在球面上显示的字（一个汉字，直接当"字母"用）

export function elemGlyph(elem) {
  return ELEM[elem] ? ELEM[elem].name : (elem === QUICK ? '激' : '?');
}

// 给 HUD / 事件用的简述
export function describeReaction(r) {
  if (!r) return '';
  return r.name + (r.mult > 0 ? ' ×' + r.mult : '');
}

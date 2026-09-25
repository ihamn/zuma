// 场景装配 + 每帧推进。main.js 与 tools/preview.mjs / 单测共用同一份逻辑（单一真源）。
// 组合：几何(U2) + 珠串(U3) + 核糖体(U6) + 弹丸与命中分流(U7/U8) + 阅读框(U9) + 生命与计分(U11)

import { DESIGN, metrics, BASES, COMPLEMENT, isComplement, complementColor, WRONG_GLOW, colorOf, inkOf } from './config.js';
import { buildPath, assignLayers, layerRuns, buildRail, validateTrack } from './geometry.js';
import { makeRng } from './rng.js';
import { makeChain, advanceChain, spawnBall, prefillChain, removeRange, insertBall, touchDist, applyBackward, hasBackward } from './chain.js';
import { computeRuns, clearableRuns, findExplosion, markFinal, classicRuns, classicClearable } from './run.js';
import { makeRibosome, tickRibosome, fire, drawBase } from './ribosome.js';
import { makeProjectile, advanceProjectile, sweepHit, projectileExpired } from './projectile.js';
import { ELEMENTS, QUICK, reactionFor, sevenReaction, beadElemsFor, elemColor, elemGlyph, ELEM, SHATTER } from './elements.js';

// 珠袋可用池：场上**未配对**大球的互补碱基（去重）。
// 动机见 DESIGN.md §17.5：纯均匀抽时，随机一发配上的概率只有 6/25 = 24%。
// ★ 新手关的固定开局序列（DESIGN.md §60）。
//   写法："A1 U1 A0 U1 A1" —— 字母是碱基，后面跟的 1 表示**开局就已经配对**（默认 0）。
//   空格随便加，只是为了关卡作者自己看得清。
//   为什么需要它：有些课必须摆出确定的局面。§28 的 1-间隔死球（11 0 11）随机是碰不到的，
//   而它恰恰是"配对中间那颗 = 陷阱"这条最重要的反直觉规则。
export function parseScript(str) {
  const out = [];
  for (let i = 0; i < str.length; i++) {
    const c = str.charAt(i);
    if (c === ' ' || c === ',' || c === '|') continue;
    // ⚠ 数字是**紧跟着上一颗球的标记**，不是独立的一颗球。
    //   第一版把它们当成 token 推进去了 —— "A1 A1" 会变成 4 颗球（A,1,A,1），
    //   带标记的关卡于是全部错位（场上球数是脚本长度的两倍，标记全丢）。
    if (c === '0' || c === '1' || c === '2') {
      if (out.length) out[out.length - 1] = out[out.length - 1].charAt(0) + c;
      continue;
    }
    out.push(c);
  }
  return out;
}
// 某颗球的互补碱基里，**本关池子里真的有**的那些。
//   例：本关只有 A/U，那么 A 的互补只有 U 算数（T 不在池里，抽出来就是废弹）。
export function allowedComplements(sc, base) {
  const c = COMPLEMENT[base];
  if (!c) return [];
  const pool = sc.bases || BASES;
  return c.filter(function (x) { return pool.indexOf(x) >= 0; });
}
export function inPool(sc, base) {
  return (sc.bases || BASES).indexOf(base) >= 0;
}

// "A"  未配对   "A1" 已正确读出   "A2" 配错（灰球，之后会爆炸）
export function parseScriptEntry(tok) {
  const d = tok.charAt(1);
  const mark = (d === '1') ? 1 : ((d === '2') ? 2 : 0);
  return { base: tok.charAt(0), mark: mark, paired: mark !== 0 };
}

// 珠袋可用池。★ 两种模式的"身份token"不同（DESIGN.md §57 改版）：
//   匹配模式：token = 碱基，可用 = 场上未配对球的**互补碱基**
//   七球模式：token = 元素，可用 = 能跟场上某颗未配对球**发生反应**的元素
export function usefulPool(sc) {
  const out = [];
  const balls = sc.chain.balls;
  for (let i = 0; i < balls.length; i++) {
    const b = balls[i];
    if (b.paired) continue;
    const c = sc.mode === 'seven' ? beadElemsFor(b.elem, b.quickened) : allowedComplements(sc, b.base);
    if (!c || !c.length) continue;
    for (let k = 0; k < c.length; k++) if (out.indexOf(c[k]) < 0) out.push(c[k]);
  }
  return out;
}

// ★★ 加权池（DESIGN.md §54）：**不去重** —— 场上每有一颗粒子需要某个碱基，
//   那个碱基就在池子里多出现一次。珠子袋按这个池子抽，就等于"按目标数量加权"。
//
//   ⚠ 原来用的是 usefulPool（**去重**）：只留"有哪些碱基有用"，丢掉了数量。
//     后果实测很严重：场上 35.8 颗未配对球，手里那颗平均只能配上 **1.58** 颗
//     （均匀的话该有 7~14 颗），于是 **85.7% 的帧根本没有可打的目标**，
//     发射率只有 0.87 发/秒（冷却允许 6.3），清球 0.7 颗/秒 < 冒球 1.06 颗/秒
//     -> 链子无限增长、必输。这不是速率问题，是**弹药与目标的匹配问题**。
export function weightedPool(sc) {
  const out = [];
  const balls = sc.chain.balls;
  for (let i = 0; i < balls.length; i++) {
    const b = balls[i];
    if (b.paired) continue;                       // 已占用的球不是合法目标
    const c = sc.mode === 'seven' ? beadElemsFor(b.elem, b.quickened) : allowedComplements(sc, b.base);
    if (!c || !c.length) continue;
    for (let k = 0; k < c.length; k++) out.push(c[k]);   // ★ 不去重
  }
  return out;
}

// 轨道上的球心 = 骨架点 + 法线偏移（k 用于吸附飞行：0=贴合主轨，1=完全落到三消道）
export function beadPos(path, rail, wp, k) {
  const s = k == null ? 1 : k;
  const p = path.pointAt(wp);
  const n = path.normalAt(wp);
  return { x: p.x + n.x * rail.offset * s, y: p.y + n.y * rail.offset * s, z: p.z };
}

export function assembleScene(level, view, seed) {
  const mt = metrics(view.scale);
  const spine = level.makeSpine(view, level);
  const path = buildPath(spine, { samples: DESIGN.pathSamples, center: { x: view.cx, y: view.cy } });
  assignLayers(path, level.layers ? level.layers(path, spine) : null);

  const sign = level.railOrder === 'spawn-outer' ? 1 : -1;
  const rails = {
    spawn: { id: 'spawn', offset: sign * mt.d / 2, radius: mt.R },
    eliminate: { id: 'eliminate', offset: -sign * mt.d / 2, radius: mt.r }
  };
  const railPolys = {
    spawn: buildRail(path, rails.spawn.offset),
    eliminate: buildRail(path, rails.eliminate.offset)
  };
  const runs = { spawn: layerRuns(path), eliminate: layerRuns(path) };

  const zLevels = [];
  for (let i = 0; i < runs.spawn.length; i++) {
    const z = runs.spawn[i].z;
    if (zLevels.indexOf(z) < 0) zLevels.push(z);
  }
  zLevels.sort(function (a, b) { return a - b; });

  const issues = validateTrack(path, mt, { rails: [rails.spawn.offset, rails.eliminate.offset] });

  const rng = makeRng(seed);
  const chain = makeChain(mt, {});
  const rb = makeRibosome(view.cx, view.cy, mt, rng);
  const sc = {
    level: level, spine: spine, metrics: mt, path: path, rails: rails,
    railPolys: railPolys, runs: runs, zLevels: zLevels, issues: issues,
    view: view, rng: rng, chain: chain, rb: rb,
    projectiles: [], merges: [], events: [], spawnCount: 0, drained: 0,
    winReason: null,                // 过关原因：'clear' / 'score' / 'match'（读出全部）
    still: !!(level && level.still),  // §63 静止练习关：不前进、没有洞穴、不会输
    // ★ §64 noClear：这一关**只教配对**，不消球也不爆炸。
    //   起因（用户）：「第一关融入了三的倍数，不太对」——
    //   ① 名义上教"看颜色发反色"，可玩家一配对就碰上了 3n 消，
    //   两条规则同时压上来，第一关就不干净了。这里把它彻底摘掉。
    noClear: !!(level && level.noClear),
    goalMatchAll: level && level.goal === 'matchAll',   // 过关 = 把每一颗都读出来
    shields: 0,                     // §57 结晶护盾：每片抵挡一次洞穴吞噬
    cores: [],                      // §57 绽放的草原核
    nextCoreId: 1,
    lastReaction: null,             // 最近一次反应（给 HUD 用）
    reactionFlash: 0,               // 反应横幅剩余秒数（纯渲染）
    stopAdding: level.stopAdding === true,
    mode: DESIGN.defaultMode,        // 'match' 或 'insert'
    // ★ 经典祖玛（DESIGN.md §66）：rules === 'classic' 时走"同色连续 ≥3 消"的规则，
    //   和 RNA 配对玩法**完全分开**；缺省 'rna' ⇒ 现有 10 关行为一个字不变。
    rules: level.rules || 'rna',
    modeFlash: 0,                    // 按模式按钮后的高亮剩余时间
    lives: DESIGN.startLives, score: 0, losing: false, gameOver: false, won: false,
    runsInfo: [], lastClear: null,
    // §57 元素反应计数：reactions 触发次数 / cores 草原核 / freezes 冻结 /
    // reactionRemoves 反应造成的"移除 3 颗"次数（**不计进 explosions** ——
    // 那是"错误配对爆炸"的计数，混在一起以后就分不清盘面是怎么变的了）
    stats: { fired: 0, pairs: 0, mismatches: 0, merges: 0, cleared: 0, codons: 0, lost: 0,
             explosions: 0, reactions: 0, cores: 0, freezes: 0, reactionRemoves: 0 },
    beads: { spawn: [], eliminate: [] }
  };

  // 七球模式：球的身份token就是元素（玩家看到的是七色球，不是五种碱基）
  // ★★ 新手关需要的四个关卡字段（DESIGN.md §60）：
  //   bases    本关出现的碱基（缺省 = 全部五色）。教"反色配对"时只放 A/U，信息量才压得住。
  //   script   固定开局序列（缺省 = 随机）。有些课必须摆出**确定的局面**才教得会 ——
  //            比如 §28 的 1-间隔死球 11011，随机是碰不到的。
  //   speed    珠串推进速度（缺省 = DESIGN.chainSpeed）。前两关要慢，玩家才有时间看。
  //   startWp  开局把整链往前挪一段（缺省 0）。教"被洞穴吞掉"时，得让危险近在眼前。
  sc.bases = (level.bases && level.bases.length) ? level.bases.slice() : BASES.slice();
  if (level.script) {
    const bs2 = parseScript(level.script);
    const n = bs2.length;
    // ⚠ 下标方向：prefillChain 的第 i 次调用对应 wp = i*T，而数组约定 balls[0] = 洞端。
    //   所以 script[0] 要放到**最后**一次调用 —— 不这样写的话，关卡作者写的第一个球
    //   会跑到出球口那一头去。
    // ⚠ 必须取 .base —— token 是 "A1"（碱基+标记）这种两字符形式，
    //   把整个 token 当碱基写进球里的话 COMPLEMENT['A1'] 是 undefined，
    //   那关的球**一颗都配不上**（这种错会安静地毁掉整个关卡，不会报错）。
    prefillChain(chain, n, function (i) { return parseScriptEntry(bs2[n - 1 - i]).base; });
    for (let i = 0; i < chain.balls.length; i++) {
      const spec = parseScriptEntry(bs2[i]);
      const b = chain.balls[i];
      if (spec.mark) {
        const c = COMPLEMENT[b.base];
        b.paired = true;
        b.wrongMark = (spec.mark === 2);
        b.pairBase = (c && c.length) ? c[0] : null;
        b.dock = 1;
      }
    }
  } else {
    prefillChain(chain, level.prefill || 14, function () {
      return sc.mode === 'seven' ? rng.pick(ELEMENTS) : rng.pick(sc.bases);
    });
  }
  // ★ 用**占轨道全长的比例**而不是绝对弧长：轨道长度随视口/缩放变，
  //   写死绝对值的话换个屏幕比例这关就不是"离洞口很近"了。
  // ⚠ 语义是"让**队头**落在轨道的这个比例处"，不是"整链平移这么多" ——
  //   第一版写成整链平移，§62 把轨道缩短之后 t5 的队头直接被推到了洞口外，
  //   开局 2.3 秒连丢三条命（探针当场抓到）。
  if (level.startWpFrac && chain.balls.length) {
    const off = level.startWpFrac * path.length - chain.balls[0].wp;
    if (off > 0) for (let i = 0; i < chain.balls.length; i++) chain.balls[i].wp += off;
  }
  // 静止练习关：把整链摆到轨道正中间（不然会挤在一头）
  if (level.centerChain && chain.balls.length) {
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < chain.balls.length; i++) {
      lo = Math.min(lo, chain.balls[i].wp); hi = Math.max(hi, chain.balls[i].wp);
    }
    const off = path.length / 2 - (lo + hi) / 2;
    for (let i = 0; i < chain.balls.length; i++) chain.balls[i].wp += off;
  }
  // ★ §65 静止关速度归零（但绳模型继续跑，见 advanceScene 里的注释）
  if (level.still) chain.targetSpeed = 0;
  else if (level.speed != null) chain.targetSpeed = level.speed * mt.scale;
  if (sc.mode === 'seven') for (let i = 0; i < chain.balls.length; i++) chain.balls[i].elem = chain.balls[i].base;
  sc.spawnCount = chain.balls.length;
  // 珠子袋挂上可用池，并按池重抽口中两颗（开局就该是能用的）
  rb.poolFn = function () { return weightedPool(sc); };   // ★ 加权池（不去重）
  // ★ 过期判定：这颗珠子还能不能找到目标（场上有没有与它互补的未配对球）
  // "手里这颗还能不能打到东西"。七球模式下判据变成"能不能跟某颗球反应"。
  rb.freshFn = function (tok) {
    const bs = sc.chain.balls;
    for (let i = 0; i < bs.length; i++) {
      if (bs[i].paired) continue;
      if (sc.mode === 'seven') { if (sevenReaction(bs[i].elem, tok, bs[i].quickened)) return true; }
      else if (isComplement(tok, bs[i].base) && inPool(sc, tok)) return true;
    }
    return false;
  };
  // ★ 身份token 的取值域必须在**开局时就定好**。
  //   早先只在模式切换（convertBoard）里设，于是"直接以七球模式开局"或
  //   "在七球模式下 rebuild"时，手里装的是碱基、场上摆的是元素 —— 两边对不上，
  //   HUD 上直接显示"装载 —/—"。smoke 的断言把这一条抓出来了。
  rb.tokens = sc.mode === 'seven' ? ELEMENTS : (sc.bases || BASES);
  // 按顺序抽：第二颗能看到第一颗，从而避开重复（见 ribosome.js drawBase）
  rb.loaded = [];
  rb.loaded.push(drawBase(rb));
  rb.loaded.push(drawBase(rb));
  syncBeads(sc);
  return sc;
}

export function syncBeads(sc) {
  const spawn = [], eliminate = [];
  const balls = sc.chain.balls;
  for (let i = 0; i < balls.length; i++) {
    const b = balls[i];
    const wpv = b.wp + (b.visOff || 0);          // 渲染位置 = 逻辑位置 + 视觉滞后
    b.wpv = wpv;
    const p = beadPos(sc.path, sc.rails.spawn, wpv);
    b.x = p.x; b.y = p.y; b.z = p.z;
    b.index = i;
    // 被配对的大球描一圈「该发什么色」——就是它互补碱基的颜色，玩家不用背配对表。
    // 错误配对（mark=2）改描警示红（DESIGN.md §32）。
    // ★ 七球模式下球的**填充色**就是元素色、球面上的字就是元素字（火水冰雷草岩风）。
    //   于是"该发什么"不再能靠反色直觉回答 —— 那件事改由瞄准提示负责（§57.11）。
    if (sc.mode === 'seven') {
      b.col = elemColor(b.elem);
      b.ink = ELEM[b.elem] ? ELEM[b.elem].ink : '#101820';
      b.label = elemGlyph(b.elem);
      b.pairGlow = b.paired ? (b.wrongMark ? WRONG_GLOW : elemColor(b.pairBase)) : null;
    } else if (sc.rules === 'classic') {
      // ★★ 经典祖玛（§66）：**用经典专用配色**（用户："原版球的颜色不要沿用，重新搞"）；
      //   球面**不显示字母**（原版是纯色球）。其它一切照旧 —— 所以这里只改这两样。
      b.col = colorOf(b.base, 'classic');
      b.ink = inkOf(b.base, 'classic');
      b.label = '';
      b.pairGlow = null;                 // 经典玩法没有配对，也就不该有"该发什么色"的描边
    } else {
      b.col = null; b.ink = null; b.label = b.base;
      b.pairGlow = b.paired ? (b.wrongMark ? WRONG_GLOW : complementColor(b.base)) : null;
    }
    spawn.push(b);
    if (b.paired) {
      const k = b.dock == null ? 1 : b.dock;      // 吸附飞行：0 -> 1
      const q = beadPos(sc.path, sc.rails.eliminate, wpv, k);
      const sevenB = sc.mode === 'seven';
      eliminate.push({
        // 匹配模式：小球用自己的碱基色 —— 调色板保证「互补 = 反色」，天然就是伙伴的反色。
        // 七球模式：小球显示**打中它的那个元素**（b.pairBase 存的就是它）。
        x: q.x, y: q.y, z: q.z, r: sc.metrics.r, base: b.pairBase,
        col: sevenB ? elemColor(b.pairBase) : null,
        ink: sevenB && ELEM[b.pairBase] ? ELEM[b.pairBase].ink : null,
        label: sevenB ? elemGlyph(b.pairBase) : b.pairBase,
        partner: b, paired: true, wrong: b.wrongMark === true, docked: k >= 1, index: i
      });
    }
  }
  sc.beads.spawn = spawn;
  sc.beads.eliminate = eliminate;
}

function pushEvent(sc, ev) {
  sc.events.push(ev);
  if (sc.events.length > 64) sc.events.splice(0, sc.events.length - 64);
}

// 命中分流（DESIGN.md §4.4）：互补 -> 配对；不互补 -> 爆炸
function resolveHit(sc, p, hit) {
  const ball = sc.chain.balls[hit.index];
  const ev = { type: '', index: hit.index, x: hit.x, y: hit.y, base: p.base, target: ball.base, mode: p.mode };
  // ★★ 先看**模式**，再看化学 —— 顺序反了就是 bug。
  //   ⚠ 曾经把 isComplement 放在最前面，于是「加球模式下打中一颗恰好互补的球」
  //     会走配对分支、根本不并入 —— 玩家看到的就是「都切到加球了为什么还能匹配」。
  //   规则：模式决定这一发干什么，化学只决定匹配模式下的结果。
  if (sc.mode === 'seven') {
    // ★★ 七球模式：**匹配本身就是元素反应**（用户原话「匹配相当于元素反应」）。
    //   球上写着元素、珠子也是元素；两者之间有反应 = 匹配成功 -> 读出 + 触发反应；
    //   没有反应 = 匹配失败 -> 走原有的"错误配对"（mark 2 -> 爆炸）。
    //   所以玩家不是在找"唯一能配上的那颗"，而是在选"我要哪个反应"。
    const r = sevenHit(sc, hit.index, p.base);
    ev.type = r ? 'pair' : 'mismatch';
    if (r) { ev.reaction = r.name; ev.mult = r.mult; }
    pushEvent(sc, ev);
    return ev;
  }
  // ★★ 经典祖玛（DESIGN.md §66）：射出的球**无条件插进链子**（原版行为），
  //   没有配对、没有错配、没有爆炸；随后的消除由 clearImmediately 按"同色连续 ≥3"判定
  //   （连锁由那个循环自动产生，回退由 pushBack 统一施加）。
  if (sc.rules === 'classic') {
    ev.type = 'insert';
    const mgc = startMerge(sc, ball, p.base, hit.x, hit.y);
    mgc.elem = p.elem || null;
    ev.willMerge = true;
    pushEvent(sc, ev);
    return ev;
  }
  if (p.mode === 'insert') {
    // 加球模式：**无条件**并入主链。这就是原版的行为 —— 原版子弹必然并入
    // （CurveMgr.cpp:1817 InsertInList，随后 1860 CheckSet 自动判消除）。
    ev.type = 'insert';
    const mg = startMerge(sc, ball, p.base, hit.x, hit.y);
    mg.elem = p.elem || null;      // §57：并入的球也带上这发的元素
    ev.willMerge = true;
  } else if (isComplement(p.base, ball.base)) {
    ball.paired = true;
    ball.wrongMark = false;
    ball.pairBase = p.base;
    ball.dock = 0;
    ev.type = 'pair';
    sc.stats.pairs += 1;
  } else {
    // 错误配对（mark = 2，DESIGN.md §32）：走**同一条**配对路径 ——
    // 占用 + 吸附飞行 + 三消道上出现绑定小球，只是状态值记成 2、外观上区分。
    ball.paired = true;
    ball.wrongMark = true;
    ball.pairBase = p.base;
    ball.dock = 0;
    ev.type = 'mismatch';
    sc.stats.mismatches += 1;
  }
  pushEvent(sc, ev);
  return ev;
}

// U12 加球：弹丸并入出球道珠串。分两步——先钻进去（mergeTime），再正式入列。
// 入列时只做 splice，槽位由绳模型下一帧自动顶开（见 chain.js insertBall 注释）。
// 遮挡：并入过程中的 z **由它所在的 wp 决定**（beadPos 返回轨道层 z），
// 所以在桥/自交处不会穿到上层轨道带外面去。
// ★ 命中侧判定（DESIGN.md §49）：照原版 CurveMgr::CheckCollision:427
//     flag = (子弹位置 − 球心) × 轨道法线 < 0   ->  mHitInFront
//   原版可以插在命中球的**前侧或后侧**；我们最早只会插"出球端那一侧"，
//   玩家没法控制插在哪边 —— 而"插在哪边"恰恰是解卡死区段的关键。
export function startMerge(sc, target, base, hitX, hitY) {
  // 2D 叉积：(dx,dy) x (nx,ny) = dx*ny - dy*nx
  const n = sc.path.normalAt(target.wp);
  const dx = (hitX == null ? target.x : hitX) - target.x;
  const dy = (hitY == null ? target.y : hitY) - target.y;
  const inFront = (dx * n.y - dy * n.x) < 0;      // true = 插在靠洞（队头）那一侧
  const m = {
    targetId: target.id,
    base: base,
    inFront: inFront,
    t: 0,
    x: target.x, y: target.y, z: target.z,
    r: sc.metrics.r
  };
  sc.merges.push(m);
  sc.stats.merges += 1;
  pushEvent(sc, { type: 'merge', base: base, index: target.index });
  return m;
}

function findBallIndex(ch, id) {
  for (let i = 0; i < ch.balls.length; i++) if (ch.balls[i].id === id) return i;
  return -1;
}

function updateMerges(sc, dt) {
  const mt = sc.metrics;
  for (let i = sc.merges.length - 1; i >= 0; i--) {
    const m = sc.merges[i];
    const idx = findBallIndex(sc.chain, m.targetId);
    if (idx < 0) { sc.merges.splice(i, 1); continue; }   // 目标被消掉了，并入作废
    const target = sc.chain.balls[idx];
    m.t += dt / DESIGN.mergeTime;
    const k = Math.min(1, m.t);
    const T = touchDist(sc.chain.mt, target, { r: mt.R });
    // 靠洞那侧 = wp 增大方向；靠出球端那侧 = wp 减小方向
    const wp = m.inFront ? (target.wp + T * k) : Math.max(0, target.wp - T * k);
    const p = beadPos(sc.path, sc.rails.spawn, wp);
    m.x = p.x; m.y = p.y; m.z = p.z;
    m.r = mt.r + (mt.R - mt.r) * k;      // 从小球长成大球：护住"尺寸=哪条道"这条识别通道
    if (m.t >= 1) {
      // 我们的下标 0 = 洞端。插在靠洞那侧 -> 下标 idx；靠出球端那侧 -> idx+1
      const at = m.inFront ? idx : idx + 1;
      insertBall(sc.chain, at, {
        wp: wp, base: m.base, r: mt.R, id: sc.chain.nextId++,
        // ⚠ 这里**不能**再 sc.spawnCount++ —— spawnCount 是"出球道喂进来的球数"，
        //   是关卡预算（原版 CurveDesc::mNumBalls）的计数器；玩家自己加进去的球
        //   不该算进关卡预算里，否则切到加球模式打几发就把关卡的球数提前耗光了。
        //   （球上的 n 字段没有任何地方读，早先只是顺手拿来当序号。）
        n: null, paired: false, wrongMark: false, pairBase: null, dock: null,
        elem: m.elem || null            // §57：并入进来的球带的是这一发的元素
      });
      if (DESIGN.insertPairs) tryInsertPair(sc, at);
      sc.merges.splice(i, 1);
    }
  }
}

// 加球的正反馈（DESIGN.md §18）：插入后若与**任一邻居**互补，这颗新球自己获得绑定小球。
// 规则表述统一为「绑定小球表示这颗主链球已被读出」：
//   - 射击配对：被识别的 A 获得小球
//   - 插入配对：新掺入的 B 获得小球
// 小球上显示的字母 = 伙伴的碱基，颜色 = 持有者颜色的反色（与射击配对同构）。
export function tryInsertPair(sc, i) {
  const balls = sc.chain.balls;
  const b = balls[i];
  if (!b || b.paired) return null;
  const head = balls[i - 1];     // 队头侧（阅读方向）
  const tail = balls[i + 1];
  let mate = null;
  if (head && isComplement(b.base, head.base)) mate = head;
  else if (tail && isComplement(b.base, tail.base)) mate = tail;
  if (!mate) return null;
  b.paired = true;
  b.wrongMark = false;
  b.pairBase = mate.base;        // 小球显示"和我配对的那颗"的碱基
  b.dock = 0;
  pushEvent(sc, { type: 'insert-pair', base: b.base, with: mate.base });
  return b;
}

function updateProjectiles(sc, dt) {
  const list = sc.projectiles;
  for (let i = list.length - 1; i >= 0; i--) {
    const p = list[i];
    advanceProjectile(p, dt);
    // 匹配模式：已占用的球是惰性的，弹丸直接穿过；加球模式：任何球都能当并入锚点
    const hit = sweepHit(sc.chain.balls, p.px, p.py, p.x, p.y, p.r, p.mode !== 'insert');
    if (hit) {
      resolveHit(sc, p, hit);
      list.splice(i, 1);
      continue;
    }
    if (projectileExpired(p, sc.view, sc.metrics)) list.splice(i, 1);
  }
}

// ★ 消除后退（DESIGN.md §42）：消掉 k 颗 -> 往出球端方向共退 k 个球位。
//
//   判定条件只有一个：**消除段是不是贴在洞端**（headEnd <= 0）。
//     - 贴在洞端：洞端那一侧本来就是空的，没有球该退。而且删除本身已经把队头
//       往后送了 k 个球位（实测贴洞端消除 k=3，队头当帧退 117.8 = 3×touchDist）
//       —— 奖励已经兑现，退第二次就是**双重兑现**（总退 (2k+1) 个球位）。
//     - 在链中间：删除不动队头，这时才需要后退兑现奖励 -> 标记洞端那颗（下标 0，
//       即原版 mBallList.back()），拖动被消除留下的缝截断，出球端那截不动。
//
//   ⚠ 试过两版错的替代方案，都写在这里免得重蹈覆辙：
//     v1 "一律标记洞端那颗"          -> 双重兑现；还把出球端的球拖出轨道回收（8000 帧 36~40 颗）
//     v2 "加夹紧：任何球不许退过冒球口" -> **没用**。夹紧按"这一帧会被拖动的球"算余量，
//        而消除留下的缝会截断拖动，被拖那段的末端根本到不了队尾，余量就很大 -> 几乎从不触发。
//        **夹紧管的是「别退出去」，管不了「该不该退」**；该不该退只能由消除位置决定。
function pushBack(sc, clearedCount, headEnd) {
  const ch = sc.chain;
  if (ch.balls.length === 0) return null;
  if (headEnd == null || headEnd <= 0) return null;
  const T = touchDist(ch.mt, { r: sc.metrics.R }, { r: sc.metrics.R });
  return applyBackward(ch, 0, DESIGN.backFrames, clearedCount * T);
}


// ⚠ 这里曾经有一个 pairBackPush()：配对定型时给洞端侧那颗邻居打后退标记（照原版
//   UpdateSuckingBalls 的 SetBackwardsCount(30)）。**已删除**，因为那个映射是错的：
//     原版的「合并(suck)」= 两颗同色球**物理合并成一颗**，链真的缩短了 -> 后退是给这个动作做缓冲；
//     我们的「配对」     = 给主链球**贴一个标记**，链的几何完全不变 -> 根本没有需要缓冲的事件。
//   实测后果：配对一颗球，它会往出球端退 15 单位，而它前面的球不动 -> **链从配对点裂开一条缝**，
//   同时 stopTime 每帧被重置 -> **整链冻结约 30 帧**。玩家看到的就是「只配对了一个，链却莫名其妙地动」。
//   见 DESIGN.md §37。

// ★ 过关（对应原版 Board::mHaveReachedTarget -> GameState_LevelUp）。
//   两个条件任一满足即过关：分数达标 / 场上清空。见 DESIGN.md §52。
function win(sc, reason) {
  if (sc.won) return false;
  sc.won = true;
  sc.stopAdding = true;
  // ★ 记下过关原因（DESIGN.md §55）：清空过关 / 分数过关在 HUD 上要能看出来。
  //   早先只记事件不记状态，排查"到底是哪条路赢的"时踩过坑
  //   （探针报告"6/6 清零路"，实际是分数路，过关时间恒定 16 秒）。
  sc.winReason = reason;
  pushEvent(sc, { type: 'win', score: sc.score, reason: reason });
  return true;
}

// ★ 爆炸（DESIGN.md §30.3 / §32）：移除那颗 2 **加上左右各一颗**，共 3 颗。
//   这正是「所有移除都是长度 3 的倍数」这条统一律的一个实例，所以不会破坏 mod-3 结构
//   （这也是为什么不采纳"只移除那颗 2"——那样会得到非 3 的倍数）。
//   注意：爆炸**不施加**后退冲量 —— 后退是 3n 消的奖励，爆炸是玩家主动付出的成本。
function explodeAt(sc, i) {
  // 邻域快照（i-2 .. i+2 的状态）—— 排查"为什么这里会爆"时非常有用
  const bs = sc.chain.balls;
  const pat = [
    i - 2 >= 0 ? markFinal(bs[i - 2]) : -1,
    i - 1 >= 0 ? markFinal(bs[i - 1]) : -1,
    2,
    i + 1 < bs.length ? markFinal(bs[i + 1]) : -1,
    i + 2 < bs.length ? markFinal(bs[i + 2]) : -1
  ];
  const removed = removeRange(sc.chain, i - 1, i + 1);
  sc.stats.explosions += 1;
  pushEvent(sc, { type: 'explode', index: i, n: removed.length, pat: pat });
  // ★ 爆炸也要走后退 —— 它移除 3 颗，和 3n 消在几何上完全一样。
  //   按 §42 的规则：该不该退由**消除位置**决定（洞端靠删除兑现，链中间靠后退兑现）。
  //   爆炸发生在链中间时删除不动队头 -> 就该退。早先漏了这一步，表现为
  //   "爆炸后链子不夹紧、缝要 2.8 秒才补上（消除只要 0.9 秒）"。
  //   headEnd = i - 1：接缝靠洞端那一侧的下界（和 eliminateRun 传 run.i0 同义）。
  pushBack(sc, removed.length, i - 1);
  return removed.length;
}

// ★ 结算循环（DESIGN.md §32）：**先爆炸，后 3n 消，循环到不动点**。
//   一次只处理一个爆炸、从左到右扫 —— 结果因此是确定的：两个三元组重叠时
//   （例 1 2 1 2 1），先爆的那个会把后面那颗一起清掉，不会产生歧义。
function settle(sc) {
  let total = 0;
  // ★ §64 noClear：不消球、也不爆炸 —— 这一关只有"配对"这一件事。
  //   注意爆炸也要一起关掉：不然玩家打错一颗，场上就莫名其妙炸了 3 颗，
  //   而这一关根本没教过爆炸是什么。
  if (!sc.noClear) {
    for (let guard = 0; guard < 128; guard++) {
      // ★ 经典祖玛（§66）：**没有"错配"这回事**（打错只是插进去）→ 不做爆炸判定。
      //   即使不做这层护栏也不会误炸（经典模式没有任何球会被标成 wrongMark），
      //   但写出来是为了让"经典不做爆炸"这条规则在代码里看得见。
      if (sc.rules !== 'classic') {
        const ei = findExplosion(sc.chain);
        if (ei >= 0) { total += explodeAt(sc, ei); continue; }
      }
      const cleared = clearImmediately(sc);
      if (!cleared) break;
      total += cleared;
    }
  }
  refreshRuns(sc);
  // ★ 过关条件二：**场上清空**（DESIGN.md §52）。
  //   正常玩法里链子会立刻从出球口补上，所以"空"只可能来自"你把整场清光了"
  //   —— 比如场上只剩 3 颗 mark=2，一次爆炸全带走。这种时候必须结束，不能干等着。
  //   （失败演出 updateLosing 也会清空链子，但那条走的是 sc.losing，不会到这里。）
  // ★ §64 读出全部：这一关的目标就是"把每一颗都配对"，不做别的。
  //   判据用 mark != 0（读对读错都算"打中过"）—— 第一关不该因为一次手滑就没法完成。
  if (sc.goalMatchAll && !sc.losing && !sc.gameOver && !sc.won && sc.chain.balls.length > 0) {
    let all = true;
    for (let i = 0; i < sc.chain.balls.length; i++) {
      if (markFinal(sc.chain.balls[i]) === 0) { all = false; break; }
    }
    if (all) win(sc, 'match');
  }

  // ★ 清空过关：**预算已发满** + 场上清空（DESIGN.md §53 / §55）。
  //   链子清空本身不算——它每帧都在补；只有"发完了 + 清光了"才是真的清关。
  // ★ 清空过关**只在有限球数的关卡里生效**（DESIGN.md §55）：无限出球时链子每帧
  //   都在补，"场上为空"只是清球后的一瞬间，判赢会秒过关 —— 所以无尽关走分数过关。
  //
  // ★ 判"不足 3 颗"而不是"等于 0"（DESIGN.md §56）：这不是"差不多清了"，
  //   而是**逻辑上已经不可能再消**。所有移除都是 3 的倍数（3n 消与爆炸各 3 颗），
  //   场上剩 1~2 颗时不存在任何合法的 3n 段，玩家再怎么打也清不空。
  //   实测（tools/probe-sloppy.mjs，30% 错误率的玩家）出现过"场上剩 2 颗、都已正确配对、
  //   预算发完"的死局（残留标记 = 11）—— 按 === 0 判就永远卡在那里。
  // ⚠ 必须显式挡 gameOver：命尽时 updateLosing 会把 losing 置回 false 并把链子吸空，
  //   只判 !sc.losing 的话，一次 gameOver 会被误判成过关。
  if (DESIGN.winOnClear && !sc.losing && !sc.gameOver && !sc.won &&
      sc.chain.balls.length < 3) {
    const bud = sc.level.ballBudget != null ? sc.level.ballBudget : DESIGN.ballBudget;
    if (bud > 0 && sc.spawnCount >= bud) win(sc, 'clear');
  }
  return total;
}

// U9：立即消除 + 级联到不动点。
// 从后往前删，避免下标位移；删完重算 run（空隙 λ=0 会自然阻断级联，等回缩闭合后下一帧继续）。
// ★ 经典祖玛（§66）：规则函数按 ruleset 选 ——
//   RNA 用"已配对标记 + 长度是 3 的倍数"，经典用"同色 + 长度 ≥3"。
function clearableFor(sc) {
  return (sc.rules === 'classic') ? classicClearable(sc.chain) : clearableRuns(sc.chain);
}
// 给渲染/HUD 用的分段读数（两套规则的"段"含义不同，要各用各的）
function refreshRuns(sc) {
  sc.runsInfo = (sc.rules === 'classic') ? classicRuns(sc.chain) : computeRuns(sc.chain);
}

function clearImmediately(sc) {
  let total = 0;
  let minPos = -1;          // 这一帧里"洞端那侧最小的一段"的位置（决定后退标记打在哪）
  for (let guard = 0; guard < 64; guard++) {
    const hits = clearableFor(sc);
    if (!hits.length) break;
    for (let i = hits.length - 1; i >= 0; i--) {
      const run = hits[i];
      // ★ eliminateRun 返回的是**被移除的球数组**，不是数量 —— 直接加会把 total 变成字符串，
      //   进而让 pushBack 的距离算出 NaN。这里必须取 .length。
      total += eliminateRun(sc, run).length;
      if (run.i0 > 0 && (minPos < 0 || run.i0 < minPos)) minPos = run.i0;
    }
  }
  if (total) {
    pushBack(sc, total, minPos);   // ★ 整帧只结算一次（见 pushBack 注释）
    refreshRuns(sc);
  }
  return total;
}

// U9：整段消除。
// ★ 消除后**不回填、不瞬移**：出球道按原版逻辑（留下空隙，由绳模型的后段追上来补）。
//   解围靠**原版式后退冲量**：整链沿轨道往冒球口方向渐进后退 k×touchDist（k = 消掉的颗数）。
//   这样"消除 = 后退 k 个球位"从视觉上真的看得见，而不是瞬移。
function eliminateRun(sc, run) {
  const removed = removeRange(sc.chain, run.i0, run.i1);
  sc.stats.cleared += removed.length;
  sc.stats.codons += 1;
  // ★ 增幅反应计分（DESIGN.md §57）：被标记了 amp 的球按倍率计分。
  //   这正是原神「增幅反应基于技能伤害倍率」的映射 —— 剧变反应则去改盘面（explode/autoPair…）。
  let gained = 0;
  for (let k = 0; k < removed.length; k++) gained += DESIGN.scorePerBall * (removed[k].amp || 1);
  sc.score += Math.round(gained);
  // ★ 过关条件一：分数达标（对应原版 Board::mHaveReachedTarget -> GameState_LevelUp）
  const sTgt = sc.level.scoreTarget != null ? sc.level.scoreTarget : DESIGN.scoreTarget;
  if (!sc.won && sTgt > 0 && sc.score >= sTgt) win(sc, 'score');
  sc.lastClear = { i0: run.i0, i1: run.i1, len: run.len };
  pushEvent(sc, { type: 'clear', len: run.len, i0: run.i0, i1: run.i1 });
  // 后退**不在这里**施加：同一帧可能连续消多段，若每段各施加一次，
  // 先被标记的那颗球可能被后一次消除连带删掉（实测过：级联时标记直接消失）。
  // 统一由 clearImmediately 在整帧结算完后施加一次。

  refreshRuns(sc);
  return removed;
}

// A15 失败条件：与祖玛一致 —— 队头撞到降解洞穴，整条珠串被吸进去，扣 1 命。
// 原版对应 Board::SetLosing()（mLives -= 1）+ CurveMgr::UpdateLosing()（所有球推向终点并逐颗删除）。
export function startLosing(sc) {
  if (sc.losing || sc.gameOver) return sc.lives;
  // ★ 结晶护盾（DESIGN.md §57）：晶片抵挡一次洞穴吞噬 —— 不扣命，把整链往回拽一截。
  //   不拽的话队头还贴在洞口，下一帧立刻又触发，会一口气把护盾全吃光。
  if (sc.shields > 0) {
    sc.shields -= 1;
    const bs = sc.chain.balls;
    if (bs.length) {
      const pull = 3 * touchDist(sc.chain.mt, bs[0], bs[Math.min(1, bs.length - 1)]);
      for (let i = 0; i < bs.length; i++) bs[i].wp = Math.max(0, bs[i].wp - pull);
      sc.chain.stopTime = DESIGN.backStopFrames;
    }
    pushEvent(sc, { type: 'shieldBlock', shields: sc.shields });
    return sc.lives;
  }
  sc.losing = true;
  sc.lives = Math.max(0, sc.lives - 1);
  sc.stats.lost += 1;
  pushEvent(sc, { type: 'losing', lives: sc.lives });
  return sc.lives;
}

function updateLosing(sc, dt) {
  const ch = sc.chain;
  const end = sc.path.length;
  const step = DESIGN.losingSpeed * sc.metrics.scale * dt;
  const keep = [];
  for (let i = 0; i < ch.balls.length; i++) {
    const b = ch.balls[i];
    b.wp += step;
    if (b.wp < end) keep.push(b);
  }
  ch.balls = keep;
  syncBeads(sc);
  if (ch.balls.length > 0) return;

  if (sc.lives <= 0) {
    sc.losing = false;
    sc.gameOver = true;
    pushEvent(sc, { type: 'gameover', score: sc.score });
    return;
  }
  restartBoard(sc);
}

// 扣命后重开本关（分数与剩余命保留）。对应原版失败演出结束后重铺轨道。
function restartBoard(sc) {
  const ch = sc.chain;
  ch.balls = [];
  ch.speed = 0;
  if (sc.level.script) {
    const bs2 = parseScript(sc.level.script);
    const n = bs2.length;
    prefillChain(ch, n, function (i) { return parseScriptEntry(bs2[n - 1 - i]).base; });
    for (let i = 0; i < ch.balls.length; i++) {
      const sp = parseScriptEntry(bs2[i]);
      if (sp.mark) {
        const c = COMPLEMENT[ch.balls[i].base];
        ch.balls[i].paired = true;
        ch.balls[i].wrongMark = (sp.mark === 2);
        ch.balls[i].pairBase = (c && c.length) ? c[0] : null; ch.balls[i].dock = 1;
      }
    }
  } else {
    prefillChain(ch, sc.level.prefill || 14, function () {
      return sc.mode === 'seven' ? sc.rng.pick(ELEMENTS) : sc.rng.pick(sc.bases || BASES);
    });
  }
  if (sc.level.startWpFrac && ch.balls.length) {
    const off = sc.level.startWpFrac * sc.path.length - ch.balls[0].wp;
    if (off > 0) for (let i = 0; i < ch.balls.length; i++) ch.balls[i].wp += off;
  }
  if (sc.level.centerChain && ch.balls.length) {
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < ch.balls.length; i++) {
      lo = Math.min(lo, ch.balls[i].wp); hi = Math.max(hi, ch.balls[i].wp);
    }
    const off = sc.path.length / 2 - (lo + hi) / 2;
    for (let i = 0; i < ch.balls.length; i++) ch.balls[i].wp += off;
  }
  if (sc.mode === 'seven') for (let i = 0; i < ch.balls.length; i++) ch.balls[i].elem = ch.balls[i].base;
  sc.spawnCount = ch.balls.length;
  sc.runsInfo = [];
  sc.projectiles.length = 0;
  sc.merges.length = 0;
  sc.cores.length = 0;           // §57：草原核挂在不存在的球上，直接清掉
  sc.losing = false;
  pushEvent(sc, { type: 'restart', lives: sc.lives });
  syncBeads(sc);
}

export function fireShot(sc) {
  if (sc.losing || sc.gameOver || sc.won) return null;
  const shot = fire(sc.rb);
  if (!shot) return null;
  const p = makeProjectile(shot, sc.metrics, sc.mode);
  p.mode = sc.mode;
  sc.projectiles.push(p);
  sc.stats.fired += 1;
  return p;
}

// 一帧推进：冒球 -> 绳子推进 -> 核糖体/弹丸 -> 吸附 -> 阅读框消除 -> 洞穴吞球 -> 同步渲染位置
export function advanceScene(sc, dt) {
  if (sc.gameOver) return [];                            // 命尽：场景冻结
  if (sc.won) return [];                                 // 过关：场景冻结（对应原版 GameState_LevelUp）
  if (sc.losing) { updateLosing(sc, dt); return []; }    // 失败演出：珠子被吸进洞穴
  const ch = sc.chain;

  // 后退冲量期间不喂入 —— 对应原版 AdvanceBackwardBalls 末尾的 mStopTime = 20
  const budget = sc.level.ballBudget != null ? sc.level.ballBudget : DESIGN.ballBudget;
  const underBudget = budget <= 0 || sc.spawnCount < budget;      // 预算 0 = 无限出球
  // ★ §63 静止练习关不出球：链子不动，队尾没腾出位置，出了也塞不进；
  //   更关键的是"这一关的球就是场上这些"，教具要可控。
  if (!sc.still && !sc.stopAdding && underBudget && ch.stopTime <= 0 && !hasBackward(ch)) {
    // ★ 同碱基成段（原版 CurveDesc::mBallRepeat，见 DESIGN.md §54）：
    //   以 baseRepeat 概率重复上一颗；否则**一定换成不同的**（原版 do-while 保证）。
    const seven = sc.mode === 'seven';
    const tail = ch.balls.length ? ch.balls[ch.balls.length - 1].base : null;
    let base;
    if (tail && sc.rng() < DESIGN.baseRepeat) {
      base = tail;
    } else {
      const pool = seven ? ELEMENTS : (sc.bases || BASES);
      base = sc.rng.pick(pool);
      let guard = 0;
      while (base === tail && guard++ < 16) base = sc.rng.pick(pool);
    }
    const ball = spawnBall(ch, base);
    if (ball) {
      ball.n = sc.spawnCount++;
      // ★ 七球模式（§57 改版）：球的**身份**就是元素，不再有"碱基 + 附着"两层。
      //   所以这里直接把 base 也写成同一个元素 —— 两条通道指向同一个值，
      //   老代码里凡是用 base 的地方（字母、配色）都不会读到 undefined。
      if (seven) ball.elem = base;
    }
  }
  // ★ §65 静止练习关：**速度归零**，但绳模型照常跑。
  //   ⚠ 不能整个跳过 advanceChain —— 那样"插入一颗把珠串顶开"就不工作了，
  //     ④ 加球那一关会直接叠在一起（绳模型的推动就在 advanceChain 里）。
  //   速度 0 的效果是：队尾不前进，但推动/缝合照旧 —— 这正是"静止"要的东西。
  advanceChain(ch, dt, sc.path.length);

  tickRibosome(sc.rb, dt);
  updateProjectiles(sc, dt);
  updateMerges(sc, dt);
  tickElements(sc, dt);          // §57：草原核 / 燃烧 / 冻结计时

  for (let i = 0; i < ch.balls.length; i++) {
    const b = ch.balls[i];
    if (b.dock == null || b.dock >= 1) continue;
    b.dock = Math.min(1, b.dock + dt / DESIGN.dockTime);
    if (b.dock >= 1 && b.dockDone !== true) b.dockDone = true;
  }

  if (sc.modeFlash > 0) sc.modeFlash = Math.max(0, sc.modeFlash - dt);
  decayVisual(sc, dt);

  // U9 + 2 态：**当帧结算到不动点**（先爆炸、后 3n 消）。
  // 任何"长度是 3 的倍数且 >=3"的 run、以及任何"该爆没爆"的 2，都不允许存活到下一帧。
  settle(sc);

  // A15：队头撞上降解洞穴 -> 整条珠串被吸走 + 扣 1 命
  // ★ §63 静止练习关没有洞穴 —— 也就没有失败。玩家可以慢慢想。
  if (!sc.still && ch.balls.length > 0 && ch.balls[0].wp >= sc.path.length) startLosing(sc);

  syncBeads(sc);
  return [];
}

// ★ 切换轨道（模式）。加球模式打出去的是大球，所以口中珠子的尺寸也跟着变 —— 尺寸就是模式。
// ==================== §57 元素反应 ====================
//
// 两层结构：
//   序列层（碱基）：A/U/G/C 互补 -> 能不能配对（能不能消）—— 原有规则，完全不动
//   能量层（元素）：附着在球上；配对成功时把珠子带的元素附着上去，并与左右邻居结算反应
//
// ★ 先手 / 后手：邻居身上已有的附着 = **先手**，本次打上去的 = **后手**。
//   倍率由后手决定（原神：水打火 2.0、火打水 1.5），所以反应表里同一反应有两条。
// ★ 所有反应造成的移除都是 **3 颗**（和爆炸同一条铁律），所以 mod-3 结构不会被破坏。

// 能当"先手附着"的元素（风/岩不行）
// ★★ 七球模式的匹配判定 —— **单一真源**：真正命中时用它，瞄准提示也用它。
//    ⚠ 绝不能写两套：一旦分叉就会出现“提示说会蒸发、打下去却是冻结”，
//      而玩家唯一的判断依据就是提示 —— 提示骗人比没有提示更糟。
//    纯读，不改任何状态，所以可以每帧对每颗球调用。
export function findSevenReaction(sc, idx, beadElem) {
  const ball = sc.chain.balls[idx];
  if (!ball || !beadElem) return null;
  // 碎冰优先：原神里“冻结 + 岩元素伤害”是独立的一条（此时冰+岩本来会查成结晶）
  if (ball.frozen > 0 && beadElem === 'geo') return SHATTER;
  return sevenReaction(ball.elem, beadElem, ball.quickened);
}

// 七球模式的"一颗球被打中"：**匹配 = 有反应**。
//   有反应 -> 球被读出（mark 1）+ 当场触发那个反应
//   没反应 -> 走原有的"错误配对"（mark 2）-> 后续爆炸
// 单独抽出来是为了让单测能直接打一颗球，不必每次摆弹道（弹道那条路径另有覆盖），
// 而且保证"测试打的"和"玩家打的"是同一条代码。
export function sevenHit(sc, idx, beadElem) {
  const ball = sc.chain.balls[idx];
  if (!ball) return null;
  const r = findSevenReaction(sc, idx, beadElem);
  ball.paired = true;
  ball.wrongMark = !r;
  ball.pairBase = beadElem;
  ball.dock = 0;
  if (!r) { sc.stats.mismatches += 1; return null; }
  sc.stats.pairs += 1;
  fireReaction(sc, idx, idx, r, beadElem, 0);
  // ★ 草原核被雷/火打中 -> 超绽放 / 烈绽放。和上面那次反应**是两件事**，都会发生。
  //   （原来这一步挂在两层模式的 applyElement 里，改成七球之后漏了 —— 测试当场抓到。）
  detonateCoresFor(sc, ball.id, beadElem);
  return r;
}

// 切换模式时把场上的球与手里的珠子搬到新模式的身份空间里。
// ⚠ 不做这一步的话，从匹配模式切到七球模式后场上全是碱基字母、手里也是碱基 ——
//   两边对不上，一发都打不中（元素模式时代就踩过“切过去全是裸球”这个坑）。
function convertBoard(sc) {
  const seven = sc.mode === 'seven';
  const bs = sc.chain.balls;
  for (let i = 0; i < bs.length; i++) {
    const b = bs[i];
    if (seven) {
      if (ELEMENTS.indexOf(b.base) < 0) b.base = sc.rng.pick(ELEMENTS);
      b.elem = b.base;
    } else {
      if (BASES.indexOf(b.elem) < 0) b.elem = null;   // 七球的身份不是碱基 -> 清掉
      if (ELEMENTS.indexOf(b.base) >= 0) b.base = sc.rng.pick(BASES);
    }
  }
  // 手里两颗也要换到新的身份空间，否则第一发必然是废弹
  sc.rb.tokens = seven ? ELEMENTS : BASES;
  for (let k = 0; k < sc.rb.loaded.length; k++) sc.rb.loaded[k] = sc.rng.pick(sc.rb.tokens);
  if (sc.rb.loadedElem) {
    for (let k = 0; k < sc.rb.loadedElem.length; k++) sc.rb.loadedElem[k] = sc.rng.pick(ELEMENTS);
  }
  syncBeads(sc);
}

function fireReaction(sc, idx, auraIdx, r, trigger, depth) {
  const balls = sc.chain.balls;
  const ball = balls[idx];
  const ev = {
    type: 'reaction', id: r.id, name: r.name, mult: r.mult, effect: r.effect,
    index: idx, auraIndex: auraIdx, aura: balls[auraIdx] ? balls[auraIdx].elem : null,
    trigger: trigger, score: DESIGN.elemScorePerReaction
  };
  sc.stats.reactions += 1;
  switch (r.effect) {
    case 'amp':
      // 增幅：这颗球被消掉时按倍率计分（原神：增幅基于技能伤害倍率）
      ball.amp = Math.max(ball.amp || 1, r.mult);
      break;
    case 'quicken':
      // 原激化：施加激元素附着（原神原文），之后再被雷/草触发就是超激化/蔓激化
      // ⚠ 七球模式下球的 elem **就是它的身份**，改掉等于把球换了种 —— 只能打标记。
      if (sc.mode !== 'seven') ball.elem = QUICK;
      ball.quickened = true;
      break;
    case 'explode':
      ev.removed = removeAround(sc, idx);
      break;
    case 'autoPair':
      ev.pairedCount = autoPairNear(sc, idx, DESIGN.elemAutoPairCount);
      break;
    case 'chain':
      ev.pairedCount = electroChargedBurst(sc);
      break;
    case 'freeze':
      ev.frozen = freezeSegment(sc, idx, DESIGN.elemFreezeTime);
      break;
    case 'swirl':
      // ★ 被扩散出去的是**触发它的那个元素**（原神：风触及火水雷冰，被带走的是火水雷冰）。
      //   两层模式里 auraIdx 是邻居，它身上那个元素就是要扩散的元素；
      //   但七球模式里 auraIdx === idx，而那颗球的元素是**风本身** ——
      //   直接读 balls[auraIdx].elem 会把"风"当成被扩散物，于是扩散什么都不做
      //   （回归测试当场抓到：反应次数只有 1，邻居的蒸发没发生）。
      ev.spread = swirlFrom(sc, auraIdx,
        sc.mode === 'seven' ? trigger : (balls[auraIdx] ? balls[auraIdx].elem : null),
        idx, depth + 1);
      break;
    case 'shield':
      sc.shields = Math.min(DESIGN.elemShieldMax, sc.shields + 1);
      ev.shields = sc.shields;
      break;
    case 'core':
      ev.coreId = spawnCore(sc, idx);
      break;
    case 'burn':
      ball.burn = DESIGN.elemBurnTime;
      ball.burnAcc = 0;
      break;
  }
  sc.score += DESIGN.elemScorePerReaction;
  sc.lastReaction = ev;
  sc.reactionFlash = DESIGN.reactionFlashTime;
  pushEvent(sc, ev);
  return ev;
}

// 就地移除 3 颗（以 idx 为中心；贴边时整体挪进来，保证永远是 3 颗）
function removeAround(sc, idx) {
  const bs = sc.chain.balls;
  const n = bs.length;
  if (n === 0) return 0;
  let lo = idx - 1, hi = idx + 1;
  if (lo < 0) { lo = 0; hi = Math.min(n - 1, 2); }
  if (hi > n - 1) { hi = n - 1; lo = Math.max(0, n - 3); }
  const removed = removeRange(sc.chain, lo, hi);
  sc.stats.reactionRemoves += 1;
  pushBack(sc, removed.length, lo);
  return removed.length;
}

// 自动"读出"一颗球（= 正确配对，标记 1）。超导/感电/燃烧都用它 ——
// 它们帮玩家**凑够 3n 段**，但一颗都不移除，所以不碰 mod-3 结构。
function autoPairBall(sc, i) {
  const b = sc.chain.balls[i];
  if (!b || b.paired) return false;
  const c = COMPLEMENT[b.base];
  b.paired = true;
  b.wrongMark = false;
  b.pairBase = (c && c.length) ? c[0] : null;
  b.dock = 1;
  return true;
}

function autoPairNear(sc, idx, count) {
  const n = sc.chain.balls.length;
  const order = [];
  for (let d = 1; d < n; d++) { order.push(idx - d, idx + d); }
  let done = 0;
  for (let k = 0; k < order.length && done < count; k++) {
    const j = order[k];
    if (j < 0 || j >= n) continue;
    if (autoPairBall(sc, j)) done += 1;
  }
  return done;
}

// 感电传导：原神原文「如果周围有附着水元素的敌人，会间歇性地向周围放电」
function electroChargedBurst(sc) {
  const bs = sc.chain.balls;
  let done = 0;
  for (let i = 0; i < bs.length; i++) {
    if (bs[i].elem !== 'hydro') continue;
    for (let s = -1; s <= 1; s += 2) {
      const j = i + s;
      if (j < 0 || j >= bs.length) continue;
      if (autoPairBall(sc, j)) { done += 1; break; }
    }
  }
  return done;
}

function freezeSegment(sc, idx, secs) {
  const bs = sc.chain.balls;
  sc.chain.freezeTime = Math.max(sc.chain.freezeTime || 0, secs);
  let n = 0;
  for (let j = idx - 1; j <= idx + 1; j++) {
    if (j >= 0 && j < bs.length) { bs[j].frozen = secs; n += 1; }
  }
  sc.stats.freezes += 1;
  return n;
}

// 扩散：把元素往两侧传播（原神原文「产生附着，或进一步引发其他反应」）
function swirlFrom(sc, srcIdx, elem, skipIdx, depth) {
  if (!elem || depth > DESIGN.elemReactionDepth) return 0;
  const bs = sc.chain.balls;
  let n = 0;
  for (let d = -DESIGN.elemSwirlRange; d <= DESIGN.elemSwirlRange; d++) {
    if (d === 0) continue;
    const j = srcIdx + d;
    if (j < 0 || j >= bs.length) continue;
    if (j === skipIdx) continue;
    const b = bs[j];
    if (sc.mode === 'seven') {
      // ★ 七球模式：邻居的身份也是元素，**不能**覆盖它。
      //   原神原文是"扩散会造成对应元素伤害、产生附着，或**进一步引发其他反应**"——
      //   这里就取后半句：拿被扩散的那个元素去和邻居的身份结算反应。
      // （起风的那颗球本身已经在上面被 skipIdx 跳过了）
      const r7 = sevenReaction(b.elem, elem, b.quickened);
      // ★★ 连锁里**不允许再出扩散**。
      //   原神里扩散是"风触及火水雷冰"，而被扩散出去的是火/水/雷/冰本身 —— 不是风，
      //   所以一条扩散链上不可能再套一次扩散。不挡的话会滚雪球：
      //   深度 4 × 每层两个邻居 -> 实测一关 **217 次反应**、无尽关 2.7 秒就通关。
      //   （这个坑是自动对局探针量出来的，不是看代码看出来的。）
      if (r7 && r7.id !== 'swirl') { fireReaction(sc, j, srcIdx, r7, elem, depth); n += 1; }
    } else if (!b.elem) { b.elem = elem; n += 1; }
    else if (b.elem !== elem && b.elem !== QUICK) {
      const r = reactionFor(b.elem, elem);
      if (r) { fireReaction(sc, j, srcIdx, r, elem, depth); n += 1; }
    }
  }
  return n;
}

// 绽放：生成草原核（原神：至多 5 个、存在 6 秒，超出的立即爆炸）
function spawnCore(sc, idx) {
  const b = sc.chain.balls[idx];
  const core = {
    id: sc.nextCoreId++, ballId: b ? b.id : null,
    x: b ? b.x : 0, y: b ? b.y : 0, z: b ? b.z : 0,
    t: DESIGN.elemCoreLife
  };
  sc.cores.push(core);
  while (sc.cores.length > DESIGN.elemCoreMax) detonateCore(sc, sc.cores[0]);
  return core.id;
}

function detonateCore(sc, core) {
  const i = sc.cores.indexOf(core);
  if (i < 0) return 0;
  sc.cores.splice(i, 1);
  // 找离核心最近的一颗球，就地移除 3 颗
  const best = nearestIndexTo(sc, core.x, core.y);
  const removed = best >= 0 ? removeAround(sc, best) : 0;
  sc.stats.cores += 1;
  pushEvent(sc, { type: 'core', x: core.x, y: core.y, removed: removed });
  return removed;
}

// 离某个点最近的那颗球（核失去宿主时用来定位）
function nearestIndexTo(sc, x, y) {
  const bs = sc.chain.balls;
  let best = -1, bd = Infinity;
  for (let k = 0; k < bs.length; k++) {
    const dx = bs[k].x - x, dy = bs[k].y - y;
    const d2 = dx * dx + dy * dy;
    if (d2 < bd) { bd = d2; best = k; }
  }
  return best;
}

// 草原核遇到雷/火 -> 超绽放 / 烈绽放（原神：倍率都是 3）。
// ⚠ 按**球的 id** 找宿主、不按下标：引爆它的那次反应（比如超载）可能已经把球带走了，
//   这时候按下标去读会读到完全不相干的球。
function detonateCoresFor(sc, ballId, trigger) {
  if (trigger !== 'electro' && trigger !== 'pyro') return 0;
  let n = 0;
  for (let k = sc.cores.length - 1; k >= 0; k--) {
    const c = sc.cores[k];
    if (c.ballId !== ballId) continue;
    sc.cores.splice(k, 1);
    const bi = findBallIndex(sc.chain, ballId);
    const at = bi >= 0 ? bi : nearestIndexTo(sc, c.x, c.y);
    const ev = {
      type: 'reaction', id: trigger === 'electro' ? 'hyperbloom' : 'burgeon',
      name: trigger === 'electro' ? '超绽放' : '烈绽放',
      mult: 3, effect: 'explode', index: at, aura: 'dendro', trigger: trigger,
      score: DESIGN.elemScorePerReaction
    };
    ev.removed = at >= 0 ? removeAround(sc, at) : 0;
    sc.stats.reactions += 1;
    sc.stats.cores += 1;
    sc.score += DESIGN.elemScorePerReaction;
    sc.lastReaction = ev;
    sc.reactionFlash = DESIGN.reactionFlashTime;
    pushEvent(sc, ev);
    n += 1;
  }
  return n;
}

// 每帧推进：草原核、燃烧、冻结计时
export function tickElements(sc, dt) {
  if (sc.reactionFlash > 0) sc.reactionFlash = Math.max(0, sc.reactionFlash - dt);
  // 草原核：跟着它的球走，到期自爆
  for (let k = sc.cores.length - 1; k >= 0; k--) {
    const c = sc.cores[k];
    const bi = c.ballId == null ? -1 : findBallIndex(sc.chain, c.ballId);
    if (bi >= 0) { const b = sc.chain.balls[bi]; c.x = b.x; c.y = b.y; c.z = b.z; }
    c.t -= dt;
    if (c.t <= 0) detonateCore(sc, c);
  }
  // 燃烧：原神 0.25 秒跳一次 —— 这里每次把相邻一颗未配对的球"烧"成已读
  const bs = sc.chain.balls;
  for (let i = 0; i < bs.length; i++) {
    const b = bs[i];
    if (b.burn > 0) {
      b.burn -= dt;
      b.burnAcc = (b.burnAcc || 0) + dt;
      while (b.burnAcc >= DESIGN.elemBurnTick) {
        b.burnAcc -= DESIGN.elemBurnTick;
        for (let s = -1; s <= 1; s += 2) {
          const j = i + s;
          if (j >= 0 && j < bs.length && autoPairBall(sc, j)) break;
        }
      }
      if (b.burn <= 0) { b.burn = 0; b.burnAcc = 0; }
    }
    if (b.frozen > 0) b.frozen = Math.max(0, b.frozen - dt);
  }
}

export function setMode(sc, mode) {
  const m = (mode === 'insert') ? 'insert' : ((mode === 'seven') ? 'seven' : 'match');
  const wasSeven = sc.mode === 'seven';
  sc.mode = m;
  sc.modeFlash = DESIGN.modeFlashTime;   // 按钮闪一下 = 「点到了」的确认
  // ★ 身份空间变了（匹配 <-> 七球）就把场上的球和手里的珠子一起搬过去。
  //   不搬的话切过去两边 token 对不上，一发都打不中（元素模式时代踩过这个坑）。
  if (wasSeven !== (m === 'seven')) convertBoard(sc);
  return sc.mode;
}

// 三种模式循环：匹配 -> 加球 -> 七球 -> 匹配
export function toggleMode(sc) {
  const order = ['match', 'insert', 'seven'];
  const i = order.indexOf(sc.mode);
  return setMode(sc, order[(i + 1) % order.length]);
}

export function drainEvents(sc) {
  const out = sc.events;
  sc.events = [];
  return out;
}

// 视觉滞后量的指数衰减（时间常数 = retreatTime/3，约 retreatTime 后收敛到 5% 以内）。
// 纯渲染：所有判定都只看 wp。
function decayVisual(sc, dt) {
  const k = Math.exp(-dt / (DESIGN.retreatTime / 3));
  const balls = sc.chain.balls;
  for (let i = 0; i < balls.length; i++) {
    const b = balls[i];
    if (b.visOff) {
      b.visOff *= k;
      if (Math.abs(b.visOff) < 0.05) b.visOff = 0;
    }
  }
}

export function sceneInfo(sc) {
  const ch = sc.chain;
  return {
    balls: ch.balls.length,
    headWp: ch.balls.length ? ch.balls[0].wp : 0,
    tailWp: ch.balls.length ? ch.balls[ch.balls.length - 1].wp : 0,
    speed: ch.speed,
    curveLength: sc.path.length,
    progress: ch.balls.length ? ch.balls[0].wp / sc.path.length : 0,
    paired: sc.beads.eliminate.length,
    runs: sc.runsInfo.map(function (r) { return r.len; }),
    shots: sc.projectiles.length,
    merges: sc.merges.length,
    score: sc.score,
    lives: sc.lives,
    losing: sc.losing,
    gameOver: sc.gameOver,
    won: sc.won,
    // ⚠ 用 != null 而不是 ||：有限球数关把 scoreTarget 显式设成 Infinity 表示
    //   "不靠分数过关"，用 || 虽然也能过（Infinity 是真值），但 0 会被吞掉。
    scoreTarget: sc.level.scoreTarget != null ? sc.level.scoreTarget : DESIGN.scoreTarget,
    winReason: sc.winReason,
    spawned: sc.spawnCount,
    budget: sc.level.ballBudget != null ? sc.level.ballBudget : DESIGN.ballBudget,
    endless: (sc.level.ballBudget != null ? sc.level.ballBudget : DESIGN.ballBudget) <= 0,
    remaining: (function () {
      const b = sc.level.ballBudget != null ? sc.level.ballBudget : DESIGN.ballBudget;
      return b > 0 ? Math.max(0, b - sc.spawnCount) : 0;
    })(),
    onField: sc.chain.balls.length,
    stats: sc.stats,
    mode: sc.mode,
    loaded: sc.rb.loaded.slice(),          // 手里两颗的身份token（碱基或元素）
    // ---- §57 元素反应 ----
    shields: sc.shields,
    cores: sc.cores.length,
    reactions: sc.stats.reactions,
    lastReaction: sc.lastReaction
  };
}


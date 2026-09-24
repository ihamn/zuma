// U9 三消道的 3N 消除。纯逻辑，不碰 DOM。
//
// ★ 架构（用户 2026-09 定稿）：
//   出球道 = **原版祖玛逻辑原样保留**（绳模型、真空隙、后段追上来、插入顶开）；
//   三消道 = **标记序列**，只做匹配；3n 消**只在这个序列上判定**。
//   两条道互不干扰：匹配不改动出球道，"连续"也不看物理位置。
//
// ★ 3N 语义（用户明确）：存在连续的 3n 个 x=1 就**立马**消除。
//   所以一帧结束时不允许存在长度是 3 的倍数且 >= 3 的 run —— 当帧整段消除，级联到不动点。
//
// 记号：x_i ∈ {0,1} 表示序列里第 i 颗主链球是否"已被读出"（在三消道上有绑定小球）。

// 标记是否已"定型"（吸附飞行结束）。1 和 2 都算标记，只是含义不同。
export function isMarked(b) {
  return b.paired === true && (b.dock == null || b.dock >= 1);
}

// 定型后的状态值：0 = 空、1 = 正确配对、2 = 错误配对。
// 存储上仍是两个布尔（paired + wrongMark），这里给出唯一的读取口径。
export function markFinal(b) {
  if (!isMarked(b)) return 0;
  return b.wrongMark === true ? 2 : 1;
}

// 一颗球是否"已被读出"（x=1）：**正确**配对，且吸附飞行已完成。
// 注意：错误配对（2）在这里和 0 一样返回 false —— 所以 2 会像 0 一样断开 run。
export function isDocked(b) {
  return isMarked(b) && b.wrongMark !== true;
}

// ★ 爆炸判定（DESIGN.md §32 / §34）。三条：
//   1. 两侧**都必须是已定型的标记**（1 或 2）—— 只要有一侧是「没有绑定小球」的球，
//      这颗 2 就**待定、不爆**。
//      ⚠ 这一条是用户实测后加回来的：原先把「无绑定球」也当成 0 参与判定，
//        结果 40 次爆炸里只有 3 次是真正的 121，绝大多数都在把没绑定小球的球
//        白白卷进去炸掉 —— 玩家看到的就是「我根本没碰那两颗，它们消失了」。
//   2. 两侧**同为 1** 或**同为 2** -> 爆；一边 1 一边 2 -> 稳。
//   3. 爆炸移除 3 颗（它 + 左右各一颗），所以参与的球都带绑定小球。
//      这同时保住了「所有移除都是 3 的倍数」这条统一律。
//   链首/链尾那颗亦然：它缺一侧真邻居 -> 待定，等冒球把它顶出边界再判。
export function findExplosion(chain) {
  const balls = chain.balls;
  for (let i = 1; i < balls.length - 1; i++) {
    if (markFinal(balls[i]) !== 2) continue;
    const l = markFinal(balls[i - 1]);
    const r = markFinal(balls[i + 1]);
    if (l === 0 || r === 0) continue;
    if ((l === 1) === (r === 1)) return i;
  }
  return -1;
}

// run = 标记序列上的极大连续区间 [a,b]（只看序列相邻，**与出球道的物理空隙无关**）
export function computeRuns(chain) {
  const balls = chain.balls;
  const runs = [];
  let cur = null;
  for (let i = 0; i < balls.length; i++) {
    const b = balls[i];
    if (!isDocked(b)) { cur = null; continue; }
    if (cur === null) {
      cur = { i0: i, i1: i, len: 1, key: b.id };
      runs.push(cur);
    } else {
      cur.i1 = i;
      cur.len += 1;
    }
  }
  return runs;
}

// 当前所有"该消"的段：长度是 3 的倍数且 >= 3
export function clearableRuns(chain) {
  return computeRuns(chain).filter(function (r) { return r.len >= 3 && r.len % 3 === 0; });
}

// 给渲染用的读数
export function runStatus(run) {
  const mod = run.len % 3 === 0;
  return {
    len: run.len,
    mod: mod,
    // 还差几颗到下一个 3 的倍数（本身已是倍数时为 0）
    toNext: mod ? 0 : (3 - (run.len % 3))
  };
}


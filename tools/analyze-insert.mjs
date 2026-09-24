// 插入机制的形式化验证（穷举）。用法：node tools/analyze-insert.mjs
//
// 记号（用户提出）：
//   状态 Σ = ((x_1,y_1), ..., (x_N,y_N))
//   x_i ∈ {0,1} = 第 i 颗球在三消链上"有无绑定小球"（0 无 / 1 有）
//   y_i = 第 i 颗球本体；i 按**发出顺序**递增（越早发出编号越小，即越靠近洞穴）
//
// 本脚本只关心 x 序列（消除/插入的组合结构），把 y 的碱基内容抽象成"x* 可自由取 0/1"。
// 空隙 λ 一律取 1（即假设回缩已闭合的稳态），瞬态时序另见 DESIGN.md §19.4。

function runsOf(x) {
  const out = [];
  let a = -1;
  for (let i = 0; i <= x.length; i++) {
    const one = i < x.length && x[i] === '1';
    if (one && a < 0) a = i;
    if (!one && a >= 0) { out.push([a, i - 1]); a = -1; }
  }
  return out;
}

// 消除不动点：反复把所有"长度是 3 的倍数且 >=3"的极大段整段删掉，直到没有
function fixpoint(x) {
  let cur = x, removed = 0;
  for (let guard = 0; guard < 100; guard++) {
    const rs = runsOf(cur).filter(function (r) { return (r[1] - r[0] + 1) % 3 === 0; });
    if (!rs.length) break;
    const del = new Array(cur.length).fill(false);
    for (let i = 0; i < rs.length; i++) for (let j = rs[i][0]; j <= rs[i][1]; j++) del[j] = true;
    let keep = '';
    for (let i = 0; i < cur.length; i++) if (!del[i]) keep += cur[i];
    removed += cur.length - keep.length;
    cur = keep;
  }
  return { x: cur, removed: removed };
}

function insertAt(x, k, xs) { return x.slice(0, k) + xs + x.slice(k); }
function allBinaries(n) {
  const out = [];
  for (let m = 0; m < (1 << n); m++) {
    let s = '';
    for (let i = n - 1; i >= 0; i--) s += ((m >> i) & 1) ? '1' : '0';
    out.push(s);
  }
  return out;
}

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail++; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}

console.log('[穷举范围] N = 0..10 的全部 x 序列 x 全部插入位置 x x* ∈ {0,1}');
let cases = 0;
let extraCases = 0;
let worstDelta = 0;
let badT1 = [], badT2 = [], badT3 = [];
let sabotage = 0, maxSabotage = 0;
let maxExtra = 0;

for (let n = 0; n <= 10; n++) {
  const seqs = allBinaries(n);
  for (let si = 0; si < seqs.length; si++) {
    const x = seqs[si];
    const before = fixpoint(x);
    for (let k = 0; k <= x.length; k++) {
      for (let xs = 0; xs <= 1; xs++) {
        cases++;
        const x2 = insertAt(x, k, String(xs));
        const after = fixpoint(x2);
        const extra = after.removed - before.removed;     // 这次插入额外引发的消除数
        const deltaN = 1 + before.removed - after.removed; // 净球数变化
        if (extra > 0) {
          extraCases++;
          maxExtra = Math.max(maxExtra, extra);
          worstDelta = Math.min(worstDelta, deltaN);
          if (!(extra >= 3)) badT1.push(x + '|k=' + k + '|x*=' + xs + '|extra=' + extra);
          if (!(deltaN <= -2)) badT1.push(x + '|k=' + k + '|x*=' + xs + '|deltaN=' + deltaN);
        } else if (extra === 0) {
          if (deltaN !== 1) badT2.push(x + '|k=' + k + '|x*=' + xs + '|deltaN=' + deltaN);
        } else {
          // extra < 0：插入**阻止**了原本会发生的消除
          sabotage++;
          maxSabotage = Math.max(maxSabotage, -extra);
          if (!(deltaN >= 2)) badT3.push(x + '|k=' + k + '|x*=' + xs + '|deltaN=' + deltaN);
        }
      }
    }
  }
}

check('T1 ★ 只要插入引发消除，额外消除必 >=3 且净变化必 <= -2',
  badT1.length === 0, badT1.slice(0, 3).join(' ； ') || ('穷举 ' + cases + ' 例，其中 ' + extraCases + ' 例触发消除'));
check('T2 插入没有改变消除结果时，净变化恒 = +1（只加了那一颗）', badT2.length === 0, badT2.slice(0, 3).join(' ； '));
check('T3- ★ 插入**破坏**了原本会发生的消除时，净变化 >= +2（比单纯加一颗还亏）', badT3.length === 0,
  badT3.slice(0, 3).join(' ； ') || ('发生 ' + sabotage + ' 例，最严重多亏 ' + maxSabotage + ' 颗'));
console.log('        穷举 ' + cases + ' 例；触发消除 ' + extraCases + ' 例；最差净变化 ' + worstDelta + '；单次最大额外消除 ' + maxExtra);

console.log('');
console.log('[单段 run 的可达性：延长 vs 切开]');
console.log('  ℓ   长度%3   延长(x*=1,插端点)   切开(x*=0,插内部)   最好净变化');
for (let L = 1; L <= 12; L++) {
  const x = '1'.repeat(L);
  const before = fixpoint(x);
  let bestExtend = null, bestSplit = null, bestAll = Infinity, canSabotage = false;
  for (let k = 0; k <= L; k++) {
    for (let xs = 0; xs <= 1; xs++) {
      const after = fixpoint(insertAt(x, k, String(xs)));
      const deltaN = 1 + before.removed - after.removed;
      const extra = after.removed - before.removed;
      if (extra > 0) {
        if (xs === 1) bestExtend = Math.min(bestExtend === null ? 99 : bestExtend, deltaN);
        else bestSplit = Math.min(bestSplit === null ? 99 : bestSplit, deltaN);
      }
      bestAll = Math.min(bestAll, deltaN);
      if (after.removed - before.removed < 0) canSabotage = true;
    }
  }
  const at = (k) => (k === 0 || k === L) ? '端点' : '内部';
  console.log('  ' + String(L).padStart(2) + '     ' + (L % 3) + '        ' +
    (bestExtend === null ? '不可行' : ('可行 ' + bestExtend)) + '            ' +
    (bestSplit === null ? '不可行' : ('可行 ' + bestSplit)) + '             ' +
    (bestAll > 0 ? ('+' + bestAll + '（亏）') : bestAll) + '        ' + (canSabotage ? '是' : '否'));
}

console.log('');
console.log('[与"延长可行性"的预测对照]');
let predOk = true, predDetail = [];
for (let L = 1; L <= 12; L++) {
  const x = '1'.repeat(L);
  const before = fixpoint(x);
  let extendable = false;
  for (let k = 0; k <= L; k++) {
    const after = fixpoint(insertAt(x, k, '1'));
    if (after.removed - before.removed > 0) extendable = true;
  }
  const predicted = (L % 3 === 2);
  predDetail.push('ℓ=' + L + (extendable ? '✓' : '✗') + (predicted ? '✓' : '✗'));
  if (extendable !== predicted) predOk = false;
}
check('T4 单段 run 可被「延长」消除 <=> ℓ ≡ 2 (mod 3)', predOk, predDetail.join(' '));

console.log('');
console.log('analyze-insert: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


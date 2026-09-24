// 自动对局探针：验证「有限球数关能不能被打通」。用法：node tools/probe-play.mjs
// 关注三件事：
//   1) 清空过关真的会触发吗（reason === 'clear'）
//   2) 打完要多久（预算 48 颗 @ 冒球率 1.06 颗/秒 大致是 45 秒的出球量）
//   3) ★ 有没有"卡死"：预算发完、场上还剩 1~2 颗永远消不掉
//      —— 这是有限球数关的最大风险：所有移除都是 3 的倍数，如果预算不是 3 的倍数，
//         终局残留就会 ≡ 预算 (mod 3)，剩 1~2 颗时**永远不可能清空**。
import { metrics, viewFor, DESIGN, isComplement } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { assembleScene, advanceScene, fireShot, sceneInfo, setMode } from '../src/scene.js';
import { aimAt } from '../src/ribosome.js';
import { sevenReaction } from '../src/elements.js';

const DT = 1 / 60;
const view = viewFor(900, 900);
const MAX_FRAMES = 60 * 300;      // 5 分钟上限

// 环境变量 ZUMA_MODE=seven 时用七球模式跑（§57）——
// 机器人不刻意凑反应，只是照常打互补球，所以这测的是"元素模式能不能正常打完一局"。
const MODE = process.env.ZUMA_MODE || 'match';

function play(level, seed) {
  const sc = assembleScene(level, view, seed);
  if (MODE !== 'match') setMode(sc, MODE);
  let frames = 0, lastProgress = 0, lastCount = sc.chain.balls.length, stuckFrom = -1;
  while (frames < MAX_FRAMES && !sc.won && !sc.gameOver) {
    const bs = sc.chain.balls;
    if (sc.projectiles.length === 0) {
      const bead = sc.rb.loaded[0];
      for (let bi = 0; bi < bs.length; bi++) {
        const b = bs[bi];
        if (b.paired) continue;
        // ★ 两种模式的"能不能打中"判据不同：匹配模式看碱基互补，七球模式看有没有反应
        const ok = MODE === 'seven'
          ? !!sevenReaction(b.elem, bead, b.quickened)
          : isComplement(bead, b.base);
        if (!ok) continue;
        aimAt(sc.rb, b.x, b.y);
        fireShot(sc);
        break;
      }
    }
    advanceScene(sc, DT);
    frames += 1;
    if (bs.length !== lastCount) { lastCount = bs.length; lastProgress = frames; }
    // 卡死判定：预算发完 + 场上还有球 + 30 秒没有任何变化
    if (stuckFrom < 0 && sceneInfo(sc).remaining === 0 && bs.length > 0 && frames - lastProgress > 60 * 30) stuckFrom = frames;
  }
  const i = sceneInfo(sc);
  return {
    level: level.id, seed: seed, won: sc.won, reason: sc.winReason, gameOver: sc.gameOver,
    sec: (frames / 60).toFixed(1), field: sc.chain.balls.length, fed: i.spawned, budget: i.budget,
    remaining: i.remaining, cleared: sc.stats.cleared, explosions: sc.stats.explosions,
    reactions: sc.stats.reactions, cores: sc.stats.cores,
    lives: sc.lives, score: sc.score, stuck: stuckFrom >= 0
  };
}

console.log('模式: ' + MODE);
// ZUMA_ALL=1 时把新手关也算上（§60）
let ALL = null;
if (process.env.ZUMA_ALL) {
  const m = await import('../src/levels.js');
  ALL = m.ALL_LEVELS;
}
const pool = ALL || LEVELS;
const only = process.argv[2];
const list = only ? pool.filter(function (l) { return l.id === only || String(pool.indexOf(l)) === only; }) : pool;
let bad = 0;
for (let li = 0; li < list.length; li++) {
  const lv = list[li];
  for (let s = 0; s < 3; s++) {
    const seed = 20260101 + s * 7919;
    const r = play(lv, seed);
    const finite = r.budget > 0;
    // §64 过关原因有三种：clear（清空）/ score（分数）/ match（读出全部，练习关用）
    const want = (lv.goal === 'matchAll') ? 'match' : (finite ? 'clear' : 'score');
    const okWon = r.won && r.reason === want;
    const verdict = r.stuck ? '卡死！'
      : (okWon ? (want === 'match' ? '读出全部 OK' : (want === 'clear' ? '清空过关 OK' : '分数过关 OK'))
               : (r.gameOver ? '命尽' : '未过关(' + (r.reason || '-') + ')'));
    if (r.stuck || !okWon) bad += 1;
    console.log(
      lv.id.padEnd(13) + ' seed=' + seed + '  ' + String(r.sec).padStart(6) + 's  ' +
      'won=' + (r.won ? 'Y' : 'n') + '(' + (r.reason || '-') + ')' +
      '  场上=' + String(r.field).padStart(2) + '  待出=' + String(r.remaining).padStart(2) +
      '  已发=' + String(r.fed).padStart(2) + '  消=' + String(r.cleared).padStart(3) +
      '  爆=' + String(r.explosions).padStart(2) + '  反应=' + String(r.reactions).padStart(3) +
      '  命=' + r.lives + '  分=' + r.score +
      '   ' + verdict);
  }
}
console.log('');
// ★ 不变量自检：有限球数关的预算必须是 3 的倍数
for (let i = 0; i < LEVELS.length; i++) {
  const b = LEVELS[i].ballBudget;
  if (b > 0 && b % 3 !== 0) { console.log('!! ' + LEVELS[i].id + ' 预算 ' + b + ' 不是 3 的倍数 -> 终局会残留 1~2 颗、永远清不掉'); bad += 1; }
}
console.log(bad ? ('探针：' + bad + ' 项不合格') : '探针：全部合格');
process.exit(bad ? 1 : 0);

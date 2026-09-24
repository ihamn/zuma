// 会犯错的玩家探针：故意打错配对（mark=2 -> 爆炸），看有限球数关还能不能打通。
// 用法：node tools/probe-sloppy.mjs [错误率] [秒数上限]
//
// 判"死局"必须用**真正的进展信号**：已消除 + 已爆炸的次数。
// ⚠ 早先版本用"场上球数变了没有"当进展信号，结果把"球数长时间不变但在正常消球"的
//   局面误报成死局（一排 won=Y 的行被标成死局）—— 信号选错，结论就全错。
// 死局定义：预算已发完 + 场上 >= 3 颗 + 30 秒内没有任何消除/爆炸 + 既没赢也没 gameOver。
import { metrics, viewFor, DESIGN, isComplement } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { assembleScene, advanceScene, fireShot, sceneInfo } from '../src/scene.js';
import { aimAt } from '../src/ribosome.js';
import { markFinal } from '../src/run.js';

const DT = 1 / 60;
const view = viewFor(900, 900);
const SLOPPY = parseFloat(process.argv[2] || '0.3');
const MAX_FRAMES = parseInt(process.argv[3] || '240', 10) * 60;
const IDLE_LIMIT = 60 * 30;

function play(level, seed) {
  const sc = assembleScene(level, view, seed);
  let s = seed;
  const rng = function () { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
  let frames = 0, lastProg = 0, lastProgFrame = 0;
  while (frames < MAX_FRAMES && !sc.won && !sc.gameOver) {
    if (sc.projectiles.length === 0) {
      const bs = sc.chain.balls;
      const bead = sc.rb.loaded[0];
      const wantWrong = rng() < SLOPPY;
      let pick = -1;
      for (let k = 0; k < bs.length; k++) {
        const idx = Math.floor(rng() * bs.length);
        const b = bs[idx];
        if (b.paired) continue;
        if (wantWrong === isComplement(bead, b.base)) continue;   // 想打错却正好互补 -> 换一颗
        pick = idx; break;
      }
      if (pick < 0) {
        for (let k = 0; k < bs.length; k++) {
          if (!bs[k].paired && isComplement(bead, bs[k].base)) { pick = k; break; }
        }
      }
      if (pick >= 0) { aimAt(sc.rb, bs[pick].x, bs[pick].y); fireShot(sc); }
    }
    advanceScene(sc, DT);
    frames += 1;
    const prog = sc.stats.cleared + sc.stats.explosions;
    if (prog !== lastProg) { lastProg = prog; lastProgFrame = frames; }
  }
  const i = sceneInfo(sc);
  // ★ 死局必须按**终局状态**判，不能中途一发现就钉死：
  //   中途 30 秒没进展、之后又打通了的局，照样是"打通了"。
  //   同理，中途卡过 30 秒但最后是命尽，那是输了，不是卡住。
  const idle = frames - lastProgFrame;
  const stuck = !sc.won && !sc.gameOver && i.remaining === 0 &&
    sc.chain.balls.length >= 3 && idle > IDLE_LIMIT;
  return {
    won: sc.won, reason: sc.winReason, gameOver: sc.gameOver, stuck: stuck,
    idleSec: (idle / 60).toFixed(0),
    sec: (frames / 60).toFixed(0), field: sc.chain.balls.length, remaining: i.remaining,
    exploded: sc.stats.explosions, cleared: sc.stats.cleared, lives: sc.lives,
    marks: sc.chain.balls.map(markFinal).join('')
  };
}

let dead = 0, lost = 0;
for (let li = 0; li < 3; li++) {
  const lv = LEVELS[li];
  for (let s = 0; s < 4; s++) {
    const seed = 20260101 + s * 104729;
    const r = play(lv, seed);
    if (r.stuck) dead += 1;
    const tag = r.stuck ? '   <<< 死局！'
      : (r.won ? '' : (r.gameOver ? '   <<< 命尽（输了，不是卡住）' : '   <<< 打不完（机器人太慢）'));
    if (!r.won && r.gameOver) lost += 1;
    console.log(lv.id.padEnd(13) + ' seed=' + seed + ' 错率=' + SLOPPY + '  ' + String(r.sec).padStart(4) + 's  ' +
      'won=' + (r.won ? 'Y' : 'n') + '(' + (r.reason || '-') + ')' +
      '  场上=' + String(r.field).padStart(2) + '/待出' + String(r.remaining).padStart(2) +
      '  爆=' + String(r.exploded).padStart(3) + '  消=' + String(r.cleared).padStart(3) +
      '  命=' + r.lives + '  末次进展=' + r.idleSec + 's  残留标记=' + (r.marks || '(空)') + tag);
  }
}
console.log('');
console.log('死局 ' + dead + '/12   输球 ' + lost + '/12');
process.exit(dead ? 1 : 0);

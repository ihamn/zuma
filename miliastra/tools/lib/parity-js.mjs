// parity-js.mjs —— 对拍的 **JS 侧**解释器。
//
// ★ 与 lua/parity/run.lua 一一对应：同一份命令表，两个解释器。
//   任何一处 op 逻辑改了，另一处必须同步改 —— 这是这个文件唯一的维护负担，
//   换来的是"场景只写一次"。
//
// 下标对账：JS 侧是 0 基、Lua 侧是 1 基。凡是会把下标写进输出的地方，
// JS 侧统一 **+1**，让两边的输出可以直接逐字比对。

import { makeRng } from '../../../src/rng.js';
import { BASES, metrics, viewFor, menuLayout, menuButtonRect } from '../../../src/config.js';
import { ALL_LEVELS, TUTORIALS } from '../../../src/levels.js';
import * as GEO from '../../../src/geometry.js';
import * as SP from '../../../src/spines.js';
import * as RUN from '../../../src/run.js';
import * as CH from '../../../src/chain.js';
import * as PJ from '../../../src/projectile.js';
import * as SCENE from '../../../src/scene.js';
import * as RIBO from '../../../src/ribosome.js';

function fmt(v) {
  if (v === undefined || v === null) return 'nil';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'string') return v;
  if (Number.isNaN(v)) return 'nan';
  if (v === Infinity) return 'inf';
  if (v === -Infinity) return '-inf';
  if (Number.isInteger(v)) return String(v);
  return v.toPrecision(12);
}

const LEVELS = {};

export function evalCommands(lines) {
  const out = [];
  const emit = (...parts) => out.push(parts.map(fmt).join(' '));

  const makeLevel = (turns, budget, inner) => {
    if (turns < 0 && budget < 0 && inner < 0) return undefined;
    const lv = {};
    if (turns >= 0) lv.turns = turns;
    if (budget >= 0) lv.ballBudget = budget;
    if (inner >= 0) lv.innerRatio = inner;
    return lv;
  };

  const makeSpine = (kind, view, level) =>
    kind === 1 ? SP.crossReturnSpine(view, level) : SP.spiralSpine(view, level);

  for (const raw of lines) {
    const line = raw.trim();
    if (line === '' || line.startsWith('#')) continue;
    const toks = line.split(/\s+/);
    const cmd = toks.shift();
    const a = toks.map(Number);

    if (cmd === 'mark') {
      emit('mark', a[0]);

    } else if (cmd === 'rng') {
      const r = makeRng(a[0]);
      const vals = [];
      for (let i = 0; i < a[1]; i++) vals.push(r());
      emit('rng', a[0], ...vals);

    } else if (cmd === 'rngint') {
      const r = makeRng(a[0]);
      const vals = [];
      for (let i = 0; i < a[1]; i++) vals.push(r.int(a[2]));
      emit('rngint', a[0], ...vals);

    } else if (cmd === 'metrics') {
      const m = metrics(a[0]);
      emit('metrics', a[0], m.p, m.R, m.r, m.d, m.linkGap, m.diameterRatio, m.areaRatio);

    } else if (cmd === 'menu') {
    // 菜单布局（本体 config.js menuLayout / menuButtonRect）——和移植侧 menu.lua 逐值对拍。
    // 条目表按本体 main.js rebuild() 里那段映射原文算（新手关用全名、核心关带序号）。
    const [w, h, scale, mode] = a;
    const v = viewFor(w, h);
    const mt = metrics(scale);
    const items = ALL_LEVELS.map((l, i) => {
      const tut = i < TUTORIALS.length;
      return {
        index: i,
        group: tut ? '新手关' : '核心关',
        label: tut ? (l.name || l.short) : ((i + 1) + ' ' + (l.short || l.name)),
      };
    });
    if (mode === 0) {                              // 条目表
      emit('menu.items', items.length, TUTORIALS.length);
      for (const it of items) emit('menu.item', it.index + 1, it.group === '新手关' ? 1 : 0, it.label);
    } else if (mode === 1) {                       // 布局
      const L = menuLayout(v, mt, items);
      emit('menu.layout', L.x0, L.innerW, L.cols, L.bw, L.bh, L.titleY, L.footerY, L.buttons.length, L.groups.length);
      for (const b of L.buttons) emit('menu.btn', b.x, b.y, b.w, b.h, b.item.index + 1);
      for (const g of L.groups) emit('menu.group', g.name, g.y);
    } else {                                       // 局内左下角按钮 + 命中判定
      const b = menuButtonRect(v, mt);
      emit('menu.playbtn', b.x, b.y, b.r);
      const L = menuLayout(v, mt, items);
      for (let i = 4; i + 1 < a.length; i += 2) {
        const px = a[i], py = a[i + 1];
        const hit = L.buttons.find((q) => px >= q.x && px <= q.x + q.w && py >= q.y && py <= q.y + q.h);
        emit('menu.pick', px, py, hit ? hit.item.index + 1 : 0);
      }
    }

  } else if (cmd === 'view') {
      const v = viewFor(a[0], a[1]);
      emit('view', a[0], a[1], v.cx, v.cy, v.rx, v.ry, v.scale, v.portrait ? 1 : 0);

    } else if (cmd === 'turns') {
      const v = viewFor(a[1], a[2]);
      emit('turns', a[0], SP.turnsForBudget(v, a[0]));

    } else if (cmd === 'spine') {
      const [kind, turns, budget, inner, w, h, n] = a;
      const v = viewFor(w, h);
      const fn = makeSpine(kind, v, makeLevel(turns, budget, inner));
      const vals = [];
      for (let i = 0; i <= n; i++) {
        const q = fn(i / n);
        vals.push(q.x, q.y);
      }
      emit('spine', kind, turns, budget, inner, ...vals);
      if (fn.junctionU != null) emit('spine.junction', kind, fn.junctionU);

    } else if (cmd === 'path') {
      const [kind, turns, budget, inner, w, h, samples] = a;
      const v = viewFor(w, h);
      const fn = makeSpine(kind, v, makeLevel(turns, budget, inner));
      const path = GEO.buildPath(fn, { samples, center: { x: v.cx, y: v.cy } });
      emit('path.head', kind, path.length, path.samples);
      for (let i = 7; i < a.length; i++) {
        const u = a[i];
        const s = path.sAtU(u);
        const p = path.pointAt(s);
        const nn = path.normalAt(s);
        emit('path', u, s, p.x, p.y, nn.x, nn.y, path.zAt(s));
      }

    } else if (cmd === 'curv') {
      const [kind, turns, budget, inner, w, h, samples] = a;
      const v = viewFor(w, h);
      const fn = makeSpine(kind, v, makeLevel(turns, budget, inner));
      const path = GEO.buildPath(fn, { samples, center: { x: v.cx, y: v.cy } });
      const vals = [];
      for (let i = 7; i < a.length; i++) vals.push(GEO.curvatureAt(path.pts, a[i]));
      emit('curv', ...vals);

    } else if (cmd === 'marks') {
      const s = String(toks[0]);
      const chain = { balls: [] };
      for (let i = 0; i < s.length; i++) {
        const c = Number(s[i]);
        const b = { id: i + 1, wp: 0, r: 19 };
        if (c === 1 || c === 2 || c === 3) b.paired = true;
        if (c === 2) b.wrongMark = true;
        if (c === 3) b.dock = 0.5;
        chain.balls.push(b);
      }
      emit('marks.final', ...chain.balls.map(RUN.markFinal));
      emit('marks.docked', ...chain.balls.map((b) => (RUN.isDocked(b) ? 1 : 0)));
      const ex = RUN.findExplosion(chain);
      emit('marks.explosion', ex < 0 ? -1 : ex + 1);
      const runs = RUN.computeRuns(chain);
      const flat = [];
      for (const r of runs) flat.push(r.i0 + 1, r.i1 + 1, r.len);
      emit('marks.runs', runs.length, ...flat);
      emit('marks.clearable', RUN.clearableRuns(chain).length);

    } else if (cmd === 'chain') {
      const [seed, steps, dt] = a;
      let curveLength = a[3];
      if (curveLength < 0) curveLength = null;
      const prefill = a[4];
      const r = makeRng(seed);
      const mt = metrics(1);
      const ch = CH.makeChain(mt, {});
      if (prefill > 0) CH.prefillChain(ch, prefill, (i) => BASES[i % 5]);
      for (let step = 1; step <= steps; step++) {
        const op = r.int(12);
        if (op <= 5) {
          CH.advanceChain(ch, dt, curveLength);
        } else if (op === 6) {
          ch.freezeTime = 0.3;
          CH.advanceChain(ch, dt, curveLength);
        } else if (op === 7) {
          CH.spawnBall(ch, BASES[r.int(5)], null);
        } else if (op === 8) {
          const idx = r.int(ch.balls.length + 1);
          const dist = r() * 120;
          CH.applyBackward(ch, idx, 30, dist);
          CH.advanceChain(ch, dt, curveLength);
        } else if (op === 9) {
          CH.drainHead(ch, curveLength ? curveLength * 0.9 : 0);
        } else if (op === 10) {
          if (ch.balls.length >= 2) {
            const i0 = r.int(ch.balls.length);
            const i1 = r.int(ch.balls.length - i0) + i0;
            CH.removeRange(ch, i0, i1);
          }
        } else {
          CH.recycleFront(ch);
        }
        const parts = ['ch', step, ch.balls.length, ch.speed, ch.stopTime, ch.freezeTime,
          ch.stats.spawned, ch.stats.drained, ch.stats.removed, ch.stats.leftField || 0,
          CH.chainRuns(ch).length];
        for (const b of ch.balls) {
          parts.push(`${fmt(b.wp)}:${b.base || '-'}:${b.id}:${b.backLeft != null ? b.backLeft : -1}`);
        }
        emit(...parts);
      }

    } else if (cmd === 'sweep') {
      const [seed, n] = a;
      const r = makeRng(seed);
      const balls = [];
      for (let i = 0; i < n; i++) {
        balls.push({ x: r() * 800, y: r() * 800, r: 10 + r() * 12, paired: r() < 0.3 });
      }
      const mt = metrics(1);
      for (let k = 1; k <= 12; k++) {
        const x0 = r() * 800, y0 = r() * 800, x1 = r() * 800, y1 = r() * 800;
        const pr = 8 + r() * 10;
        const hit = PJ.sweepHit(balls, x0, y0, x1, y1, pr, true);
        if (hit) emit('sweep', k, hit.index + 1, hit.t, hit.x, hit.y);
        else emit('sweep', k, -1);
      }
      emit('sweep.metrics', mt.p);


    } else if (cmd === 'level') {
      const idx = a[0];
      const [sig, turnsv, budget, inner, prefill, flags, startFrac, speedv, railSign, sTgt, basesMask] = a.slice(1);
      let script = toks[12];
      if (script === '-') script = undefined;
      const lv = {
        id: 'L' + idx,
        makeSpine: sig === 1 ? SP.crossReturnSpine : SP.spiralSpine,
        railOrder: railSign > 0 ? 'spawn-outer' : 'spawn-inner',
        ballBudget: budget,
        prefill: prefill,
        still: flags % 2 >= 1,
        centerChain: Math.floor(flags / 2) % 2 === 1,
        noClear: Math.floor(flags / 4) % 2 === 1,
        layersFromJunction: Math.floor(flags / 16) % 2 === 1,
        scoreTarget: sTgt < 0 ? Infinity : sTgt,
      };
      if (turnsv >= 0) lv.turns = turnsv;
      if (inner >= 0) lv.innerRatio = inner;
      if (Math.floor(flags / 8) % 2 === 1) lv.goal = 'matchAll';
      if (startFrac >= 0) lv.startWpFrac = startFrac;
      if (speedv >= 0) lv.speed = speedv;
      if (basesMask > 0) {
        const b = [];
        for (let i = 0; i < BASES.length; i++) if (Math.floor(basesMask / 2 ** i) % 2 === 1) b.push(BASES[i]);
        lv.bases = b;
      }
      if (script) lv.script = script;
      lv.insertMode = Math.floor(flags / 32) % 2 === 1;   // flags bit5 = 加球模式
      if (lv.layersFromJunction) {
        lv.layers = function (path, spine) {
          const cut = path.sAtU(spine.junctionU != null ? spine.junctionU : 0.64);
          return [{ from: 0, to: cut, z: 0 }, { from: cut, to: path.length, z: 1 }];
        };
      }
      LEVELS[idx] = lv;

    } else if (cmd === 'board') {
      const [lvIdx, seed, frames, dt, firePct, fireMode, dumpEvery] = a;
      const lv = LEVELS[lvIdx];
      if (!lv) throw new Error('level not defined: ' + lvIdx);
      const view = viewFor(900, 900);
      const sc = SCENE.assembleScene(lv, view, seed);
      if (lv.insertMode) SCENE.setMode(sc, 'insert');   // 对应 Lua 侧手动设 mode + modeFlash
      const drv = makeRng(seed * 7919 + 13);

      const dump = (tag, frame) => {
        const parts = [tag, frame, sc.chain.balls.length, fmt(sc.score), sc.lives, sc.spawnCount,
          sc.won ? 1 : 0, sc.winReason != null ? sc.winReason : '-', sc.gameOver ? 1 : 0, sc.losing ? 1 : 0,
          sc.stats.fired, sc.stats.pairs, sc.stats.mismatches, sc.stats.merges,
          sc.stats.cleared, sc.stats.codons, sc.stats.lost, sc.stats.explosions,
          fmt(sc.chain.speed), fmt(sc.chain.balls.length > 0 ? sc.chain.balls[0].wp : 0)];
        for (const b of sc.chain.balls) {
          parts.push(fmt(b.wp) + ':' + b.base + ':' + RUN.markFinal(b) + ':' +
            (b.pairBase != null ? b.pairBase : '-') + ':' +
            (b.dock != null ? fmt(b.dock) : '-') + ':' +
            (b.backLeft != null ? b.backLeft : -1));
        }
        emit(...parts);
      };

      dump('b0', 0);
      for (let f = 1; f <= frames; f++) {
        if (fireMode > 0 && drv() < firePct / 100) {
          const bs = sc.chain.balls;
          if (bs.length > 0) {
            let pick = drv.int(bs.length) + 1;
            if (fireMode === 2) {
              let found = 0;
              for (let k = 0; k < bs.length; k++) {
                const j = ((pick - 1 + k) % bs.length) + 1;
                if (!bs[j - 1].paired) { found = j; break; }
              }
              pick = found;
            }
            if (pick > 0) {
              RIBO.aimAt(sc.rb, bs[pick - 1].x, bs[pick - 1].y);
              SCENE.fireShot(sc);
            }
          }
        }
        SCENE.advanceScene(sc, dt);
        if (dumpEvery > 0 && f % dumpEvery === 0) dump('b', f);
      }
      dump('bend', frames);

    } else {
      throw new Error('unknown command: ' + cmd);
    }
  }
  return out;
}

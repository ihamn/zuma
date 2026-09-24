// U3 珠串模型单元测试。用法：node tools/test-chain.mjs
// 重点验证绳子模型的三条真实机制：刚性同步 / 空隙 / 回缩不变量。

import { metrics, DESIGN } from '../src/config.js';
import {
  makeChain, touchDist, advanceChain, spawnBall, drainHead,
  chainRuns, chainHasGap, removeRange, smoothSpeed
} from '../src/chain.js';

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass += 1; console.log('  ok    ' + name + (extra ? '   ' + extra : '')); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
}
function group(t) { console.log('\n[' + t + ']'); }

const mt = metrics(1);
const DT = 1 / 60;
const FAR = 1e9;      // 不触发洞穴减速带
const T = touchDist(mt, { r: mt.R }, { r: mt.R });   // 大球-大球

function clone(ch) {
  const c = makeChain(ch.mt, { speed: ch.targetSpeed });
  c.speed = ch.speed;
  c.nextId = ch.nextId;
  c.balls = ch.balls.map(function (b) { return { wp: b.wp, base: b.base, r: b.r, id: b.id }; });
  return c;
}

// 造一条 n 颗、已经完全相接的链
function fresh(n) {
  const ch = makeChain(mt, {});
  let guard = 0;
  while (ch.balls.length < n && guard < 200000) {
    if (!spawnBall(ch, 'A')) advanceChain(ch, DT, FAR);
    else advanceChain(ch, DT, FAR);
    guard += 1;
  }
  return ch;
}

// ---------- 基础 ----------
group('基础：touchDist 与速度平滑');
check('空链推进不炸', (function () { const c = makeChain(mt, {}); advanceChain(c, DT, FAR); return c.balls.length === 0; })());
check('大-大 touchDist = 2R + linkGap', Math.abs(T - (2 * mt.R + mt.linkGap)) < 1e-12, 'T=' + T.toFixed(3));
const tBS = touchDist(mt, { r: mt.R }, { r: mt.r });
check('大-小 touchDist 逐对算半径（!= 2R）', Math.abs(tBS - (mt.R + mt.r + mt.linkGap)) < 1e-12 && Math.abs(tBS - T) > 1,
  'T(大,小)=' + tBS.toFixed(3) + '  T(大,大)=' + T.toFixed(3));
check('p 与 touchDist(大,大) 一致', Math.abs(mt.p - T) < 1e-12, 'p=' + mt.p.toFixed(3));

const cs = makeChain(mt, {});
const accelFrames = (function () {
  let f = 0;
  while (cs.speed < cs.targetSpeed - 1e-6 && f < 100000) { smoothSpeed(cs, DT); f += 1; }
  return f;
})();
cs.targetSpeed = 0;
const decelFrames = (function () {
  let f = 0;
  while (cs.speed > 1e-6 && f < 100000) { smoothSpeed(cs, DT); f += 1; }
  return f;
})();
check('加速慢、减速快（原版手感）', accelFrames > decelFrames * 4,
  '加速 ' + accelFrames + ' 帧 vs 减速 ' + decelFrames + ' 帧');

// ---------- 生成 ----------
group('生成：只从 wp≈0 进入，且必须等队尾让位');
const g = makeChain(mt, {});
const first = spawnBall(g, 'A');
check('空链立刻冒出第一颗', first !== null && Math.abs(first.wp - 0) < 1e-12);
check('队尾未让位时拒绝生成', spawnBall(g, 'U') === null);
let gf = 0;
while (spawnBall(g, 'U') === null && gf < 10000) { advanceChain(g, DT, FAR); gf += 1; }
check('让位后成功生成第二颗', g.balls.length === 2, '等待 ' + gf + ' 帧');
check('新球恒从 wp = spawnWp 进入', Math.abs(g.balls[1].wp - g.spawnWp) < 1e-9);
const gapAfterSpawn = g.balls[0].wp - g.balls[1].wp;
check('生成瞬间间距 >= touchDist，且不超过一帧喂入量', gapAfterSpawn >= T - 1e-9 && gapAfterSpawn <= T + g.targetSpeed * DT + 1e-9,
  'spacing-T=' + (gapAfterSpawn - T).toFixed(4) + 'px  一帧喂入=' + (g.targetSpeed * DT).toFixed(3) + 'px');
advanceChain(g, DT, FAR);
check('下一帧即被顶到恰好相切', Math.abs((g.balls[0].wp - g.balls[1].wp) - T) < 1e-9,
  'spacing-T=' + (g.balls[0].wp - g.balls[1].wp - T).toExponential(2));

// ---------- 刚性同步 ----------
group('刚性：无空隙时整链同步前进，间距恒为 touchDist');
const rigid = fresh(8);
const wp0 = rigid.balls.map(function (b) { return b.wp; });
for (let f = 0; f < 300; f++) advanceChain(rigid, DT, FAR);
let maxErr = 0;
for (let i = 0; i + 1 < rigid.balls.length; i++) {
  maxErr = Math.max(maxErr, Math.abs((rigid.balls[i].wp - rigid.balls[i + 1].wp) - T));
}
check('相邻间距恒为 touchDist', maxErr < 1e-6, 'maxErr=' + maxErr.toExponential(2));
check('全程无空隙', !chainHasGap(rigid), 'runs=' + chainRuns(rigid).length);
const dHead = rigid.balls[0].wp - wp0[0];
const dTail = rigid.balls[7].wp - wp0[7];
check('队头位移 === 队尾位移（刚性绳）', Math.abs(dHead - dTail) < 1e-6, 'Δhead=' + dHead.toFixed(4) + ' Δtail=' + dTail.toFixed(4));
check('位移 = 速度×时间', Math.abs(dHead - rigid.targetSpeed * 300 * DT) < 1e-6, 'Δ=' + dHead.toFixed(4));

// ---------- 空隙 ----------
group('空隙：中间移除即断开，两段独立');
const gp = fresh(9);
removeRange(gp, 3, 4);              // 移除 2 颗
const runs = chainRuns(gp);
check('移除中间两颗粒后切成两段', runs.length === 2, 'runs=' + JSON.stringify(runs));
check('chainHasGap 为真', chainHasGap(gp));
check('队头段在前（i0=0）', runs[0].i0 === 0 && runs[0].i1 === 2);
check('队尾段在后（i1=n-1）', runs[1].i0 === 3 && runs[1].i1 === 6);

// ---------- 回缩 ----------
group('回缩：队头先停住、队尾继续爬，空隙从后往前闭合');
const ctrl = fresh(10);
const cut = clone(ctrl);
removeRange(cut, 3, 5);             // 移除 3 颗
const headBefore = cut.balls[0].wp;
const tailBefore = cut.balls[cut.balls.length - 1].wp;
for (let f = 0; f < 5; f++) { advanceChain(cut, DT, FAR); advanceChain(ctrl, DT, FAR); }
check('空隙未闭合期间队头完全不动', Math.abs(cut.balls[0].wp - headBefore) < 1e-9,
  'Δhead=' + (cut.balls[0].wp - headBefore).toExponential(2));
check('同时队尾正常前进', cut.balls[cut.balls.length - 1].wp > tailBefore + 1e-9,
  'Δtail=' + (cut.balls[cut.balls.length - 1].wp - tailBefore).toFixed(4));
check('此时两链队尾位置一致（喂入不受影响）',
  Math.abs(cut.balls[cut.balls.length - 1].wp - ctrl.balls[ctrl.balls.length - 1].wp) < 1e-9);

let ff = 0;
while (chainHasGap(cut) && ff < 100000) { advanceChain(cut, DT, FAR); advanceChain(ctrl, DT, FAR); ff += 1; }
check('空隙最终闭合', !chainHasGap(cut), '用了 ' + ff + ' 帧');
const k = 3;
const expect = ctrl.balls[0].wp - k * T;
check('★ 回缩不变量：队头恰好落后 k×touchDist', Math.abs(cut.balls[0].wp - expect) < 1e-6,
  '实测落后 ' + (ctrl.balls[0].wp - cut.balls[0].wp).toFixed(6) + '  期望 ' + (k * T).toFixed(6));
for (let f = 0; f < 120; f++) { advanceChain(cut, DT, FAR); advanceChain(ctrl, DT, FAR); }
check('闭合后恢复刚性同步（差距保持 k×touchDist）',
  Math.abs((ctrl.balls[0].wp - cut.balls[0].wp) - k * T) < 1e-6);

// ---------- 洞穴 ----------
group('洞穴：队头越过即被吸入');
const dr = fresh(6);
const drainWp = dr.balls[2].wp;        // 洞口正好落在第 3 颗上
const got = drainHead(dr, drainWp);
check('越过洞穴的球被移除', got.length === 3, '吸走 ' + got.length + ' 颗，剩 ' + dr.balls.length);
check('剩余球的 wp 全部小于洞口', dr.balls.every(function (b) { return b.wp < drainWp; }));
check('stats.drained 已累加', dr.stats.drained === got.length);

// ---------- 数值健康 ----------
group('数值健康');
const hs = fresh(12);
for (let f = 0; f < 600; f++) advanceChain(hs, DT, FAR);
check('长跑无 NaN', hs.balls.every(function (b) { return Number.isFinite(b.wp); }));
check('长跑后 wp 严格递增（队头在前）', (function () {
  for (let i = 0; i + 1 < hs.balls.length; i++) if (hs.balls[i].wp <= hs.balls[i + 1].wp) return false;
  return true;
})());
const c2 = makeChain(mt, {});
c2.speed = 0;
const cl = clone(hs);
check('克隆链与原链逐球一致', cl.balls.every(function (b, i) { return b.wp === hs.balls[i].wp; }));

console.log('');
console.log('test-chain: ' + pass + ' 通过 / ' + fail + ' 失败');
process.exit(fail ? 1 : 0);


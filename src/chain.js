// U3 珠串模型：绳子/推动模型，逐行依据原版 CurveMgr::AdvanceBalls() 复刻。
// 见 refs/circleshoot/NOTES.md §3。纯逻辑：只存"沿轨道的弧长 wp"，不碰 DOM 也不碰几何。
//
// 数组约定：**队头在前**，balls[0] 最靠近洞穴（wp 最大），balls[n-1] 是刚冒出来的队尾。

import { DESIGN } from './config.js';

// 相邻两颗球"相接"所需的弧长距离。**逐对算半径**：原版全同尺寸才用 2*defaultRadius，
// 我们两轨球大小不同（U2 的 1:√2），必须逐对算，否则大小球相邻时会错判。
export function touchDist(mt, a, b) {
  return a.r + b.r + mt.linkGap;
}

export function makeChain(mt, opts) {
  opts = opts || {};
  return {
    mt: mt,
    balls: [],
    speed: 0,
    targetSpeed: opts.speed != null ? opts.speed : DESIGN.chainSpeed * mt.scale,
    accel: DESIGN.chainAccel * mt.scale,
    decel: DESIGN.chainDecel * mt.scale,
    slowDistance: DESIGN.slowDistance * mt.scale,
    slowFactor: DESIGN.slowFactor,
    spawnWp: opts.spawnWp != null ? opts.spawnWp : 0,
    stopTime: 0,            // 后退期间暂停推进的剩余帧数（原版 mStopTime）
    freezeTime: 0,          // §57 冻结反应的剩余秒数（>0 时整链不前进）
    nextId: 1,
    stats: { spawned: 0, drained: 0, removed: 0 }
  };
}

// 速度平滑：加速慢、减速快
export function smoothSpeed(ch, dt) {
  const t = ch.targetSpeed;
  if (ch.speed < t) ch.speed = Math.min(t, ch.speed + ch.accel * dt);
  else if (ch.speed > t) ch.speed = Math.max(t, ch.speed - ch.decel * dt);
  return ch.speed;
}

// 洞穴前的减速带：越靠近越慢（原版 mSlowDistance / mSlowFactor）
export function speedAtHead(ch, headWp, curveLength) {
  if (!(ch.slowDistance > 0)) return ch.speed;   // B7 冻结：减速带未启用
  const slope = curveLength - ch.slowDistance;
  if (headWp <= slope) return ch.speed;
  if (headWp >= curveLength) return ch.speed / ch.slowFactor;
  const t = (headWp - slope) / ch.slowDistance;
  return ch.speed * (1 - t) + (ch.speed / ch.slowFactor) * t;
}

// 一帧推进：只推队尾 -> 推动逐节向队头传递（遇空隙即断）
export function advanceChain(ch, dt, curveLength) {
  const balls = ch.balls;
  const n = balls.length;

  // ★ §57 冻结反应：整链停止前进（原神里冻结 = 无法行动）。
  //   喂入也一起停 —— 冒球要靠队尾腾出空间，链子不动自然就喂不进来。
  if (ch.freezeTime > 0) {
    ch.freezeTime = Math.max(0, ch.freezeTime - dt);
    return;
  }

  // ★ 后退（CurveMgr::AdvanceBackwardBalls 的同构实现，DESIGN.md §36）。
  //   每颗球自带 backLeft（剩余帧数）/ backSpeed（自己的速度）；一个扫描函数负责传播；
  //   只要这一帧有球后退，就设 stopTime（原版 mStopTime = 20）并**跳过推进**。
  const movedBack = advanceBackwardBalls(ch, dt);
  if (movedBack) ch.stopTime = Math.max(ch.stopTime, DESIGN.backStopFrames);
  recycleFront(ch);
  if (movedBack || ch.stopTime > 0) {
    if (ch.stopTime > 0) ch.stopTime -= 1;
    return;
  }

  smoothSpeed(ch, dt);
  if (n === 0) return;

  const head = balls[0];
  const effSpeed = curveLength != null ? speedAtHead(ch, head.wp, curveLength) : ch.speed;
  balls[n - 1].wp += effSpeed * dt;

  for (let i = n - 2; i >= 0; i--) {
    const back = balls[i + 1];
    const front = balls[i];
    const d = back.wp + touchDist(ch.mt, front, back);
    if (front.wp < d) {
      // visOff 只是渲染用的视觉滞后量（此球被顶开了一个跳变），不参与任何判定
      front.visOff = (front.visOff || 0) - (d - front.wp);
      front.wp = d;
    }
  }
}

// 施加一次后退冲量。totalDist = 这次总共要退多少（px），frames = 用多少帧退完 —— 对应原版的
// mBackwardsCount / mBackwardsSpeed 一对参数（原版：30 帧、速度 = comboCount * 1.5）。
// ★ 给**某一颗球**施加后退（对应原版 Ball::SetBackwardsCount / SetBackwardsSpeed）。
//   只标记这一颗；传播交给 advanceBackwardBalls —— 这比"预先给整段打标记"忠实得多，
//   因为原版就是"标记一颗 + 每帧沿相接关系往外拖、遇缝即断"。
export function applyBackward(ch, i, frames, dist) {
  const b = ch.balls[i];
  if (!b) return null;
  const f = Math.max(1, frames);
  // 距离**累加**（同一帧级联消多段时，后退量应当叠加），帧数取较长者。
  // 原版没有这条，是因为它每次只给一颗球设 count；我们级联时会连续调用。
  const remain = (b.backLeft > 0) ? b.backSpeed * (b.backLeft / 60) : 0;
  b.backLeft = Math.max(b.backLeft || 0, f);
  b.backSpeed = (remain + dist) / (b.backLeft / 60);   // px/秒
  return b.backSpeed;
}

export function hasBackward(ch) {
  const balls = ch.balls;
  for (let i = 0; i < balls.length; i++) if (balls[i].backLeft > 0) return true;
  return false;
}

// ★ CurveMgr::AdvanceBackwardBalls 的同构实现：
//   从**洞端**（下标 0）扫到**出球端**（下标 n-1）；带 backLeft 的球按自己的速度后退，
//   并把**身后（朝出球端）相接的球一起拖**；缝隙大于一步就停止传递。
//
//   命名陷阱：原版的 front() 是**出球端**、back() 是**洞端**，和中文习惯相反。
//   我们的下标 0 = 洞端、n-1 = 出球端。
//
//   ⚠ 这里试过一版"夹紧"（不允许任何球退到冒球口之外），**已删除**，两个原因：
//     1) 它管不了"该不该退"——那是规则层的事，由消除位置决定（见 scene.js pushBack）。
//     2) 它有副作用：消除段离洞很远时，"洞端那一侧"会一直延伸到接近出球口，
//        夹紧按那段最靠出球端那颗的余量卡住 -> k×touchDist 只兑现一点点 ✗
//   退到冒球口之外的球交给 recycleFront 回收 —— 这正是原版 RemoveBallsAtFront 的行为。
export function advanceBackwardBalls(ch, dt) {
  const balls = ch.balls;
  let anyMoved = false;
  let collided = false;
  let speed = 0;
  for (let i = 0; i < balls.length; i++) {
    const b = balls[i];
    if (b.backLeft > 0) {
      speed = b.backSpeed;
      b.wp -= speed * dt;
      b.backLeft -= 1;
      collided = true;
      anyMoved = true;
    }
    if (!collided) continue;
    const nb = balls[i + 1];
    if (!nb) break;
    const T = touchDist(ch.mt, b, nb);
    if (b.wp - nb.wp <= T + 1e-6) {
      nb.wp -= speed * dt;                       // 挨着 -> 同速拖
    } else {
      const over = (b.wp - T) - nb.wp;           // 缝隙比一步还小？
      if (over < speed * dt) {
        nb.wp = b.wp - T;                        // 顶到刚好相切，用缩小后的速度继续传
        speed = dt > 0 ? over / dt : 0;
      } else {
        collided = false;                        // 缝太大 -> 停止传递
      }
    }
  }
  return anyMoved;
}


// 回收滚出出球端的球（对应原版 RemoveBallsAtFront，wp < 1 的球被回收）
export function recycleFront(ch) {
  const balls = ch.balls;
  let cut = 0;
  while (cut < balls.length && balls[balls.length - 1 - cut].wp < ch.spawnWp) cut += 1;
  if (cut > 0) {
    balls.length -= cut;
    ch.stats.leftField = (ch.stats.leftField || 0) + cut;
  }
  return cut;
}

// 从队尾冒一颗新球；必须等队尾让出位置（原版 AddBall 的同款约束）
export function spawnBall(ch, base, radius) {
  const balls = ch.balls;
  const r = radius != null ? radius : ch.mt.R;
  const cand = { wp: ch.spawnWp, base: base, r: r, id: ch.nextId++ };
  if (balls.length > 0) {
    const tail = balls[balls.length - 1];
    if (tail.wp < cand.wp + touchDist(ch.mt, cand, tail)) return null;
  }
  balls.push(cand);
  ch.stats.spawned += 1;
  return cand;
}

// 队头越过洞穴即被吸入
export function drainHead(ch, curveLength) {
  const out = [];
  while (ch.balls.length > 0 && ch.balls[0].wp >= curveLength) {
    out.push(ch.balls.shift());
    ch.stats.drained += 1;
  }
  return out;
}

// 按"相接"判据切出连续段（队头在前）。空隙 = 相邻两球间距 > touchDist。
export function chainRuns(ch) {
  const balls = ch.balls;
  const runs = [];
  if (balls.length === 0) return runs;
  let i0 = 0;
  for (let i = 0; i + 1 < balls.length; i++) {
    const linked = (balls[i].wp - balls[i + 1].wp) <= touchDist(ch.mt, balls[i], balls[i + 1]) + 1e-6;
    if (!linked) { runs.push({ i0: i0, i1: i }); i0 = i + 1; }
  }
  runs.push({ i0: i0, i1: balls.length - 1 });
  return runs;
}

export function chainHasGap(ch) {
  return chainRuns(ch).length > 1;
}

// 闭区间移除（队头在前）
export function removeRange(ch, i0, i1) {
  const removed = ch.balls.splice(i0, i1 - i0 + 1);
  ch.stats.removed += removed.length;
  return removed;
}

// 预装珠串：关卡开始时轨道上就已经有货（原版关卡配 mNumBalls 一次性铺满）。
// i=0 放在队头（wp 最大），队尾正好落在 wp=0 的冒球口。
export function prefillChain(ch, count, baseFn) {
  const T = touchDist(ch.mt, { r: ch.mt.R }, { r: ch.mt.R });
  for (let i = 0; i < count; i++) {
    // ★ 必须把下标传给回调（§60）：固定开局序列（level.script）要靠它取第 i 颗。
    //   ⚠ 这里原来是 baseFn() 空参调用 —— 老的回调都忽略参数所以看不出问题，
    //     但脚本关会拿到 bs2[NaN] = undefined，**整关的球碱基全是 undefined**：
    //     既不报错、也配不上，界面上只会看到一排写着 "undefined" 的球。
    ch.balls.unshift({ wp: i * T, base: baseFn(i), r: ch.mt.R, id: ch.nextId++, n: i, paired: false, pairBase: null });
  }
  return ch;
}

// 把一颗球插进珠串（U12 加球）。只需要"塞进去"，不需要手写顶开逻辑：
// 相邻间距小于 touchDist 时，下一帧的绳子推动会**自动把队头那侧整体前移一个球位**，
// 这就是祖玛"插一颗球把珠串顶开"的行为，只是交给绳模型自然完成。
export function insertBall(ch, index, ball) {
  ch.balls.splice(index, 0, ball);
  if (ch.stats.inserted == null) ch.stats.inserted = 0;
  ch.stats.inserted += 1;
  return ball;
}

export function chainLength(ch) {
  return ch.balls.length;
}


# 参考实现笔记：alula/CircleShootApp（Zuma Deluxe 1.0.0 反编译）

> 来源：https://github.com/alula/CircleShootApp （C++，87★，2025-12 仍在更新）
> 本目录只存了与玩法直接相关的 7 个文件：`Board.h/.cpp`、`Ball.h/.cpp`、`CurveMgr.h/.cpp`、`WayPoint.h`。
> 读它的目的只有一个：**珠串到底怎么动、怎么插、怎么算分**——这三件事自己拍脑袋必错。

---

## 1. 对象模型

| 原版 | 职责 | 我们的对应 |
|---|---|---|
| `WayPointMgr` | 一整条轨道的点表（`mWayPoints`，**下标即弧长，约 1px 一格**） | `src/geometry.js` 的 `TrackPath` |
| `WayPoint` | 每个点的 `x,y` + **`mPerpendicular`（法线）** + `mRotation` + `mInTunnel` + **`mPriority`（遮挡层级）** | 我们的 `nx,ny` + `z` |
| `Ball` | 一颗球：**`mWayPoint`（单个浮点 = 位置）** + `mx,my` + `mCollidesWithNext` + `mBackwardsCount/Speed` + `mSuckCount` + `mGapBonus/mNumGaps` | `src/chain.js` |
| `CurveMgr` | 珠串 + 弹丸 + 计分 + 关卡 | `src/chain.js` + 后续 |

**要点：球的位置就是"沿轨道的弧长"一个标量。** —— 和我们的 `wp` 模型一致。

## 2. 链表顺序与 wp 语义（最容易搞反的地方）

`mBallList` 的 `begin()` 是**队尾（刚冒出来的球，wp≈1）**，`back()` 是**队头（最靠近洞穴的球）**，`wp` 从队尾向队头递增，洞穴在 `wp = GetEndPoint()`。

证据（不是猜的）：
- `AddBall()`：新球 `SetWayPoint(aBall, 1.0f)` 后 `InsertInList(mBallList, mBallList.begin())`；
- `IsLosing()`：`GetEndPoint() > mBallList.back()->GetWayPoint()` 时不输 → 队头到洞穴才算输。

## 3. ★ 每帧推进：这是"绳子模型"，不是"刚性链"

`CurveMgr::AdvanceBalls()`（CurveMgr.cpp:1382）：

    if (!mFirstBallMovedBackwards && !mStopTime)
        SetWayPoint(front(), front().wp + mAdvanceSpeed);   // 只推队尾

    for (ball 从队尾走向队头):
        next = ball 的前一颗
        if (ball.wp > next.wp - (ball.r + next.r))          // 挨上了
            next.wp = ball.wp + ball.r + next.r;            // 把前一颗顶到刚好相切
            ball.collidesWithNext = true;
            ball.needCheckCollision = false;

**我们原来的设计（"每帧用 headDist 反推所有球的位置"）是错的**：那样链是刚性的，**永远不存在空隙**，于是"穿隙"和"回缩"都不可能真实发生。

正确模型：**只有队尾被喂入，推动逐节向前传递；遇到空隙传递就断**。于是：
- 中间被清掉一段 → 出现真空隙；
- **队头那一截立刻停住**，队尾这一截继续爬，**空隙从后往前闭合**；
- 闭合后整条链恢复同步前进。

这就是祖玛"回缩"的真实机制：不是后段后退，而是**前段等、后段追**。
副作用（也是玩法）：**清得越早，队头等得越久，等于争取到 k×2R 的时间**。

其他细节：
- 速度 `mAdvanceSpeed` 向目标速度平滑：**加速 +0.005/帧、减速 -0.1/帧**（约 20:1，减快加慢）；
- 快接近洞穴时按 `mSlowDistance/mSlowFactor` 线性降到 `speed/slowFactor`（"越接近终点越慢"是真的）；
- `mInDanger = back().wp >= mDangerPoint`。

## 4. ★ 插入：子弹怎么并进珠串（CurveMgr.cpp:1766 `AdvanceMergingBullet`）

1. 子弹命中球 A，带一个 `GetHitPercent()`（0→1 表示"并入进度"）；
2. 把 A 前方的球 P（`aPushBall`）**顶开**：`aPercent = (rP + rBullet) * hitPercent²`，`P.wp = max(A.wp + aPercent, P.wp)` —— 顶开的距离随并入进度**平方增长**，不是线性；
3. `hitPercent >= 1` 时，子弹**变成一颗真球**，按 `hitInFront` 插到 A 的前面或后面；
4. 立刻 `CheckSet(newBall)` 判同色三消；
5. 判不中时，若隔壁（跨空隙）有同色球 → 触发 `SuckPending/SuckCount`（被吸走）。

**我们只需要第 2、3 步**：我们的"配对"不是插入球，而是"把小球挂到大球上并让大球变成已配对"。但**顶开邻球**这一手有用——将来做"配错爆炸把主链顶开"时可以借用。

## 5. 穿隙计分公式（原版原式）

    命中时若子弹穿过了空隙：aMinGapDist = 穿过的最小空隙宽度
    aMinGapDist -= 4 * ballRadius;  if (<0) = 0
    aGapBonus = (MAX_GAP_SIZE - aMinGapDist) * (endless ? 250 : 500) / MAX_GAP_SIZE
    aGapBonus = (aGapBonus / 10) * 10;   if (<10) = 10
    if (aNumGaps > 1) aGapBonus *= aNumGaps;

即：**穿过的缝越窄、穿的缝越多，分越高**。我们的 U7 直接抄这个形状。

## 6. 遮挡层级 = 原版就有

`BallDrawer` 里有 `mBalls[MAX_PRIORITY][1024]` 和 `mForeImage[MAX_PRIORITY]`，`WayPointMgr::GetPriority(Ball*)` 给出每颗球所在轨道的优先级，绘制时按优先级分组。**这正是我们 U4 的 z 层方案**，说明这条路是对的（不是我拍脑袋发明的）。
另外 `mInTunnel` 表示轨道有一段是"隧道"（球经过时被遮住）—— 又一个同族机制，U14 可借鉴。

## 7. 冲突 / 我们有意不同的地方

| 点 | 原版 | 我们 | 理由 |
|---|---|---|---|
| 球尺寸 | 全部同尺寸（`GetDefaultBallRadius()`） | 出球道大球 / 三消道小球（直径比 √2:1） | 你的设计要求：靠大小瞬间区分两条道 |
| 相切判据 | `2 * defaultRadius` | **逐对** `r_i + r_j + linkGap` | 尺寸不同后必须逐对算，否则大小球相邻时会错判 |
| 消除 | 同色 ≥3，跨空隙不算 | 连续配对，长度是 3 的倍数 | 你的设计 |
| 配错 | （无此概念） | 爆炸 + 连锁，不扣分 | 你的设计 |
| 已配对球 | — | 挂在三消道，绑主球 wp，不参与推动 | 双轨设计 |


---

# 附：原版完整逻辑（第二轮补读，逐条带行号）

补读文件：`WayPoint.cpp`（之前漏了，正是"设位置"的底层）、`CurveMgr::GetNumInARow/CheckSet`。
仍未读：`Gun.cpp`、`LevelParser.cpp`、`Board.cpp` 的 UI/存档部分。

## A. 数据结构：原版**没有"编号"这个概念**

- `BallList = std::list<Ball*>`；顺序：`begin()` = 队尾（冒球口，wp≈1），`back()` = 队头（洞穴，wp 最大）。
- 球的身份 = `Ball*` 指针 + 自增的 `mId`（Ball.cpp:22 `mIdGen`）。
- 位置 = **单个浮点** `mWayPoint`（弧长，1 单位 ≈ 1 像素），另缓存 `mx,my`。
- 点表 `mWayPoints`：每点带 `x,y / mPerpendicular(法线) / mRotation / mAvgRotation / mInTunnel / **mPriority(遮挡层级)**`。

**结论：原版根本不存在"编号重排"问题** —— 它用「链表位置 + 稳定 id」，正是我们最后采用的方案。

## B. 设位置：**只设这一颗，没有任何自动压实**（WayPoint.cpp:30-64）

    void WayPointMgr::SetWayPoint(Ball *theBall, float thePoint) {
        ... 取整点 aPoint、插值 aMix ...
        theBall->SetPos(插值坐标);
        theBall->SetWayPoint(thePoint);
        theBall->SetRotation(...);
    }

**没有任何一行去动别的球。** 所以原版**不存在**"消除后自动补位"这套东西。

配套的 `FindFreeWayPoint(existing, new, inFront, pad)`（:92-123）才是"找位置"的逻辑：
从已有球的格号出发，沿 `inFront ? +1 : -1` **逐格试**，直到新球与已有球**不再物理重叠**，就放那儿。
即"**找离它最近的空位**"。

## C. 推进：只推队尾，遇空隙即断（CurveMgr.cpp:1382 `AdvanceBalls`）

    SetWayPoint(front(), front().wp + mAdvanceSpeed);      // 只推队尾
    for (球 从队尾走向队头) {
        if (ball.wp > next.wp - (r_ball + r_next))
            SetWayPoint(next, ball.wp + r_ball + r_next);  // 顶到刚好相切
    }

- 速度平滑：**加速 +0.005/帧、减速 −0.1/帧**（约 20:1）。
- 接近危险点按 `mSlowDistance / mSlowFactor` 线性减速。
- **空隙会截断推动** ⟹ **队头那截冻结，队尾那截以喂入速度追上来**。

## D. 消除判定：**同色 ≥ 3**，不是 3n（CurveMgr.cpp:992 / 1031）

    int GetNumInARow(ball, color) {
        count = 1;
        while (next = ball->GetNextBall(true), 同色) count++;   // mustCollide = 必须物理相接
        while (prev = ball->GetPrevBall(true), 同色) count++;
        return count;
    }
    bool CheckSet(ball) {
        count = GetNumInARow(ball, ball->GetType());
        if (count < 3) return false;
        for (整段 [aPrevEnd, aNextEnd]) StartClearCount(b);      // 整段标记，不是只消 3 颗
    }

- `GetNextBall(true)` 内部要求 `GetCollidesWithNext()` —— **空隙会断段**（λ 在原版是真实存在的）。
- 规则是 `count >= 3`，**不是 3 的倍数**。

## E. 消除后的时序：**球先原地爆炸 40 帧，期间还在链上**

`UpdateSets`（:1670）：

- `clearCount` 从 1 涨到 40；期间带 clearCount 的球**仍在 mBallList 里**，仍然参与推动链
  ⟹ **动画期间链条不出现空隙**。
- 满 40 帧才 `DeleteBall + mBallList.erase` ⟹ 这时才出现空隙 ⟹ 由 C 的推动从后往前补。
- 特例：若删的是 `begin()`（**队尾**那颗）⟹ `mAdvanceSpeed = 0; mStopTime = 40`（暂停喂入 40 帧）。
- 若被删段的**前后邻居同色** ⟹ `aNextBall->SetSuckCount(10); combo+1`。

## F. 插入：`hitPercent²` 顶开（CurveMgr.cpp:1766 + Bullet.cpp）

    flag = (子弹位置 − 球心) × 轨道法线 < 0       // 命中侧，CurveMgr.cpp:427
    aPushBall = !hitInFront ? hitBall : hitBall->GetNextBall();       // Bullet.cpp:119
    aPercent  = (r_push + r_bullet) * hitPercent * hitPercent;        // 平方，不是线性
    pushBall.wp = max(bullet.wp + aPercent, 原值);
    hitPercent >= 1 ⟹ 生成真球，插到命中球的 前/后（hitInFront 决定）⟹ CheckSet(newBall)

## G. 后退：原版**有**，但挂在 combo / 道具上，不在普通消除上

- `UpdateSuckingBalls`（:1652-1662）：combo 后给 `aNextBall` 设 `BackwardsCount = 30`，
  速度 = `comboCount * 1.5`（下限 0.5）。
- `AdvanceBackwardBalls`（:1517）：带 BackwardsCount 的球 `wp -= speed`（**后退**），并把相邻球一起带退。
- 另有 `PowerType_MoveBackwards` 道具。

**所以"珠子后退"在原版里是真机制，只是它由连击触发，而不是由普通消除触发。**

## H. 洞穴 / 失败

- `IsLosing`（:546）：队头越过终点 && 没有球处于 suck 中。
- `Board::SetLosing`（:294）：`mLives -= 1`，进入 `GameState_Losing`；`mLives <= 0` 时结算最高分。
- `CurveMgr::UpdateLosing`（:302）：所有球 `wp += suckCount/4` 加速推向终点，越界即删。
- 初始 `mLives = 3`（Board.cpp:153）；每 50000 分加一命（:2201）。

## I. 我们**有意偏离**原版的地方（都是你的设计决定）

| # | 项 | 原版 | 我们 | 依据 |
|---|---|---|---|---|
| 1 | 消除条件 | 同色 **ℓ ≥ 3** → 整段消 | 配对 **ℓ ≥ 3 且 ℓ ≡ 0 (mod 3)** → 整段消 | 你的 A3/A4/A19 |
| 2 | 消除后 | **前段冻结**，后段以喂入速度追上来补 | **前段往出球口方向后退**（逻辑当帧、画面缓动） | 你的 §21 |
| 3 | 消除的可见时序 | 球原地爆炸 **40 帧**（仍在链上），之后才删 | 逻辑**当帧**删除，视觉用 `visOff` 缓动 | 你的"立即消除"+"要卡一下" |
| 4 | 配对语义 | 同色三消 | 碱基互补 + 绑定小球（"已被读出"） | 你的 A2/A3 |
| 5 | 加球 | 子弹**必然**并入 | 只在"加球模式"下并入（配对模式失败则无事发生） | 你的 A17 + §16 方案 2 |
| 6 | 空隙 λ | 真实存在（`GetPrevBall(true)` 要求相接） | **λ ≡ 1**（消除当帧压实） | 由 #2 推出 |

**一致的部分**：弧长参数化、法线偏移、点表带遮挡层级、遮挡分层渲染、扫掠命中、按 id 而非下标跟踪、洞穴吞球扣命。


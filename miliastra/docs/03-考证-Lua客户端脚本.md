# 03 考证：客户端脚本（Lua API）

> 官方出处全部来自本地文档快照 `docs/official/md/`（219 篇，2026-09-20 抓取）。
> 复核命令：`python3 tools/doc-section.py <docId> <章节标题> [结束标题]`

## 0. 一句话结论

**千星奇域有 Lua 客户端脚本，官方原话是"客户端脚本可以实现绝大多数 2D 玩法"。**
本作是 2D 玩法。所以移植的**主路线不再是"节点图 + 实体 + 基础运动器"**，
而是**"一张客户端控件画布 + 一个 Lua 脚本"**。

这条结论**推翻了 README 里 6 条硬约束中的 5 条**（见 §4）。

## 1. 出处

| 文档 | ID | 内容 |
|---|---|---|
| 客户端控件 API 文档 | `mhtakr07vej4` | 全部 Lua 接口：生命周期 / game.* / 控件类 / 枚举 |
| 客户端控件和客户端脚本 | `mhbgxf0nynww` | 脚本怎么挂、怎么打包、能干什么 |
| 编辑项范围限制 | `mh74ae9fsg8i` | 控件数量上限 |

## 2. 关键原文（逐条带出处）

### 2.1 能不能做 2D 玩法

> 「客户端脚本可以实现绝大多数 2D 玩法，以及界面的动态效果」
> —— `mhbgxf0nynww` 七、客户端脚本的使用方式

这一句是整个移植方案的地基。

### 2.2 运行环境（`mhtakr07vej4` 三、运行环境）

> 「Lua 版本：运行时使用 Lua 5.3」

不可用的标准库（**注意：只列了这些，其余都可用**）：

- `string.dump`
- `io.*`
- `coroutine.*`
- 除 `os.time` / `os.date` / `os.clock` / `os.difftime` 外的 `os.*`
- 除 `debug.traceback` 外的 `debug.*`

补充方法：`math.isnan(n)`、`math.isinf(n)`。

> **含义**：`math.*` / `table.*` / `string.*` / `pairs` / `ipairs` 全部可用。
> 本作 `src/` 里的三角、向量、弧长积分、绳模型，全部可以在 Lua 里原样写。
> **没有 I/O，所以所有素材必须在编辑器里做** —— 不能读文件、不能联网。

### 2.3 主循环（`mhtakr07vej4` 四、1. 脚本生命周期 / 2. 逐帧控制）

| 回调 | 参数 | 说明 |
|---|---|---|
| `OnInit()` | 无 | 脚本初始化 |
| `OnStart()` | 无 | 脚本启动 |
| `OnEnable()` / `OnDisable()` | 无 | 启用 / 停用 |
| `OnUpdate(dt)` | `dt: number` | **逐帧更新，不受关卡时停影响** |
| `OnLevelUpdate(dt)` | `dt: number` | 逐帧更新，受关卡时停影响 |
| `OnDestroy()` | 无 | 销毁 |

另有 `script:EnableUpdate(enabled)` 可随时开关逐帧。

> **含义**：**有真正的每帧主循环，还有 dt。**
> README 里"没有每帧执行节点、只能靠 33Hz 定时器"那条约束，
> 对 **Lua 路线完全不成立**。本作的 `step(dt)` 可以 1:1 搬过来。

### 2.4 渲染（`mhtakr07vej4` 14. ClientUIImageControl）

字段：`localRotationX/Y/Z`、`localScaleX/Y/Z`、
`anchoredPositionX/Y`、`sizeDeltaX/Y`、`anchorMin/Max`、`pivot` —— **全部 Tweenable（可补间）**。

图片相关：`imageSource` / `imageId` / `imageColor`（读写，染色）/ `imageType` /
`enableMask` / `softEdge*` / `fillType` + `fillAmount`（**读写，进度**）。

方法：`SetImage(imageSource, imageId)`、`SetFillRadial90/180/360(...)`、`SetFillHorizontal/Vertical`。

> **含义**：一颗球 = 一个图片控件。画球只要设 `anchoredPositionX/Y` + `localRotationZ` + `imageColor`。
> `fillAmount` 的环绕/水平填充正好可以做**洞穴吸入**和**进度条**。
> `imageColor` 读写 = **七球模式的 7 种颜色不用 7 张图，一张图染色即可**。

文字（15. ClientUITextBoxControl）：`text`（**读写**）、`fontSize`、`fontColor`、
`enableOutline` / `outlineColor`、对齐、`adaptiveFontSize`。
> **含义**：分数 / 提示 / 连击全部可运行时刷新，不需要服务端变量 + 文本框富文本那套。

### 2.5 输入（`mhtakr07vej4` 18/19/26）

- `ClientUICursorEventAreaControl.AddCursorEventListener(eventType, callback)`，
  事件类型 `CursorDown / CursorUp / CursorEnter / CursorExit / CursorDrag / CursorBeginDrag / CursorEndDrag / CursorClick`。
- `CursorEventData:GetUIPos()` —— **「以画布左下角为原点，获取当前屏幕 UI 坐标」**
  （另有 `GetPressUIPos()` / `GetUIPosDelta()` / `dragging` / `touchId`）。
- `game.GetCursorUIPos()` —— 直接拿光标 UI 坐标，**不需要事件**。
- 键盘：`Enum.KeyboardKeyCode` 有 40+ 个"奇匠按键"（含方向键、WASD、Space、左右 Shift/Ctrl、数字、字母）
  和语义键（`NormalAttackKey`=鼠标左键、`CharacterSkill1Key`=E、`InteractKey`=F 等）。
- 手柄：`AddNavigationEventListener` + 左右摇杆轴值。

> **含义**：瞄准 = `game.GetCursorUIPos()` 减去发射口坐标；开火 = 光标点击或按键。
> **坐标空间天然统一**（都是画布 UI 坐标），不需要世界坐标 <-> 屏幕坐标转换。
> 触屏也有 `GetPressUIPos` / `touchId`，手机端可用。

### 2.6 动画（`mhtakr07vej4` 7/8. Tween / TweenSequence）

`game.Tween(object, {字段=目标值}, 时长)` → `:SetEase / :SetRelative / :Play / :SetLoops`；
`game.TweenSequence()` 可编排 `Append / AppendInterval / AppendCallback / Join / Insert`。
缓动枚举 30 种（Linear / InOutQuad / OutBack / OutElastic / OutBounce ...）。

> **含义**：消除时的"回缩"、爆炸、飘字，可以用补间，不必每帧手算。
> 但**主串的推进建议还是每帧自己算**（要跟物理一致），补间只用于表现层。

### 2.7 客户端 <-> 服务端（`mhbgxf0nynww` + `mhtakr07vej4` 9. ServerSignal）

- 客户端 → 服务端：`game.ServerSignal(name)` → `:AddInt/AddEntity/AddVector3/AddString...` → `:SendSignal()`。
  参数类型枚举 `ParamType` 覆盖 实体 / 实体列表 / 整数 / 整数列表 / 浮点 / 字符串 / 三维向量 / GUID / 元件ID / 配置ID 及各自列表。
- 服务端 → 客户端：服务器节点【发送客户端脚本信号】，脚本用
  `script:RegisterServerSignalHandler(name, cb)` 监听。
- **延迟**：「联机情况下，服务器发送信号的延迟最低为 100ms」。

### 2.8 读全局自定义变量（`mhtakr07vej4` 6.(3)）

- `game.GetGlobalCustomVariableValue(entityType, name)` —— 「支持复杂变量结构（列表、字典、结构体）」。
- `script:RegisterCustomVariableChangedHandler(entityType, name, cb)` —— 变量变化回调。
- `entityType` 只有三种：`Level` / `PlayerSelf` / `AvatarSelf`。

> **含义**：**Lua 读不到任意实体**。要跟服务端共享状态，只能走"关卡变量 + 信号"。

### 2.9 挂载与打包（`mhbgxf0nynww` 六/七/八）

- 入口：千星沙箱 - 客户端脚本资源管理器 - 客户端脚本映射。
- 「脚本需要与客户端控件关联才能正常生效」——在客户端控件的**脚本页签**里挂。
- 「只有在千星沙箱里建立了映射的 lua 文件才会被打包上传，仅在本地创建文件但未建立映射的脚本，
  无法在运行时正常上传」。
- 「除客户端控件容器画布中的客户端控件以及客户端控件模板中的控件外，**其他控件均为服务器控件**，
  服务器控件的模板索引无法被客户端脚本调用」。
- 动态创建：`game.InstantiateClientUIControl(prefabIndex, parent)`；
  「挂载在**主屏**中的客户端控件，以及存为模板的客户端控件的**子节点**，均不支持通过脚本接口动态创建」。

> **含义（要小心）**：动态创建控件有坑。
> **稳妥做法：编辑期就把球位控件摆好（比如 64~128 个），运行时只做 显示/隐藏 + 改位置/颜色/大小**。
> 上限见 §3，完全够。

## 3. 平台上限（`mh74ae9fsg8i` 编辑项范围限制）

| 项 | 上限 |
|---|---|
| 界面布局最大数量 | 100 |
| 自定义控件模板最大数量 | 2000 |
| **单个界面控件组内界面控件最大数量** | **1000** |
| **单次玩家屏幕内可显示的界面控件最大数量** | **10000** |
| 字符串最大长度 | 1000 |

> 本作最多同时显示 ~150 个球 + 若干 HUD，离 1000 差一个数量级。

## 4. 这条路线推翻了 README 的哪几条硬约束

| # | 旧结论（节点图 + 实体路线） | Lua 路线 |
|---|---|---|
| 1 | 路径没有弧长读数 -> 只能离散槽位 | ❌ 不成立。弧长就是 Lua 里一个数组 + 累加，**原样保留** |
| 2 | 速度是逐段到达时长 | ❌ 不成立。速度就是 `wp += v*dt` |
| 3 | 没有反向运动节点 | ❌ 不成立。`wp -= impulse` |
| 4 | 投射运动器各端不一致 | ❌ 不成立。不用运动器 |
| 5 | 路径运动器不可叠加 | ❌ 不成立。一个球不是一个实体 |
| 6 | **单条路径最多 50 路点** | ❌ 不成立。Lua 里的路径**点数是自己的数组长度** |
| 7 | **没有每帧执行节点，只能 33Hz 定时器** | ❌ 不成立。`OnUpdate(dt)` |
| 8 | 自定义变量存球状态 | ⚠️ 降级为"存档 / 跨端同步"用途 |
| 9 | 判定逻辑必须在服务端 | ⚠️ 单人玩法下判定放客户端；联机才需要同步 |

**仍然成立**的约束只有：

- 没有 I/O → 素材必须手做；
- Lua 读不到任意实体 → 如果要联机，状态得靠关卡自定义变量 + 信号来回搬；
- 动态创建控件有"主屏 / 模板子节点"限制 → 用固定控件池绕开。

## 5. 方案对比（保留两条路线，主路线已定）

### 路线 A（主）：客户端 Lua 2D

```
一个客户端控件容器画布
  ├─ 背景 / 轨道（图片控件，静态）
  ├─ 球池：N 个图片控件（运行时只改 位置/旋转/颜色/可见性）
  ├─ 发射器 + 待发球
  ├─ 命中检测区域（一个铺满玩区的 CursorEventArea）
  └─ HUD：分数 / 提示 / 连击（文本框控件）
Lua 脚本（挂在该容器上）
  └─ OnUpdate(dt) -> 直接搬运 ../src/ 的 step(dt)
```

优点：`../src/` 的 3700 行数学**几乎可以逐函数翻译**；无路点/实体/定时器限制；单人零同步。
代价：**只做单人**；联机要另加一层服务端同步。

### 路线 B（备）：服务端节点图 + 实体

就是 README 原来那套（离散槽位 + 路径运动器 + 33Hz 定时器）。
**保留为备选**，在"必须联机"或"必须用 3D 场景物体"时才启用。
`export-path.mjs` / `export-slots.mjs` / `lib/platform-limits.mjs` 属于路线 B 的资产，
**不删**，但不再是关键路径。

## 6. 未证实 / 必须实测（不许当成结论）

1. `OnUpdate` 的实际频率与是否与渲染帧一致（文档只说不受时停影响）。
2. 一帧内改 150 个控件的 `anchoredPosition` 的性能 —— 需要做一个压力测试关卡。
3. `game.InstantiateClientUIControl` 到底能创建什么（"仅存为模板的客户端控件的父节点"这句主语不明），
   **方案不依赖它**。
4. 客户端 Lua 能否在**单人关卡**里正常跑（"联机 100ms"只说明联机有延迟，没说单人有无）。
5. 球用图片控件、玩家用光标点击 —— 与"原生玩法"混用时的层级/遮挡关系。
6. 脚本变量（编辑器里配的"脚本变量"）与 `script:GetParam` 的实际可用类型。

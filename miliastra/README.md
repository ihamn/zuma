# 千星奇域移植（miliastra/）

把 `Zuma/` 里那套做好的玩法**搬到原神千星奇域**。这个文件夹是移植工作区，
和游戏本体（`../src/`、`../DESIGN.md`）分开 —— 本体继续按自己的节奏走，这里只做翻译与验证。

## 目录

```
miliastra/
  README.md          本文件：干什么、怎么用、还差什么
  docs/              官方文档考证 + 施工图（都要有出处）
    01 路径与运动   02 节点图   03 客户端脚本(Lua)   04 移植规则清单   05 移植方案(定稿)
    official/        219 篇官方文档离线快照 + md/ 可 grep 版
  lua/
    src/             ★ Lua 侧真源（14 个模块，会被打包上传）
    host/mock.lua    假宿主：照官方 API + **真机契约**实现的无头环境（本地工具）
    test/            假宿主自测 + 表现层/输入层整关 + 打包产物端到端（164 项断言）
    parity/run.lua   对拍的 Lua 侧解释器
  tools/             复用工具（只读 src/，产物写 out/）
    sim-play.mjs     ★ 本地试玩台：在千星客户端 Lua 运行时里真跑一遍
    sim-render.mjs   把试玩台的控件树画成 PNG（好"看见"画面）
  out/               产物（**不要手改**）：zuma.lua（上传用）/ paths / slots / params / levels
  vendor/            Lua 5.3.6 源码 + 编译好的解释器（不进仓库）
```

## 一条命令

```
node miliastra/tools/run-all.mjs      # 导出 + 沙箱检查 + 打包 + 对拍 + Lua 测试 + 试玩台 + 打包电脑端，退出码即结果
```

**解释器不用管**：`lib/lua-runner.mjs` 会按 `ZUMA_LUA` > `vendor/bin/lua` > PATH > Windows 默认安装位置
找一个能用的 Lua，并在输出第一行报版本。**千星奇域是 Lua 5.3**；本机若只有 5.4（`winget install DEVCOM.Lua`）
也能跑，81339 个对拍值实测**零差异**，但那行版本提醒会一直挂着 —— 要严格对齐就装 5.3。

## 工具清单

| 工具 | 干什么 | 产物 |
|---|---|---|
| **`parity.mjs`** | **JS↔Lua 对拍** —— 移植正确性的唯一证据 | 通过/失败 |
| `parity-diff.mjs` | 对拍失败时定位**第一处分叉**（行 + 列 + 上下文） | 控制台 |
| **`test-lua.mjs`** | Lua 侧测试（假宿主 / 整关 / 打包产物） | 通过/失败 |
| **`sim-play.mjs`** | **本地试玩台**：在客户端 Lua 运行时里真跑（没装模拟器就跳过） | 控制台 + `out/sim-*.json` |
| `sim-render.mjs` | 控件树 → PNG（几何/配色/HUD 一眼可见） | `out/sim-*.png` |
| **`check-lua-sandbox.mjs`** | 拦"千星奇域没有的标准库"和项目规矩 | 通过/失败 |
| **`bundle-lua.mjs`** | 14 个模块打成单文件 + 暴露生命周期全局 | `out/zuma.lua` |
| `export-levels.mjs` | `levels.js` → Lua 关卡表（**不手抄**） | `lua/src/levels_data.lua` / `out/levels.*` |
| `build-lua.sh` | 从 lua.org 编译 Lua 5.3.6 参考解释器（手机端用） | `vendor/bin/lua` |
| `fetch-docs.mjs` / `ctx-grep.py` / `doc-section.py` | 官方文档抓取与检索 | `docs/official/` |
| `export-path.mjs` / `export-slots.mjs` / `export-params.mjs` | 轨道/槽位/常量导出（路线 B 资产） | `out/paths.*` 等 |
| `verify-export.mjs` / `calc-balance.mjs` | 往返校验 / 平衡 sanity | 通过/失败 |
| `pack-pc.mjs` | 打包电脑端 zip（固定时间戳，产物字节稳定） | `pc/zuma-pc.zip` |
| `lib/platform-limits.mjs` | 平台硬限制（带官方出处） | — |
| `lib/lua-runner.mjs` / `lib/python.mjs` | 找 Lua / 找 Python 3（Windows 的 Store 占位程序要绕开） | — |

## 三条工具约定

**① 导出物必须能验证。** 往返校验误差 **2.8e-6**（比一颗球小两个数量级）✓

**② 平台硬限制写在代码里，不写在文档里。** 见 `lib/platform-limits.mjs` 与
`check-lua-sandbox.mjs` —— 违规当场报错，不靠人记得去查文档。

**③ 跨语言移植必须逐值对拍。** 当前 **308 条命令 / 5702 行 / 81339 个数值零差异** ✓

## 主路线：客户端 Lua 脚本

**一句话**：官方原话是

> 「**客户端脚本可以实现绝大多数 2D 玩法**，以及界面的动态效果」——`mhbgxf0nynww`

本作就是 2D 玩法。所以主路线是 **"一张客户端控件画布 + 一个 Lua 脚本"**：

```
客户端控件容器（画布）
├── 玩区容器
│   ├── 球池：N 个图片控件（运行期只改 位置/尺寸/颜色/图片/可见性）
│   ├── 弹药池：M 个图片控件
│   ├── HUD：6 个文本框
│   └── 光标检测区域：铺满画布
Lua 脚本（挂在容器上）
  OnUpdate(dt) -> input.update -> board.advanceScene -> ui.sync
```

| 需要的能力 | 官方有什么 |
|---|---|
| 每帧主循环 | `OnUpdate(dt)`，「逐帧更新，不受关卡时停影响」 |
| 数学 | Lua 5.3；`math.*` / `table.*` / `string.*` 全可用 |
| 画球 | `ClientUIImageControl`：位置/尺寸/`imageColor` 读写 |
| 打字/分数 | `ClientUITextBoxControl.text` **读写** |
| 瞄准开火 | `game.GetCursorUIPos()` + `CursorEventArea` + 键盘枚举 |
| 消除动画 | `game.Tween` / `TweenSequence`（30 种缓动） |
| 容量 | 我们只用 45 个控件（上限 1000/组、10000/屏） |

## 已经验证到什么程度（**本工作区最有价值的一栏**）

| 层 | 状态 | 证据 |
|---|---|---|
| 数学内核（路径/珠串/匹配/爆炸/弹丸） | ✅ | `lua/src/` 8 个模块 |
| 规则层（装配/命中/并入/结算/生命/分数） | ✅ | `ribosome.lua` + `board.lua` |
| 与本体一致 | ✅ **零差异** | 12 局完整对局逐帧逐球，81339 个数值 |
| 关卡数据 | ✅ | 11 关从 `levels.js` 导出 + 自检 |
| 表现层 / 输入层 / 生命周期 | ✅ | `ui.lua` / `input.lua` / `game.lua` |
| **真机运行时契约** | ✅ | 4 条硬限制写进代码 + 假宿主强制 + 8 项契约断言（见下节） |
| 本地能跑一整关 | ✅ | 假宿主 **164 项断言**（含打包产物端到端） |
| 在客户端 Lua 运行时里真跑 | ✅ | 试玩台：114 个控件建出来、整关推进、可出图 |
| 打包产物可直接上传 | ✅ ~91 KB，14 模块 | `out/zuma.lua`（92,899 字节） |
| **编辑器里跑起来** | ❌ **没做过** | 见 `docs/05` §10 M2 |

**换句话说：代码侧已经写完并本地验证；剩下的是编辑器里的手工搭建 + 真机实测。**

移植过程中还**发现本体两处问题**（`baseRepeat` 悬空引用、`startWpFrac` 留下 28 秒空档），
本轮**没有改动 `src/`**，记录在 `docs/05` §11。

## 真机运行时契约（4 条硬限制，写进代码、也有断言守着）

这些是"看着对、真机第一帧就崩"的那一类。来源：`miliastra-beyond-simulator` 的真机探针结论
（`client/lua-runtime/docs/observed-contract.md`）+ 官方《客户端控件 API 文档》。

| # | 真机行为 | 原来错在哪 | 现在 |
|---|---|---|---|
| 1 | 控件 ID 字段是 **`Id`**（首字母大写）；小写 `id` 读出来是 nil | `ui.last[c.id]` → 真机 `table index is nil`，**第一帧就崩** | `ui.ctrlId()` 认 `Id`；假宿主的 `id` 已删掉 |
| 2 | `visible` / `active` / `alive` / `prefabIndex` 是**只读**字段，写报 `cannot set X, no such field` | `setField(c,'visible',…)` 直接赋值 | 改可见性一律走 `c:SetVisible()` |
| 3 | `InstantiateClientUIControl` 在 **OnInit 阶段返回 nil**，`OnStart` 才建得出来 | 原来在 OnInit 里建控件 → 一个都建不出来，连"报错的那行字"本身也是控件 → **白屏且无提示** | `OnInit` 只登记 + `EnableUpdate`；建控件全在 `OnStart`（`G.tryBoot`），`OnUpdate` 里还有兜底 |
| 4 | **`EnableUpdate` 前没有 `OnUpdate`** | 不打开就永远是死画面 | `OnInit` 里 `script:EnableUpdate(true)`，日志会记下成功与否 |

外加一条：`game` 的函数是**点号调用**（`game.GetUICanvasSize()`），写冒号会被当真机报
`bad argument count … (0 expected, got 1)`。

**为什么这些现在跑不掉**：假宿主 `lua/host/mock.lua` 已经按真机契约封死 ——
字段白名单（不在表里读 nil、写报错）、`Id` 大小写、只读字段、生命周期阶段、
`EnableUpdate` 开关、点号调用，全部照做。`test_mock.lua` / `test_diag.lua` / `test_bundle.lua`
里有 8 项契约断言。**这些断言存在的唯一理由，就是当初 `c.id` 这种错在本地一路绿灯、到真机才炸。**

## 本地试玩台（sim-play / sim-render）

```
node miliastra/tools/sim-play.mjs --level=6 --frames=260 --play           # 真跑一遍，看日志
node miliastra/tools/sim-play.mjs --level=1 --json=miliastra/out/sim-L1.json
node miliastra/tools/sim-render.mjs miliastra/out/sim-L1.json miliastra/out/sim-L1.png
```

它用的是社区的千星客户端运行时模拟器（`miliastra-beyond-simulator`，默认找
`D:/miliastra-beyond-simulator`，可用 `ZUMA_SIM` 覆盖；**没装就跳过**，退出码 0）。

- 它证明什么：控件真的建出来了、生命周期真的走通了、光标事件真的派发了、
  位置/尺寸/HUD 文案在**沙箱的控件树**里是对的（`sim-render` 出的图上能直接看）。
- ⚠ 它**不是真机证明**（契约 §14 的 `imageType`、下一条的整数位宽……模拟器与真机必然有差异）。
- ⚠ **已知假象：模拟器跑在 Fengari 上，整数是 32 位**（`0xFFFFFFFF == -1`），
  `rng.lua` 的 `& 0xFFFFFFFF` 收不回无符号数 → `step()` 取值域变成 `[-0.5, 0.5)`，
  `rng.pick` 约一半取到 nil → **碱基变 nil、球画成白色**。
  实测：20000 次 `step()` 有 10101 次越界、`rng.pick` 200 次有 105 次 nil。
  真机是 Lua 5.3（64 位整数）不会这样；对拍/本地测试用的是原生 64 位 Lua，所以是绿的。
  `sim-play.mjs` 会自己探一次整数位宽并**在输出里警告**，`sim-render` 把白球画成带 `?` 的空心圆。

## 路线对比（主 / 备）

| | 路线 A（**主**）Lua 2D | 路线 B（备）节点图 + 实体 |
|---|---|---|
| 渲染 | 客户端控件画布 | 场景实体 / 元件 |
| 逻辑 | Lua `OnUpdate(dt)` | 事件驱动节点图 + 33Hz 定时器 |
| 弧长模型 | **原样保留** | 必须离散化成槽位 |
| 路径点数 | 无限 | **最多 50 路点**（卡死 4 个核心关） |
| 每球一个实体 | 不需要 | 需要，且要配受击盒才能拿到"命中实体" |
| 单人 | ✅ 零同步 | ✅ |
| 联机 | ❌ 需另做同步 | ⚠️ 天然服务端权威 |
| 代码复用 | `../src/` 已证明可逐函数翻译 | 只能重写 |

**换路判别标准**：只有在"必须联机"或"必须用 3D 场景物体"时才切回路线 B ——
那两条是路线 A 的硬边界，其余困难都不是换路理由。

## 状态

- [x] 考证（`docs/01``02``03``04`）—— 主路线据此改定为 Lua
- [x] 数学内核 + 规则层移植，对拍零差异（81339 个数值 / 12 局对局）
- [x] 关卡数据导出 + 自检
- [x] 表现层 / 输入层 / 宿主胶水 + 假宿主 + **164 项 Lua 断言**
- [x] 真机运行时契约 4 条（`Id` / 只读字段 / OnStart 才能建控件 / EnableUpdate）+ 契约断言
- [x] 本地试玩台：在客户端 Lua 运行时里真跑 + 出图
- [x] 单文件打包 + **打包产物端到端**跑通一整关
- [x] 移植方案定稿（`docs/05`）
- [ ] **在编辑器里搭出来并实测**（M2，关键路径）
- [ ] 选关菜单 / 结算界面 / 模式按钮 / 音效

## 路线 A 下的真实约束（其余旧约束已作废）

1. **没有 I/O**：`io.*` 不可用、不能联网 → 素材必须在编辑器里手做。
2. **Lua 读不到任意实体**：只能读 关卡/玩家自身/角色自身 的全局自定义变量。
3. **动态创建控件有坑**：主屏控件、模板控件子节点都不能动态创建 → 池子建在**玩区容器**下，
   运行期只改属性、不新建/销毁。**且只能在 `OnStart` 及之后建**（`OnInit` 阶段返回 nil）。
4. **客户端脚本必须挂在客户端控件上**；只有**建过脚本映射**的 lua 才会被上传。
5. **联机信号延迟 ≥ 100ms** → 只做单人。
6. **字段与生命周期是"封死"的** —— 见上面「真机运行时契约」四条；
   写错字段名**不报错也不生效**（或当场崩），所以本地假宿主照真机封死。
7. **`/storage` 是 noexec**（手机端）→ 本地编译的 Lua 解释器要先拷到 `$TMPDIR` 才能跑。

## 下一步

1. **（关键路径）在编辑器里搭 M2**：4 个控件模板 + 脚本映射 + 脚本变量（见 `docs/05` §9）；
2. 实测帧率与坐标手感；若 `InstantiateClientUIControl` 不好用，改成"编辑期摆好球控件池"；
3. 补选关菜单与结算界面；
4. 把两条本体待办（`baseRepeat`、`startWpFrac`）拿回本体侧处理。

# 祖玛 · RNA（Zuma-RNA）

把《祖玛》的"同色三消"改写成"**序列翻译**"的双轨道玩法：出球道自动冒碱基（mRNA），玩家控制核糖体往三消道发射 tRNA 珠做互补配对，**连续配对段长度是 3 的倍数**才整体消除；配错不扣分，而是触发**可连锁的爆炸**。

完整设计见 `DESIGN.md`（术语、尺寸推导、遮挡层级、球的完整状态机、轨道设计体系、验收标准）。

---

## 怎么跑

**1）直接玩（单文件，零依赖）**

    node tools/build.mjs      # 把 src/ 内联成 zuma.html
    # 然后双击 / 用浏览器打开 zuma.html

产物是纯静态单文件，走 file:// 也能玩（安卓浏览器 file:// 会拦 ES module import，所以必须打包）。

**2）开发模式（改完刷新即见效）**

    python3 -m http.server 8080
    # 浏览器打开 http://127.0.0.1:8080/index.html

**3）自检**

    node tools/test-geometry.mjs   # 几何内核单元测试（36 项）
    node tools/smoke.mjs           # 无头自检台：mock DOM 跑 600 帧 + 切关 + 极端尺寸（17 项）
    node tools/preview.mjs 0 900 out.png            # 无头光栅预览（不用浏览器也能看图）
    node tools/preview.mjs 2 800 out.png 3.2 714 435  # 定点放大看遮挡

## 当前按键

| 键 | 作用 |
|---|---|
| 1 / 2 / 3 | 切换演示关（螺旋·出球道在外 / 螺旋·出球道在内 / 交叉演示） |
| D | 调试层（骨架法线、校验问题标记） |
| O | 原地交换内外圈 |

## 目录

    DESIGN.md              设计书（唯一规格来源）
    index.html             开发用页面（<script type="module">）
    zuma.html              构建产物（单文件，可分发）
    src/config.js          设计常量与尺寸派生（R / r = R/√2 / d / p）
    src/geometry.js        弧长参数化、双轨法线偏移、层级分段、轨道校验器
    src/spines.js          骨架原型（spiral / crossReturn）
    src/levels.js          关卡配方
    src/scene.js           装配：关卡 + 视口 -> 可渲染状态
    src/render.js          分层渲染（按 z 升序：先轨道带，后该层珠子）
    src/main.js            主循环 / 输入 / 调试钩子
    src/rng.js             确定性随机
    tools/build.mjs        极简打包器（ES模块 -> 单文件）
    tools/smoke.mjs        无头自检台
    tools/test-geometry.mjs 几何单元测试
    tools/preview.mjs      无头光栅预览器（自写 PNG 编码 + 光栅器）
    refs/shared-chat.json  原始点子的分享对话存档

## 进度

| 单元 | 状态 |
|---|---|
| 单元 | 状态 |
|---|---|
| U0 拆解与验收标准 | ✅ |
| 设计书 DESIGN.md（含 v0.2 绳子模型修正 + 优先级重排） | ✅ |
| 参考实现：读 alula/CircleShootApp 反编译源码并写 NOTES.md | ✅ |
| U1 工程骨架 + 无头自检台 + 单文件打包 | ✅ |
| U2 几何内核 + 轨道校验器 | ✅ |
| U4 层级与遮挡（分层绘制顺序，已在真实像素上验证） | ✅ |
| U3 珠串模型（绳子模型：喂入/推动传递/空隙/回缩） | ✅ |
| U5 渲染基线 | ✅ 够看就行（核糖体/瞄准线/双珠/弹丸都画了，不做美术） |
| U6 核糖体控制器 + 输入 + 珠袋 | ✅ 固定中心 / 旋转瞄准 / 双珠待命 / 空格与右键切换 |
| U7 发射与扫掠碰撞 | ✅ 胶囊扫掠防穿透 / 最近优先 / 存活期回收（穿隙加分仍冻结） |
| U8 互补配对 + 副轨吸附 | ✅ 真实碱基配对 / 命中分流 / 0.30s 吸附飞行（demoPairs 脚手架已删） |
| U9 阅读框 + 三联体消除（3→6→9→12→15 加码，A14） | ✅ 识别窗口 + 升档刷新 + 移码 + run 徽标 |
| U10 爆炸与连锁 | ⏸ **冻结**（用户要求延后） |
| U11 生命与计分（A15） | ✅ 队头撞洞 → 整条被吸走 + 扣 1 命 → 重开 / 命尽 GameOver |
| U12 特效与音效 | ⏸ 推迟 |
| U13 UI/UX 与触控 | ⏸ 只做必要部分 |
| U14 关卡包与调参 | ⏸ 低优先级 |

**v0.2 验收线（基本玩法闭环）**：能发射 → 能配对 → 连续配对段是 3 的倍数就消除 → 配错就爆炸 → 球进洞穴扣命 → 分数能涨。
这条线之外的（美术、音效、关卡包、教程）一律不阻塞。

## 自检现状

    11 个测试文件 / 546 项全部通过：
    node tools/test-geometry.mjs    # 38      node tools/test-chain.mjs   # 31
    node tools/test-shot.mjs        # 57      node tools/test-run.mjs     # 42
    node tools/test-life.mjs        # 58      node tools/test-insert.mjs  # 27
    node tools/test-mark.mjs        # 55      node tools/test-elem.mjs    # 80
    node tools/test-tutorial.mjs    # 72      node tools/smoke.mjs        # 82
    node tools/analyze-insert.mjs   # 4

    # 千星奇域移植的那一套（对拍 + 沙箱检查 + Lua 侧测试）一条命令：
    node miliastra/tools/run-all.mjs

    # 无头看图（本环境没有浏览器，靠它做视觉验收）
    node tools/preview.mjs 0 900 out.png frames=900
    node tools/preview.mjs 0 900 out.png frames=45 cut=8-10   # 切掉一段看空隙
    node tools/preview.mjs 0 900 play.png frames=1500 autofire  # 自动瞄准可配对球并开火（可玩性自检）

> 关键不变量 1：**清掉 k 颗球 = 队头恰好落后 k×touchDist**（单测断言到 1e-6）。这就是祖玛「清得越早越省时间」的量化形式。
>
> 关键不变量 2：**吸附完成后小球与大球的间距精确 == 轨距 d = 35.635029**；半径比恒为 √2:1。
>
> ⚠️ 已知验证盲区：`tools/preview.mjs` 是**独立实现的简化光栅器**，不调用 `src/render.js`，
> 所以游戏 UI（HUD、run 徽标、GameOver 横幅）**不会出现在预览图里**。改 UI 时不能只看预览图。

---

## 在这台手机上用 git

远程仓库：<https://github.com/ihamn/zuma>（SSH 走 `ssh.github.com:443`，密钥在 `~/.ssh/id_ed25519`，已配好）。

    source tools/gitenv.sh      # 必须先 source，见下
    git status

两个 Android 特有的坑，都写在 `tools/gitenv.sh` 的注释里：

1. `/storage` 是 **FUSE 挂载，不支持硬链接**（`ln` 直接 Permission denied），
   而 git 建对象库要用它 -> 所以用 `--separate-git-dir` 把**对象库放到 $TMPDIR**，
   工作区仍留在 /storage（你的文件在这）。`.git` 只是一个指向 `$TMPDIR/zuma-git` 的文本文件。
2. `git add` / `git push` 需要 **hardlink 权限**，在默认沙箱模式下会被拒 —— 这两个命令要提权跑。
   只读操作（status / log / diff）不需要。

## 千星奇域移植（miliastra/）

本作正在往**原神千星奇域**移植，工作区在 `miliastra/`。路线是**客户端 Lua 脚本**
（官方原话：「客户端脚本可以实现绝大多数 2D 玩法」），所以整个游戏逻辑被翻译成了 Lua，
再用客户端控件当画面。

已经做到：

- 数学内核 + 规则层**逐值对拍**通过：308 条命令 / 5702 行 / **81339 个数值零差异**（含 12 局完整对局）
- 表现层 / 输入层 / 脚本生命周期写完，**假宿主无头测试 133 项**通过（含打包产物端到端）
- 一条命令产出上传用的单文件：`node miliastra/tools/bundle-lua.mjs` → `miliastra/out/zuma.lua`

**要在电脑上的千星沙箱里把它跑起来，看这份手册：**
[`miliastra/pc/操作手册.html`](miliastra/pc/操作手册.html)（浏览器直接打开）。
移植的现状与施工图见 [`miliastra/README.md`](miliastra/README.md) 与
[`miliastra/docs/05-移植方案.md`](miliastra/docs/05-移植方案.md)。

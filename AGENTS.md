# AGENTS.md — zuma 项目的常驻说明

> 每个在这个工作区开的会话都会自动读到这一份。**规矩写在这里，理由写在链接的那一头。**

## 这是什么

RNA 主题的祖玛（双轨道：出球道冒碱基、三消道发珠配对、连续 3 的倍数才消除、配错会爆炸）。
两个产物：**网页版本体**（`src/` + `tools/`）和**千星奇域移植**（`miliastra/`，Lua 客户端脚本）。
唯一规格是 `DESIGN.md`（约 4200 行，带 § 编号）；改玩法先改它。

## 接手先读三份（按顺序）

1. `HANDOFF.md` —— 项目怎么走到今天的、每步做了什么、现在卡在哪、下一步干什么
2. `miliastra/README.md` —— 移植现状：做到哪、怎么验、还剩什么
3. `miliastra/docs/05-移植方案.md` —— 施工图（编辑器里怎么搭）

## 开始干活前

    node miliastra/tools/run-all.mjs        # 导出 + 沙箱检查 + 打包 + 对拍 + Lua 测试，退出码即结果
    node tools/test-*.mjs ; node tools/smoke.mjs   # 本体回归（11 个文件 / 546 项）

## 硬规则（都是踩过坑换来的）

1. **移植期间不要改 `src/`。** 本体的 546 项测试是"对拍"的基准，动它就等于失去参照物。
   发现本体有问题 → 写进 `HANDOFF.md` §5，交给本体侧决定。
2. **Lua 侧的任何结论都要有对拍证据。** `node miliastra/tools/parity.mjs` 必须零差异。
   这类移植最容易"看着对、其实错，而且不报错"；肉眼看和"跑起来没崩"都不算证据。
3. **平台硬限制写在代码里，不写在文档里。** 写在文档里没人查；写在代码里导出时就报错。
   见 `miliastra/tools/lib/platform-limits.mjs` 与 `check-lua-sandbox.mjs`。
4. **千星奇域的 Lua 不许用** `io.*` / `coroutine.*` / `string.dump` / 大部分 `os.*` `debug.*`
   （`print`/`printerr` 是官方日志 API，**可以**用）。`check-lua-sandbox.mjs` 会拦。
5. **不要凭记忆编千星奇域的 API。** 官方 219 篇文档在 `miliastra/docs/official/md/`，
   查它：`python3 miliastra/tools/doc-section.py <docId> <章节>` 或 `ctx-grep.py`。
   引用代码位置时给文件 + 函数名，不要给记忆里的行号。
6. **导出物必须能验证**（往返校验 / 对拍 / 自检），**产物不要手改**（`miliastra/out/`、`levels_data.lua` 都是生成的）。

## 手机端特有（在这台设备上开工才需要注意）

- `/storage` 是 **FUSE**：**不支持硬链接** → `git` 的对象库要放 `$TMPDIR`，用 `source tools/gitenv.sh`
- `/storage` 是 **noexec**：本地编译出来的可执行文件要先拷到 `$TMPDIR` 才能跑（`tools/lib/lua-runner.mjs` 已自动处理）
- `git add` / `git push` 需要提权（要写对象库的硬链接），只读命令不需要
- 远程仓库 `git@github.com:ihamn/zuma.git`，密钥在 `~/.ssh/id_ed25519`（已配好）

## 现在在哪

代码全写完，**本地验证全绿**（对拍 81339 个数值零差异 / Lua 侧 133 项断言 / 本体 546 项）。
卡在"搬到千星沙箱编辑器里"：**云电脑不让访问游戏本地目录**，脚本映射建不起来。
下一步的四条试法在 `HANDOFF.md` §6。

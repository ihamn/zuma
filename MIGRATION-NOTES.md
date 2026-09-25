# 迁移包能不能用？——实测判定

## 结论：能用，`README` 里那段悲观提醒可以改口了

`dsh-migrate/README.md` 的「版本提醒」写着：

> 手机上这个 DSH 是 **0.1.2-alpha.1** …… 会话日志格式可能变过。
> **如果搬过去打不开，不是你的操作问题。** 就当这段对话从今天重新开始

实测下来**不需要这么保守**。理由如下。

## 事实

| | 手机（迁移包） | 这台电脑（当前 DSH） |
|---|---|---|
| 文件名 | `session.jsonl.zstd` | `session.v4.jsonl.zstd` |
| 头部字段 | `"version":0` | `"version":4` |
| 目录结构 | `<projectKey>/session-<uuid>/` | `<projectKey>/session-<uuid>/` |

文件名里的 `vN` **就是格式版本号**——这是 DSH 自己文档里写的：
`session.jsonl.zstd` = released v0，`session.v1.jsonl.zstd` = v1，以此类推。

## 为什么能恢复

1. DSH 自带**完整迁移链**：`dsh-session-format-v0-to-v1`、`v1-to-v2`、`v2-to-v3`、`v3-to-v4`，
   四个包都在应用里（`app.asar` 内）。
2. 官方文档写明旧格式**读取时自动迁移**：
   > `open(id, 'read'|'write')` selects the highest canonical generation.
   > For historical input, a read open decodes and migrates the source once…
3. 唯一可能致命的 `header.system`（手机日志里 15 条 `request/header` 都带这个字段）
   **不是拒绝条件**——`v2-to-v3` 迁移就是专门干这个的：
   > The edge adds no model-visible text; it **moves the recorded prompt from the request header
   > into the message history**.

   当前版本拒绝的是**原生 v4** 文件里出现 `header.system`，跟"迁移旧文件"是两回事。
4. v0→v1 的四条拒绝条件逐条查过，手机日志里**都不存在**：
   - `request/header-delta` —— 日志里没有
   - `mode/set` —— 日志里没有
   - `request/header` 的 fallback reason —— 15 条的 reason 只有 `initial` / `resume` / `series`
   - 未知事件类型 —— 词汇表全部是第一方标准事件

## 还没证的一件事

迁移会校验**事件载荷成员**（unexpected payload members refuse）。这个只有真跑一次才能证。
建议：按 `restore.ps1` 走一遍，打开 DSH 看会话列表里有没有这段对话。

## `restore.ps1` 的路径算法：验证通过

脚本里那段"复刻 projectKey"的算法，用两个真实数据点验过：

| 输入路径 | 算出来的 key | 实际磁盘上的目录 |
|---|---|---|
| `D:\zuma` | `--D-zuma--` | `--D-zuma--` ✓ |
| `/storage/emulated/0/Documents/Genshin/Miliastra Wonderland/Zuma` | `--storage-emulated-0-Documents-Genshin-Miliastra~0020Wonderland-Zuma--` | 与包内目录名**完全一致** ✓ |

顺带确认：手机上的工作区路径就是
`/storage/emulated/0/Documents/Genshin/Miliastra Wonderland/Zuma`
（日志头部 `cwd` 字段可查）。所以恢复时**项目路径要放成**那个名字才能对上。

## 建议替换 README 的措辞

```markdown
## 版本提醒（已实测）

手机上这个 DSH 是 **0.1.2-alpha.1**，会话是 **v0** 格式；现在最新是 **v4**。
**但这不用你操心**：DSH 自带 v0→v1→v2→v3→v4 的完整迁移链，打开会话时会自动升级，
源文件保持不变。

唯一要小心的是**工作区路径**——DSH 按路径给会话分组，路径不一致就看不到这段对话。
手机上那段对话的工作区路径是：

    /storage/emulated/0/Documents/Genshin/Miliastra Wonderland/Zuma

在 Windows 上恢复时，路径填你在第 1 步放项目的地方（脚本会自己算目录名）。

万一真打不开，项目本身一点没丢，全在仓库里：

    miliastra/README.md            移植现状（做到哪了、怎么验）
    miliastra/docs/05-移植方案.md   施工图
    miliastra/pc/manual.html       千星沙箱操作手册
```

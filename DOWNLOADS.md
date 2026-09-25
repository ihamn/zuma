# 下载卡（实测核对版）

> 本文件里每个字节数、每个 sha256 都是**实际下载后算出来的**，不是抄的。
> 两个镜像分别下载，逐字节比对。核对方法见文件末尾。
>
> ★ 2026-09-25 重打包：之前发出去的 `zuma.lua` 是**会崩的旧版**（真机第一帧
> `table index is nil`：控件 ID 字段真机是 `Id` 大写、`visible` 是只读字段，
> 详见 `HANDOFF.md` §10）。下表是**修复版**的数字，旧文件请删掉重下。

## 一个总入口（什么都在这儿）

```
https://github.com/ihamn/zuma
```
点进目录 → 点文件 → 右上角 **Download raw file**。GitHub 慢的话用下面的直链。

## 直链（在电脑浏览器里粘这一行就下）

**① 游戏要用的包** — 79,496 字节
```
https://ghproxy.net/https://raw.githubusercontent.com/ihamn/zuma/main/miliastra/pc/zuma-pc.zip
```
里面有 4 个文件：`zuma.lua`（184,786）、`hello.lua`（5,141）、`manual.html`（28,870）、`README.txt`（837）

**② DSH 迁移包** — 18,714,097 字节（17.8 MB）
```
https://ghproxy.net/https://raw.githubusercontent.com/ihamn/zuma/main/dsh-migrate/dsh-session.zip
```
里面有 8 个条目：5 个会话日志 + `settings.yaml`（2,149）+ `README.md`（4,179）+ `restore.ps1`（2,960）

**③ 只要单个文件**
```
https://ghproxy.net/https://raw.githubusercontent.com/ihamn/zuma/main/miliastra/out/zuma.lua
https://ghproxy.net/https://raw.githubusercontent.com/ihamn/zuma/main/miliastra/pc/hello.lua
https://ghproxy.net/https://raw.githubusercontent.com/ihamn/zuma/main/dsh-migrate/restore.ps1
```

**④ DSH 本体**（不在仓库里，走官方）
```
https://download.deepseek.com/
```

## 下不动就换镜像

把开头这段换掉就行，后面路径完全一样：

```
https://ghproxy.net/https://raw.githubusercontent.com/ihamn/zuma/main/
                    ↓ 换成 ↓
https://cdn.jsdelivr.net/gh/ihamn/zuma@main/
```

例：`https://cdn.jsdelivr.net/gh/ihamn/zuma@main/miliastra/pc/zuma-pc.zip`

> 实测：两个镜像**都能下**，包括 17.8 MB 的 ②。
> 速度上 ghproxy 明显快（②那条 31 秒 vs 61 秒），优先用 ghproxy。

## 下完核对（30 秒，能省掉一半的坑）

| 文件 | 字节数 | 属性里显示约 | sha256 |
|---|---|---|---|
| `zuma-pc.zip` | 79,496 | 77.6 KB | `6d92d94ab85a298780722536860c92e428fe930ce11ab4126ecbe0b16664d60d` |
| `dsh-session.zip` | 18,714,097 | 17.8 MB | `233ccbc40484ac58d891ed1798ef2a354c249fb7332e983eab3f9b850f1c51a8` |
| `zuma.lua` | 183,314 | 179 KB | `d1bf0c893876344867a67096fc39b66c24b8da51c4193a3f43d5d9d046dd0913` |
| `hello.lua` | 5,141 | 5.02 KB | `3d6f67feaf7298c94ac7511f82776bf94fbe81510ef9288f521c8010b32dc9e8` |
| `manual.html` | 28,870 | 28.2 KB | `83596bd376348f64341cc7bc537086d67ecbadf279e4e8b660c963afd9a0a076` |
| `README.txt` | 837 | 0.82 KB | `18154af54fc0e0322f12f1339a5c92cd5e769adbad6cde544514567d137e7399` |
| `restore.ps1` | 2,960 | 2.89 KB | `cf6875c5e7ed33b71ff2a022ef6e4b715ddb802adf7fcc359bd2dc6a7d0b6984` |

> `zuma.lua` 的 sha256 也会写在 `pc/README.txt` 里 —— 包里那份自报的哈希对不上，
> 就说明文件在下的时候坏了。

**对不上就是没下完**，重新下一次。半截的文件不会报错，只会"跑起来怪怪的"。

字节数只能抓"下了一半"。想抓"大小一样但内容坏了"，用 sha256：

```powershell
Get-FileHash .\zuma.lua -Algorithm SHA256
# 或者整包一起看
Get-ChildItem *.zip,*.lua | Get-FileHash -Algorithm SHA256
```

## 两个坑，先说在前面

1. **浏览器可能直接"打开"zip，不下载** → 对着链接**右键 → 另存为**
2. ⚠ **`.lua` / `.ps1` 可能被浏览器当成文本显示出来。千万别在网页里全选复制！**
   89 KB 手抄一定会漏，而且漏了**不会报错** —— 只会"玩起来不对劲"。
   **一律右键 → 另存为**，要的是文件，不是文本。

---

## 实测记录（怎么核的）

- **2026-09-25 重打包后重核**：`miliastra/pc/zuma-pc.zip` 里 4 个条目逐个算 sha256，
  与上面表格**完全一致**（`zuma.lua` 92,899 / `manual.html` 17,110 / `hello.lua` 5,141 / `README.txt` 836）。
  并且**连跑两次 `pack-pc.mjs`，zip 的哈希一模一样**（固定时间戳，产物字节稳定）。
- 早先那轮（修复版之前）用 `Invoke-WebRequest` 从 ghproxy 和 jsDelivr **各下一份**比过字节数与
  sha256：7 个文件全部逐字节一致。② 18.7 MB 那条两个镜像都实测能下（ghproxy 31 秒 / jsDelivr 61 秒）。
- 该 zip 的未压缩总量是 18,708,287 字节，**比 zip 本身还小**——
  说明包里的 `.zstd` 会话日志已压缩过，zip 几乎没再压缩，别指望它能变小。

> ⚠ 尺寸预警：jsDelivr 对单文件有约 20 MB 的上限，②现在 17.8 MB。
> 往里**再加一个中等大小的会话就会越线**，那时 jsDelivr 那条会失效、只剩 ghproxy。
> 真要长期分发，②建议拆包或改用 GitHub Release 附件。

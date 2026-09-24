# DSH 迁移包 —— 把手机上的对话搬到这台电脑

## 包里有什么

    sessions/...     手机上的会话记录（我们这段对话 + 3 个子代理会话）
    settings.yaml    手机上的 DSH 设置
    restore.ps1      一键恢复脚本（内容和本文件第 3 步里那段一样）

⚠ 里面**故意没有** API 密钥 —— 仓库是公开的，密钥放进去等于公开。见文末「密钥怎么办」。

---

## 一共 4 步

### 第 0 步 · 先把 DSH 装好并打开一次

见文末「DSH 怎么装」。先装好、打开过一次，确保它能正常运行。

### 第 1 步 · 把项目放到电脑上

放哪儿都行，例如：

    C:\Users\你\zuma

两种拿法，挑一个：

    git clone https://github.com/ihamn/zuma.git zuma

或者：在 GitHub 页面上点 Code → Download ZIP，解压到 C:\Users\你\zuma

**记住这个路径**，第 3 步要用，而且必须**一模一样**。

### 第 2 步 · 打开 PowerShell

开始菜单搜「PowerShell」，打开（**不用**管理员）。

### 第 3 步 · 把 restore.ps1 的全部内容粘进去，回车

它会问你项目路径 —— 把第 1 步那个路径粘进去，回车。

看到绿色的「===== 完成 =====」就成了。

### 第 4 步 · 打开 DeepSeek Harness

工作区选**第 1 步那个路径**。会话列表里应该能看到我们这段对话。

---

## 脚本到底干了什么（出错了你能看懂）

1. 算出 DSH 要求的**会话目录名**。规则：把工作区路径里的斜杠和冒号变成一个减号，
   其他特殊字符（空格、中文）变成 波浪号 + 4 位十六进制。
   例：C:\Users\Abc\zuma 变成 --C-Users-Abc-zuma--
2. 把包里的会话文件夹**改名**成上一步算出来的名字，放进 %USERPROFILE%\.dsh\sessions\
3. 把 settings.yaml 放进 %USERPROFILE%\.dsh\

**为什么非改名不可**：DSH 是按「工作区路径」给会话分组的。名字对不上，那个工作区里就看不到这段对话。

---

## 密钥怎么办（不进仓库）

包里没有密钥。两个办法挑一个：

1. **最省事**：在这台电脑的 DSH 里重新登录，或直接把 API Key 填进设置页。
2. 手机上的密钥在 ~/.dsh/.credentials.yaml（371 字节）。

---

## 出问题怎么办

| 现象 | 原因 | 怎么办 |
|---|---|---|
| 「无法加载文件 restore.ps1，因为在此系统上禁止运行脚本」 | 执行策略 | **别双击运行 .ps1**，直接把内容粘进 PowerShell 窗口 |
| 找不到 dsh-session.zip | 下载到了别处 | 放到「桌面」或「下载」文件夹，脚本会自动找 |
| 「这个路径不存在」 | 第 1 步还没做，或路径打错 | 先放好项目，路径要一模一样 |
| 打开 DSH 看不到这段对话 | 工作区路径和填的不一样 | 重跑脚本，路径必须和 DSH 里选的工作区完全一致 |
| DSH 报会话格式错误 / 打不开 | 版本差太多 | 见下 |

---

## 版本提醒

手机上这个 DSH 是 **0.1.2-alpha.1**，今天官方最新是 **0.1.7-rc.2**。会话日志格式可能变过。

**如果搬过去打不开，不是你的操作问题。** 就当这段对话从今天重新开始 —— 项目本身一点没丢，全在仓库里：

    miliastra/README.md            移植现状（做到哪了、怎么验）
    miliastra/docs/05-移植方案.md   施工图
    miliastra/pc/manual.html       千星沙箱操作手册

---

## DSH 怎么装（Windows）

官方安装包**不在 GitHub Releases 里**（查过，最近 5 个 release 全是 0 个附件）。

官方分发域名是 **download.deepseek.com** —— 这是从官方源码
apps/desktop/scripts/installed-update-cos.ts 里读出来的（那里写死了 ORIGIN）。

    https://download.deepseek.com/

用浏览器打开它，找 Windows 版下载。

找不到桌面端入口的话，用源码装：

    装 Node.js
    git clone https://github.com/deepseek-ai/deepseek-harness.git
    pnpm install
    pnpm run build
    pnpm dsh web

⚠ 网上搜到的「Windows 一键安装包」（dsh_desktop / actdsh / deepseek-harness-desktop 等）
**都是社区版不是官方**。装之前先确认来源。

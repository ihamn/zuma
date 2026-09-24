# 临时远程访问：在学校电脑上打开游戏 / 连 DSH

> 场景：DSH 和游戏跑在**手机**的 Termux 里，人在**学校机房电脑**上想用。
> 核心风险：**游戏页是静态页，暴露无害；DSH 控制台暴露 = 把"能在你手机上执行任意命令的 agent"交给任何拿到链接的人。**

---

## 决策树（按"最省事 -> 最可靠"）

### ① 手机和机房电脑同一个 WiFi？先试直连（0 安装）

    bash tools/share.sh lan

它会把地址算出来。然后：
- 游戏页：`http://<手机IP>:8080/zuma.html` —— **已绑 0.0.0.0，局域网直接可达**（实测 `http://10.13.242.3:8080/zuma.html` 返回 200）
- DSH：**默认不行**，DSH 只监听 127.0.0.1。若要在局域网访问，需要在**你自己的 Termux 里**另开一个裸转发（见 `tools/forward-3080.sh`）

**最常见的失败原因**：机房 WiFi 开了客户端隔离（AP isolation）-> 电脑根本连不到手机，只能走隧道。

### ② serveo 反向隧道（**已实测可用**，零安装）

    bash tools/share.sh game      # 游戏页 -> 公网（无害）
    bash tools/share.sh dsh       # DSH 控制台 -> 公网（危险，会先警告 3 秒）

终端会打印：

    Forwarding HTTP traffic from https://xxxxxxxx.serveousercontent.com

**实测**：公网访问 `/zuma.html` 返回 **HTTP 200 / 64902 bytes / 标题正确**。

三个坑：
1. **免费版会给访客弹提示页**，点一下才进（Pro 才去掉）。
2. **自定义子域名要先登录 console.serveo.net 注册 SSH 公钥**，否则只有一长串随机地址。
3. **WebSocket/SSE 兼容性未验证** —— DSH 控制台的实时流可能不通，DSH 建议用 ③。

### ③ cloudflared 快速隧道（DSH 最可靠，需装一次）

**我这边装不了**：workspace 挂载是 `noexec`（二进制不能执行），`$HOME` 我的沙箱不可写。
**但你自己在 Termux 里可以**：

    pkg install cloudflared        # 先试 Termux 源
    # 或者手动下 aarch64 二进制（手机就是 aarch64）：
    cd ~ && curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
    chmod +x cloudflared

然后：

    ~/cloudflared tunnel --url http://127.0.0.1:8080     # 游戏
    ~/cloudflared tunnel --url http://127.0.0.1:3080     # DSH

打印 `https://xxxx.trycloudflare.com`。**无提示页**、WebSocket 支持好，比 serveo 稳。

---

## 安全要点

| 暴露 | 风险 | 建议 |
|---|---|---|
| 8080 游戏页 | 无（静态） | 随便开 |
| 3080 DSH 控制台 | **任何拿到链接的人都能让 agent 在手机上执行命令** | 只在课上开，下课立刻 Ctrl-C；能不开就不开 |

隧道地址会经浏览器历史、Referer、代理日志泄漏。**DSH 要开就当"一次性、用完即关"。**


---

## ★ 前提变了：**手机不能带到学校**

手机留守在家，人在机房。这带来三个新问题，**但其中两个只影响 DSH，不影响游戏**：

| 问题 | 影响谁 | 说明 |
|---|---|---|
| URL 必须提前知道且不变 | 两者 | 你在学校看不到手机屏幕，随机地址记不下来 |
| 保活（手机待机一整天） | 两者 | Termux 被 Doze 杀 / WiFi 休眠 = 全没了 |
| 风险升级 | **只有 DSH** | 暴露**一整天**；机房电脑常有行为管理软件记录 URL 与流量 |

### 最优解：**游戏根本不走手机 —— 出门前做静态托管**

`zuma.html` 是**零依赖单文件**，天生适合静态托管：

    # 方式 A：surge.sh（最快，手机上 30 秒搞定；首次会让你填邮箱注册）
    npx surge . --domain 你的名字.surge.sh
    # -> 永久地址 https://你的名字.surge.sh/zuma.html

    # 方式 B：GitHub Pages（更持久）
    #   建仓库 -> 上传 zuma.html -> Settings > Pages -> 得到 https://<用户名>.github.io/<仓库>/zuma.html

**好处**：永久 URL、不用手机开机、零安全风险、机房电脑直接打开、断网重连也不变。
**代价**：改代码后要重新上传（但托管一次能撑一整天）。

### DSH 只能留在手机 -> 用 `tools/park.sh`

    bash tools/park.sh      # 出门前跑一次：build + 唤醒锁 + 起服务 + 起隧道 + 把地址写进 PARKED.txt
    bash tools/unpark.sh    # 回家收工

`park.sh` 会把公网地址写进 `PARKED.txt`（方便你拍照），并且：
- 用 `nohup` 让隧道脱离终端（Ctrl-C 不会断它）
- 尝试 `termux-wake-lock`
- 用 `ServerAliveInterval` 保持 SSH 隧道不断

**必须配合的三个手机设置**（脚本管不了）：
1. **插上充电器** —— Doze 在充电时宽松得多
2. 设置 > 应用 > Termux > 电池 > **无限制**（关掉电池优化）
3. 设置 > WLAN > 高级 > **休眠时保持连接**；最近任务里**锁定 Termux** 别被清后台

### 风险提醒（DSH）

- `park.sh` **默认不暴露 DSH**，只暴露游戏页 ✓ 这是有意的
- 要暴露 DSH 得自己另跑 `bash tools/share.sh dsh` —— 那意味着**一整天**任何人都能用这个 URL 让 agent 在你手机上执行命令
- 机房电脑大概率有**行为管理/还原卡**，你打开的 URL 会被记录


---

## 口令网关（`tools/gate.mjs`）—— 给公网入口加一道密码

    # 1) 起网关（一个窗口；先跑着别关）
    node tools/gate.mjs --target 3080 --port 3090 --password ihamn
    #    --target 3080 = 保护 DSH 控制台；换成 8080 就是保护游戏页

    # 2) 另开一个窗口，把隧道指向网关的端口
    bash tools/share.sh gate

    # 3) 公网地址 + 口令 -> 先出登录页，输对口令才进

### 实测（公网全链路，2026-09-19）

    ① 公网 无口令      -> HTTP 401
    ② 公网 错口令      -> HTTP 401
    ③ 公网 正确口令    -> 302 + Set-Cookie -> HTTP 200 / 64902B（游戏页完整透传）
    本地 带假 Cookie   -> HTTP 401

### 它做了什么

- 口令正确后发一个**随机 Cookie**（口令本身不进 Cookie）
- 支持**流式响应（SSE）**和 **WebSocket 升级**（DSH 控制台的实时流要用；普通静态代理会在这里挂掉）
- 转发时把 `Host` 改写成 `127.0.0.1:<target>`

### 局限（必须知道）

1. **"ihamn" 是弱口令** —— 5 个小写字母，暴力枚举空间只有约 1.2e7。它是一道**路障**，不是认证。
   隧道是 HTTPS，所以口令不会明文上网；但如果有人盯上这个 URL，枚举是可行的。**建议换成更长的，或只开短时间。**
2. 它只保护**入口**。URL 本身泄漏了（机房行为管理记录），别人一样会看到登录页 —— 只是进不去。
3. 网关进程被杀，隧道就变成 502（不会裸奔，但也不可用）。


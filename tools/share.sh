#!/data/data/com.termux/files/usr/bin/bash
# 临时把本机服务暴露出去（局域网 / 公网），Ctrl-C 结束。
#
#   bash tools/share.sh lan             # 打印局域网地址（手机和电脑连同一个 WiFi 时用）
#   bash tools/share.sh game [子域名]   # serveo 隧道 -> 公网，游戏页 8080（无口令）
#   bash tools/share.sh gate [子域名]   # serveo 隧道 -> 公网，口令网关 3090（推荐）
#   bash tools/share.sh dsh  [子域名]   # serveo 隧道 -> 公网，DSH 3080（危险！）
#
# 注意：
#  1) serveo 免费版会给访客显示一个"提示页"，点一下才能进。想免掉它用 cloudflared（见 README）。
#  2) serveo 自定义子域名需要先用 GitHub/Google 登录 console.serveo.net 注册 SSH 公钥；
#     没注册就只能拿到一长串随机地址（一样能用）。
#  3) 暴露 DSH = 任何拿到链接的人都能让 agent 在这台手机上执行命令。只在必须时开。
set -u

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes"

lan_ip() {
  { ip -4 addr show 2>/dev/null || ifconfig 2>/dev/null || ip addr 2>/dev/null; } \
    | awk '/inet /{split($2,a,"/"); print a[1]}' | grep -v '^127[.]' | head -1
}

CMD="${1:-}"; SUB="${2:-}"

case "$CMD" in
  lan)
    IP="$(lan_ip)"
    echo "局域网地址（手机和电脑必须连同一个 WiFi，且该 WiFi 没开客户端隔离）："
    echo "    游戏页      http://${IP:-<手机IP>}:8080/zuma.html"
    echo "    DSH 控制台  http://${IP:-<手机IP>}:3080/   （需 DSH 监听 0.0.0.0，见 README）"
    echo
    echo "手机当前地址：${IP:-未找到私有网段地址（可能在用移动数据）}"
    exit 0
    ;;
  game) PORT=8080; LABEL="游戏页（无口令）";;
  gate) PORT=3090; LABEL="口令网关（推荐）";;
  dsh)  PORT=3080; LABEL="DSH 控制台（裸暴露，危险）";;
  *)
    sed -n '2,14p' "$0"; exit 1;;
esac

if [ "$CMD" = "gate" ]; then
  if ! curl -s -o /dev/null -m 3 http://127.0.0.1:3090/ ; then
    echo "[share] 提示：3090 上没有服务。请先另开一个窗口跑："
    echo "        node tools/gate.mjs --target 3080 --port 3090 --password ihamn"
    exit 1
  fi
fi

if [ "$CMD" = "dsh" ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!! 正在把 DSH 控制台暴露到公网。"
  echo "!! 任何拿到链接的人都能让 agent 在这台手机上执行命令。"
  echo "!! 用完立刻 Ctrl-C。"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  sleep 3
fi

echo "[share] 本地 $LABEL -> 127.0.0.1:$PORT"
echo "[share] 连接 serveo.net 中……下面会打印公网地址："
if [ -n "$SUB" ]; then
  exec ssh $SSH_OPTS -R "$SUB:80:localhost:$PORT" serveo.net
else
  exec ssh $SSH_OPTS -R "80:localhost:$PORT" serveo.net
fi


#!/data/data/com.termux/files/usr/bin/bash
# 出门前跑一次：把"手机留守"状态布置好，并把信息写到 PARKED.txt
#   bash tools/park.sh
# Ctrl-C 不会停掉隧道（用 nohup 脱离终端）。收工回家后：bash tools/unpark.sh
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
OUT="$DIR/PARKED.txt"
LOG="$DIR/.tunnel.log"

echo "=== park $(date) ===" | tee "$OUT"

# 1) 重新构建单文件
node tools/build.mjs 2>&1 | tee -a "$OUT" >/dev/null

# 2) 唤醒锁：防 Android Doze 把 Termux 冻住
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock && echo "wake-lock: 已获取" | tee -a "$OUT"
else
  echo "wake-lock: 命令不存在 -> 手动去 设置>应用>Termux>电池 关掉优化" | tee -a "$OUT"
fi

# 3) 本机游戏服务（0.0.0.0，局域网也能用）
pkill -f "http.server 8080" 2>/dev/null
nohup python3 -m http.server 8080 --bind 0.0.0.0 >/dev/null 2>&1 &
echo "游戏服务: http://127.0.0.1:8080/zuma.html" | tee -a "$OUT"

# 4) 公网隧道（游戏页）
pkill -f "localhost:8080 serveo.net" 2>/dev/null
: > "$LOG"
nohup ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
      -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
      -R "80:localhost:8080" serveo.net >>"$LOG" 2>&1 &
sleep 10

URL="$(grep -o 'https://[A-Za-z0-9.-]*\.serveousercontent\.com' "$LOG" | head -1)"
if [ -n "$URL" ]; then
  { echo; echo "★ 游戏公网地址（抄下来 / 拍下来）："; echo "   $URL/zuma.html"; } | tee -a "$OUT"
else
  { echo; echo "!! 隧道没起成功，日志尾部："; tail -5 "$LOG"; } | tee -a "$OUT"
fi

{
  echo
  echo "提醒："
  echo " 1) 手机插上充电器；设置里把 WLAN 的"休眠时保持连接"打开"
  echo " 2) 别让 Termux 被清后台（最近任务里锁定它）"
  echo " 3) DSH 控制台默认没暴露 —— 要暴露请自行 bash tools/share.sh dsh，风险自负"
  echo " 4) 回家后跑 bash tools/unpark.sh 收工"
} | tee -a "$OUT"


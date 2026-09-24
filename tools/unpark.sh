#!/data/data/com.termux/files/usr/bin/bash
# 收工：停掉隧道和游戏服务、释放唤醒锁
set -u
pkill -f "localhost:8080 serveo.net" 2>/dev/null && echo "隧道已停"
pkill -f "http.server 8080" 2>/dev/null && echo "游戏服务已停"
if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock && echo "wake-lock 已释放"; fi
rm -f "$(cd "$(dirname "$0")/.." && pwd)/.tunnel.log"
echo "收工完成"


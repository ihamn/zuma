#!/data/data/com.termux/files/usr/bin/bash
# 构建 Lua 5.3 参考解释器（与千星奇域的 Lua 5.3 对齐），产物放 vendor/bin/lua。
#
# 为什么要本地解释器：Lua 侧的移植必须能**离线验证**，不能靠"上传到游戏里试"。
# 详见 tools/lib/lua-runner.mjs 顶部的环境说明（/storage 是 noexec）。
set -e
cd "$(dirname "$0")/.."
VER=5.3.6
mkdir -p vendor/bin
if [ ! -f vendor/lua-$VER.tar.gz ]; then
  echo "下载 lua-$VER.tar.gz ..."
  curl -sSL --max-time 180 -o vendor/lua-$VER.tar.gz https://www.lua.org/ftp/lua-$VER.tar.gz
fi
if [ ! -d vendor/lua-$VER ]; then
  echo "解包 ..."
  tar xzf vendor/lua-$VER.tar.gz -C vendor
fi
echo "编译 ..."
make -C vendor/lua-$VER posix -j4 >/dev/null
cp vendor/lua-$VER/src/lua vendor/bin/lua
chmod 755 vendor/bin/lua
echo "OK: vendor/bin/lua"

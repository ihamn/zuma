# 本机 git 环境（source 一下再用）。
#
# ★ 为什么需要这个文件：Android 的 /storage 是 **FUSE** 挂载，**不支持硬链接**
#   （实测 ln 直接 Permission denied），而 git 建对象库要用到它 ——
#   在 /storage 里 git init 会报 "insufficient permission for adding an object"。
#   所以：**工作区留在 /storage（你的文件在这），对象库放到 $TMPDIR（真文件系统）**，
#   用 --separate-git-dir 拆开。
#
# 用法：
#   source tools/gitenv.sh
#   git status
#
# ⚠ $TMPDIR 被系统清掉的话，仓库历史会丢（文件还在）。真正的备份是 GitHub 上的那份。

export GIT_DIR_ALT="${TMPDIR:-/tmp}/zuma-git"
export GIT_CONFIG_GLOBAL="$GIT_DIR_ALT/local.gitconfig"
export GIT_CONFIG_NOSYSTEM=1

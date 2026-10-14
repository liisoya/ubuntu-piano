#!/usr/bin/env bash
# 公共环境：Ubuntu 版本 ↔ suite 代号映射 + 日志工具
# 被 host/ 与 in-chroot/ 下的脚本共同 source。
#
# 说明：Ubuntu 的 suite 代号必须与 ubuntu-base tarball、apt 源一致，
# 这里集中维护，避免散落在 workflow YAML 里（上游正是把套件名直接写进
# workflow_dispatch 的 choices，新增发行版就要改 YAML）。

# 镜像内由 workflow 写入的构建参数（/root/build.env）；宿主阶段不存在该文件
if [[ -f /root/build.env ]]; then
  set -a
  # shellcheck source=/dev/null
  . /root/build.env
  set +a
fi

# ── 环境变量卫生 ────────────────────────────────────────────────────────────
# 上面的 set -a 会把 build.env 里的**每一个**变量导出成环境变量，而 LANGUAGE
# 用的是 workflow_dispatch choices 的哨兵值 "None (C.UTF-8)" —— 带括号的。
# 这个值会一路传进 dpkg 子进程，而 keyboard-configuration 的 config 脚本
# （第 1298 行）有一句：
#     eval `locale`
# `locale` 把环境里的值原样打印，eval 吃到括号就报
#     Syntax error: "(" unexpected
# 于是 dpkg 在 --unpack 阶段失败：
#     new keyboard-configuration package preinst ... failed with exit status 2
# 整个 "[chroot] Install Desktop" 步骤就此中止（Lomiri/GNOME/KDE 都会撞上，
# 因为默认 language 就是这个哨兵值）。
#
# 需要哨兵值的脚本自己会用 ${LANGUAGE:-None (C.UTF-8)} 取回，所以这里必须把它
# 从环境里摘掉。同理，任何会被子进程 eval 的 locale 变量都不该带 shell 元字符。
if [[ "${LANGUAGE:-}" == "None (C.UTF-8)" ]]; then
  unset LANGUAGE
fi
case "${LANG:-}" in
  *\(*|*\)*|*\;*|*\|*|*\`*) unset LANG ;;
esac
case "${LC_ALL:-}" in
  *\(*|*\)*|*\;*|*\|*|*\`*) unset LC_ALL ;;
esac
export LANG="${LANG:-C.UTF-8}"

: "${DISTRO_SERIES:=26.04}"

case "$DISTRO_SERIES" in
  26.10|stonking) DISTRO_SUITE="stonking"; DISTRO_DEVEL="true" ;;  # Ubuntu 26.10 Stonking Stingray（开发中）
  26.04|resolute) DISTRO_SUITE="resolute" ;;   # Ubuntu 26.04 LTS Resolute Raccoon
  25.10|questing) DISTRO_SUITE="questing" ;;   # Ubuntu 25.10 Questing Quokka
  *) echo "不支持的 Ubuntu 版本: $DISTRO_SERIES（可选 26.10 / 26.04 / 25.10）" >&2; exit 1 ;;
esac
export DISTRO_SUITE
# 开发中的版本：官方 releases/ 下还没有 ubuntu-base tarball，引导阶段优先试 daily 构建
export DISTRO_DEVEL="${DISTRO_DEVEL:-false}"

# ── arm64 归档位置（随版本变化，不要写死）────────────────────────────────
# 官方公告「Ubuntu on ARM: summer '26 update」与 ubuntu-images 的 MR（LP #2147101、
# ubuntu-release-upgrader 的守卫条件）均已确认：
#   **从 26.04 (resolute) 起 arm64 已从 ports.ubuntu.com 迁到 archive.ubuntu.com**；
#   25.10 (questing) 及更早仍用 ports。
# ports 上仍留有 resolute 的副本但**不再刷新**（安全更新会缺失），所以必须按版本选。
case "$DISTRO_SUITE" in
  resolute|stonking)
    export UBUNTU_MAIN_MIRROR="${UBUNTU_MAIN_MIRROR:-http://archive.ubuntu.com/ubuntu/}"
    export UBUNTU_SECURITY_MIRROR="${UBUNTU_SECURITY_MIRROR:-http://security.ubuntu.com/ubuntu/}"
    ;;
  *)
    export UBUNTU_MAIN_MIRROR="${UBUNTU_MAIN_MIRROR:-http://ports.ubuntu.com/ubuntu-ports/}"
    export UBUNTU_SECURITY_MIRROR="${UBUNTU_SECURITY_MIRROR:-http://ports.ubuntu.com/ubuntu-ports/}"
    ;;
esac
# 兼容旧引用（mmdebstrap 回退路径等）
export UBUNTU_PORTS_MIRROR="${UBUNTU_PORTS_MIRROR:-$UBUNTU_MAIN_MIRROR}"
export UBUNTU_CDIMAGE_BASE="${UBUNTU_CDIMAGE_BASE:-https://cdimage.ubuntu.com/ubuntu-base/releases}"

log()  { printf '[%s] %s\n' "${0##*/}" "$*"; }
warn() { printf '[%s] 警告: %s\n' "${0##*/}" "$*" >&2; }
die()  { printf '[%s] 错误: %s\n' "${0##*/}" "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "需要 root 权限（请用 sudo 调用本脚本）"
}

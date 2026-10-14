#!/usr/bin/env bash
# 01-bootstrap.sh —— 往已挂载的镜像里铺 Ubuntu 基础系统
#
# 首选官方 ubuntu-base rootfs tarball（跨版本最稳，不受 runner 自带
# debootstrap 是否认识新 suite 的影响）；若所有候选地址都失败，退回 mmdebstrap。
#
# 环境变量：
#   DISTRO_SERIES  26.10 / 26.04 / 25.10（见 common/distro-env.sh）
#   UBUNTU_BASE_URL 可选，直接指定 tarball 地址（覆盖候选列表）
#
# 用法: sudo scripts/host/01-bootstrap.sh [挂载点]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
require_root

MOUNT="${1:-/mnt/rootfs}"
[[ -d "$MOUNT" ]] || die "挂载点不存在: $MOUNT"

# ---------------------------------------------------------------------------
# 1) 取 ubuntu-base tarball
# ---------------------------------------------------------------------------
TARBALL="$(mktemp -d)/ubuntu-base.tar.gz"
trap 'rm -rf "$(dirname "$TARBALL")"' EXIT

candidates=()
if [[ -n "${UBUNTU_BASE_URL:-}" ]]; then
  candidates+=("$UBUNTU_BASE_URL")
fi
if [[ "${DISTRO_DEVEL}" == "true" ]]; then
  # 开发中的版本（如 26.10）官方 cdimage 的 releases/ 下还没有 ubuntu-base，
  # 只有 daily 构建；先试 daily，全部失败会自动回退 mmdebstrap。
  log "开发中的版本（${DISTRO_SERIES} / ${DISTRO_SUITE}）：优先尝试 ubuntu-base daily 构建"
  candidates+=(
    "https://cdimage.ubuntu.com/ubuntu-base/daily/current/ubuntu-base-${DISTRO_SERIES}-base-arm64.tar.gz"
    "https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/daily/current/ubuntu-base-${DISTRO_SERIES}-base-arm64.tar.gz"
  )
fi
candidates+=(
  # 点发行版（26.04.1 之类）比 GA 版新数月，优先取；文件不存在时自动落到下一个候选
  "${UBUNTU_CDIMAGE_BASE}/${DISTRO_SERIES}.1/release/ubuntu-base-${DISTRO_SERIES}.1-base-arm64.tar.gz"
  "${UBUNTU_CDIMAGE_BASE}/${DISTRO_SERIES}/release/ubuntu-base-${DISTRO_SERIES}-base-arm64.tar.gz"
  "${UBUNTU_CDIMAGE_BASE}/${DISTRO_SUITE}/release/ubuntu-base-${DISTRO_SUITE}-base-arm64.tar.gz"
  "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/${DISTRO_SERIES}.1/release/ubuntu-base-${DISTRO_SERIES}.1-base-arm64.tar.gz"
  "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/${DISTRO_SERIES}/release/ubuntu-base-${DISTRO_SERIES}-base-arm64.tar.gz"
  "https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/${DISTRO_SERIES}/release/ubuntu-base-${DISTRO_SERIES}-base-arm64.tar.gz"
)

fetched=0
for url in "${candidates[@]}"; do
  log "尝试下载: $url"
  if curl -fL --retry 3 --connect-timeout 20 -o "$TARBALL" "$url"; then
    fetched=1
    break
  fi
  warn "该地址不可用，换下一个"
done

if [[ "$fetched" -eq 1 ]]; then
  log "解包 ubuntu-base 到 $MOUNT"
  tar -xpf "$TARBALL" -C "$MOUNT"
else
  # -------------------------------------------------------------------------
  # 2) 回退：mmdebstrap（suite 无关，不需要 debootstrap 的 scripts 符号链接）
  # -------------------------------------------------------------------------
  warn "未能获取 ubuntu-base tarball，回退 mmdebstrap"
  command -v mmdebstrap >/dev/null 2>&1 || die "mmdebstrap 未安装；请在 workflow 里安装 mmdebstrap 或指定 UBUNTU_BASE_URL"
  # --include=apt：minbase 在开发中的 suite 上有时不会把 apt 带进来，
  # 没有 apt-get 的 rootfs 会在 chroot 第一步就失败（且错误信息很不直观），这里显式要求。
  mmdebstrap \
    --architectures=arm64 \
    --variant=minbase \
    --include=apt,ubuntu-keyring,ca-certificates \
    --components=main,restricted,universe,multiverse \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    --mode=root \
    "$DISTRO_SUITE" "$MOUNT" "$UBUNTU_MAIN_MIRROR"
fi

# 引导结果自检：chroot 阶段依赖 apt-get，缺失时在这里就报清楚（否则要等到
# “apt-get: command not found” 才发现，且看不出根因）
if [[ ! -x "$MOUNT/usr/bin/apt-get" ]]; then
  warn "引导后的 rootfs 里没有 /usr/bin/apt-get，目录内容如下："
  ls -l "$MOUNT/usr/bin" 2>/dev/null | head -30 | sed 's/^/    /' || true
  die "引导失败：rootfs 缺少 apt-get（tarball 路径与 mmdebstrap 回退路径都没能装出可用系统）"
fi
log "已确认 rootfs 内有 apt-get"

# ---------------------------------------------------------------------------
# 3) apt 源：arm64 用 ports，补齐 -updates/-security/-backports
#    （ubuntu-base 自带的源只有主 pocket，且没有 universe/multiverse）
# ---------------------------------------------------------------------------
log "写入 apt 源（deb822 格式）"
mkdir -p "$MOUNT/etc/apt/sources.list.d"
cat > "$MOUNT/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: ${UBUNTU_MAIN_MIRROR}
Suites: ${DISTRO_SUITE} ${DISTRO_SUITE}-updates ${DISTRO_SUITE}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: ${UBUNTU_SECURITY_MIRROR}
Suites: ${DISTRO_SUITE}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
log "apt 源: main=${UBUNTU_MAIN_MIRROR} security=${UBUNTU_SECURITY_MIRROR}（suite=${DISTRO_SUITE}）"
rm -f "$MOUNT/etc/apt/sources.list"

log "引导完成：$DISTRO_SERIES ($DISTRO_SUITE)"
cat "$MOUNT/etc/os-release" 2>/dev/null | sed 's/^/    /' || true

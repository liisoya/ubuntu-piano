#!/usr/bin/env bash
# 00-prepare-image.sh —— 创建并挂载 rootfs.img（纯文件系统镜像，无分区表）
#
# 与上游 debian-sheng 一致：truncate + mkfs.ext4，直接刷到设备已有分区
# （userdata / linux / 自定义），因此镜像内部不需要分区表。
#
# 用法: sudo scripts/host/00-prepare-image.sh [镜像路径] [大小] [挂载点]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
require_root

IMAGE="${1:-rootfs.img}"
SIZE="${2:-10G}"
MOUNT="${3:-/mnt/rootfs}"

rm -f "$IMAGE"
truncate -s "$SIZE" "$IMAGE"
mkfs.ext4 -F -q -L rootfs "$IMAGE"

mkdir -p "$MOUNT"
mount -o loop "$IMAGE" "$MOUNT"

log "已创建并挂载: $IMAGE ($SIZE) → $MOUNT"
df -h "$MOUNT" | sed 's/^/    /'

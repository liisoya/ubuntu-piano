#!/usr/bin/env bash
# 03-umount-chroot.sh —— 逆序卸载虚拟文件系统（即使前序步骤失败也要执行）
#
# 用法: sudo scripts/host/03-umount-chroot.sh [挂载点]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
require_root

MOUNT="${1:-/mnt/rootfs}"

for d in dev/pts dev proc sys; do
  target="$MOUNT/$d"
  if mountpoint -q "$target"; then
    umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null || warn "卸载失败: $target"
    log "已卸载 $target"
  fi
done

# 注意：这里只卸载 chroot 用的虚拟文件系统，不卸载镜像本身
# （镜像的卸载由 04-finalize-image.sh 负责，否则 e2fsck 会拒绝在"已挂载"的文件上运行）
log "虚拟文件系统清理完成"

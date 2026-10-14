#!/usr/bin/env bash
# 04-finalize-image.sh —— 卸载镜像 → 校验 → 收缩 → 固定 UUID
#
# 相对上游补齐：上游只 umount + tune2fs -U，产物永远是 10 GiB 稀疏文件
# （上传压缩率低、刷写慢）。这里增加 e2fsck + resize2fs -M 收缩，
# 首启再由 fstab 的 x-systemd.growfs 扩到分区实际大小。
#
# 环境变量：
#   FS_UUID       要写入的文件系统 UUID（默认沿用上游固定值）
#   SHRINK_IMAGE  true/false，默认 true
#
# 用法: sudo scripts/host/04-finalize-image.sh [镜像] [挂载点]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
require_root

IMAGE="${1:-rootfs.img}"
MOUNT="${2:-/mnt/rootfs}"
FS_UUID="${FS_UUID:-ee8d3593-59b1-480e-a3b6-4fefb17ee7d8}"
SHRINK_IMAGE="${SHRINK_IMAGE:-true}"

# 卸载（可能残留 bind mount，递归卸载兜底）
umount -R "$MOUNT" 2>/dev/null || umount "$MOUNT" 2>/dev/null || warn "挂载点未挂载或已卸载: $MOUNT"
sync
log "镜像已卸载"

e2fsck -fy "$IMAGE" >/dev/null 2>&1 || warn "e2fsck 报告了问题（已尝试修复）"

if [[ "$SHRINK_IMAGE" == "true" ]]; then
  before="$(du -h --apparent-size "$IMAGE" | cut -f1)"
  if resize2fs -M "$IMAGE" >/dev/null 2>&1; then
    # 把文件本身截断到文件系统实际大小（resize2fs -M 只缩文件系统不缩文件）
    blocks="$(dumpe2fs -h "$IMAGE" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')"
    bsize="$(dumpe2fs -h "$IMAGE" 2>/dev/null | awk -F: '/Block size/{gsub(/ /,"",$2); print $2}')"
    if [[ -n "$blocks" && -n "$bsize" ]]; then
      truncate -s "$((blocks * bsize))" "$IMAGE"
      SHRINK_RESULT="成功（$before → $(du -h --apparent-size "$IMAGE" | cut -f1)）"
      log "镜像已收缩: $SHRINK_RESULT"
    else
      SHRINK_RESULT="文件系统已缩小，但未能算出块数（文件未截断）"
      warn "$SHRINK_RESULT"
    fi
  else
    SHRINK_RESULT="失败（保持 $before；镜像仍可刷写，首启前会占满分区）"
    warn "resize2fs -M 不可用，$SHRINK_RESULT"
  fi
else
  SHRINK_RESULT="已跳过（shrink_image=false）"
fi

tune2fs -U "$FS_UUID" "$IMAGE" >/dev/null 2>&1 || warn "设置文件系统 UUID 失败（fstab 用 PARTLABEL，不影响启动）"

log "最终产物:"
ls -lh "$IMAGE" | sed 's/^/    /'
du -h --apparent-size "$IMAGE" | sed 's/^/    实际大小(逻辑): /'

# 把「是否真的收缩成功」写进 step summary：这一步全部是 best-effort，
# 不显式报告的话，产物保持 10 GiB 也不会有人注意到。
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### rootfs.img"
    echo ""
    echo "| 项 | 值 |"
    echo "|---|---|"
    echo "| 最终大小（逻辑） | $(du -h --apparent-size "$IMAGE" | cut -f1) |"
    echo "| 文件系统 UUID | $(tune2fs -l "$IMAGE" 2>/dev/null | awk -F': ' '/Filesystem UUID/{print $2}') |"
    echo "| shrink_image | $SHRINK_IMAGE |"
    echo "| 收缩结果 | $SHRINK_RESULT |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

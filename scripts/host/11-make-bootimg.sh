#!/usr/bin/env bash
# 11-make-bootimg.sh —— custom_build 时用本地 mkbootimg 生成 boot.img
#
# 与上游一致：Image.gz 与 sm8550-xiaomi-sheng.dtb 已拼接为 Image.gz-dtb_sheng，
# cmdline 为 root=PARTLABEL=<分区>，quiet boot 时追加 quiet splash 等参数。
#
# 环境变量：
#   PARTITION_LABEL  userdata / linux / 自定义
#   QUIET_BOOT       true/false
#
# 用法: scripts/host/11-make-bootimg.sh [Image.gz-dtb_sheng 路径]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"

KERNEL_IMAGE="${1:-Image.gz-dtb_sheng}"
PARTITION_LABEL="${PARTITION_LABEL:?需要 PARTITION_LABEL}"
QUIET_BOOT="${QUIET_BOOT:-false}"

[[ -f "$KERNEL_IMAGE" ]] || die "内核镜像不存在: $KERNEL_IMAGE"
[[ -f mkbootimg ]] || die "仓库内缺少 mkbootimg"

CMDLINE="root=PARTLABEL=${PARTITION_LABEL}"
if [[ "$QUIET_BOOT" == "true" ]]; then
  CMDLINE="${CMDLINE} quiet splash plymouth.ignore-serial-consoles fbcon=map:1"
fi

chmod +x mkbootimg
log "生成 boot.img（cmdline: $CMDLINE）"
./mkbootimg \
  --kernel "$KERNEL_IMAGE" \
  --cmdline "$CMDLINE" \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --tags_offset 0x01e00000 \
  --pagesize 4096 \
  --id -o boot.img

log "boot.img 就绪: $(du -h boot.img | cut -f1)"

#!/usr/bin/env bash
# 打包 linux-image-piano-kde（内核 deb：Image + modules + dtbs）
#
# 照 sheng 的 linux-xiaomi-sheng deb 模式（ianchb/sm8550-mainline release 载体）：
# chroot 装配时 dpkg -i，postinst 自动 depmod——模块问题结构性消失；
# 用户后续在设备上 dpkg -i 本包即可升级内核。
#
# 需要环境变量：
#   KVER        内核版本串（如 7.2.6-piano-kde-g453bb567f2fc-dirty）
#   KERNEL_DIR  内核构建目录（含 Image 与 .config）
#   MODULES_DIR modules_install 的 staging（含 lib/modules/$KVER）
#   DTB_DIR     （可选）dtb 目录，装入 /usr/lib/linux-image-$KVER/
#
# 用法: sudo scripts/packages/build-kernel-deb.sh   （root 以保 ownership）
set -euo pipefail

KVER="${KVER:?需要 KVER}"
KERNEL_DIR="${KERNEL_DIR:?需要 KERNEL_DIR}"
MODULES_DIR="${MODULES_DIR:?需要 MODULES_DIR}"
DTB_DIR="${DTB_DIR:-}"

PKG=linux-image-piano-kde
OUT="${PWD}/${PKG}_${KVER}_arm64.deb"
BUILD="${PWD}/build/${PKG}"

rm -rf "$BUILD"
mkdir -p "$BUILD/DEBIAN" "$BUILD/boot" "$BUILD/lib/modules"

# 内核镜像：/boot/vmlinuz-$KVER（同时保留裸 Image 供 mkbootimg 引用）
[[ -f "$KERNEL_DIR/arch/arm64/boot/Image" ]] || { echo "缺 Image" >&2; exit 1; }
install -m 644 "$KERNEL_DIR/arch/arm64/boot/Image" "$BUILD/boot/vmlinuz-$KVER"

# 模块树
[[ -d "$MODULES_DIR/lib/modules/$KVER" ]] || { echo "缺模块树 $MODULES_DIR/lib/modules/$KVER" >&2; exit 1; }
cp -a "$MODULES_DIR/lib/modules/$KVER" "$BUILD/lib/modules/"
rm -f "$BUILD/lib/modules/$KVER/build" "$BUILD/lib/modules/$KVER/source"

# dtbs（可选）
if [[ -n "$DTB_DIR" && -d "$DTB_DIR" ]]; then
  mkdir -p "$BUILD/usr/lib/linux-image-$KVER"
  cp -a "$DTB_DIR/." "$BUILD/usr/lib/linux-image-$KVER/"
fi

cat > "$BUILD/DEBIAN/control" <<EOF
Package: $PKG
Version: $KVER
Section: kernel
Priority: optional
Architecture: arm64
Maintainer: liisoya <liisoya@users.noreply.github.com>
Description: Linux kernel $KVER for Xiaomi Pad 8 Pro (piano)
 Mainline kernel with piano device support and the iris decode-order
 patch series. Provides /boot/vmlinuz-$KVER and /lib/modules/$KVER.
 Built from blu-sharky/linux-piano; see the builder MANIFEST for the
 exact commit/config provenance.

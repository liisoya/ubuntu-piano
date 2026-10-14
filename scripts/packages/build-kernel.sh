#!/usr/bin/env bash
# custom_build：用 ianchb/sm8550-mainline 源码编译内核并打成 deb
#
# 与上游 debian-sheng 的 build-kernel 作业一致（clang + LLVM=1 + ccache，
# Image.gz 与 DTB 拼接成 Image.gz-dtb_sheng 供 mkbootimg 使用）。
# 相对上游补齐两点：
#   1. 打包内执行 depmod（上游全程没有 depmod）
#   2. 同时输出 boot/ 下的内核与 DTB 副本，便于排查
#
# 需要环境变量：
#   KERNEL_REPO    默认 https://github.com/ianchb/sm8550-mainline
#   KERNEL_BRANCH  默认 sheng-7.2.6
#   KERNEL_CONFIG  默认 sm8550.config（仓库内文件）
#
# 用法: scripts/packages/build-kernel.sh
set -euo pipefail

KERNEL_REPO="${KERNEL_REPO:-https://github.com/ianchb/sm8550-mainline}"
KERNEL_BRANCH="${KERNEL_BRANCH:-sheng-7.2.6}"
KERNEL_CONFIG="${KERNEL_CONFIG:-sm8550.config}"

SRC="${PWD}/linux"
PKGDIR="${PWD}/linux-xiaomi-sheng"
OUT="${PWD}/linux-xiaomi-sheng.deb"

rm -rf "$SRC" "$PKGDIR"
echo "[build-kernel] 克隆 $KERNEL_REPO ($KERNEL_BRANCH)"
git clone "$KERNEL_REPO" --branch "$KERNEL_BRANCH" --depth 1 "$SRC"

install -Dm644 "$KERNEL_CONFIG" "$SRC/.config"

export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
export PATH="/usr/lib/ccache:$PATH"
export CC="ccache clang"
export CXX="ccache clang++"
export AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf STRIP=llvm-strip

JOBS="$(nproc)"
echo "[build-kernel] 编译中 (JOBS=$JOBS)"
make -C "$SRC" -j"$JOBS" ARCH=arm64 LLVM=1

KVER="$(make -C "$SRC" -s ARCH=arm64 LLVM=1 kernelrelease)"
[[ -n "$KVER" ]] || { echo "[build-kernel] 无法获取 kernelrelease" >&2; exit 1; }
echo "[build-kernel] 内核版本: $KVER"

make -C "$SRC" -j"$JOBS" ARCH=arm64 LLVM=1 INSTALL_MOD_PATH="$PKGDIR" modules_install
rm -rf "$PKGDIR/lib/modules/$KVER/build" "$PKGDIR/lib/modules/$KVER/source"

DTB="$SRC/arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb"
[[ -f "$DTB" ]] || { echo "[build-kernel] 未找到 DTB: $DTB" >&2; exit 1; }

install -Dm644 "$SRC/arch/arm64/boot/Image.gz" "$PKGDIR/boot/vmlinuz-$KVER"
install -Dm644 "$DTB"                          "$PKGDIR/boot/dtb-$KVER.dtb"
install -Dm644 "$SRC/.config"                  "$PKGDIR/boot/config-$KVER"
install -Dm644 "$SRC/System.map"               "$PKGDIR/boot/System.map-$KVER"

# mkbootimg 用的拼接镜像（内核 + DTB）
cat "$SRC/arch/arm64/boot/Image.gz" "$DTB" > "${PWD}/Image.gz-dtb_sheng"

mkdir -p "$PKGDIR/DEBIAN"
cat > "$PKGDIR/DEBIAN/control" <<EOF
Package: linux-xiaomi-sheng
Version: ${KVER}
Architecture: arm64
Maintainer: map220v
Section: kernel
Description: Kernel and Modules for Xiaomi Pad 6s Pro
EOF

find "$PKGDIR" -type d -exec chmod 755 {} +
find "$PKGDIR" -type f -exec chmod 644 {} +

# 上游缺失的 depmod：在包内生成 modules.dep 等索引，装机后无需再依赖 postinst
depmod -b "$PKGDIR" "$KVER" || echo "[build-kernel] 警告：depmod 失败，装机阶段会再执行一次"

dpkg-deb --build --root-owner-group "$PKGDIR" "$OUT"
echo "[build-kernel] 产出 $OUT ($(du -h "$OUT" | cut -f1))"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "kernel_version=$KVER"
    echo "kernel_image=${PWD}/Image.gz-dtb_sheng"
  } >> "$GITHUB_OUTPUT"
fi

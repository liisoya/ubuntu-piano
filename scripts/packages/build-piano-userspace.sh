#!/usr/bin/env bash
# 打包 piano-userspace（piano 设备运行时件：piano-* 服务/UCM2/规则/touch-view/camerad/busybox）
#
# 对应 sheng 的 xiaomi-* 逐包模式；内容来自仓库内 piano-userspace/ 包树
# （二进制来自 Bulid/archive/old-kubuntu-salvage 打捞，见 RESEARCH-LOG R12）。
#
# 用法: scripts/packages/build-piano-userspace.sh   （在仓库根目录执行）
set -euo pipefail

PKG=piano-userspace
OUT="${PWD}/${PKG}.deb"
BUILD="${PWD}/build/${PKG}"

rm -rf "$BUILD"
mkdir -p "$BUILD"

cp -a "$PKG/DEBIAN" "$BUILD/"
cp -a "$PKG/usr"    "$BUILD/"
cp -a "$PKG/etc"    "$BUILD/"

# 权限纪律：目录 755、脚本/二进制 755、数据 644
find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD/usr/lib/piano" "$BUILD/usr/bin" -type f -exec chmod 755 {} +
find "$BUILD/usr/share" "$BUILD/etc" -type f -exec chmod 644 {} +

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-piano-userspace] 产出 $OUT ($(du -h "$OUT" | cut -f1))"

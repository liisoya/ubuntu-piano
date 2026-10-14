#!/usr/bin/env bash
# 打包 firmware-xiaomi-sheng（设备固件与配置：ath12k/WCN7850、QCA 蓝牙、Cirrus DSP 等）
#
# 对应上游 debian-sheng 的 “Package firmware-xiaomi-sheng” 步骤：
#   克隆 firmware 仓库 → 全部内容装到 /usr/lib/firmware → dpkg-deb
# control 里保留 Debian 语义的 Conflicts/Replaces: linux-firmware
#
# 需要环境变量：
#   FIRMWARE_REPO   固件仓库 URL（默认 https://github.com/ianchb/sheng-firmware）
#   FIRMWARE_BRANCH 分支（默认 master）
#
# 用法: scripts/packages/build-firmware.sh
set -euo pipefail

PKG=firmware-xiaomi-sheng
FIRMWARE_REPO="${FIRMWARE_REPO:-https://github.com/ianchb/sheng-firmware}"
FIRMWARE_BRANCH="${FIRMWARE_BRANCH:-master}"
OUT="${PWD}/${PKG}.deb"
BUILD="${PWD}/build/${PKG}"
SRC="${PWD}/build/firmware-src"

rm -rf "$BUILD" "$SRC"
mkdir -p "$BUILD/usr/lib/firmware"

echo "[build-firmware] 克隆 $FIRMWARE_REPO ($FIRMWARE_BRANCH)"
git clone --depth 1 --branch "$FIRMWARE_BRANCH" "$FIRMWARE_REPO" "$SRC"

cp -a "$PKG/DEBIAN" "$BUILD/"
cp -a "$SRC/." "$BUILD/usr/lib/firmware/"
rm -rf "$BUILD/usr/lib/firmware/.git" \
       "$BUILD/usr/lib/firmware/.github" \
       "$BUILD/usr/lib/firmware/.gitignore"

# 固件 blob 必须保持原样：不做 strip、不压缩
find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-firmware] 产出 $OUT ($(du -h "$OUT" | cut -f1))"
find "$BUILD/usr/lib/firmware" -maxdepth 1 -mindepth 1 -printf '    %f\n' | sort

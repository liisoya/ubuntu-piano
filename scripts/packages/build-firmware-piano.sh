#!/usr/bin/env bash
# 打包 firmware-piano（piano 设备固件：ath12k/adsp/cdsp/novatek 触摸等）
#
# 照 sheng 的 build-firmware.sh 模式：包骨架在本仓库（只有 DEBIAN/control，
# 不分发二进制），构建时克隆 blu-sharky/piano-firmware，把 firmware/ 子树
# 装进 /usr/lib/firmware。
#
# 需要环境变量：
#   FIRMWARE_REPO   固件仓库 URL（默认 https://github.com/blu-sharky/piano-firmware）
#   FIRMWARE_BRANCH 分支（默认 main；本地核验克隆为 48M，含 ath12k/PEACH hw2.0）
#
# 用法: scripts/packages/build-firmware-piano.sh
set -euo pipefail

PKG=firmware-piano
FIRMWARE_REPO="${FIRMWARE_REPO:-https://github.com/blu-sharky/piano-firmware}"
FIRMWARE_BRANCH="${FIRMWARE_BRANCH:-main}"
OUT="${PWD}/${PKG}.deb"
BUILD="${PWD}/build/${PKG}"
SRC="${PWD}/build/firmware-src"

rm -rf "$BUILD" "$SRC"
mkdir -p "$BUILD/usr/lib/firmware"

echo "[build-firmware-piano] 克隆 $FIRMWARE_REPO ($FIRMWARE_BRANCH)"
git clone --depth 1 --branch "$FIRMWARE_BRANCH" "$FIRMWARE_REPO" "$SRC"

[[ -d "$SRC/firmware" ]] || { echo "[build-firmware-piano] 固件仓库缺 firmware/ 子树" >&2; exit 1; }

cp -a "$PKG/DEBIAN" "$BUILD/"
cp -a "$SRC/firmware/." "$BUILD/usr/lib/firmware/"
rm -rf "$BUILD/usr/lib/firmware/.git" "$BUILD/usr/lib/firmware/.github" "$BUILD/usr/lib/firmware/.gitignore"

# 固件 blob 必须保持原样：不做 strip、不压缩
find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-firmware-piano] 产出 $OUT ($(du -h "$OUT" | cut -f1))"
find "$BUILD/usr/lib/firmware" -maxdepth 1 -mindepth 1 -printf '    %f\n' | sort

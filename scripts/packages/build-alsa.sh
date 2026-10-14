#!/usr/bin/env bash
# 打包 alsa-xiaomi-sheng（ALSA UCM2 用例配置）
#
# 对应上游 debian-sheng 的 “Package alsa-xiaomi-sheng” 步骤。
# 关键修正：上游 conf.d/sm8550/Xiaomi-Pad6SPro.conf 是 symlink，在非 POSIX 文件系统
# （例如 Windows 上克隆/拷贝本仓库）会退化成普通文本文件，直接 dpkg-deb 会打出坏配置。
# 这里强制重建软链，与上游 GitHub Actions 上的行为对齐。
#
# 用法: scripts/packages/build-alsa.sh   （在仓库根目录执行）
set -euo pipefail

PKG=alsa-xiaomi-sheng
OUT="${PWD}/${PKG}.deb"
BUILD="${PWD}/build/${PKG}"

rm -rf "$BUILD"
mkdir -p "$BUILD"

cp -a "$PKG/DEBIAN" "$BUILD/"
cp -a "$PKG/usr"    "$BUILD/"

CONF="$BUILD/usr/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf"
if [[ -e "$CONF" && ! -L "$CONF" ]]; then
  echo "[build-alsa] $CONF 不是软链（典型原因：仓库在 Windows 上克隆），正在重建"
  rm -f "$CONF"
  ln -s ../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf "$CONF"
fi
[[ -L "$CONF" ]] || { echo "[build-alsa] 软链创建失败: $CONF" >&2; exit 1; }

find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-alsa] 产出 $OUT"
dpkg-deb -c "$OUT" | sed 's/^/    /'

#!/usr/bin/env bash
# 打包 sheng-sensors（Qualcomm SSC 传感器 registry / 标定数据）
#
# 对应上游 debian-sheng 的 build-sheng-sensors 作业。上游在作业内联生成
# DEBIAN/control 与 DEBIAN/postinst；这里同样在上面的 heredoc 里生成，
# postinst 保留原语义。
#
# 用法: scripts/packages/build-sheng-sensors.sh
set -euo pipefail

PKG=sheng-sensors
SRCDIR=sheng-sensors-files
VERSION="${SENSORS_VERSION:-20240917-1}"
OUT="${PWD}/${PKG}_${VERSION}_arm64.deb"
BUILD="${PWD}/build/${PKG}"

rm -rf "$BUILD"
mkdir -p "$BUILD/DEBIAN"

cp -a "$SRCDIR/usr" "$BUILD/"

cat > "$BUILD/DEBIAN/control" <<EOF
Package: ${PKG}
Version: ${VERSION}
Architecture: arm64
Maintainer: map220v
Section: misc
Description: Qualcomm SSC sensor registry and calibration files for Xiaomi Pad 6S Pro
EOF

# postinst：与上游逐句一致（含 [ -d /run/systemd/system ] 守卫，chroot 内不会误触发）
cat > "$BUILD/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
udevadm control --reload || true
if [ -e /sys/devices/virtual/misc/fastrpc-adsp ]; then
    udevadm trigger || true
fi
systemctl daemon-reload || true
if [ -d /run/systemd/system ]; then
    systemctl try-restart iio-sensor-proxy.service || true
fi
exit 0
EOF
chmod 755 "$BUILD/DEBIAN/postinst"

find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +
chmod 755 "$BUILD/DEBIAN/postinst"

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-sheng-sensors] 产出 $OUT"

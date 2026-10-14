#!/usr/bin/env bash
# 打包 iio-sensor-proxy（启用 SSC 后端，读取 /usr/share/qcom 传感器注册表）
#
# 对应上游 debian-sheng 的 build-iio-sensor-proxy 作业（needs: build-libssc）：
#   先安装上一步产出的 libssc deb 以满足编译期依赖 → 下载 iio-sensor-proxy 3.9 →
#   meson -Dssc-support=enabled → 打包，版本号刻意写成 99993.9-6 以压过发行版自带包
#
# 需要环境变量：
#   IIO_VERSION  默认 3.9；IIO_DEB_VERSION 默认 99993.9-6
#   LIBssc_DEB   上一步产出的 libssc deb 路径（默认自动在 $PWD 查找）
#
# 用法: scripts/packages/build-iio-sensor-proxy.sh
set -euo pipefail

VER="${IIO_VERSION:-3.9}"
DEBVER="${IIO_DEB_VERSION:-99993.9-6}"
OUT="${PWD}/iio-sensor-proxy_${DEBVER}_arm64.deb"
WORK="${PWD}/build/iio-src"
STAGE="${PWD}/build/iio-stage"
BUILD="${PWD}/build/iio-sensor-proxy"

# 编译期依赖：安装 libssc（宿主是目标同架构的原生 arm64 runner，可直接安装）
LIBssc_DEB="${LIBssc_DEB:-$(ls -1 "$PWD"/libssc_*.deb 2>/dev/null | head -n1 || true)}"
[[ -n "$LIBssc_DEB" ]] || { echo "[build-iio] 找不到 libssc deb，请先运行 build-libssc.sh" >&2; exit 1; }
echo "[build-iio] 安装编译期依赖: $LIBssc_DEB"
sudo dpkg -i "$LIBssc_DEB"
sudo ldconfig

rm -rf "$WORK" "$STAGE" "$BUILD"
mkdir -p "$WORK" "$BUILD/DEBIAN"

echo "[build-iio] 下载 iio-sensor-proxy ${VER}"
wget -q "https://gitlab.freedesktop.org/hadess/iio-sensor-proxy/-/archive/${VER}/iio-sensor-proxy-${VER}.tar.gz" \
     -O "$WORK/src.tar.gz"
tar -xzf "$WORK/src.tar.gz" -C "$WORK"

if ! command -v meson >/dev/null 2>&1; then
  pip3 install --user --upgrade meson
  export PATH="$HOME/.local/bin:$PATH"
fi

SRCDIR="$WORK/iio-sensor-proxy-${VER}"
( cd "$SRCDIR"
  meson setup output --prefix=/usr \
    -Db_lto=true \
    -Dssc-support=enabled \
    -Dsystemdsystemunitdir=/usr/lib/systemd/system
  meson compile -C output
  DESTDIR="$STAGE" meson install --no-rebuild -C output
)

cp -a "$STAGE/usr" "$BUILD/"

cat > "$BUILD/DEBIAN/control" <<EOF
Package: iio-sensor-proxy
Version: ${DEBVER}
Architecture: arm64
Maintainer: Dylan Van Assche <me@dylanvanassche.be>
Section: misc
Depends: dbus, libglib2.0-0 | libglib2.0-0t64, libgudev-1.0-0, libpolkit-gobject-1-0
Description: IIO sensors to D-Bus proxy (SSC backend enabled)
EOF

find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +
if [[ -f "$BUILD/usr/bin/monitor-sensor" ]]; then
  chmod 755 "$BUILD/usr/bin/monitor-sensor"
fi
if [[ -f "$BUILD/usr/libexec/iio-sensor-proxy" ]]; then
  chmod 755 "$BUILD/usr/libexec/iio-sensor-proxy"
fi

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-iio] 产出 $OUT"

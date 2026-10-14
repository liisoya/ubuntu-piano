#!/usr/bin/env bash
# 打包 fastrpc（Qualcomm FastRPC 用户态库 + adsprpcd）
#
# 对应上游 debian-sheng 的 build-fastrpc 作业：
#   qualcomm/fastrpc v1.0.2 → autoreconf -is → ./configure --prefix=/usr → make →
#   make DESTDIR=stage install → 追加 patches/adsprpcd-sensorspd.service →
#   control(Depends: libyaml-0-2, systemd) → dpkg-deb
#
# 需要环境变量：
#   FASTRPC_VERSION 默认 1.0.2
#
# 用法: scripts/packages/build-fastrpc.sh
set -euo pipefail

PKG=fastrpc
VER="${FASTRPC_VERSION:-1.0.2}"
OUT="${PWD}/${PKG}_${VER}-1_arm64.deb"
WORK="${PWD}/build/${PKG}-src"
STAGE="${PWD}/build/${PKG}-stage"
BUILD="${PWD}/build/${PKG}"

rm -rf "$WORK" "$STAGE" "$BUILD"
mkdir -p "$WORK" "$BUILD/DEBIAN"

echo "[build-fastrpc] 下载 qualcomm/fastrpc v${VER}"
wget -q "https://github.com/qualcomm/fastrpc/archive/refs/tags/v${VER}.zip" -O "$WORK/src.zip"
unzip -q "$WORK/src.zip" -d "$WORK"

SRCDIR="$WORK/fastrpc-${VER}"
[[ -d "$SRCDIR" ]] || { echo "[build-fastrpc] 源码目录不存在: $SRCDIR" >&2; exit 1; }

( cd "$SRCDIR"
  autoreconf -is
  ./configure --prefix=/usr
  make -j"$(nproc)"
  make DESTDIR="$STAGE" install
)

# 传感器 aDSP RPC 守护进程的 unit（上游同样在打包阶段补入）
install -Dm644 patches/adsprpcd-sensorspd.service "$STAGE/usr/lib/systemd/system/adsprpcd-sensorspd.service"

cp -a "$STAGE/usr" "$BUILD/"

cat > "$BUILD/DEBIAN/control" <<EOF
Package: ${PKG}
Version: ${VER}-1
Architecture: arm64
Maintainer: Fauzan Amir Al Ghiffary <alghaffaryfa19@gmail.com>
Section: libs
Depends: libyaml-0-2, systemd
Description: Qualcomm FastRPC user space libraries and adsprpcd
EOF

find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +
chmod 755 "$BUILD/usr/bin/adsprpcd"

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-fastrpc] 产出 $OUT"

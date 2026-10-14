#!/usr/bin/env bash
# 打包 libssc（Qualcomm Snapdragon Sensor Core 客户端库）
#
# 对应上游 debian-sheng 的 build-libssc 作业：
#   codeberg.org/DylanVanAssche/libssc → 应用 patches/wait_for_qmi_service.patch
#   （给 QRTR 节点查找加 5 次 sleep(1) 重试，解决开机早期 QMI 服务未就绪）
#   → meson setup/compile/install → control(Depends: libglib2.0-0, libprotobuf-c1, libqmi-glib5)
#
# 需要环境变量：
#   LIBssc_VERSION 默认 0.3.0；MESON 由 meson 或 pip 提供
#
# 用法: scripts/packages/build-libssc.sh
set -euo pipefail

PKG=libssc
VER="${LIBssc_VERSION:-0.3.0}"
OUT="${PWD}/${PKG}_${VER}-1_arm64.deb"
SRC="${PWD}/build/${PKG}-src"
STAGE="${PWD}/build/${PKG}-stage"
BUILD="${PWD}/build/${PKG}"

rm -rf "$SRC" "$STAGE" "$BUILD"
mkdir -p "$BUILD/DEBIAN"

echo "[build-libssc] 克隆 libssc 源码"
git clone https://codeberg.org/DylanVanAssche/libssc.git "$SRC"

cp patches/wait_for_qmi_service.patch "$SRC/"
( cd "$SRC"
  # 上游用 `|| true`：补丁可能因上游已合并而失败，此时继续构建
  patch -Np1 < wait_for_qmi_service.patch || echo "[build-libssc] 补丁未应用（可能已合入上游）"
)

# 硬校验：QRTR 节点查找的重试逻辑必须存在 —— 要么补丁打上了，要么上游已自己合入。
# 两者都没有的话，开机早期 QMI 服务未就绪会导致传感器不可用，必须让构建失败而不是静默产出坏镜像。
# 匹配写成宽松正则：上游改写法（attempts / tries / retry）时不应误报失败。
if ! grep -qE 'for[[:space:]]*\([^)]*(attempt|tries|retry)|retry|RETRY' "$SRC/src/libssc-client.c"; then
  echo "[build-libssc] 错误：wait_for_qmi_service 补丁未生效，且上游源码里也找不到重试逻辑" >&2
  echo "             可把源码钉到已知可用版本（如 codeberg 的 v0.4.2 tag）或重做补丁" >&2
  exit 1
fi

# meson 版本：优先系统包，其次 pip 安装的用户级
if ! command -v meson >/dev/null 2>&1; then
  pip3 install --user --upgrade meson
  export PATH="$HOME/.local/bin:$PATH"
fi

( cd "$SRC"
  meson setup build --prefix=/usr
  meson compile -C build
  DESTDIR="$STAGE" meson install -C build
)

cp -a "$STAGE/usr" "$BUILD/"

cat > "$BUILD/DEBIAN/control" <<EOF
Package: ${PKG}
Version: ${VER}-1
Architecture: arm64
Maintainer: Dylan Van Assche <me@dylanvanassche.be>
Section: libs
Depends: libglib2.0-0 | libglib2.0-0t64, libprotobuf-c1, libqmi-glib5
Description: Qualcomm Snapdragon Sensor Core client library
EOF

find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +
if [[ -f "$BUILD/usr/bin/ssccli" ]]; then
  chmod 755 "$BUILD/usr/bin/ssccli"
fi

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-libssc] 产出 $OUT"

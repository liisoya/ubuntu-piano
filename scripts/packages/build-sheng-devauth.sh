#!/usr/bin/env bash
# 打包 sheng-devauth（与内核驱动配合完成小米官方键盘认证的守护进程）
#
# 对应上游 debian-sheng 的 build-sheng-devauth 作业：
#   克隆 ianchb/sheng_devauth → make → 二进制放入包树 usr/bin/ →
#   生成 postinst（daemon-reload + enable + start）与 prerm（stop + disable）
#
# 需要环境变量：
#   DEVAUTH_REPO 源码仓库（默认 https://github.com/ianchb/sheng_devauth）
#
# 用法: scripts/packages/build-sheng-devauth.sh
set -euo pipefail

PKG=sheng-devauth
DEVAUTH_REPO="${DEVAUTH_REPO:-https://github.com/ianchb/sheng_devauth}"
OUT="${PWD}/${PKG}.deb"
BUILD="${PWD}/build/${PKG}"
SRC="${PWD}/build/devauth-src"

rm -rf "$BUILD" "$SRC"
mkdir -p "$BUILD/usr/bin"

echo "[build-sheng-devauth] 克隆 $DEVAUTH_REPO"
git clone --depth 1 "$DEVAUTH_REPO" "$SRC"

( cd "$SRC" && make )
[[ -f "$SRC/xiaomi_devauth" ]] || { echo "[build-sheng-devauth] make 未产出 xiaomi_devauth" >&2; exit 1; }

install -Dm755 "$SRC/xiaomi_devauth" "$BUILD/usr/bin/xiaomi_devauth"

# 包树里的 control 与 systemd unit 来自仓库（与上游同源）
cp -a "$PKG/DEBIAN" "$BUILD/"
cp -a "$PKG/usr/lib" "$BUILD/usr/"

cat > "$BUILD/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload || true
systemctl enable sheng-devauth.service || true
if [ -d /run/systemd/system ]; then
    systemctl start sheng-devauth.service || true
fi
exit 0
EOF

cat > "$BUILD/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ -d /run/systemd/system ]; then
    systemctl stop sheng-devauth.service || true
fi
systemctl disable sheng-devauth.service || true
systemctl daemon-reload || true
exit 0
EOF

find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +
chmod 755 "$BUILD/usr/bin/xiaomi_devauth" "$BUILD/DEBIAN/postinst" "$BUILD/DEBIAN/prerm"

# 依赖核对提示：如上游引入新动态库，这里会打印出来便于补 control 的 Depends
if command -v ldd >/dev/null 2>&1; then
  echo "[build-sheng-devauth] ldd 依赖概览："
  ldd "$BUILD/usr/bin/xiaomi_devauth" | sed 's/^/    /' || true
fi

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-sheng-devauth] 产出 $OUT"

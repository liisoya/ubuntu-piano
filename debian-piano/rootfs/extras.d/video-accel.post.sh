#!/bin/sh
# extras 后置钩子：视频硬件加速用户态（VA-API + Qualcomm Iris stateful V4L2 M2M）
#
# 为什么是后置钩子：依赖 vendor piano-mesa 的 libgbm.so.1 在位（手工提取 gbm
# headers 要用它建 .so 符号链接），且要在 Chrome 包装机之后补丁其 desktop 文件。
# pre 钩子跑在所有包装机之前，两者都不满足，故用 post 钩子机制
# （build-rootfs.sh：所有包装机 + overlay + piano-mesa + 用户创建之后运行）。
#
# 内核侧（iris decode-order + deblocking 补丁）在 kernel/patches/ 无条件应用，
# 与本片段无关；本片段只负责用户态。
#
# 配方来源：code002-2/sm8750-video-accel 的 10/20/30/40 脚本，
# 2026-10-14 在 piano 真机逐字验证通过（Bulid/issues/23、RESEARCH-LOG R7）。
set -eu

SRC=/tmp/piano-extra-video-accel-src/libva-v4l2
[ -d "$SRC" ] || { echo "video-accel: missing vendored source $SRC" >&2; exit 1; }

echo "== video-accel: hold 图形栈（防 libgbm-dev 降级 vendor Mesa） =="
for p in libgbm1 libegl1 libgles2 libgl1 libglx0 mesa-libgallium mesa-vulkan-drivers; do
    dpkg -l "$p" >/dev/null 2>&1 && { apt-mark hold "$p" >/dev/null 2>&1 && echo "  held $p"; } || true
done

echo "== video-accel: 安装非 Mesa 构建依赖 =="
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    build-essential meson ninja-build pkg-config \
    libva-dev libdrm-dev libegl-dev libgles-dev

echo "== video-accel: 手工提取 gbm headers（绝不安装 libgbm-dev） =="
# libgbm-dev 是 Mesa 包：依赖精确版本的 libgbm1，在 vendor-patched Mesa 上会
# 降级图形栈、可能带走 GPU（sm8750-video-accel 的教训）。只需要 headers +
# libgbm.so -> libgbm.so.1 符号链接，手工取，不装包。
[ -e /usr/lib/aarch64-linux-gnu/libgbm.so.1 ] || \
    { echo "video-accel: no libgbm.so.1 (Mesa not installed?)" >&2; exit 1; }
cd /tmp
apt-get download libgbm-dev >/dev/null 2>&1
rm -rf /tmp/gbm-dev && mkdir -p /tmp/gbm-dev
dpkg-deb -x libgbm-dev_*.deb /tmp/gbm-dev
install -d -m 0755 /usr/local/include /usr/local/lib/pkgconfig
cp -a /tmp/gbm-dev/usr/include/. /usr/local/include/
LIBDIR=$(dirname "$(readlink -f /usr/lib/*/libgbm.so.1 | head -1)")
PC=$(find /tmp/gbm-dev -name gbm.pc | head -1)
[ -n "$PC" ] || { echo "video-accel: no gbm.pc in libgbm-dev" >&2; exit 1; }
sed -e 's|^prefix=.*|prefix=/usr/local|' \
    -e "s|^libdir=.*|libdir=$LIBDIR|" \
    -e 's|^includedir=.*|includedir=/usr/local/include|' \
    "$PC" > /usr/local/lib/pkgconfig/gbm.pc
TARGET=$(basename "$(readlink -f "$LIBDIR"/libgbm.so.1)")
ln -sf "$TARGET" "$LIBDIR/libgbm.so"

echo "== video-accel: 构建 libva-v4l2（radxa fork，Iris stateful M2M） =="
rm -rf /tmp/libva-v4l2-build
cp -a "$SRC" /tmp/libva-v4l2-build
cd /tmp/libva-v4l2-build
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
rm -rf build
meson setup build >/dev/null
ninja -C build >/dev/null
ninja -C build install >/dev/null

echo "== video-accel: 系统级驱动链接（libva 默认探测路径） =="
# msm_drv_video.so 是 libva 对高通部件的探测名：vaInitialize() 零配置找到
# 后端（Chrome 的 VaapiVideoDecoder 同样走默认探测）。
for n in v4l2_drv_video.so msm_drv_video.so; do
    ln -sf "/usr/local/lib/aarch64-linux-gnu/dri/$n" "/usr/lib/aarch64-linux-gnu/dri/$n"
done

echo "== video-accel: 环境配置（environment.d + profile.d） =="
install -d -m 0755 /etc/environment.d /etc/profile.d
printf 'LIBVA_DRIVER_NAME=v4l2\nLIBVA_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri:/usr/local/lib/aarch64-linux-gnu/dri\nGST_VAAPI_ALL_DRIVERS=1\n' \
    > /etc/environment.d/50-vaapi.conf
printf 'export LIBVA_DRIVER_NAME=v4l2\nexport LIBVA_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri:/usr/local/lib/aarch64-linux-gnu/dri\nexport GST_VAAPI_ALL_DRIVERS=1\n' \
    > /etc/profile.d/vaapi.sh

echo "== video-accel: Chrome VA-API flags（装了 Chrome 才补丁 desktop） =="
# flags 来自 sm8750-video-accel 的 chrome-flags.conf（对 Chrome 155 二进制实证，
# 非照抄教程）。Exec= 行必须以可执行文件开头，否则桌面环境隐藏菜单项。
FLAGS='--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecoder,AcceleratedVideoEncoder,VaapiVideoDecoder,VaapiVideoEncodeAccelerator,VaapiIgnoreDriverChecks --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --ozone-platform-hint=auto'
for F in /usr/share/applications/google-chrome.desktop /usr/share/applications/com.google.Chrome.desktop; do
    [ -f "$F" ] || continue
    [ -f "$F.orig" ] || cp -a "$F" "$F.orig"
    CHROME_FLAGS="$FLAGS" python3 - "$F" <<'PY'
import os, re, sys
path = sys.argv[1]
flags = os.environ["CHROME_FLAGS"]
s = open(path).read()
out = []
for line in s.splitlines(True):
    if line.startswith("Exec=") and "chrome" in line:
        parts = line[5:].rstrip("\n").split(" ", 1)
        exe, rest = parts[0], (parts[1] if len(parts) > 1 else "")
        for opt in ("--enable-features=", "--ozone-platform-hint=", "--enable-zero-copy",
                    "--ignore-gpu-blocklist", "--enable-gpu-rasterization"):
            rest = re.sub(re.escape(opt) + r"\S*\s*", "", rest)
        line = f"Exec={exe} {flags}" + (f" {rest.strip()}" if rest.strip() else "") + "\n"
    out.append(line)
open(path, "w").writelines(out)
PY
    echo "  patched $F"
done

echo "== video-accel: 清理构建依赖（保留小的 -dev 头文件包备用） =="
apt-get purge -y -qq build-essential meson ninja-build >/dev/null
apt-get autoremove -y -qq --purge >/dev/null
rm -rf /tmp/gbm-dev /tmp/libva-v4l2-build /tmp/gbm-dev_*.deb /tmp/libgbm-dev_*.deb
apt-get clean

echo "== video-accel: 完成 =="
ls -l /usr/local/lib/aarch64-linux-gnu/dri/*drv_video.so

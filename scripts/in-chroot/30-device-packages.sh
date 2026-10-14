#!/usr/bin/env bash
# 30-device-packages.sh —— 安装全部设备功能包（/tmp/debs/*.deb）并做设备侧收尾
#
# 对应上游 debian-sheng 的 “Install All .deb Packages” + “Fix Permissions” +
# “Enable Sensor Services” 三步，差异：
#   * 依赖解析失败时报错终止（上游是 `apt-get install /tmp/*.deb || apt-get install -f -y`
#     之后无脑 rm，可能在半配置状态下静默产出坏镜像）
#   * 补上上游缺失的 depmod（内核模块索引）
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/piano-build/in-chroot/30-device-packages.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/piano-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-apt.sh"

shopt -s nullglob
debs=(/tmp/debs/*.deb)
[[ "${#debs[@]}" -gt 0 ]] || die "/tmp/debs 下没有 .deb"

log "待安装设备包（${#debs[@]} 个）："
for d in "${debs[@]}"; do
  printf '    %-42s %s\n' "$(basename "$d")" \
    "$(dpkg-deb -f "$d" Package 2>/dev/null) $(dpkg-deb -f "$d" Version 2>/dev/null)"
done

log "安装中"
if ! apt_install "${debs[@]}"; then
  warn "首次安装失败，尝试 apt-get install -f 修复依赖后重试"
  apt-get install -f -y || true
  apt_install "${debs[@]}" || die "设备包安装失败，请检查上面的依赖错误"
fi

# 版本断言：GNOME 桌面会把发行版的 iio-sensor-proxy 作为 Recommends 带进来，
# 必须以我们自己的版本覆盖（发行版版没有 SSC 后端 → 传感器不工作）。
# 合法来源有两支（run 38523614571 的 deb 清单实证）：
#   * 9999x  —— scripts/packages/build-iio-sensor-proxy.sh 本地构建
#   * *piano1* —— piano-sensors 仓库产物（components job 下载的 3.9-1+piano1）
IIO_VER="$(dpkg-query -W -f='${Version}' iio-sensor-proxy 2>/dev/null || true)"
case "$IIO_VER" in
  "")       warn "iio-sensor-proxy 未安装（本仓库的 deb 可能没装上）" ;;
  9999*)    log "iio-sensor-proxy 使用本仓库版本: $IIO_VER" ;;
  *piano1*) log "iio-sensor-proxy 使用 piano-sensors 版本: $IIO_VER" ;;
  *)        die "iio-sensor-proxy 装成了发行版版本（$IIO_VER），不带 SSC 后端" ;;
esac

# 权限修复：dpkg-deb 打包时统一 644，可执行文件需要显式补权限
log "修复可执行权限"
for f in /usr/sbin/adsprpcd /usr/libexec/iio-sensor-proxy /usr/bin/monitor-sensor /usr/bin/ssccli; do
  if [[ -e "$f" ]]; then
    chmod +x "$f"
    printf '    +x %s\n' "$f"
  else
    printf '    (跳过，不存在) %s\n' "$f"
  fi
done

# depmod（上游缺失）：让 /usr/lib/modules/<kver>/modules.dep 等索引在镜像内就生成
KVER="$(ls -1 /usr/lib/modules 2>/dev/null | head -n1 || true)"
if [[ -n "$KVER" ]]; then
  log "为内核 $KVER 生成模块依赖索引（depmod）"
  depmod -a "$KVER" || warn "depmod 返回非 0（可能已有现成索引）"
  # 与 90-verify.sh 的判定保持一致：这里就硬失败，别等到最后一步才炸
  [[ -f "/usr/lib/modules/$KVER/modules.dep" ]] \
    || die "modules.dep 未生成（$KVER）：模块在设备上无法自动加载"
else
  warn "未找到 /usr/lib/modules/*，内核包可能没有装上"
fi

# 传感器服务（与上游一致）# 拼写务必照抄：unit 文件名与二进制都是 adsprpcd（a-d-s-p-r-p-c-d），
# 上游 workflow 的 enable 步骤把它写成 adsrpcd（少一个 rp）→ 那个 unit 永远启用不了。
# 这里**写死正确文件名**并先判断存在性（不要用通配符：adsrp*cd 与真实名在第 4 个字符
# 就不同，永远匹配不上，会静默走 warn 分支）。
if [[ -f /usr/lib/systemd/system/adsprpcd-sensorspd.service ]]; then
  systemctl enable adsprpcd-sensorspd.service || warn "启用 adsprpcd-sensorspd 失败"
else
  warn "未找到 adsprpcd-sensorspd.service（fastrpc 包可能没装上）"
fi
if [[ -f /usr/lib/systemd/system/sheng-devauth.service ]]; then
  systemctl enable sheng-devauth.service || warn "启用 sheng-devauth 失败"
fi

log "设备包安装完成"

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
all_debs=(/tmp/debs/*.deb)
[[ "${#all_debs[@]}" -gt 0 ]] || die "/tmp/debs 下没有 .deb"

# ── kisak-mesa PPA（run 38534360122 实录）──────────────────────────────────
# piano-mesa resolute 变体的运行期包 Depends libdrm2/libdrm-amdgpu1 >= 2.4.134-3~，
# 而 resolute 归档只有 2.4.131-1：整个 libdrm 家族只有 kisak PPA 提供。
# 做法与上游 debian-piano/scripts/build-rootfs.sh 一致（vendored 钥匙 + 源 + pin），
# 且三者常驻镜像：日后 apt upgrade 也不允许无补丁的 stock mesa 顶掉 piano 版。
if [[ "$DISTRO_SUITE" == "resolute" ]]; then
  KEY=/root/piano-build/assets/kisak-mesa.asc
  [[ -s "$KEY" ]] || die "缺少 kisak PPA 钥匙: $KEY（02-mount-chroot.sh 应拷入 scripts/assets）"
  # 上游教训：钥匙曾被 404 响应体覆盖，症状是 apt 报签名无效而不是文件缺失 → 早断言
  grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$KEY" \
    || die "$KEY 不是 PGP 公钥块（拷贝损坏？）"
  install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d
  install -m 0644 "$KEY" /etc/apt/keyrings/kisak-mesa.asc
  printf 'deb [signed-by=/etc/apt/keyrings/kisak-mesa.asc] %s resolute main\n' \
    "${KISAK_PPA_URL:-https://ppa.launchpadcontent.net/kisak/kisak-mesa/ubuntu}" \
    > /etc/apt/sources.list.d/kisak-mesa.list
  cat > /etc/apt/preferences.d/piano-mesa <<'PIN'
# Keep the piano-mesa build: stock Mesa lacks the Adreno 830 patches.
Package: src:mesa
Pin: version *+piano*
Pin-Priority: 1001
PIN
  log "已加入 kisak-mesa PPA（resolute）与 piano-mesa pin，刷新 apt 索引"
  apt_update
else
  die "piano-mesa deb 是 resolute 构建（依赖 PPA 的 libdrm >= 2.4.134），当前 suite=$DISTRO_SUITE 未支持"
fi

# ── 选择要安装的 deb ───────────────────────────────────────────────────────
# 两道过滤（证据：run 38534360122 的 unmet deps 清单）：
#   1) *-dev / *-dbgsym / *-dbg 不进运行镜像（与 piano-mesa build-mesa-debs.sh
#      的 runtime/ 分组同口径）；它们会拖出 libgl-dev/libglvnd-dev/libdrm-dev/
#      libglib2.0-dev/libqmi-glib-dev 一整条开发依赖链。
#   2) mesa 运行期包只装上游 MESA_CORE 白名单 + 替换已装的 stock mesa。
#      mesa 二进制互相 Depends 精确版本，已装的会被强制成套升级；白名单外
#      （如 mesa-opencl-icd）不装，避免拖进整条 clang-21 依赖链。
MESA_CORE=' mesa-libgallium libgbm1 libegl-mesa0 libglx-mesa0 mesa-vulkan-drivers '
debs=()
for d in "${all_debs[@]}"; do
  pkg="$(dpkg-deb -f "$d" Package 2>/dev/null)" || die "读不到包名: $d"
  case "$pkg" in
    *-dev|*-dbgsym|*-dbg)
      log "跳过开发/符号包: $pkg"
      continue ;;
  esac
  src="$(dpkg-deb -f "$d" Source 2>/dev/null || true)"
  # shellcheck disable=SC2016 # dpkg-query 格式串，不是 shell 展开
  if [[ "$src" == mesa ]] \
     && [[ $MESA_CORE != *" $pkg "* ]] \
     && [[ "$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true)" != installed ]]; then
    log "跳过非核心 mesa 包: $pkg（MESA_CORE 白名单外且当前未装）"
    continue
  fi
  debs+=("$d")
done
[[ "${#debs[@]}" -gt 0 ]] || die "过滤后没有可安装的 deb"

log "待安装设备包（${#debs[@]}/${#all_debs[@]} 个）："
for d in "${debs[@]}"; do
  printf '    %-42s %s\n' "$(basename "$d")" \
    "$(dpkg-deb -f "$d" Package 2>/dev/null) $(dpkg-deb -f "$d" Version 2>/dev/null)"
done

# --no-install-recommends：上游装设备 deb 同款口径（fastrpc-support 的
# Recommends hexagon-dsp-binaries 无候选源、不该进镜像；硬 Depends 照常解析）。
log "安装中"
if ! apt-get install "${APT_OPTS[@]}" --no-install-recommends "${debs[@]}"; then
  warn "首次安装失败，尝试 apt-get install -f 修复依赖后重试"
  apt-get install -f -y || true
  apt-get install "${APT_OPTS[@]}" --no-install-recommends "${debs[@]}" \
    || die "设备包安装失败，请检查上面的依赖错误"
fi

# 上游同款收尾断言：不允许任何未打 Adreno 830 补丁的 stock mesa 残留
# shellcheck disable=SC2016
stale="$(dpkg-query -W -f='${source:Package} ${Package} ${Version} ${db:Status-Status}\n' \
  | awk '$1 == "mesa" && $4 == "installed" && $3 !~ /[+]piano/')"
[[ -z "$stale" ]] || die "残留未打补丁的 stock mesa：$(tr '\n' ' ' <<<"$stale")"

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

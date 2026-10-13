#!/usr/bin/env bash
# ci/build-piano.sh — piano-kubuntu orchestrator (dual-boot Kubuntu 26.04).
#
# Faithful adaptation of blu-sharky/xiaomi-piano-linux scripts/build-rootfs-image.sh
# (workspace pin a75f8c5d) to the dual-boot profile. Differences vs upstream are
# marked "KUBUNTU-DIFF" inline; everything else mirrors the upstream sequence so
# the proven boot contract stays intact.
#
# Usage:
#   ci/build-piano.sh [--stage kernel|rootfs|images|all] [upstream options...]
#
# KUBUNTU-DIFF summary (vs scripts/build-rootfs-image.sh @ a75f8c5d):
#   - rootfs suite: resolute (Ubuntu 26.04) via our build-rootfs.sh, not trixie
#   - kernel cmdline: root=PARTLABEL=linux-root (injected into
#     piano_rootfs.config by the workflow; this script asserts it)
#   - kernel release suffix: -piano-kde (injected by the workflow)
#   - MANIFEST wording: dual-boot safety lines, device-tested: no
#   - arm64-tools fetched into the output tree when missing
#   - boot.img requires AVB signing for cold boot (done by the workflow via
#     scripts/sign-boot-avb.sh); RAM boot works unsigned
set -euo pipefail

usage() { sed -n '2,30p' "$0"; exit 2; }
die() { echo "build-piano: error: $*" >&2; exit 1; }

STAGE=all JOBS=$(nproc) OUTPUT='' BASE='' KEYS='' SIZE=8G
# Advanced Configuration（spec §3）：由 workflow 输入经 flag 传入，转发给 build-rootfs.sh
USERNAME='' PASSWORD='' HOSTNAME='' LANGUAGE='' TIMEZONE='' SSH_AUTH='' DESKTOP='' EXTRAS=''
KERNEL_TREE='' FW_TREE='' MESA_DIR='' SENSORS_DIR='' TOPOLOGY='' LOOPBACK=''

while [ $# -gt 0 ]; do
    case "$1" in
        --stage) STAGE=${2:?}; shift 2 ;;
        --jobs) JOBS=${2:?}; shift 2 ;;
        --username) USERNAME=${2:?}; shift 2 ;;
        --password) PASSWORD=${2:?}; shift 2 ;;
        --hostname) HOSTNAME=${2:?}; shift 2 ;;
        --language) LANGUAGE=${2:?}; shift 2 ;;
        --timezone) TIMEZONE=${2:?}; shift 2 ;;
        --ssh-auth) SSH_AUTH=${2:?}; shift 2 ;;
        --desktop) DESKTOP=${2:?}; shift 2 ;;
        --extras) EXTRAS=${2:?}; shift 2 ;;
        --output) OUTPUT=$(realpath -m "${2:?}"); shift 2 ;;
        --rootfs-build) BASE=$(realpath "${2:?}"); shift 2 ;;
        --authorized-keys) KEYS=$(realpath "${2:?}"); shift 2 ;;
        --image-size) SIZE=${2:?}; shift 2 ;;
        --kernel-tree) KERNEL_TREE=$(realpath "${2:?}"); shift 2 ;;
        --firmware-tree) FW_TREE=$(realpath "${2:?}"); shift 2 ;;
        --mesa-dir) MESA_DIR=$(realpath "${2:?}"); shift 2 ;;
        --sensors-dir) SENSORS_DIR=$(realpath "${2:?}"); shift 2 ;;
        --audioreach-topology) TOPOLOGY=$(realpath "${2:?}"); shift 2 ;;
        --v4l2loopback) LOOPBACK=$(realpath "${2:?}"); shift 2 ;;
        -h|--help) usage ;;
        *) die "unknown option: $1" ;;
    esac
done
case "$STAGE" in kernel|rootfs|images|all) ;; *) die '--stage must be kernel|rootfs|images|all' ;;
esac
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be positive (got '$JOBS')"
[ -n "$OUTPUT" ] || die '--output is required'
# 多 job 流水线会分次调用本脚本（--stage kernel 后再 --stage images），
# 因此只有 --stage all 要求输出目录全新；单阶段允许复用同一输出目录。
if [ "$STAGE" = all ] && [ -e "$OUTPUT" ]; then
    die 'output exists; choose a fresh directory'
fi
# 多 job 拆分后，rootfs 阶段不需要内核树；内核相关断言只在内核/镜像阶段生效
# （多 job 工作流：components → rootfs → kernel-images）。
if [ "$STAGE" != rootfs ]; then
    [ -n "$KERNEL_TREE" ] || die '--kernel-tree is required'
    [ -f "$KERNEL_TREE/Makefile" ] || die "$KERNEL_TREE does not look like a kernel tree"
    [ -f "$KERNEL_TREE/arch/arm64/configs/piano_defconfig" ] || die 'piano_defconfig missing'
    # KUBUNTU-DIFF: the workflow must have injected the dual-boot cmdline and
    # release suffix before calling us; assert instead of trusting.
    ROOTCFG="$KERNEL_TREE/arch/arm64/configs/piano_rootfs.config"
    grep -q 'root=PARTLABEL=linux-root' "$ROOTCFG" || die 'piano_rootfs.config lacks root=PARTLABEL=linux-root (workflow injection missing)'
    grep -q 'root=PARTLABEL=userdata' "$ROOTCFG" && die 'piano_rootfs.config still contains root=PARTLABEL=userdata'
    grep -q 'CONFIG_LOCALVERSION="-piano-kde"' "$ROOTCFG" || die 'piano_rootfs.config lacks the -piano-kde release suffix'
else
    KERNEL_TREE=${KERNEL_TREE:-.}
fi

# 工具检查同样按阶段区分：rootfs 阶段不需要内核编译工具链
# （多 job 下每个 job 只装自己需要的依赖；冒烟 run 38425831233 实证：
#   rootfs job 未装 clang/lld，统一检查会以 missing ld.lld 失败）。
if [ "$STAGE" != rootfs ]; then
    for cmd in clang ld.lld cpio depmod modinfo dtc python3 mkfs.ext4 dumpe2fs; do
        command -v "$cmd" >/dev/null || die "missing $cmd"
    done
else
    for cmd in debootstrap chroot; do
        command -v "$cmd" >/dev/null || die "missing $cmd"
    done
    [ "$(id -u)" = 0 ] || command -v sudo >/dev/null || die 'sudo or root is required for the rootfs stage'
fi

REPO=$(cd "$(dirname "$0")/.." && pwd)
D=$REPO/debian-piano
K=$KERNEL_TREE
O=$K/out/rootfs-image
STAGE_DIR=$OUTPUT/stage
TOOLS=$OUTPUT/arm64-tools
ROOT=()
if [ "$STAGE" != kernel ]; then
    if [ "$(id -u)" != 0 ]; then ROOT=(sudo); sudo -v; fi
fi
mkdir -p "$OUTPUT" "$STAGE_DIR"
OUTPUT=$(realpath "$OUTPUT")
if [ -z "$KEYS" ]; then
    ssh-keygen -q -t ed25519 -N '' -C piano -f "$OUTPUT/access-key"
    KEYS=$OUTPUT/access-key.pub
fi

MAKE=(make -C "$K" ARCH=arm64 LLVM=1 O="$O")
if command -v ccache >/dev/null; then MAKE+=("CC=ccache clang"); fi

stage_kernel() {
    mkdir -p "$O"
    "${MAKE[@]}" piano_defconfig
    # piano_rootfs.config is a kconfig fragment merged after piano_defconfig
    # (upstream recipe; do not "simplify" into a single defconfig).
    "$K/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" "$ROOTCFG"
    "${MAKE[@]}" olddefconfig
    rm -f "$O/include/config/kernel.release" "$O/include/generated/utsrelease.h" "$O/.version"
    "${MAKE[@]}" prepare
    find "$O" \( -name '*.mod.c' -o -name '*.ko' \) -delete
    "${MAKE[@]}" -j"$JOBS" Image modules
    KVER=$(cat "$O/include/config/kernel.release")
    "${MAKE[@]}" -j"$JOBS" modules_install INSTALL_MOD_PATH="$STAGE_DIR/modules" INSTALL_MOD_STRIP=1
    if [ -n "$LOOPBACK" ]; then
        cp -a "$LOOPBACK" "$STAGE_DIR/v4l2loopback"
        rm -rf "$STAGE_DIR/v4l2loopback/.git"
        "${MAKE[@]}" -j"$JOBS" M="$STAGE_DIR/v4l2loopback" modules
        "${MAKE[@]}" M="$STAGE_DIR/v4l2loopback" modules_install INSTALL_MOD_PATH="$STAGE_DIR/modules" \
            INSTALL_MOD_DIR=updates INSTALL_MOD_STRIP=1
    fi
    # Upstream gate: every installed module must carry the built release.
    while IFS= read -r -d '' ko; do
        [[ "$(modinfo -F vermagic "$ko")" == "$KVER "* ]] || { echo "Stale module: $ko" >&2; exit 1; }
    done < <(find "$STAGE_DIR/modules" -name '*.ko*' -print0)
    echo "build-piano: kernel OK ($KVER)"
}

stage_rootfs() {
    if [ -z "$BASE" ]; then
        BASE=$OUTPUT/rootfs-build
        "${ROOT[@]}" "$D/scripts/build-rootfs.sh" --suite resolute --output "$BASE" --authorized-keys "$KEYS" \
            ${MESA_DIR:+--mesa-dir "$MESA_DIR"} ${SENSORS_DIR:+--userspace-dir "$SENSORS_DIR"} \
            ${USERNAME:+--username "$USERNAME"} ${PASSWORD:+--password "$PASSWORD"} \
            ${HOSTNAME:+--hostname "$HOSTNAME"} ${LANGUAGE:+--language "$LANGUAGE"} \
            ${TIMEZONE:+--timezone "$TIMEZONE"} ${SSH_AUTH:+--ssh-auth "$SSH_AUTH"} \
            ${DESKTOP:+--desktop "$DESKTOP"} ${EXTRAS:+--extras "$EXTRAS"}
    fi
    [ -f "$BASE/COMPLETE" ] || die 'Rootfs bootstrap incomplete'
    # A reused base gets the same key as the new rescue image.
    RB_USER=${USERNAME:-piano}
    for home in root "home/$RB_USER"; do
        "${ROOT[@]}" install -m 0600 "$KEYS" "$BASE/rootfs/$home/.ssh/authorized_keys"
    done
    "${ROOT[@]}" chroot "$BASE/rootfs" chown -R "$RB_USER:$RB_USER" "/home/$RB_USER/.ssh"
    echo "build-piano: rootfs OK ($BASE)"
}

stage_images() {
    [ -n "${KVER:-}" ] || KVER=$(cat "$O/include/config/kernel.release")
    [ -d "$STAGE_DIR/modules/lib/modules/$KVER" ] || die 'kernel stage outputs missing (run --stage kernel first)'
    [ -n "$BASE" ] && [ -f "$BASE/COMPLETE" ] || die 'rootfs stage outputs missing (run --stage rootfs first)'
    [ -d "$TOOLS" ] || "$D/scripts/fetch-arm64-tools.sh" --output-dir "$TOOLS"
    FW_ARGS=()
    if [ -n "$FW_TREE" ]; then
        echo "build-piano: verifying firmware tree $FW_TREE"
        (cd "$FW_TREE" && sha256sum --check SHA256SUMS)
        cp -a "$FW_TREE" "$STAGE_DIR/firmware"
        FW_ARGS=(--firmware-dir "$STAGE_DIR/firmware")
        [ -z "$TOPOLOGY" ] || "$D/scripts/build-topology.sh" "$TOPOLOGY" "$STAGE_DIR/firmware"
    else
        die '--firmware-tree is required (dual boot never ships without audio topology inputs)'
    fi
    "${MAKE[@]}" headers_install INSTALL_HDR_PATH="$STAGE_DIR/uapi"
    "$D/scripts/build-touch-view.sh" --uapi "$STAGE_DIR/uapi" --sysroot "$TOOLS/musl-sysroot" --output "$STAGE_DIR/piano-touch-view"
    "$D/scripts/build-touch-view.sh" --uapi "$STAGE_DIR/uapi" --sysroot "$TOOLS/musl-sysroot" \
        --source "$D/camera/piano-camerad.c" --output "$STAGE_DIR/piano-camerad"
    # Neither UFS host nor PHY may probe before the initramfs debug network.
    UFS_MODULES=()
    for module in phy_qcom_qmp_ufs ufs_qcom; do
        dependencies=$(modprobe -S "$KVER" -d "$STAGE_DIR/modules" --show-depends "$module")
        while read -r kind ko rest; do
            [ "$kind" != insmod ] || UFS_MODULES+=(--module "$ko")
        done <<< "$dependencies"
    done
    [ "${#UFS_MODULES[@]}" -gt 0 ] || die 'Missing UFS module closure'
    "$D/scripts/build-initramfs.sh" --mode rootfs --busybox "$TOOLS/busybox" \
        --dropbear-tree "$TOOLS/dropbear/tree" --authorized-keys "$KEYS" \
        --kernel-version "$KVER" "${UFS_MODULES[@]}" --output "$STAGE_DIR/initramfs.cpio.gz"
    "$K/scripts/config" --file "$O/.config" --set-str INITRAMFS_SOURCE "$STAGE_DIR/initramfs.cpio.gz"
    "${MAKE[@]}" olddefconfig
    for option in CONFIG_CMDLINE_FORCE=y CONFIG_EXT4_FS=y CONFIG_DRM_SIMPLEDRM=y \
        CONFIG_SCSI_UFSHCD=m CONFIG_SCSI_UFS_QCOM=m CONFIG_PHY_QCOM_QMP_UFS=m CONFIG_USB_CONFIGFS_NCM=y \
        CONFIG_PINCTRL_SM8750=m CONFIG_QCOM_GPI_DMA=m CONFIG_PHY_QCOM_QMP_PCIE=m; do
        grep -qxF "$option" "$O/.config" || die "Required: $option"
    done
    "${MAKE[@]}" -j"$JOBS" Image
    [ "$(cat "$O/include/config/kernel.release")" = "$KVER" ] || die 'kernel release changed after INITRAMFS_SOURCE rebuild'
    # Upstream rootfs mode: boot.img (v4, kernel-embedded initramfs, empty
    # external ramdisk) + dtbo from dtbo-piano-power.dts; provenance-gated
    # params; round-trip verified inside the script.
    "$D/scripts/build-test-bootimg.sh" --kernel-dir "$O" --output-dir "$OUTPUT" \
        --kernel-include "$K/include" \
        --dtbo-source "$D/boot/dtbo-piano-power.dts" --mode rootfs
    "${ROOT[@]}" "$D/scripts/assemble-rootfs-image.sh" --rootfs "$BASE/rootfs" \
        --modules "$STAGE_DIR/modules" --kernel-release "$KVER" "${FW_ARGS[@]}" \
        --touch-view "$STAGE_DIR/piano-touch-view" --camera-daemon "$STAGE_DIR/piano-camerad" --busybox "$TOOLS/busybox/busybox" \
        --output-dir "$OUTPUT" --image-size "$SIZE"
    cp "$BASE/build-manifest.txt" "$OUTPUT/packages.txt"
    cp "$O/.config" "$OUTPUT/kernel.config"
    {
        sha256sum "$ROOTCFG" "$REPO/ci/build-piano.sh"
        (cd "$D" && git ls-files -z --cached --others --exclude-standard | sort -zu | xargs -0 sha256sum)
    } > "$OUTPUT/SOURCE-SHA256SUMS"
    {
        echo "Piano Kubuntu dual-boot image set"
        if [ -n "$FW_TREE" ]; then
            echo "firmware=piano-firmware $(git -C "$FW_TREE" rev-parse HEAD 2>/dev/null || echo unknown); see its README compliance statement"
        fi
        echo "kernel=$KVER"
        for repo in "$REPO" "$K"; do
            echo "source=$repo $(git -C "$repo" rev-parse HEAD)"
            git -C "$repo" diff --binary HEAD | sha256sum
        done
        echo 'KUBUNTU-DIFF: root=PARTLABEL=linux-root; ext4; KDE Plasma (resolute); device-tested: no'
        echo 'Dual boot: slot A stays stock Android; only boot_b/dtbo_b and the linux-root partition are ours.'
        echo 'WARNING: writing the linux-root partition is irreversible for its contents; keep persist untouched.'
        echo 'WARNING: flashing userdata destroys Android data; never fastboot flash userdata.'
        echo 'Keep stock slot A, vendor_boot and init_boot. Never flash bootloader-chain partitions.'
        echo 'Check current-slot=b and partition sizes before any write; RAM boot preferred.'
        (cd "$OUTPUT" && sha256sum boot.img dtbo.img kernel.config SOURCE-SHA256SUMS)
        (cd "$OUTPUT" && sha256sum userdata.img userdata.raw.img packages.txt)
    } > "$OUTPUT/MANIFEST.txt"
    echo "Built $OUTPUT; see MANIFEST.txt. No device writes performed."
}

case "$STAGE" in
    kernel) stage_kernel ;;
    rootfs) stage_rootfs ;;
    images) stage_images ;;
    all)    stage_kernel; stage_rootfs; stage_images ;;
esac

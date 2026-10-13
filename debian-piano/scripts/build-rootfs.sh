#!/usr/bin/env bash
# Build a firmware-free Kubuntu (Ubuntu resolute 26.04 + KDE Plasma) arm64 tree.
# Local image assembly adds hardware inputs.
# Usage: build-rootfs.sh --suite resolute --output DIR [--authorized-keys FILE] [--userspace-dir DIR] [--mesa-dir DIR]
# Adapted from blu-sharky debian-piano (trixie/GNOME baseline), commit a75f8c5d.
# Suite facts verified 2026-10-09: 26.04 LTS = resolute; arm64 served from
# archive.ubuntu.com (Release lists arm64); debootstrap suite script may be
# missing on a noble runner -- install debootstrap from resolute updates then
# (1.0.142ubuntu2 carries the resolute script).
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
SUITE=resolute OUTDIR='' KEYS='' USERSPACE_DIR='' MESA_DIR=''
die() { echo "build-rootfs: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --suite) SUITE=${2:?}; shift 2 ;;
        --output) OUTDIR=${2:?}; shift 2 ;;
        --authorized-keys) KEYS=$(realpath "${2:?}"); shift 2 ;;
        --userspace-dir) USERSPACE_DIR=$(realpath "${2:?}"); shift 2 ;;
        --mesa-dir) MESA_DIR=$(realpath "${2:?}"); shift 2 ;;
        -h|--help) echo 'Usage: build-rootfs.sh --suite resolute --output DIR [--authorized-keys FILE] [--userspace-dir DIR] [--mesa-dir DIR]'; exit 0 ;;
        *) die "unknown option $1" ;;
    esac
done
[ "$SUITE" = resolute ] || die 'this desktop profile supports resolute (Ubuntu 26.04) only'
[ -n "$OUTDIR" ] || die '--output is required'
[ "$(id -u)" = 0 ] || die 'run with sudo (debootstrap and chroot mounts require root)'
for tool in debootstrap chroot curl ssh-keygen openssl mount umount; do
    command -v "$tool" >/dev/null 2>&1 || die "missing $tool"
done
if ! grep -qs "^$SUITE\$" /usr/share/debootstrap/scripts/sid /usr/share/debootstrap/scripts/gutsy 2>/dev/null && \
   [ ! -e "/usr/share/debootstrap/scripts/$SUITE" ]; then
    die "debootstrap lacks the $SUITE suite script; install a newer debootstrap (resolute updates carries 1.0.142ubuntu2)"
fi
KEYRING=${UBUNTU_ARCHIVE_KEYRING:-/usr/share/keyrings/ubuntu-archive-keyring.gpg}
[ -s "$KEYRING" ] || die 'install ubuntu-archive-keyring or set UBUNTU_ARCHIVE_KEYRING'
[ -z "$KEYS" ] || [ -s "$KEYS" ] || die 'empty authorized keys'
QEMU=
if [ "$(uname -m)" != aarch64 ]; then
    QEMU=$(command -v qemu-aarch64-static) || die 'install qemu-aarch64-static'
    grep -q '^enabled' /proc/sys/fs/binfmt_misc/qemu-aarch64 || die 'enable qemu-aarch64 binfmt first'
fi
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=$(realpath -m "$OUTDIR")
[ ! -e "$OUTDIR" ] || die 'output exists; choose a new directory'
MIRROR=${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
curl -fsI --max-time 30 "$MIRROR/dists/$SUITE/Release" >/dev/null
mkdir -p "$OUTDIR/rootfs"
ROOTFS=$OUTDIR/rootfs
# Install the trap before the first mount; never propagate unmounts to the host.
cleanup() {
    for d in dev/pts dev sys proc; do
        if mountpoint -q "$ROOTFS/$d"; then umount "$ROOTFS/$d"; fi
    done
}
trap cleanup EXIT
if [ -z "$KEYS" ]; then
    ssh-keygen -q -t ed25519 -N '' -C piano -f "$OUTDIR/access-key"
    KEYS=$OUTDIR/access-key.pub
fi
debootstrap --arch=arm64 --variant=minbase \
    --components=main,restricted,universe,multiverse --keyring="$KEYRING" --foreign \
    "$SUITE" "$ROOTFS" "$MIRROR"
[ -z "$QEMU" ] || install -m 0755 "$QEMU" "$ROOTFS/usr/bin/qemu-aarch64-static"
chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
mount -t proc proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"
mount --make-slave "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount --make-slave "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount --make-slave "$ROOTFS/dev/pts"
# Suppress service starts and kernel/initramfs hooks inside the build chroot.
printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"
cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE main restricted universe multiverse
deb $MIRROR $SUITE-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $SUITE-security main restricted universe multiverse
EOF
# Bootstrap has no CA store yet; install it using the authenticated archive.
printf 'deb %s %s main restricted universe multiverse\n' "$MIRROR" "$SUITE" > "$ROOTFS/etc/apt/sources.list.d/bootstrap.list"
chroot "$ROOTFS" apt-get -o Dir::Etc::sourcelist=sources.list.d/bootstrap.list -o Dir::Etc::sourceparts=- update
chroot "$ROOTFS" apt-get -o Dir::Etc::sourcelist=sources.list.d/bootstrap.list -o Dir::Etc::sourceparts=- install -y ca-certificates
rm "$ROOTFS/etc/apt/sources.list.d/bootstrap.list"
# Google Chrome official arm64 build (dl.google.com serves arch=arm64;
# install pattern from Droidspaces configure-chrome.sh, verified on resolute).
install -d -m 0755 "$ROOTFS/etc/apt/keyrings" "$ROOTFS/etc/apt/sources.list.d"
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    -o "$ROOTFS/etc/apt/keyrings/google-chrome.asc"
grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$ROOTFS/etc/apt/keyrings/google-chrome.asc" \
    || die 'Google signing key download failed'
printf 'deb [arch=arm64 signed-by=/etc/apt/keyrings/google-chrome.asc] https://dl.google.com/linux/chrome/deb/ stable main\n' \
    > "$ROOTFS/etc/apt/sources.list.d/google-chrome.list"
# Snap must never come back via dependency resolution: pin it away like
# Droidspaces nosnap.sh does (chromium-browser is a snap transition package).
mkdir -p "$ROOTFS/etc/apt/preferences.d"
cat > "$ROOTFS/etc/apt/preferences.d/nosnap.pref" <<'PIN'
Package: snapd snapd-desktop-integration gnome-software-plugin-snap plasma-discover-backend-snap
Pin: release a=*
Pin-Priority: -10

Package: chromium-browser
Pin: release o=Ubuntu
Pin-Priority: -10
PIN
# kisak-mesa PPA: the piano-mesa resolute debs depend on libdrm (>= 2.4.134),
# which only the PPA ships for resolute (archive has 2.4.131; verified
# 2026-10-09 — the PPA carries the whole libdrm family, uncompressed Packages
# paths 404, use the index apt resolves itself).
install -d -m 0755 "$ROOTFS/etc/apt/keyrings" "$ROOTFS/etc/apt/sources.list.d"
install -m 0644 "$REPO/apt/kisak-mesa.asc" "$ROOTFS/etc/apt/keyrings/kisak-mesa.asc"
printf 'deb [signed-by=/etc/apt/keyrings/kisak-mesa.asc] https://ppa.launchpadcontent.net/kisak/kisak-mesa/ubuntu resolute main\n' \
    > "$ROOTFS/etc/apt/sources.list.d/kisak-mesa.list"
mapfile -t PKGS < <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$REPO/rootfs/packages.txt")
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"
# Ubuntu has no trixie-backports analogue; resolute's base (kernel/userland)
# is newer than anything the backports profile provided, so the upstream
# packages-backports.txt stage is intentionally dropped.
if [ -n "$USERSPACE_DIR" ]; then
    shopt -s nullglob
    DEBS=("$USERSPACE_DIR"/*.deb)
    [ "${#DEBS[@]}" -gt 0 ] || die 'no userspace debs found'
    mkdir -p "$ROOTFS/tmp/piano-packages"
    cp "${DEBS[@]}" "$ROOTFS/tmp/piano-packages/"
    chroot "$ROOTFS" sh -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/piano-packages/*.deb'
    rm -r "$ROOTFS/tmp/piano-packages"
fi
if [ -n "$MESA_DIR" ]; then
    # piano-mesa runtime packages: Debian's backported Mesa with the
    # Adreno 830 patches, rebuilt by piano-mesa CI; the pin keeps stock
    # Mesa (without the patches, i.e. without the GPU) from replacing it.
    shopt -s nullglob
    DEBS=("$MESA_DIR"/*.deb)
    [ "${#DEBS[@]}" -gt 0 ] || die "no Mesa packages in $MESA_DIR"
    cat > "$ROOTFS/etc/apt/preferences.d/piano-mesa" <<'PIN'
# Keep the piano-mesa build: stock Mesa lacks the Adreno 830 patches.
Package: src:mesa
Pin: version *+piano*
Pin-Priority: 1001
PIN
    chroot "$ROOTFS" apt-get update
    mkdir -p "$ROOTFS/tmp/piano-mesa"
    cp "${DEBS[@]}" "$ROOTFS/tmp/piano-mesa/"
    # Mesa's binary packages depend on each other at the exact version:
    # replace every installed one and add the core set.
    MESA_CORE=' mesa-libgallium libgbm1 libegl-mesa0 libglx-mesa0 mesa-vulkan-drivers '
    SELECTED=()
    for deb in "$ROOTFS"/tmp/piano-mesa/*.deb; do
        pkg=$(chroot "$ROOTFS" dpkg-deb -f "/tmp/piano-mesa/${deb##*/}" Package)
        # shellcheck disable=SC2016 # dpkg-query format, not a shell expansion
        if [[ $MESA_CORE != *" $pkg "* ]] &&
           ! chroot "$ROOTFS" dpkg-query -W -f '${db:Status-Status}' "$pkg" 2>/dev/null | grep -qx installed; then
            continue
        fi
        SELECTED+=("/tmp/piano-mesa/${deb##*/}")
    done
    chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends "${SELECTED[@]}"
    rm -r "$ROOTFS/tmp/piano-mesa"
    # shellcheck disable=SC2016 # dpkg-query format, not a shell expansion
    stale=$(chroot "$ROOTFS" dpkg-query -W -f '${source:Package} ${Package} ${Version} ${db:Status-Status}\n' \
        | awk '$1 == "mesa" && $4 == "installed" && $3 !~ /[+]piano/')
    [ -z "$stale" ] || die "Mesa packages without the piano patches remain: $stale"
fi
# Purge any snap components that slipped in through the desktop seed; the
# pin above already blocks reinstall (Droidspaces nosnap.sh discipline).
for pkg in snapd snapd-desktop-integration gnome-software-plugin-snap plasma-discover-backend-snap; do
    if chroot "$ROOTFS" dpkg -s "$pkg" >/dev/null 2>&1; then
        chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg"
    fi
done
chroot "$ROOTFS" apt-get autoremove -y --purge
# The checkout belongs to the building user; the rootfs must stay root-owned.
cp -a --no-preserve=ownership "$REPO/rootfs/overlay/." "$ROOTFS/"
find "$ROOTFS/usr/lib/piano" "$ROOTFS/usr/local/bin" -type f -exec chmod 0755 {} +
chroot "$ROOTFS" useradd -m -s /bin/bash -G sudo,audio,video,input,render piano
PASSWORD=$(openssl rand -base64 18)
printf 'piano:%s\n' "$PASSWORD" | chroot "$ROOTFS" chpasswd
chroot "$ROOTFS" passwd -l root
(umask 077; printf 'User: piano\nPassword: %s\nKDE Plasma (SDDM) autologin is enabled. SSH uses keys only.\n' "$PASSWORD" > "$OUTDIR/login.txt")
for home in root home/piano; do
    install -d -m 0700 "$ROOTFS/$home/.ssh"
    install -m 0600 "$KEYS" "$ROOTFS/$home/.ssh/authorized_keys"
done
chroot "$ROOTFS" chown -R piano:piano /home/piano
printf 'piano\n' > "$ROOTFS/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 piano\n::1 localhost ip6-localhost\n' > "$ROOTFS/etc/hosts"
printf 'en_US.UTF-8 UTF-8\nzh_CN.UTF-8 UTF-8\n' > "$ROOTFS/etc/locale.gen"
chroot "$ROOTFS" locale-gen
printf 'LANG=zh_CN.UTF-8\n' > "$ROOTFS/etc/default/locale"
# Chinese workflow: Asia/Shanghai timezone (pattern from Droidspaces zh_tz).
chroot "$ROOTFS" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo 'Asia/Shanghai' > "$ROOTFS/etc/timezone"
chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive tzdata
chroot "$ROOTFS" systemctl enable NetworkManager ssh bluetooth piano-usb piano-touch piano-radio piano-adsp piano-audio piano-video piano-camera piano-camerad piano-keyboard piano-cpufreq piano-hostkeys piano-swapfile
chroot "$ROOTFS" systemctl set-default graphical.target
ln -sf /usr/lib/systemd/system/sddm.service "$ROOTFS/etc/systemd/system/display-manager.service"
# Preserve the bootloader display: neither suspend nor blanking is recoverable yet.
chroot "$ROOTFS" systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
rm -f "$ROOTFS/etc/ssh/ssh_host_"* "$ROOTFS/usr/sbin/policy-rc.d"
: > "$ROOTFS/etc/machine-id"
rm -f "$ROOTFS/var/lib/dbus/machine-id"
ln -sf /etc/machine-id "$ROOTFS/var/lib/dbus/machine-id"
rm -f "$ROOTFS/etc/resolv.conf"
ln -s /run/NetworkManager/resolv.conf "$ROOTFS/etc/resolv.conf"
{
    echo "suite=$SUITE arch=arm64 desktop=kde firmware=not-included"
    # shellcheck disable=SC2016
    chroot "$ROOTFS" dpkg-query -W -f='${Package} ${Version}\n'
} > "$OUTDIR/build-manifest.txt"
chroot "$ROOTFS" apt-get clean
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"
cleanup
trap - EXIT
touch "$OUTDIR/COMPLETE"
echo "Rootfs: $ROOTFS; credentials: $OUTDIR/login.txt"

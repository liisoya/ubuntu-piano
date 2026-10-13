#!/usr/bin/env bash
# build-mesa-debs.sh — rebuild Ubuntu/kisak Mesa with the piano patch.
#
# Usage (as root, in an Ubuntu resolute arm64 system or container):
#   scripts/build-mesa-debs.sh OUTPUT_DIR
#
# Adapted from blu-sharky/piano-mesa scripts/build-mesa-debs.sh (MIT) for the
# Kubuntu resolute profile. Facts verified 2026-10-09:
#   - No released Mesa carries the Adreno 830v1 chip id (0xffff44050001):
#     resolute has 26.0.8 (no real A830 device), Debian bpo 26.1.6 and kisak
#     26.2.4 have the real A830 device but not the v1 id (Mesa 2061a5ee,
#     MR !43878, merged 2026-08-19, still main-only).
#   - Base source: kisak-mesa PPA resolute build (26.2.4~kisak1~r at the time
#     of writing) — real A830 device definition, built for resolute, so the
#     resulting debs' Depends resolve against resolute libraries.
#   - The single upstream patch applies cleanly to mesa-26.2.4 (dry-run
#     verified, offset -22).
# Output:
#   OUTPUT_DIR/all/      every binary package of the build
#   OUTPUT_DIR/runtime/  the same without -dev and debug symbol packages
#   OUTPUT_DIR/SHA256SUMS
set -euo pipefail

OUTPUT=${1:?usage: build-mesa-debs.sh OUTPUT_DIR}
REPO=$(cd "$(dirname "$0")/.." && pwd)
BUILD_ROOT=/build/mesa
PPA_URL=${KISAK_PPA_URL:-https://ppa.launchpadcontent.net/kisak/kisak-mesa/ubuntu}
# Signing fingerprint taken from the signed InRelease of the PPA
# (gpg --status-fd ERRSIG issuer fpr), keyserver-verified 2026-10-09.
PPA_KEY=${KISAK_KEY_FINGERPRINT:-EB8B81E14DA65431D7504EA8F63F0F2B90935439}

die() { echo "build-mesa-debs: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die 'run as root'
[ "$(dpkg --print-architecture)" = arm64 ] || die 'arm64 only'
mkdir -p "$OUTPUT"
OUTPUT=$(realpath "$OUTPUT")

export DEBIAN_FRONTEND=noninteractive
# The bare ubuntu image has neither curl nor ca-certificates: bootstrap the
# fetch tooling from the resolute base repos BEFORE adding the kisak source.
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gpg
# deb-src for the resolute base (the ubuntu container image ships deb-only
# deb822 sources); kisak PPA as deb + deb-src with its signing key.
cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/piano-deb-src.sources
sed -i 's/^Types: deb$/Types: deb-src/' /etc/apt/sources.list.d/piano-deb-src.sources
install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
keyring=/etc/apt/keyrings/kisak-mesa.asc
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$PPA_KEY" -o "$keyring" \
    || die 'failed to fetch the kisak PPA signing key from keyserver.ubuntu.com'
grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$keyring" || die 'kisak key download is not a PGP key block'
printf 'deb [signed-by=%s] %s resolute main\ndeb-src [signed-by=%s] %s resolute main\n' \
    "$keyring" "$PPA_URL" "$keyring" "$PPA_URL" \
    > /etc/apt/sources.list.d/piano-kisak.list
apt-get update
apt-get install -y --no-install-recommends build-essential ccache devscripts dpkg-dev
# Resolves the kisak source (highest version wins) and its build deps.
apt-get build-dep -y mesa

export CCACHE_DIR=${CCACHE_DIR:-/root/.ccache}
export CCACHE_BASEDIR=$BUILD_ROOT
export CCACHE_COMPILERCHECK=content
ccache --zero-stats >/dev/null

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"
apt-get source mesa
cd mesa-*/
for patch in "$REPO"/patches/*.patch; do
    cp "$patch" debian/patches/
    basename "$patch" >> debian/patches/series
done
MESAV=$(dpkg-parsechangelog -S Version)
case "$MESAV" in *'+piano'*) die "mesa source already carries +piano: $MESAV" ;; esac
DEBFULLNAME='piano-linux' DEBEMAIL='piano@localhost' \
    dch --local +piano --distribution resolute \
    'Recognise the Adreno 830v1 of the Xiaomi Pad 8 Pro on drm/msm (Mesa 2061a5ee).'
DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -uc -us

rm -rf "$OUTPUT/all" "$OUTPUT/runtime"
mkdir -p "$OUTPUT/all" "$OUTPUT/runtime"
cp ../*.deb "$OUTPUT/all/"
for deb in "$OUTPUT"/all/*.deb; do
    case $(dpkg-deb -f "$deb" Package) in
        *-dev | *-dbgsym | *-dbg) ;;
        *) cp "$deb" "$OUTPUT/runtime/" ;;
    esac
done
grep -q . <(find "$OUTPUT/runtime" -name 'mesa-libgallium_*+piano*.deb') \
    || die 'no patched mesa-libgallium package was built'
(cd "$OUTPUT" && find . -name '*.deb' | sort | xargs sha256sum > SHA256SUMS)
ccache --show-stats
echo "build-mesa-debs: $(find "$OUTPUT/all" -name '*.deb' | wc -l) packages," \
    "$(find "$OUTPUT/runtime" -name '*.deb' | wc -l) runtime, in $OUTPUT"

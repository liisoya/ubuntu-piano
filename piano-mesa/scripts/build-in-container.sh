#!/usr/bin/env bash
# build-in-container.sh — run build-mesa-debs.sh in a clean ubuntu:26.04
# container on an arm64 host (CI runner or workstation) with Docker.
#
# Adapted from blu-sharky/piano-mesa scripts/build-in-container.sh (MIT):
# base image ubuntu:26.04 (resolute) instead of debian:trixie, and no
# VERSION argument — the source comes from the kisak PPA (highest version).
#
# Usage:
#   scripts/build-in-container.sh OUTPUT_DIR CCACHE_DIR
#
# CCACHE_DIR is mounted into the container, so the caller decides where the
# cache lives. Files the container creates are handed back to the calling
# user afterwards.
set -euo pipefail

OUTPUT=${1:?usage: build-in-container.sh OUTPUT_DIR CCACHE_DIR}
CCACHE=${2:?usage: build-in-container.sh OUTPUT_DIR CCACHE_DIR}
REPO=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$OUTPUT" "$CCACHE"
OUTPUT=$(realpath "$OUTPUT")
CCACHE=$(realpath "$CCACHE")

status=0
docker run --rm \
    -v "$REPO:/src:ro" -v "$OUTPUT:/out" -v "$CCACHE:/ccache" \
    -e CCACHE_DIR=/ccache -e CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-6G}" \
    ubuntu:26.04 /src/scripts/build-mesa-debs.sh /out || status=$?
docker run --rm -v "$OUTPUT:/out" -v "$CCACHE:/ccache" ubuntu:26.04 \
    chown -R "$(id -u):$(id -g)" /out /ccache
exit "$status"

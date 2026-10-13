# piano-mesa (resolute variant)

Mesa for the Xiaomi Pad 8 Pro (piano, SM8750, Adreno 830) on **Kubuntu
26.04 (resolute)**. Vendored from blu-sharky/piano-mesa (MIT) and adapted;
the adaptation is documented here and in the scripts' headers.

## Why this exists

The piano kernel reports chip id `0xffff44050001` (speed bin in the upper
half). Verified against upstream Mesa on 2026-10-09:

| Mesa | A830 device | v1 chip id (`0xffff44050001`) |
|---|---|---|
| 26.0.8 (resolute archive + updates) | absent (fake `FD830` cffdump entry only) | no |
| 26.1.6 (Debian trixie-backports) | present | no |
| 26.2.4 (kisak PPA, resolute) | present | no |
| mesa main (commit `2061a5ee`, 2026-08-19) | — | **yes** |

So any distribution needs the one-line patch on top of a Mesa that already
has the real A830 device. For Debian, upstream piano-mesa rebuilds Debian's
trixie-backports source. For resolute we build the **kisak PPA source**
(26.2.4~kisak1~r at vendoring time): it already targets resolute, so the
produced debs' Depends resolve against resolute libraries (the Debian-built
debs do not — they pull libllvm19/libdisplay-info2, which are not
installable on resolute; observed on CI run 37896432396).

## Differences vs upstream blu-sharky/piano-mesa

- `scripts/build-mesa-debs.sh`: source = kisak-mesa PPA resolute (deb-src
  added to the container, key pinned by fingerprint
  `46555F0DD369CA8A82BCFB94913EA540133323F9`, overridable via
  `KISAK_KEY_FINGERPRINT`); no backports pocket; `dch --distribution
  resolute`; version check guards against double-`+piano`.
- `scripts/build-in-container.sh`: base image `ubuntu:26.04`; no VERSION
  argument (kisak latest wins).
- `patches/`: the same single upstream commit (`2061a5ee`), unmodified —
  dry-run-verified to apply cleanly to mesa-26.2.4.

## Consumers

`ci/build-kubuntu.sh` (branch piano-kubuntu) runs
`scripts/build-in-container.sh` with the same ccache directory as the kernel
build, then installs `runtime/` into the rootfs via
`debian-piano/scripts/build-rootfs.sh --mesa-dir` with the `*+piano*` apt pin.

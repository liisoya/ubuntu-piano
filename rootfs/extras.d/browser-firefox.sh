#!/bin/sh
# extras 钩子：Mozilla 官方 apt 源（避开 Ubuntu 的 snap 过渡包）。
# ⚠ 未验证：Mozilla apt 源的 arm64 可用性待真机确认；失败则该选项不启用。
set -eu
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
    | gpg --dearmor > /etc/apt/keyrings/packages.mozilla.org.gpg
chmod 0644 /etc/apt/keyrings/packages.mozilla.org.gpg
echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main' \
    > /etc/apt/sources.list.d/mozilla.list
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
    > /etc/apt/preferences.d/mozilla
apt-get update

#!/bin/sh
# extras 钩子：Google Chrome 官方 apt 源（arm64）+ 安装前准备。
# 在 rootfs chroot 内执行（由 build-rootfs.sh 注入）。
set -eu
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor > /etc/apt/keyrings/google-chrome.gpg
chmod 0644 /etc/apt/keyrings/google-chrome.gpg
echo 'deb [arch=arm64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main' \
    > /etc/apt/sources.list.d/google-chrome.list
apt-get update

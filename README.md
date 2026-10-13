# piano — Ubuntu 26.04 (resolute) + KDE Plasma RootFS 构建器

为 **小米平板 8 Pro（piano，SM8750 / 骁龙 8 Elite / Adreno 830）** 构建可直接刷入的
Ubuntu rootfs 与启动镜像。参照 `ianchb/debian-sheng` 的构建思路（GitHub Actions +
Advanced Configuration），内核/驱动/组件采用 `blu-sharky` 的 piano 系列。

> 项目仍处于改造期：骨架已落地、冒烟构建进行中。刷机有风险，务必先读懂刷机纪律。

## 构建

1. Fork 本仓库并启用 Actions
2. Actions → **Build RootFS (piano)** → Run workflow（参数见下）
3. 产物：`piano-kde-flash-<sha>`（boot.img / dtbo.img / MANIFEST / SHA256SUMS）、
   `piano-kde-rootfs-<sha>`（rootfs tar.zst）

流水线为多 job：`components`（mesa/sensors/mipps）→ `rootfs`（debootstrap + 包 + deb）
→ `kernel-images`（内核 + initramfs + boot.img + rootfs 镜像 + gate）。

想固化预编译内核：Actions → **Publish Kernel Release**。

## Advanced Configuration（主要项）

| 参数 | 默认 | 说明 |
|---|---|---|
| Ubuntu 版本 | 26.04（resolute） | 25.10 未优化 |
| 桌面 | KDE Plasma | GNOME/server 尚未接线（fail-closed） |
| boot_mode | dual（linux-root） | single（userdata，毁 Android 数据）/ custom |
| 用户名 / 密码 | piano / piano | SSH 默认同此密码 |
| ssh_auth | password | keys-only = 仅密钥 |
| 语言 / 时区 | zh_CN.UTF-8 / Asia/Shanghai | |
| extras | fcitx5 + 压缩工具 | 另有 browser（chrome/firefox）、dev-tools、docker |
| 内核来源 | custom_build（源码） | prebuilt 待外部 ramdisk 路径支持 |

extras 是数据驱动的：`rootfs/extras.d/<name>.list`（包清单）+ 可选 `<name>.sh` 钩子，
加一个选项 = 加一个文件，构建脚本不改。

## 内核策略（ADR-0006）

基线 `blu-sharky/linux-piano @ piano-7.2.6`（不 fork 内核树）+ `kernel/patches/` 补丁集，
按 `kernel/series` 顺序应用（fail-closed fuzz=0，并需本地过编译）。每个补丁组 = 一个 PR，
来源与验证写入补丁头与 MANIFEST。

## 刷机纪律（务必遵守）

- **首次验证一律 RAM boot**：`fastboot boot boot.img`（零写入，重启即回原状）
- 只写 `boot_b` / `dtbo_b` 与 linux-root 分区；**绝不** `fastboot flash userdata`
- 槽 A 的 stock Android 必须始终可启动；绝不刷 bootloader 链分区（abl/xbl/tz/hyp…）
- 写分区前先看 `fastboot getvar current-slot`，写入后回读比对 sha256
- 产物 MANIFEST 固定 `device-tested: no`，真机验收通过后才改标

## 致谢

- **blu-sharky**：linux-piano 内核、debian-piano 构建资产、piano-firmware/mesa/sensors/mipps-auth
- **ianchb / code002-2**：debian-sheng 与 ubuntu-sheng 的构建思路与参数化外壳
- **map220v、yzddmr6（liuqin）**：同平台/同形态设备的移植先例与实现文档
- 上游内核与 Mesa/Freedreno 社区

固件为高通/小米专有二进制，仅设备持有者自用，不在本仓分发。

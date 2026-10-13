# MANIFEST-UPSTREAM — 上游来源与版本 pin

> 本分支（piano-kubuntu）所有产物的上游输入身份记录。每次 vendor/升级后回填。
> 产物 gate 依赖：CI 会把本文件与各 checkout 的实际 HEAD 对照（见 piano-kubuntu.yml）。

| 输入 | 来源 | pin（2026-10-09） | 说明 |
|---|---|---|---|
| 内核 | blu-sharky/linux-piano @ `piano-7.2.6` | 基线 `352508459733`（pristine，见 ADR-0005） | CI checkout，cmdline 由 workflow sed 注入 |
| 打包基座（vendor 进 `debian-piano/`） | blu-sharky/debian-piano @ main | `a75f8c5d5fa099d65c171ac839c2e3bb6c63ec45`（2026-10-09） | 与上游参考 run 37808998629 的构建 commit 一致 |
| 固件树 | blu-sharky/piano-firmware @ main | `05fc37c09ca8146eecfc4920f8485479db140ae5`（2026-10-01） | CI checkout |
| Mesa | blu-sharky/piano-mesa @ main | `a89c1e4`（2026-09-28，refer 快照） | 必建组件 |
| 传感器栈 | blu-sharky/piano-sensors @ main | `65a9220`（2026-10-01，refer 快照） | 必建组件 |
| MiPPS 认证 | blu-sharky/piano-mipps-auth @ main | `ccdc3ce`（2026-10-04，refer 快照） | 必建组件 |
| v4l2loopback | umlaeute/v4l2loopback | `0f9ee86760b7f2bea174b7e3e7a1d38845da0ab4` | 对本次内核编模块（上游同 pin） |
| AudioReach 拓扑 | linux-msm/audioreach-topology | `993a17dcb672357998a463a73f120064d6c74f4f` | 上游同 pin，保证拓扑二进制可复现 |

## 参考基线

- 上游全量构建成功 run：blu-sharky/debian-piano actions run `37808998629`
  （2026-10-08，commit `a75f8c5d`）——CI 步骤序列与产物体积基线（rootfs tar ≈ 918 MiB）。
- CI 路线决策与纪律：ADR-0007；完整方案见本仓库外的 `Bulid/github-actions-build-plan.md`。

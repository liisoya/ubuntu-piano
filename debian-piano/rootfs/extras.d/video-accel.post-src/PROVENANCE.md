# video-accel.post-src 内置资产出处

## libva-v4l2/ — VA-API 后端（Qualcomm Iris stateful V4L2 M2M）

- 上游：https://github.com/radxa-pkg/libva-v4l2 （radxa 的 fork，专为 Iris 的
  stateful M2M 编写；上游 mxsrc/libva-v4l2 仅支持 stateless，不适用）
- 取用 commit：0e4ce1e05da1d0a92b342efc2090b9e4987035e1（2026-09-10，master 顶端）
- 取用方式：codeload tarball（2026-10-14 拉取）
- 验证记录：该源码于 2026-10-14 在 piano 真机（Ubuntu resolute arm64）原生构建成功，
  ffmpeg -hwaccel vaapi 硬解 57/60 帧 + va_openDriver() returns 0；
  Chrome 155 chrome://gpu 显示 Video Decode/Encode = Hardware accelerated。
  详见 Bulid/issues/23-video-accel-vaapi.md 与 Bulid/notes/RESEARCH-LOG.md R7/R8。
- 许可：随源码 LICENSE（MIT）；保留上游署名。
- 为何内置而非构建时克隆：构建可复现（不依赖构建时网络与上游漂移）；
  体积仅 408K。更新时整体替换并在此登记新 commit。

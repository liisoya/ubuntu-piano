#!/usr/bin/env bash
# 从 ianchb 的 6 个设备功能包仓库下载最新 release 的 deb
#
# 对应上游 debian-sheng 中 6 组「gh release list → gh release download → upload artifact」步骤：
#   xiaomi-mipps-auth / xiaomi-charger-mode / xiaomi-sheng-thp /
#   xiaomi-pen-status / xiaomi-sheng-fingerprint / xiaomi-sheng-keyboard-helper
#
# 需要环境变量（GitHub Actions 中自动注入）：
#   GH_TOKEN
#
# 用法: scripts/packages/fetch-xiaomi-debs.sh
set -euo pipefail

REPOS=(
  xiaomi-mipps-auth
  xiaomi-charger-mode
  xiaomi-sheng-thp
  xiaomi-pen-status
  xiaomi-sheng-fingerprint
  xiaomi-sheng-keyboard-helper
)

OWNER="${XIAOMI_OWNER:-ianchb}"
mkdir -p deb-out

for repo in "${REPOS[@]}"; do
  echo "[fetch-xiaomi] $OWNER/$repo"
  tag="$(gh release list --repo "$OWNER/$repo" --limit 1 --json tagName -q '.[0].tagName')"
  if [[ -z "$tag" ]]; then
    echo "[fetch-xiaomi] 跳过 $repo：没有 release" >&2
    continue
  fi
  # 单个仓库没有 .deb 资产时不要让整个工作流失败：
  # gh 在 --pattern 无匹配时会返回非 0，而 set -e 会让 packages 工作流整体失败，
  # 进而导致 rootfs 作业（needs: packages）永不运行 —— 而这只影响一个可选功能包。
  # 因此跳过并告警；最终包里少了哪些，由 rootfs.yml 的 Verify 步骤与 step summary 报告。
  if ! gh release download "$tag" --repo "$OWNER/$repo" --pattern "*.deb" --clobber --dir deb-out; then
    echo "[fetch-xiaomi] 警告：$OWNER/$repo@$tag 没有下载到 .deb（该 release 可能只有源码），已跳过" >&2
    continue
  fi
  echo "[fetch-xiaomi] $repo @ $tag 完成"
done

count="$(find deb-out -maxdepth 1 -name '*.deb' | wc -l)"
echo "[fetch-xiaomi] 下载结果：${count} 个 deb"
if [[ "$count" -lt 6 ]]; then
  echo "[fetch-xiaomi] 警告：少于 6 个（期望 6），对应功能包会缺失（见 rootfs.yml 的 Verify Collected Packages）" >&2
fi
ls -lh deb-out/ | sed 's/^/    /'

#!/usr/bin/env bash
# 生成本次发布的"更新内容"文本（供 GitHub Release 正文与蒲公英更新说明共用，
# 保证两端的发布说明完全一致——这是用户明确要求的同步点）。
#
# 用法：
#   bash scripts/ci_release_body.sh <输出文件> <版本> <构建号> [plain]
#     - plain：给蒲公英（网页不渲染 markdown，去掉代码反引号并控制长度）
#
# 依赖：仓库需 fetch-depth: 0（能访问 github.event.before 或上一个 tag），
# 与 release.yml 的 release job 原有内联逻辑等价，只是抽成了单一来源。
# 注意：不设 pipefail——`git log | head -N` 在 head 收够后会向 git 发 SIGPIPE，
# pipefail 会把这条正常路径误判成失败。
set -eu

OUT="${1:?输出文件}"
VERSION="${2:?版本号}"
BUILD="${3:?构建号}"
MODE="${4:-markdown}"
SHA="${GITHUB_SHA:-HEAD}"
BEFORE="${GITHUB_EVENT_BEFORE:-}"

# 提交范围优先取"本次推送"（push 事件自带的 before SHA）；
# 取不到（新分支首推 / 强推 / 手动触发）就退回上一个 tag，再退回当前单个提交。
if [ -n "$BEFORE" ] && git cat-file -e "${BEFORE}^{commit}" 2>/dev/null; then
  RANGE="${BEFORE}..${SHA}"
  SOURCE="本次推送"
else
  PREV_TAG=$(git describe --tags --abbrev=0 "${SHA}^" 2>/dev/null || true)
  if [ -n "$PREV_TAG" ]; then
    RANGE="${PREV_TAG}..${SHA}"
    SOURCE="自 ${PREV_TAG} 起"
  else
    RANGE="$SHA"
    SOURCE="当前提交"
  fi
fi
TOTAL=$(git rev-list --count --no-merges "$RANGE" 2>/dev/null || echo 0)

if [ "$MODE" = "plain" ]; then
  # 蒲公英更新说明：纯文本、不带 markdown 记号；超长会被蒲公英拒收，压到 50 条
  {
    echo "SlimeWorks v${VERSION}（构建 ${BUILD}）"
    echo
    echo "提交记录（${SOURCE}，${TOTAL} 个非合并提交）："
    if [ "$TOTAL" = "0" ]; then
      echo "- 没有新提交（本次多为文档或构建配置改动）"
    else
      git log --no-merges --reverse --pretty='- %h %s' "$RANGE" | head -50
      if [ "$TOTAL" -gt 50 ]; then
        echo "- …另有 $((TOTAL - 50)) 个提交未列出"
      fi
    fi
  } > "$OUT"
else
  {
    echo "## SlimeWorks v${VERSION}"
    echo
    echo "构建号：${BUILD}"
    echo
    echo "### 提交记录（${SOURCE}，${TOTAL} 个非合并提交）"
    echo
    if [ "$TOTAL" = "0" ]; then
      echo "_没有新提交（本次多为文档或构建配置改动）。_"
    else
      git log --no-merges --reverse --pretty='- \`%h\` %s' "$RANGE" | head -80
      if [ "$TOTAL" -gt 80 ]; then
        echo "- …另有 $((TOTAL - 80)) 个提交未列出"
      fi
    fi
    echo
    echo '### 下载'
    echo
    echo '- **macOS**：自动更新（应用内）或 `.dmg` 拖进「应用程序」'
    echo '- **Windows**：`.exe` 安装包（应用内弹窗跳转下载）'
    echo '- **Android**：`.apk`（蒲公英同步有包）'
    echo '- **iOS**：`.ipa`（Ad Hoc，测试机 UDID 需已登记进描述文件）'
  } > "$OUT"
fi
cat "$OUT"

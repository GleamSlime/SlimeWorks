#!/usr/bin/env bash
# 安装完整 Xcode，让 macOS 打包（flutter build macos / fastforge）可用。
#
# 为什么需要它：本机只装了 Command Line Tools，`xcodebuild` 不存在，
# `flutter build macos` 必然失败于 XcodeProjectInterpreter.getInfo:
#   xcrun: error: unable to find utility "xcodebuild"
# 而 macOS 打包必须用完整 Xcode 里的 xcodebuild，CLT 顶替不了。
#
# 为什么不能全自动：Xcode 的下载要 Apple ID 登录 + 双重认证。另外
# `xcodes` 这个能代拉包的工具本身要靠 xcbuild 编译，而 xcbuild 属于完整
# Xcode —— 鸡生蛋问题，装不上。所以下载这一步只能人工。
#
# 用法：
#   bash scripts/install_xcode.sh --check              # 只体检，不动任何东西
#   bash scripts/install_xcode.sh --xip ~/Downloads/Xcode_16.4.xip
#
# 前置要求：根卷可用空间 ≥ 60 GB（App ~12G + 解压后 ~30G + 首次运行组件）。
set -euo pipefail

XCODE_MIN_FREE_GB=60
XCODE_APP="/Applications/Xcode.app"

info() { printf '\033[36m[xcode]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[xcode]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[xcode]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── 状态体检 ─────────────────────────────────────────────────────────────
check_status() {
  info "当前开发者目录: $(xcode-select -p 2>/dev/null || echo '未设置')"
  if [ -d "$XCODE_APP" ]; then
    info "已安装 Xcode: $(defaults read "$XCODE_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '版本未知')"
  else
    warn "未找到 $XCODE_APP"
  fi
  if xcodebuild -version >/dev/null 2>&1; then
    info "xcodebuild 可用: $(xcodebuild -version | head -1)"
  else
    warn "xcodebuild 不可用（macOS 打包会失败）"
  fi
  local free_gb
  free_gb=$(df -g / | awk 'NR==2 {print $4}')
  if [ "$free_gb" -lt "$XCODE_MIN_FREE_GB" ]; then
    warn "空间不足：Xcode 全套需约 ${XCODE_MIN_FREE_GB} GB，当前 ${free_gb} GB"
    warn "可清理参考：cd rust && cargo clean（本机实测可释放 20 GB+）"
  else
    info "根卷可用空间: ${free_gb} GB（充足）"
  fi
}

# ── 从 .xip 安装 ─────────────────────────────────────────────────────────
install_from_xip() {
  local xip="$1"
  [ -f "$xip" ] || die "找不到文件: $xip"

  local free_gb
  free_gb=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free_gb" -ge "$XCODE_MIN_FREE_GB" ] || die "空间不足（可用 ${free_gb} GB，需要 ${XCODE_MIN_FREE_GB} GB）"

  info "校验 .xip 签名（约 12 GB，需要几分钟）..."
  if ! pkgutil --check-signature "$xip" >/dev/null 2>&1; then
    warn "签名校验未通过——若来源不可疑可继续，否则请重新下载"
  fi

  # 在 /Applications 下解压，避免跨盘拷贝再翻倍占空间
  local workdir="/Applications/.xcode_install_tmp"
  rm -rf "$workdir" 2>/dev/null || sudo rm -rf "$workdir"
  mkdir -p "$workdir" 2>/dev/null || sudo mkdir -p "$workdir"
  info "解压到 $workdir（这一步最慢，约 10-30 分钟）..."
  ( cd "$workdir" && xip --expand "$xip" )

  local expanded
  expanded=$(ls -d "$workdir"/Xcode*.app 2>/dev/null | head -1 || true)
  [ -n "$expanded" ] || die "解压后没找到 Xcode*.app（xip 可能损坏）"

  info "安装到 $XCODE_APP ..."
  if [ -d "$XCODE_APP" ]; then sudo rm -rf "$XCODE_APP"; fi
  sudo mv "$expanded" "$XCODE_APP"
  rm -rf "$workdir" 2>/dev/null || sudo rm -rf "$workdir"

  finish_setup
}

# ── 切换工具链 + 首次运行组件 ────────────────────────────────────────────
finish_setup() {
  [ -d "$XCODE_APP" ] || die "安装后仍未找到 $XCODE_APP"
  echo
  info "下面几步需要 sudo 密码（会暂停，等你输入）："
  sudo xcode-select --switch "$XCODE_APP/Contents/Developer"
  sudo xcodebuild -license accept 2>/dev/null \
    || warn "许可协议需手动接受：sudo xcodebuild -license"
  info "安装首次运行组件（可能弹系统对话框，点『安装』）..."
  sudo xcodebuild -runFirstLaunch 2>/dev/null \
    || warn "首次运行组件未装完，可稍后手动执行：sudo xcodebuild -runFirstLaunch"

  echo
  check_status
  echo
  info "之后即可打包："
  echo '  export PATH="$PATH:$HOME/.pub-cache/bin"'
  echo '  fastforge package --platform macos --target dmg'
}

# ── 入口 ─────────────────────────────────────────────────────────────────
main() {
  case "${1:-}" in
    --check) check_status; exit 0 ;;
    --xip)
      [ -n "${2:-}" ] || die "用法: bash scripts/install_xcode.sh --xip <Xcode.xip>"
      check_status; echo; install_from_xip "$2" ;;
    *)
      cat <<EOF
用法：
  bash scripts/install_xcode.sh --check                     # 只体检
  bash scripts/install_xcode.sh --xip ~/Downloads/Xcode_16.4.xip

下载 Xcode（需 Apple ID 登录；本机 macOS 15.6.1 对应 Xcode 16.4）：
  https://developer.apple.com/download/all/?q=Xcode
  → 选 "Xcode 16.4" → 点 .xip 下载（约 12 GB）

下完后跑上面第二条命令即可。
EOF
      ;;
  esac
}

main "$@"

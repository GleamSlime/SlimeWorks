#!/usr/bin/env bash
# SlimeWorks 提交前校验：analyze → 全量 test → 打包，一次跑完，只输出结论摘要。
#
# 用法：
#   bash scripts/precommit_gate.sh                 # 完整三道门（提交前必须跑这个）
#   bash scripts/precommit_gate.sh --skip-package  # 临时排查：只跑分析与测试
#   bash scripts/precommit_gate.sh --skip-test     # 临时排查：只跑分析与打包
#   bash scripts/precommit_gate.sh --help
#
# 统一在这里钉住环境，避免每次手敲命令漏掉 --no-pub / 镜像变量 / SDK 版本：
#   - SDK 以 .dart_tool/version 为准（见 docs/dev-environment.md）
#   - 两个 pub 镜像变量、LIBCLANG_PATH 固定补齐
#   - flutter 命令一律 --no-pub，构建意外改写 pubspec.lock 时自动还原
#   - 打包前把旧 dmg 挪走（appdmg 遇同名目标会直接失败）
#
# 完整日志：$TMPDIR/slime_works_gate/<时间戳>/*.log
# 退出码：0 全部通过；1 有门失败；2 环境/参数问题。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

SKIP_PACKAGE=0
SKIP_TEST=0
for arg in "$@"; do
  case "$arg" in
    --skip-package) SKIP_PACKAGE=1 ;;
    --skip-test) SKIP_TEST=1 ;;
    -h|--help) awk 'NR>1 && /^#/ {print} NR>1 && !/^#/ {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数: ${arg}（--help 查看用法）"; exit 2 ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
# macOS 的 TMPDIR 自带结尾斜杠，去掉避免日志路径出现 "//"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
LOG_DIR="$TMP_BASE/slime_works_gate/$STAMP"
mkdir -p "$LOG_DIR"

# ── 环境：与 docs/dev-environment.md 的记录保持一致 ─────────────────────────
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
if command -v xcode-select >/dev/null 2>&1; then
  XCODE_DEV="$(xcode-select -p 2>/dev/null)"
  export LIBCLANG_PATH="${LIBCLANG_PATH:-$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib}"
fi

# ── SDK 选择：唯一权威来源是 .dart_tool/version ──────────────────────────────
SDK_VERSION="$(tr -d '[:space:]' < .dart_tool/version 2>/dev/null || true)"
FLUTTER_BIN=""
if [ -n "$SDK_VERSION" ] && [ -x "$HOME/fvm/versions/$SDK_VERSION/bin/flutter" ]; then
  FLUTTER_BIN="$HOME/fvm/versions/$SDK_VERSION/bin/flutter"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
fi
if [ -z "$FLUTTER_BIN" ]; then
  echo "找不到 flutter：.dart_tool/version=${SDK_VERSION:-未知}，PATH 里也没有 flutter"
  exit 2
fi
export PATH="$(dirname "$FLUTTER_BIN"):$HOME/.pub-cache/bin:$PATH"

# 记下 lock 的初始状态：构建偶尔会按镜像地址重写它，收尾时还原，避免误提交
LOCK_DIRTY_BEFORE="$(git status --porcelain -- pubspec.lock 2>/dev/null)"

FAILED=0
STEP=0
TOTAL=3
if [ "$SKIP_TEST" -eq 1 ]; then TOTAL=$((TOTAL - 1)); fi
if [ "$SKIP_PACKAGE" -eq 1 ]; then TOTAL=$((TOTAL - 1)); fi

TITLE="SlimeWorks 提交前校验"
echo "== $TITLE =="
echo "SDK: ${SDK_VERSION:-未知} ($FLUTTER_BIN)"
echo "日志: $LOG_DIR"

now() { date +%s; }
elapsed() { echo "$(( $(now) - $1 ))s"; }

# ── 1. flutter analyze ──────────────────────────────────────────────────────
STEP=$((STEP + 1))
START=$(now)
"$FLUTTER_BIN" analyze --no-pub >"$LOG_DIR/analyze.log" 2>&1
RC=$?
if [ $RC -eq 0 ]; then
  printf '[%d/%d] analyze           通过 (%s)\n' "$STEP" "$TOTAL" "$(elapsed "$START")"
else
  FAILED=1
  ERRORS="$(grep -cE '^[[:space:]]*(error|warning) •' "$LOG_DIR/analyze.log" 2>/dev/null || true)"
  printf '[%d/%d] analyze           失败 (%s 条 error/warning, %s)\n' \
    "$STEP" "$TOTAL" "${ERRORS:-0}" "$(elapsed "$START")"
  grep -E '^[[:space:]]*(error|warning) •' "$LOG_DIR/analyze.log" | head -15 | sed 's/^/    /'
  echo "    完整输出: $LOG_DIR/analyze.log"
fi

# ── 2. 全量 flutter test ────────────────────────────────────────────────────
if [ "$SKIP_TEST" -eq 1 ]; then
  printf '[跳过] test               --skip-test（提交前必须补跑）\n'
else
  STEP=$((STEP + 1))
  START=$(now)
  "$FLUTTER_BIN" test --no-pub >"$LOG_DIR/test.log" 2>&1
  RC=$?
  if [ $RC -eq 0 ]; then
    SUMMARY="$(grep -E '\+[0-9]+.*All tests passed!|All tests passed!' "$LOG_DIR/test.log" | tail -1 | sed 's/^[0-9:]*[[:space:]]*//')"
    printf '[%d/%d] test              通过 (%s, %s)\n' \
      "$STEP" "$TOTAL" "${SUMMARY:-全量通过}" "$(elapsed "$START")"
  else
    FAILED=1
    printf '[%d/%d] test              失败 (%s)\n' "$STEP" "$TOTAL" "$(elapsed "$START")"
    awk '/^Failing tests:/{flag=1} flag' "$LOG_DIR/test.log" | head -12 | sed 's/^/    /'
    echo "    完整输出: $LOG_DIR/test.log"
  fi
fi

# ── 3. 打包（本机只能验 macOS） ─────────────────────────────────────────────
if [ "$SKIP_PACKAGE" -eq 1 ]; then
  printf '[跳过] package            --skip-package（提交前必须补跑）\n'
else
  STEP=$((STEP + 1))
  START=$(now)
  if ! command -v fastforge >/dev/null 2>&1; then
    FAILED=1
    printf '[%d/%d] package           失败 (找不到 fastforge)\n' "$STEP" "$TOTAL"
    echo "    先执行: dart pub global activate fastforge"
  else
    # 旧产物挪走：appdmg 见目标文件已存在会直接报 Target already exists
    mkdir -p "$LOG_DIR/old_artifacts"
    while IFS= read -r f; do
      [ -n "$f" ] && mv "$f" "$LOG_DIR/old_artifacts/" 2>/dev/null
    done < <(find dist -maxdepth 3 -name '*.dmg' 2>/dev/null)

    MARKER="$LOG_DIR/package.start"
    touch "$MARKER"
    fastforge package --platform macos --target dmg --no-version-check \
      >"$LOG_DIR/package.log" 2>&1
    RC=$?
    NEW_DMG="$(find dist -maxdepth 3 -name '*.dmg' -newer "$MARKER" 2>/dev/null | head -1)"
    if [ $RC -eq 0 ] && [ -n "$NEW_DMG" ]; then
      printf '[%d/%d] package           通过 (%s, %s)\n' \
        "$STEP" "$TOTAL" "$NEW_DMG" "$(elapsed "$START")"
    else
      FAILED=1
      printf '[%d/%d] package           失败 (exit=%s, %s)\n' \
        "$STEP" "$TOTAL" "$RC" "$(elapsed "$START")"
      tail -15 "$LOG_DIR/package.log" | sed 's/^/    /'
      echo "    完整输出: $LOG_DIR/package.log"
    fi
  fi
fi

# ── 收尾：还原被构建改写的 pubspec.lock ──────────────────────────────────────
LOCK_DIRTY_AFTER="$(git status --porcelain -- pubspec.lock 2>/dev/null)"
if [ -z "$LOCK_DIRTY_BEFORE" ] && [ -n "$LOCK_DIRTY_AFTER" ]; then
  git checkout -- pubspec.lock 2>/dev/null
  echo "已还原 pubspec.lock（构建按镜像重写了地址，与代码无关）"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  if [ "$SKIP_TEST" -eq 1 ] || [ "$SKIP_PACKAGE" -eq 1 ]; then
    echo "结论: 已跑的门全部通过（有跳过项，提交前请完整跑一遍）"
  else
    echo "结论: 三道门全部通过，可以提交"
  fi
  exit 0
fi
echo "结论: 校验失败，禁止提交（日志: ${LOG_DIR}）"
exit 1

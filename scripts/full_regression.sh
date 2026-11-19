#!/usr/bin/env bash
# SlimeWorks 全量模拟回归测试
# ═══════════════════════════════════════════════════════════════════════════
# 一句话：起一个**真实的 slime_node**（全新空 data-dir），把无头模式/远程
# 节点下用户真正会做的写操作全部跑一遍，逐条断言「数据真的变了」，
# 最后只输出一张结论表。
#
# ★ 什么时候跑：
#   - 用户明确要求「全量模拟回归测试」；
#   - Agent 判断改动碰了以下任一区域时**应当主动跑**：
#       rust/src/node_server/**            节点 action 分发
#       rust/media_collection/**           条目/集合/聚合值
#       rust/ledger_module/**              账本
#       lib/core/services/node/**          节点客户端
#       lib/view_models/media_library_**   资源库 VM
#       lib/view_models/novel_library**    书库 VM
#       lib/view_models/ledger/**          账本 VM
#
# ★ 为什么要有这个脚本（比手点强在哪）：
#   上一轮只测「不存在的 id 报不报错」，漏掉了 8 类真 bug。这个脚本编码的是
#   **那轮之后总结出的方法论**：
#     ① 用全新空 data-dir 起节点（否则模块单例是热的，症状被掩盖）；
#     ② 测正常路径上的静默失败（删最后一条、连续两次写、空目录、特殊字符名）；
#     ③ 每条都回查节点真实数据，不只看 API 返回值；
#     ④ 直接断言「假成功」这种形态（对不存在的目标是否回了 success:true）。
#
# ★ 用法：
#   bash scripts/full_regression.sh                  # 核心回归（约 11s，默认）
#   bash scripts/full_regression.sh --with-app       # 再加真 macOS App 集成测试
#   bash scripts/full_regression.sh --with-full-test # 再加全量 flutter test 基线对照
#   bash scripts/full_regression.sh --all            # 上面两个都跑（慢，25 分钟量级）
#   bash scripts/full_regression.sh --only C,E       # 只跑指定小节
#   bash scripts/full_regression.sh --list           # 列出所有小节
#   bash scripts/full_regression.sh --keep           # 保留临时目录便于排查
#
# ★ 退出码：0 全通过；1 有失败；2 环境/参数问题。
# ★ 日志：$TMPDIR/slime_works_regress/<时间戳>/ —— 结论表只给摘要，
#   每条失败的具体输出都在对应 .log 里，**不要**把整个日志贴进上下文。
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

# ── 可调项 ───────────────────────────────────────────────────────────────────
# 测试数据根目录（用户指定的位置）。脚本只**读**它，导入用的样本会复制/
# 生成到临时目录，绝不在里面写入 .SlimeWorks 之类的缓存。
DATA_ROOT_DEFAULT="/Volumes/T22/测试数据"

WITH_APP=0
WITH_FULL_TEST=0
KEEP=0
ONLY=""
PORT=""
DATA_ROOT=""

STAMP="$(date +%Y%m%d-%H%M%S)"
TMP_BASE="${TMPDIR:-/tmp}"; TMP_BASE="${TMP_BASE%/}"
LOG_DIR="$TMP_BASE/slime_works_regress/$STAMP"
WORK_DIR="$TMP_BASE/slime_works_regress/$STAMP/work"
mkdir -p "$LOG_DIR" "$WORK_DIR" || exit 2

PASS=0; FAIL=0; SKIP=0
declare -a FAILED_NAMES=()

# 参数解析：统一用一个游标走完，支持 `--opt value` 与 `--opt=value` 两种写法。
# 早期版本用「两遍扫描 + prev 变量」补解析两段式参数，结果 `--only B,E`
# 会把 `B,E` 当成未知参数直接退出 —— 单遍带 shift 的写法更难写错。
while [ $# -gt 0 ]; do
  case "$1" in
    --with-app)       WITH_APP=1 ;;
    --with-full-test) WITH_FULL_TEST=1 ;;
    --all)            WITH_APP=1; WITH_FULL_TEST=1 ;;
    --keep)           KEEP=1 ;;
    --list)           echo "小节：A 环境自检 | B Rust 构建 | C 节点冷启动模块 | D 假成功契约 | E 条目ID稳定 | F 幽灵体积 | G 重新扫描 | H 文件上传 | I 账本口令 | J Sentry清空 | K 真App | L 全量测试 | M 真实测试数据"; exit 0 ;;
    --only)           shift; [ $# -gt 0 ] || { echo "--only 需要一个值，例如 --only B,E"; exit 2; }; ONLY="$1" ;;
    --only=*)         ONLY="${1#--only=}" ;;
    --port)           shift; [ $# -gt 0 ] || { echo "--port 需要一个值"; exit 2; }; PORT="$1" ;;
    --port=*)         PORT="${1#--port=}" ;;
    --data-root)      shift; [ $# -gt 0 ] || { echo "--data-root 需要一个值"; exit 2; }; DATA_ROOT="$1" ;;
    --data-root=*)    DATA_ROOT="${1#--data-root=}" ;;
    # 用 substr 判首字符而不是正则 /^#/：分隔线那行是全角制表符（多字节），
    # 某些 awk 版本上 /^#/ 会在多字节序列上提前失配，导致 help 只输出第一行。
    -h|--help)        awk 'NR>1 { if (substr($0,1,1) != "#") exit; sub(/^# ?/,""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)                echo "未知参数: ${1}（--help 查看用法）"; exit 2 ;;
  esac
  shift
done

DATA_ROOT="${DATA_ROOT:-$DATA_ROOT_DEFAULT}"

# ── 环境 ─────────────────────────────────────────────────────────────────────
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export FLUTTER_SWIFT_PACKAGE_MANAGER=false
PATH="$HOME/.pub-cache/bin:$PATH"

# SDK 以 .dart_tool/version 为准；本机常见位置兜底
SDK_VERSION="$(tr -d '[:space:]' < .dart_tool/version 2>/dev/null || true)"
FLUTTER_BIN=""
for cand in "/private/tmp/fl/flutter/bin/flutter" "$HOME/fvm/versions/$SDK_VERSION/bin/flutter"; do
  [ -x "$cand" ] && { FLUTTER_BIN="$cand"; break; }
done
[ -z "$FLUTTER_BIN" ] && FLUTTER_BIN="$(command -v flutter 2>/dev/null || true)"
DART_BIN="${FLUTTER_BIN%/flutter}/dart"

# 装了完整 Xcode 之后：只要 libclang，**不要**设 CXXFLAGS/CFLAGS
# （那套是「只有 CLT」时的变通，现在会让 libc++ 混用炸一脸）。
XCODE_DEV="$(xcode-select -p 2>/dev/null || true)"
if [ -n "$XCODE_DEV" ] && [ -f "$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib" ]; then
  export LIBCLANG_PATH="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib"
else
  export LIBCLANG_PATH="${LIBCLANG_PATH:-/Library/Developer/CommandLineTools/usr/lib}"
fi
unset CXXFLAGS CFLAGS 2>/dev/null || true

# ── 输出与记账 ───────────────────────────────────────────────────────────────
# 颜色：只有输出到终端时才用 ANSI（管道/重定向时给字面量会污染日志与上下文）
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
else
  C_G=""; C_R=""; C_Y=""; C_0=""
fi
say()  { printf '%s\n' "$*"; }
sec()  { printf '\n== %s ==\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  %sPASS%s  %s\n' "$C_G" "$C_0" "$*"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$*"); printf '  %sFAIL%s  %s\n' "$C_R" "$C_0" "$*"; }
skip() { SKIP=$((SKIP+1)); printf '  %sSKIP%s  %s\n' "$C_Y" "$C_0" "$*"; }
note() { printf '        %s\n' "$*"; }

want() { # want <节名>：--only 未指定则全跑
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; esac
  case "$ONLY" in *"$1"*) return 0 ;; esac
  return 1
}

# node call：回显原始 JSON；非 200 或 success:false 也照样回，
# 由调用方判断语义（很多用例要断言「必须失败」）。
call() { # call <action> <params-json>
  curl -s --max-time 120 -X POST "$BASE/node/call" \
    -H 'Content-Type: application/json' \
    -d "{\"action\":\"$1\",\"params\":${2:-{\}}}" 2>/dev/null
}
jget() { # jget <json> <python-expr over d>  例: jget "$J" "d['data']['item_count']"
  python3 -c '
import json,sys
try:
    d=json.loads(sys.argv[1])
except Exception:
    print("__PARSE_ERR__"); sys.exit(0)
try:
    v=eval(sys.argv[2])
    if v is None: print("None")
    elif isinstance(v,bool): print("true" if v else "false")
    else: print(v)
except Exception:
    print("__EVAL_ERR__")
' "$1" "$2" 2>/dev/null
}
# 断言「成功」
is_ok()  { [ "$(jget "$1" "d['success']")" = "true" ]; }
# 断言「必须失败且文案含某串」——这是本脚本最重要的判据：
# 修复前的 bug 形态就是「对不存在的目标回 success:true」。
must_fail_with() { # must_fail_with <json> <expected-substr>
  local j="$1" want="$2"
  if [ "$(jget "$j" "d['success']")" != "false" ]; then
    printf '★假成功★ %s\n' "$(printf '%s' "$j" | head -c 300)"
    return 1
  fi
  local err; err="$(jget "$j" "d.get('error','')")"
  case "$err" in
    *"$want"*) return 0 ;;
    *) printf '错误文案不含「%s」: %s\n' "$want" "$err"; return 1 ;;
  esac
}

mkimg() { # mkimg <path>  —— 必须 >10KB 才过 scanner 的 MIN_IMAGE_FILE_SIZE
  ffmpeg -y -f lavfi -i "nullsrc=s=800x600,geq=random(1)*255:128:128" \
    -frames:v 1 "$1" >/dev/null 2>&1
}

say "[全量模拟回归测试] $STAMP"
say "  项目: $ROOT"
say "  数据根: $DATA_ROOT"
say "  SDK:   ${FLUTTER_BIN:-未找到} (期望 ${SDK_VERSION:-未知})"
say "  日志:  $LOG_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# A. 环境自检 —— 这些不过，后面的结论全不可信
# ═══════════════════════════════════════════════════════════════════════════
NODE_BIN="$ROOT/rust/target/debug/slime_node"
BASE=""
NODE_PID=""

if want A; then
  sec "A 环境自检"

  if [ -n "$FLUTTER_BIN" ] && [ -x "$FLUTTER_BIN" ]; then
    got="$("$FLUTTER_BIN" --version 2>/dev/null | head -1 | sed -n 's/.*Flutter \([0-9.]*\).*/\1/p')"
    if [ -n "$SDK_VERSION" ] && [ "$got" != "$SDK_VERSION" ]; then
      bad "flutter SDK 版本不匹配：$got ≠ .dart_tool/version=${SDK_VERSION}（混用会导致诡异类型错误）"
    else
      ok "flutter SDK ${got:-未知}"
    fi
  else
    bad "找不到 flutter（.dart_tool/version=${SDK_VERSION:-未知}）"
  fi

  if [ -n "$XCODE_DEV" ] && [ -x "$XCODE_DEV/usr/bin/xcodebuild" ]; then
    ok "Xcode $(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')"
  else
    skip "无完整 Xcode（真 App 集成测试将不可用）"
  fi

  # 镜像源 pub cache 的两个残缺包：缺了 macOS 就编不出来（Swift 报
  # cannot find type 'mpv_node_list' in scope），这是很隐蔽的坑。
  MKV="$HOME/.pub-cache/hosted/pub.flutter-io.cn/media_kit_video-2.0.1/macos/Headers/mpv"
  MKL="$HOME/.pub-cache/hosted/pub.flutter-io.cn/media_kit_libs_macos_video-1.1.4/macos/Frameworks"
  if [ -d "$MKV" ] && [ "$(ls -1 "$MKV" 2>/dev/null | wc -l | tr -d ' ')" -ge 4 ]; then
    ok "pub cache: media_kit_video/mpv 头文件齐全"
  else
    bad "pub cache 缺 media_kit_video/macos/Headers/mpv（macOS 会编不过；从 pub.dev 那份 cp -R 覆盖）"
  fi
  if [ -d "$MKL" ] && [ "$(ls -1 "$MKL" 2>/dev/null | wc -l | tr -d ' ')" -ge 10 ]; then
    ok "pub cache: mpv xcframework 齐全"
  else
    bad "pub cache 缺 media_kit_libs_macos_video/macos/Frameworks（同上，从 pub.dev 覆盖）"
  fi

  [ -f "$LIBCLANG_PATH/libclang.dylib" ] \
    && ok "LIBCLANG_PATH 可用" \
    || bad "LIBCLANG_PATH 下没有 libclang.dylib: $LIBCLANG_PATH"
fi

# ═══════════════════════════════════════════════════════════════════════════
# B. Rust 构建（无头包必须能构建——AGENTS.md 硬性要求）
# ═══════════════════════════════════════════════════════════════════════════
if want B; then
  sec "B Rust 构建"
  t0=$(date +%s)
  if ( cd rust && cargo build --bin slime_node ) >"$LOG_DIR/B-build.log" 2>&1; then
    ok "cargo build --bin slime_node（$(( $(date +%s) - t0 ))s）"
  else
    bad "cargo build --bin slime_node 失败（见 B-build.log）"
    tail -20 "$LOG_DIR/B-build.log" | sed 's/^/        /'
  fi
fi

# 起节点（C 之后的所有小节都依赖它）
start_node() {
  [ -n "$NODE_PID" ] && return 0
  [ -x "$NODE_BIN" ] || { bad "节点二进制不存在: ${NODE_BIN}（先跑 B 小节）"; return 1; }
  if [ -z "$PORT" ]; then
    PORT=18300
    while lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do PORT=$((PORT+1)); done
  fi
  BASE="http://127.0.0.1:$PORT"
  local nd="$WORK_DIR/node-data"
  rm -rf "$nd"; mkdir -p "$nd"
  # ★ 全新空 data-dir：这是本脚本的关键设计。用热进程测会让「模块未初始化」
  #   这类缺陷被完全掩盖（上一轮就是这么漏的）。
  "$NODE_BIN" --host 127.0.0.1 --port "$PORT" --data-dir "$nd" --name 回归节点 \
    >"$LOG_DIR/node.log" 2>&1 &
  NODE_PID=$!
  local i=0
  while [ $i -lt 60 ]; do
    if curl -s --max-time 2 "$BASE/health" >/dev/null 2>&1; then return 0; fi
    sleep 0.5; i=$((i+1))
  done
  bad "节点在 $PORT 上 20s 内没起来（见 node.log）"
  tail -20 "$LOG_DIR/node.log" | sed 's/^/        /'
  return 1
}
cleanup() {
  if [ -n "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then
    kill "$NODE_PID" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$NODE_PID" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$NODE_PID" 2>/dev/null
  fi
  if [ "$KEEP" = "1" ]; then
    say "  临时目录已保留: $WORK_DIR"
  else
    rm -rf "$WORK_DIR" 2>/dev/null
  fi
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════
# C. 节点冷启动模块初始化
#    无头节点不跑 Flutter，这些单例没人初始化 → 客户端探测后会把整块功能
#    判成「该节点不支持」。必须用**全新空 data-dir** 验证。
# ═══════════════════════════════════════════════════════════════════════════
if want C; then
  sec "C 节点冷启动模块初始化（全新空 data-dir）"
  if start_node; then
    j="$(call ping '{}')"
    is_ok "$j" && ok "ping" || bad "ping: $(printf '%s' "$j" | head -c 200)"

    for pair in \
      "aliyun_get_status|阿里云 DDNS" \
      "power_stats_get_status|电力统计" \
      "ledger_list_accounts|流水账" ; do
      act="${pair%%|*}"; name="${pair##*|}"
      j="$(call "$act" '{}')"
      if is_ok "$j"; then
        ok "$name 已初始化"
      else
        bad "$name 未初始化：$(jget "$j" "d.get('error','')")"
      fi
    done

    # Sentry 走独立 HTTP 路由，不在 /node/call 里
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE/sentry/stats" 2>/dev/null)"
    stats="$(curl -s --max-time 10 "$BASE/sentry/stats" 2>/dev/null)"
    if [ "$code" = "200" ] && [ "$(jget "$stats" "'total_events' in d")" = "true" ]; then
      ok "Sentry 日志存储已初始化"
    else
      bad "Sentry 未初始化（HTTP $code: $(printf '%s' "$stats" | head -c 120)）"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# D. 假成功契约：对不存在的目标，写操作必须**报错**而不是回 ok:true
#    修复前的 bug 形态就是无条件回 {"ok":true}。
# ═══════════════════════════════════════════════════════════════════════════
if want D; then
  sec "D 假成功契约（不存在的 id 必须报错）"
  if start_node; then
    check_fail() { # check_fail <描述> <action> <params>
      local desc="$1" act="$2" params="$3" j
      j="$(call "$act" "$params")"
      must_fail_with "$j" "不存在" && ok "$desc" || bad "$desc"
    }
    check_fail "rename_media_folder（幽灵 id）" rename_media_folder '{"folder_id":"media_folder_ghost","name":"X"}'
    check_fail "delete_media_folder（幽灵 id）"  delete_media_folder  '{"folder_id":"media_folder_ghost"}'
    check_fail "rename_media_collection（幽灵 id）" rename_media_collection '{"collection_id":"media_collection_ghost","title":"X"}'
    check_fail "delete_media_collection（幽灵 id）" delete_media_collection '{"collection_id":"media_collection_ghost"}'
    check_fail "move_media_collection_to_folder（幽灵夹）" move_media_collection_to_folder '{"collection_id":"media_collection_ghost","folder_id":"media_folder_ghost"}'
    check_fail "delete_collection_local_files（幽灵 id）" delete_collection_local_files '{"collection_id":"media_collection_ghost"}'
    check_fail "delete_media_item_local_file（幽灵 id）" delete_media_item_local_file '{"item_id":"media_ghost","collection_id":"media_collection_ghost"}'
    check_fail "delete_smart_folder（幽灵 id）" delete_smart_folder '{"id":"smart_folder_ghost"}'
    check_fail "delete_novel（幽灵 id）" delete_novel '{"novel_id":"novel_ghost"}'
    check_fail "move_novel_to_folder（幽灵书）" move_novel_to_folder '{"novel_id":"novel_ghost","folder_id":null}'
    check_fail "create_child_media_folder（幽灵父夹）" create_child_media_folder '{"name":"孤儿夹","parent_id":"media_folder_ghost"}'

    # 幽灵父夹不仅要报错，还**不能真的建出孤儿文件夹**
    folders="$(call list_media_folders '{}')"
    if [ "$(jget "$folders" "sum(1 for f in d['data'] if f.get('name')=='孤儿夹')")" = "0" ]; then
      ok "孤儿文件夹未被创建"
    else
      bad "幽灵父夹下真的建出了「孤儿夹」"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# E. 条目 ID 稳定性（本轮最伤的 bug）
#    删任意一条 → 其余条目 id 若重生成，用户串行删就只成功第一条。
# ═══════════════════════════════════════════════════════════════════════════
if want E; then
  sec "E 条目 ID 稳定性（删一条不许动其它条目的 id）"
  if start_node; then
    d="$WORK_DIR/e-media"; mkdir -p "$d"
    for i in 1 2 3; do mkimg "$d/p$i.png"; done
    j="$(call import_media_folder "{\"folder_path\":\"$d\"}")"
    COL="$(jget "$j" "d['data']['id']")"
    if [ -z "$COL" ] || [ "$COL" = "None" ]; then
      bad "导入失败：$(printf '%s' "$j" | head -c 200)"
    else
      ok "导入 3 个文件（集合 ${COL}）"
      ids_before="$(call get_media_collection_items "{\"collection_id\":\"$COL\"}" \
        | python3 -c 'import json,sys;print(" ".join(sorted(i["id"] for i in json.load(sys.stdin)["data"])))')"
      n_before=$(printf '%s' "$ids_before" | wc -w | tr -d ' ')

      # 删第一条，然后比对**其余** id 是否逐字不变
      first="$(printf '%s' "$ids_before" | awk '{print $1}')"
      j="$(call delete_media_item_local_file "{\"item_id\":\"$first\",\"collection_id\":\"$COL\"}")"
      is_ok "$j" || bad "删第一条失败：$(jget "$j" "d.get('error','')")"
      ids_after="$(call get_media_collection_items "{\"collection_id\":\"$COL\"}" \
        | python3 -c 'import json,sys;print(" ".join(sorted(i["id"] for i in json.load(sys.stdin)["data"])))')"
      expect_rest="$(printf '%s' "$ids_before" | tr ' ' '\n' | grep -v -x "$first" | sort | tr '\n' ' ' | sed 's/ $//')"
      if [ "$ids_after" = "$expect_rest" ] && [ "$n_before" = "3" ]; then
        ok "删掉 1 条后，其余 $((n_before-1)) 条 id 逐字未变"
      else
        bad "删掉 1 条后其余条目 id 变了（其余条目将全部报「条目不存在」）"
        note "删前: $ids_before"
        note "删后: $ids_after"
      fi

      # ★ 用户真实路径：用**同一批快照 id** 逐个串行删，必须全部成功
      all_ok=1
      for id in $expect_rest; do
        j="$(call delete_media_item_local_file "{\"item_id\":\"$id\",\"collection_id\":\"$COL\"}")"
        is_ok "$j" || { all_ok=0; note "  用快照 id $id 删除失败: $(jget "$j" "d.get('error','')")"; }
      done
      [ "$all_ok" = "1" ] \
        && ok "同一批快照 id 逐个串行删，全部成功（修复前第 2 条起必失败）" \
        || bad "串行删除有失败项（快照 id 失效）"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# F. 幽灵体积：删到集合为空后 item_count/total_size 必须归零
# ═══════════════════════════════════════════════════════════════════════════
if want F; then
  sec "F 幽灵体积（删空后聚合值必须归零）"
  if start_node; then
    d="$WORK_DIR/f-media"; mkdir -p "$d"
    for i in 1 2 3; do mkimg "$d/f$i.png"; done
    j="$(call import_media_folder "{\"folder_path\":\"$d\"}")"
    COL="$(jget "$j" "d['data']['id']")"
    if [ -z "$COL" ] || [ "$COL" = "None" ]; then
      bad "导入失败：$(printf '%s' "$j" | head -c 200)"
    else
      seq_ok=1
      for id in $(call get_media_collection_items "{\"collection_id\":\"$COL\"}" \
            | python3 -c 'import json,sys;[print(i["id"]) for i in json.load(sys.stdin)["data"]]'); do
        call delete_media_item_local_file "{\"item_id\":\"$id\",\"collection_id\":\"$COL\"}" >/dev/null
      done
      row="$(call list_media_collections '{}' \
        | python3 -c "
import json,sys
for c in json.load(sys.stdin)['data']:
    if c['id']=='$COL': print(c['item_count'], c['total_size'])" 2>/dev/null)"
      if [ "$row" = "0 0" ]; then
        ok "逐条删空后 item_count=0 total_size=0"
      elif [ -z "$row" ]; then
        ok "逐条删空后集合记录已移除（客户端路径会这么做）"
      else
        bad "删空后聚合值未归零：item_count/total_size = ${row}（应为 0 0）"
      fi
      items="$(call get_media_collection_items "{\"collection_id\":\"$COL\"}" \
        | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["data"]))' 2>/dev/null)"
      [ "$items" = "0" ] && ok "条目列表已清空" || bad "条目列表仍有 $items 条"
    fi

    # 对照：整目录删（delete_collection_local_files）语义是「删文件、留记录、聚合归零」
    d2="$WORK_DIR/f2-media"; mkdir -p "$d2"; mkimg "$d2/a.png"; mkimg "$d2/b.png"
    j="$(call import_media_folder "{\"folder_path\":\"$d2\"}")"
    C2="$(jget "$j" "d['data']['id']")"
    j="$(call delete_collection_local_files "{\"collection_id\":\"$C2\"}")"
    if is_ok "$j"; then
      row2="$(call list_media_collections '{}' | python3 -c "
import json,sys
for c in json.load(sys.stdin)['data']:
    if c['id']=='$C2': print(c['item_count'], c['total_size'])" 2>/dev/null)"
      [ "$row2" = "0 0" ] && ok "delete_collection_local_files 后聚合归零" \
        || bad "delete_collection_local_files 后聚合未归零：$row2"
    else
      bad "delete_collection_local_files 失败：$(jget "$j" "d.get('error','')")"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# G. 重新扫描：节点磁盘增删文件后必须能同步进库
# ═══════════════════════════════════════════════════════════════════════════
if want G; then
  sec "G 重新扫描（磁盘增删 → 库同步）"
  if start_node; then
    d="$WORK_DIR/g-media"; mkdir -p "$d"
    mkimg "$d/r1.png"; mkimg "$d/r2.png"
    j="$(call import_media_folder "{\"folder_path\":\"$d\"}")"
    COL="$(jget "$j" "d['data']['id']")"
    if [ -z "$COL" ] || [ "$COL" = "None" ]; then
      bad "导入失败：$(printf '%s' "$j" | head -c 200)"
    else
      cnt0="$(jget "$j" "d['data']['item_count']")"
      [ "$cnt0" = "2" ] && ok "导入 2 条" || note "导入后 item_count=$cnt0"

      mkimg "$d/r3.png"
      j="$(call rescan_media_folder "{\"folder_path\":\"$d\"}")"
      if is_ok "$j" && [ "$(jget "$j" "d['data']['item_count']")" = "3" ]; then
        ok "磁盘新增 1 个文件后重扫 → item_count=3"
      else
        bad "新增后重扫未生效：$(printf '%s' "$j" | head -c 200)"
      fi

      rm -f "$d/r1.png"
      j="$(call rescan_media_folder "{\"folder_path\":\"$d\"}")"
      if is_ok "$j" && [ "$(jget "$j" "d['data']['item_count']")" = "2" ]; then
        ok "磁盘删除 1 个文件后重扫 → item_count=2"
      else
        bad "删除后重扫未生效：$(printf '%s' "$j" | head -c 200)"
      fi

      # 清空整个目录再重扫：必须是「0 条且不报错」，不能假成功也不能报失败
      rm -f "$d"/*.png
      j="$(call rescan_media_folder "{\"folder_path\":\"$d\"}")"
      if is_ok "$j" && [ "$(jget "$j" "d['data']['item_count']")" = "0" ]; then
        ok "清空目录后重扫 → item_count=0（不报错、不假成功）"
      else
        bad "空目录重扫不符合契约：$(printf '%s' "$j" | head -c 200)"
      fi

      j="$(call rescan_media_folder '{"folder_path":"/no/such/dir/xyz"}')"
      must_fail_with "$j" "重新扫描" && ok "不存在的目录重扫会报错" || bad "不存在目录重扫未报错"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# H. 文件上传（原实现是占位桩，且通用 body 上限 8MB）
# ═══════════════════════════════════════════════════════════════════════════
if want H; then
  sec "H 单文件上传（原始字节流）"
  if start_node; then
    d="$WORK_DIR/h-media"; mkdir -p "$d"
    mkimg "$d/base.png"
    j="$(call import_media_folder "{\"folder_path\":\"$d\"}")"
    COL="$(jget "$j" "d['data']['id']")"
    if [ -z "$COL" ] || [ "$COL" = "None" ]; then
      bad "导入失败：$(printf '%s' "$j" | head -c 200)"
    else
      up="$WORK_DIR/h-up.png"; mkimg "$up"
      sz=$(wc -c < "$up" | tr -d ' ')
      resp="$(curl -s --max-time 60 -X POST \
        "$BASE/node/upload?dest=$d&filename=new.png&collection_id=$COL" \
        -H 'Content-Type: application/octet-stream' \
        --data-binary @"$up" 2>/dev/null)"
      if is_ok "$resp" && [ -f "$d/new.png" ]; then
        ok "上传落盘成功（$sz bytes）"
      else
        bad "上传失败：$(printf '%s' "$resp" | head -c 200)"
      fi

      # 同名必须唯一化，绝不覆盖用户文件
      resp="$(curl -s --max-time 60 -X POST \
        "$BASE/node/upload?dest=$d&filename=new.png" \
        -H 'Content-Type: application/octet-stream' --data-binary @"$up" 2>/dev/null)"
      if [ -f "$d/new (2).png" ]; then
        ok "同名上传唯一化为「new (2).png」（不覆盖）"
      else
        bad "同名上传未唯一化（可能覆盖了已有文件）：$(printf '%s' "$resp" | head -c 160)"
      fi

      # 路径穿越必须被压平到目标目录内
      resp="$(curl -s --max-time 60 -X POST \
        "$BASE/node/upload?dest=$d&filename=../../evil.png" \
        -H 'Content-Type: application/octet-stream' --data-binary @"$up" 2>/dev/null)"
      if [ ! -f "$WORK_DIR/evil.png" ] && [ ! -f "$(dirname "$WORK_DIR")/evil.png" ]; then
        ok "路径穿越 ../../evil.png 未逃出目标目录"
      else
        bad "路径穿越成功写出了目标目录（安全缺陷）"
      fi

      resp="$(curl -s --max-time 30 -X POST "$BASE/node/upload?dest=/no/such/dir&filename=x.png" \
        -H 'Content-Type: application/octet-stream' --data-binary @"$up" 2>/dev/null)"
      is_ok "$resp" && bad "不存在的 dest 却上传成功" || ok "不存在的 dest 被拒绝"

      resp="$(curl -s --max-time 30 -X POST "$BASE/node/upload?dest=$d&filename=" \
        -H 'Content-Type: application/octet-stream' --data-binary @"$up" 2>/dev/null)"
      is_ok "$resp" && bad "空 filename 却上传成功" || ok "空 filename 被拒绝"

      # 落盘后重扫，库必须看得见新文件
      j="$(call rescan_media_folder "{\"folder_path\":\"$d\"}")"
      n="$(jget "$j" "d['data']['item_count']")"
      [ -n "$n" ] && [ "$n" != "None" ] && [ "$n" -ge 3 ] 2>/dev/null \
        && ok "上传后重扫入库（item_count=${n}）" \
        || bad "上传后重扫未入库（item_count=${n}）"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# I. 账本口令：设置/清空都必须落到后端，清空要真的清干净
# ═══════════════════════════════════════════════════════════════════════════
if want I; then
  sec "I 账本邮箱口令（设置 → 清空必须真清）"
  if start_node; then
    rule='{"id":0,"name":"回归规则","host":"imap.test.com","port":993,"username":"u","protocol":"imap","enabled":false,"folder":"INBOX","sender_filter":"","parsers":[],"password":""}'
    rj="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$rule")"
    j="$(call ledger_upsert_rule "{\"rule_json\":$rj,\"password\":\"初始口令\"}")"
    RID="$(jget "$j" "d['data']['id']")"
    if [ -z "$RID" ] || [ "$RID" = "None" ]; then
      bad "建规则失败：$(printf '%s' "$j" | head -c 200)"
    else
      j="$(call ledger_has_rule_password "{\"rule_id\":$RID}")"
      [ "$(jget "$j" "d['data']['value']")" = "true" ] \
        && ok "设口令后 has_rule_password=true" || bad "设口令后 has_rule_password 不是 true"

      j="$(call ledger_set_rule_password "{\"rule_id\":$RID,\"password\":\"\"}")"
      is_ok "$j" && ok "清口令返回成功" || bad "清口令失败：$(jget "$j" "d.get('error','')")"

      j="$(call ledger_has_rule_password "{\"rule_id\":$RID}")"
      [ "$(jget "$j" "d['data']['value']")" = "false" ] \
        && ok "清空后 has_rule_password=false（修复前会一直 true）" \
        || bad "清空后 has_rule_password 仍为 true（假清除）"

      j="$(call ledger_set_rule_password '{"rule_id":999999,"password":"x"}')"
      must_fail_with "$j" "不存在" && ok "对不存在的规则设口令会报错" || bad "不存在规则却成功"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# M. 真实测试数据（用 $DATA_ROOT 里的真素材跑一遍导入/删除/重扫）
#
#    合成的小 PNG 能验协议，但验不了真实素材的坑：日文长文件名、全角符号、
#    同名不同内容、.SlimeWorks 旁路缓存、大文件的分支。所以这里拿真数据跑。
#
#    ★ 只**读**源目录：先 rsync/cp 到临时目录再导入，绝不在用户的数据根里
#      写 .SlimeWorks 或删任何东西（--delete 之类的操作只作用于副本）。
# ═══════════════════════════════════════════════════════════════════════════
if want M; then
  sec "M 真实测试数据（${DATA_ROOT}，只读源目录）"
  src_media="$DATA_ROOT/远程/媒体"
  if [ ! -d "$src_media" ]; then
    skip "数据根下没有「远程/媒体」目录（用 --data-root 指定，或放素材进去）"
  elif ! start_node; then
    : # start_node 已报告
  else
    # 挑一个真实子目录（含音频/图片），只取其中少量文件以控制耗时
    real_dir="$(find "$src_media" -mindepth 2 -maxdepth 3 -type d ! -name '.*' 2>/dev/null | head -1)"
    if [ -z "$real_dir" ]; then
      skip "没找到可用的真实素材子目录"
    else
      note "样本目录: $(echo "$real_dir" | sed "s|$src_media/||")"
      copy="$WORK_DIR/m-media"; rm -rf "$copy"; mkdir -p "$copy"
      # 只复制前 5 个媒体文件（连同其目录结构），避免动辄几 GB
      n=0
      while IFS= read -r f; do
        rel="${f#"$src_media"/}"
        mkdir -p "$copy/$(dirname "$rel")"
        cp "$f" "$copy/$rel" 2>/dev/null && n=$((n+1))
        [ "$n" -ge 5 ] && break
      done < <(find "$real_dir" -type f \( -name '*.wav' -o -name '*.webp' -o -name '*.png' -o -name '*.jpg' \) ! -name '._*' 2>/dev/null)
      if [ "$n" = "0" ]; then
        skip "样本目录里没有可识别的媒体文件"
      else
        j="$(call import_media_folder "{\"folder_path\":\"$copy\"}")"
        if is_ok "$j"; then
          COL="$(jget "$j" "d['data']['id']")"
          cnt="$(jget "$j" "d['data']['item_count']")"
          title="$(jget "$j" "d['data']['title']")"
          ok "真实素材导入 ${cnt} 条（title=${title}，含日文/全角字符名）"

          # 真实素材上的 ID 稳定性（最容易在长路径 / 全角名上出问题）
          ids_before="$(call get_media_collection_items "{\"collection_id\":\"$COL\"}" \
            | python3 -c 'import json,sys;print(" ".join(sorted(i["id"] for i in json.load(sys.stdin)["data"])))' 2>/dev/null)"
          first="$(printf '%s' "$ids_before" | awk '{print $1}')"
          call delete_media_item_local_file "{\"item_id\":\"$first\",\"collection_id\":\"$COL\"}" >/dev/null
          ids_after="$(call get_media_collection_items "{\"collection_id\":\"$COL\"}" \
            | python3 -c 'import json,sys;print(" ".join(sorted(i["id"] for i in json.load(sys.stdin)["data"])))' 2>/dev/null)"
          expect_rest="$(printf '%s' "$ids_before" | tr ' ' '\n' | grep -v -x "$first" | sort | tr '\n' ' ' | sed 's/ $//')"
          [ "$ids_after" = "$expect_rest" ] \
            && ok "真实素材删 1 条后其余 id 未变" \
            || bad "真实素材删 1 条后其余 id 变了"

          # 重扫：真实目录上应稳定（不新增、不丢条目）
          j="$(call rescan_media_folder "{\"folder_path\":\"$copy\"}")"
          if is_ok "$j"; then
            cnt2="$(jget "$j" "d['data']['item_count']")"
            ok "真实素材重扫稳定（item_count=${cnt2}）"
          else
            bad "真实素材重扫失败：$(jget "$j" "d.get('error','')")"
          fi

          # 源目录必须零污染
          if [ -n "$(find "$src_media" -name '.SlimeWorks' -newermt '-10 minutes' 2>/dev/null | head -1)" ]; then
            bad "源数据目录被写入了新的 .SlimeWorks（污染了测试素材！）"
          else
            ok "源数据目录零污染（未写入 .SlimeWorks）"
          fi
        else
          bad "真实素材导入失败：$(printf '%s' "$j" | head -c 240)"
        fi
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# J. Sentry 清空项目事件（节点有接口，客户端曾只打日志）
# ═══════════════════════════════════════════════════════════════════════════
if want J; then
  sec "J Sentry 清空项目事件"
  if start_node; then
    pid="回归项目"
    ep="$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$pid")"
    for i in 1 2; do
      curl -s --max-time 10 -X POST "$BASE/api/$ep/store/" -H 'Content-Type: application/json' \
        -d "{\"event_id\":\"e$i\",\"level\":\"error\",\"message\":\"回归事件$i\",\"timestamp\":\"2026-11-19T08:00:0$i\"}" \
        >/dev/null 2>&1
    done
    n0="$(curl -s --max-time 10 "$BASE/sentry/logs" 2>/dev/null \
      | python3 -c 'import json,sys;print(json.load(sys.stdin).get("total",-1))' 2>/dev/null)"
    if [ "$n0" = "2" ]; then
      ok "写入 2 条事件"
      resp="$(curl -s --max-time 15 -X DELETE "$BASE/sentry/projects/$ep/events" 2>/dev/null)"
      n1="$(curl -s --max-time 10 "$BASE/sentry/logs" 2>/dev/null \
        | python3 -c 'import json,sys;print(json.load(sys.stdin).get("total",-1))' 2>/dev/null)"
      del="$(jget "$resp" "d.get('deleted')")"
      if [ "$n1" = "0" ]; then
        ok "清空后事件数=0（deleted=${del}）"
      else
        bad "清空后事件数仍为 ${n1}（假清空）"
      fi
    else
      bad "事件写入失败（total=${n0}）"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# K. 真 macOS App 集成测试（可选，慢）
# ═══════════════════════════════════════════════════════════════════════════
if want K; then
  sec "K 真 macOS App 集成测试"
  if [ "$WITH_APP" != "1" ]; then
    skip "未指定 --with-app（真 App 构建约 10 分钟起）"
  elif [ ! -x "$XCODE_DEV/usr/bin/xcodebuild" ]; then
    skip "本机无完整 Xcode"
  elif [ -z "$FLUTTER_BIN" ]; then
    skip "找不到 flutter"
  else
    # 真 App 会写真实目录：HOME + CFFIXED_USER_HOME 都要指到沙箱。
    # 只设 HOME 时 NSHomeDirectory() 仍是 /Users/<你>，path_provider /
    # UserDefaults 照样写真实目录。
    apphome="$WORK_DIR/app-home"; mkdir -p "$apphome"
    # HOME 一改 cargokit 就找不到 rustup，必须显式透传
    envs=(HOME="$apphome" CFFIXED_USER_HOME="$apphome" SLIME_E2E_HOME="$apphome"
          CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}")
    pkill -f "史莱姆工坊" 2>/dev/null; sleep 1
    for f in integration_test/real_app_smoke_test.dart integration_test/real_app_node_test.dart; do
      [ -f "$f" ] || { skip "$f 不存在"; continue; }
      base="$(basename "$f" .dart)"
      # ★ 必须逐文件跑：整目录会把多个文件放同一进程，而 RustLib.init /
      #   getItInit / runApp 都不可重入，加载阶段就崩。
      if env "${envs[@]}" "$FLUTTER_BIN" test "$f" -d macos --no-pub \
           >"$LOG_DIR/K-$base.log" 2>&1; then
        ok "真 App: $base"
      else
        bad "真 App: ${base}（见 K-$base.log）"
        grep -E "\[E\]|Exception|Error:" "$LOG_DIR/K-$base.log" | head -5 | sed 's/^/        /'
      fi
    done
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# L. 全量 flutter test + 基线失败集合对照（可选，慢）
# ═══════════════════════════════════════════════════════════════════════════
if want L; then
  sec "L 全量 flutter test（含基线对照）"
  if [ "$WITH_FULL_TEST" != "1" ]; then
    skip "未指定 --with-full-test（全量+基线对照约 15 分钟）"
  elif [ -z "$FLUTTER_BIN" ]; then
    skip "找不到 flutter"
  else
    thome="$WORK_DIR/test-home"; mkdir -p "$thome"
    ( HOME="$thome" SLIME_E2E_HOME="$thome" "$FLUTTER_BIN" test --no-pub ) \
      >"$LOG_DIR/L-full.log" 2>&1
    # 只看真实报错行（`[E]` 结尾），不要 grep 普通输出行——
    # 并发交错会把通过的用例误判成失败。
    grep -E '\[E\]$' "$LOG_DIR/L-full.log" | grep -oE 'test/[a-z0-9_]+\.dart' | sort -u \
      >"$LOG_DIR/L-head-fail.txt"
    n_head=$(wc -l <"$LOG_DIR/L-head-fail.txt" | tr -d ' ')
    ok "全量 flutter test 跑完（$n_head 个文件有失败）"

    base_rev="${BASE_REV:-$(git rev-parse origin/main 2>/dev/null || git rev-parse HEAD~12)}"
    wt="$WORK_DIR/baseline"
    if git worktree add --detach "$wt" "$base_rev" >"$LOG_DIR/L-wt.log" 2>&1; then
      cp .env "$wt/.env" 2>/dev/null
      ( cd "$wt" && "$DART_BIN" run tool/stroke_icons/generate.dart ) >>"$LOG_DIR/L-wt.log" 2>&1
      ( cd "$wt" && "$DART_BIN" run build_runner build --delete-conflicting-outputs ) >>"$LOG_DIR/L-wt.log" 2>&1
      bhome="$WORK_DIR/base-home"; mkdir -p "$bhome"
      ( cd "$wt" && HOME="$bhome" "$FLUTTER_BIN" test --no-pub ) >"$LOG_DIR/L-base.log" 2>&1
      grep -E '\[E\]$' "$LOG_DIR/L-base.log" | grep -oE 'test/[a-z0-9_]+\.dart' | sort -u \
        >"$LOG_DIR/L-base-fail.txt"
      n_base=$(wc -l <"$LOG_DIR/L-base-fail.txt" | tr -d ' ')
      comm -23 "$LOG_DIR/L-head-fail.txt" "$LOG_DIR/L-base-fail.txt" >"$LOG_DIR/L-new-fail.txt"
      n_new=$(wc -l <"$LOG_DIR/L-new-fail.txt" | tr -d ' ')
      if [ "$n_new" = "0" ]; then
        ok "零新增失败（基线 $n_base 个失败文件，全部为既有 golden 环境性问题）"
      else
        bad "新增 $n_new 个失败文件："
        sed 's/^/        /' "$LOG_DIR/L-new-fail.txt"
      fi
      git worktree remove --force "$wt" >/dev/null 2>&1
    else
      skip "建基线 worktree 失败（见 L-wt.log）"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 汇总：只输出结论，细节都在日志里
# ═══════════════════════════════════════════════════════════════════════════
say ""
say "────────────────────────────────────────────────────────"
say "  通过 $PASS    失败 $FAIL    跳过 $SKIP"
if [ "$FAIL" -gt 0 ]; then
  say "  ${C_R}✗ 有失败项：${C_0}"
  for n in "${FAILED_NAMES[@]}"; do say "      - $n"; done
  say "  日志：$LOG_DIR"
  [ "$KEEP" = "0" ] && say "  （需要排查临时目录？加 --keep 重跑）"
  exit 1
fi
say "  ${C_G}✓ 全部通过${C_0}"
say "  日志：$LOG_DIR"
exit 0

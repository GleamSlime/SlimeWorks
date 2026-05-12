#!/usr/bin/env bash
# 解压脚本 macOS 版 —— 对应 bat 版本逻辑
# 依赖：7z（支持 zip/7z/rar）
#   安装：brew install sevenzip
#   或使用系统自带 unzip 处理 zip（脚本会自动回退）
# 用法：
#   ./解压脚本.sh                 # 运行后提示输入密码
#   ./解压脚本.sh <密码>          # 直接传入密码
#   ./解压脚本.sh ""              # 无密码解压

set -uo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
DELETE_FLAG="n"          # y=解压后删除改名的 zip；n=保留（与 bat 保持一致）
DEFAULT_PASSWORD="yejiang"

# ── 工具检查 ──────────────────────────────────────────────────────────────────
if command -v 7z &>/dev/null; then
    EXTRACTOR="7z"
elif command -v 7zz &>/dev/null; then
    EXTRACTOR="7zz"        # Homebrew sevenzip 新版二进制名
else
    echo "❌ 未找到 7z，请先安装：brew install sevenzip"
    exit 1
fi

# ── 密码处理 ──────────────────────────────────────────────────────────────────
PASSWORD="$DEFAULT_PASSWORD"
if [[ $# -ge 1 ]]; then
    PASSWORD="$1"
else
    printf "请输入密码（回车使用默认 \"%s\" / 留空表示无密码）: " "$DEFAULT_PASSWORD"
    read -r __pw_input
    if [[ -n "$__pw_input" ]]; then
        PASSWORD="$__pw_input"
    fi
fi

# ── 路径 ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT0="$SCRIPT_DIR/output0"
OUTPUT="$SCRIPT_DIR/output"

mkdir -p "$OUTPUT0"
mkdir -p "$OUTPUT"

# ── 辅助：7z 解压（自动处理有/无密码）───────────────────────────────────────
do_extract() {
    local archive="$1"
    local dest="$2"
    local args=("x" "-y" "-o${dest}" "--" "$archive")
    if [[ -n "$PASSWORD" ]]; then
        args=("x" "-y" "-p${PASSWORD}" "-o${dest}" "--" "$archive")
    fi
    "$EXTRACTOR" "${args[@]}" >/dev/null
}

# ── 第一步：查找 mp4，改名为 zip 并解压到 output0 ────────────────────────────
echo "🔍 第一步：查找 mp4，改名为 zip 并解压到 output0 对应路径"
echo "──────────────────────────────────────────────────────────"

find "$SCRIPT_DIR" -type f -name "*.mp4" -print0 | sort -z | while IFS= read -r -d '' mp4_file; do
    # 跳过 output / output0 目录内的文件
    case "$mp4_file" in
        "$OUTPUT/"*|"$OUTPUT0/"*) continue ;;
    esac

    dir="$(dirname "$mp4_file")"
    filename="$(basename "$mp4_file" .mp4)"
    zip_file="$dir/$filename.zip"

    # 改名 mp4 → zip
    mv -- "$mp4_file" "$zip_file"

    # 计算相对路径（相对于脚本目录）
    relpath="${dir#"${SCRIPT_DIR}/"}"
    [[ "$relpath" == "$dir" ]] && relpath=""   # mp4 在脚本目录根下时

    if [[ -n "$relpath" ]]; then
        target_dir="$OUTPUT0/$relpath"
    else
        target_dir="$OUTPUT0"
    fi
    mkdir -p "$target_dir"

    echo "📦 解压 \"$filename.zip\" → \"$target_dir/\""
    if [[ -f "$zip_file" ]]; then
        do_extract "$zip_file" "$target_dir" \
            && echo "   ✓ 成功" \
            || echo "   ⚠️  解压失败：$filename.zip（密码错误或文件损坏？）"
    else
        echo "   ⚠️  跳过：文件不存在 $zip_file"
    fi

    # 根据 DELETE_FLAG 决定是否删除改名后的 zip
    if [[ "$DELETE_FLAG" == "y" ]]; then
        rm -f -- "$zip_file"
    fi
done

# ── 第二步：从 output0 再次解压 .zip / .7z 到 output ─────────────────────────
echo ""
echo "🔁 第二步：从 output0 中再次解压 .zip / .7z 到 output 中..."
echo "──────────────────────────────────────────────────────────"

find "$OUTPUT0" -type f \( -name "*.zip" -o -name "*.7z" \) -print0 | sort -z | while IFS= read -r -d '' archive; do
    # 计算相对于 output0 的目录层级
    rel="${archive#"${OUTPUT0}/"}"
    relpath_dir="$(dirname "$rel")"

    if [[ "$relpath_dir" == "." ]]; then
        out_path="$OUTPUT"
    else
        out_path="$OUTPUT/$relpath_dir"
    fi
    mkdir -p "$out_path"

    echo "📂 二次解压：$(basename "$archive") → $out_path/"
    do_extract "$archive" "$out_path" \
        && echo "   ✓ 成功" \
        || echo "   ⚠️  解压失败：$(basename "$archive")"
done

echo ""
echo "✅ 所有处理完成！"
echo ""
echo "✅ 所有处理完成！"

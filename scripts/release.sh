#!/bin/bash
set -e

# ========================================
# SlimeWorks 一键发版脚本
# 用法: bash scripts/release.sh <版本号> <build_number>
# 示例: bash scripts/release.sh 1.0.1 26
# ========================================

VERSION="$1"
BUILD_NUMBER="$2"
APP_NAME="史莱姆工坊"
PLATFORM=$(uname -s)

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
  echo "❌ 用法: bash scripts/release.sh <版本号> <build_number>"
  echo "   示例: bash scripts/release.sh 1.0.1 26"
  exit 1
fi

echo "🚀 开始发版 ${APP_NAME} v${VERSION}+${BUILD_NUMBER}"

# 1. 更新 pubspec.yaml 版本号
echo ""
echo "📝 [1/7] 更新版本号..."
sed -i.bak "s/^version: .*/version: ${VERSION}+${BUILD_NUMBER}/" pubspec.yaml
rm -f pubspec.yaml.bak
echo "   ✅ pubspec.yaml version: ${VERSION}+${BUILD_NUMBER}"

# 2. 代码生成
echo ""
echo "⚙️  [2/7] 运行代码生成..."
flutter_rust_bridge_codegen generate
flutter pub run build_runner build --delete-conflicting-outputs
echo "   ✅ 代码生成完成"

# 3. 静态检查
echo ""
echo "🔍 [3/7] 运行静态检查..."
flutter analyze
echo "   ✅ 静态检查通过"

# 4. 打包
echo ""
echo "📦 [4/7] 打包安装包..."
if [ "$PLATFORM" = "Darwin" ]; then
  fastforge release --name release --jobs release-macos
else
  fastforge release --name release --jobs release-windows
fi
echo "   ✅ 打包完成"

# 5. Sparkle 签名
echo ""
echo "🔑 [5/7] 签名安装包..."
if [ "$PLATFORM" = "Darwin" ]; then
  DMG_PATH=$(find dist/ -name "*.dmg" -type f | head -1)
  if [ -n "$DMG_PATH" ]; then
    dart run auto_updater:sign "$DMG_PATH"
    # 获取签名值和文件大小
    SIGNATURE=$(dart run auto_updater:sign "$DMG_PATH" 2>&1 | grep -o 'edSignature=[^ ]*' | cut -d= -f2 || true)
    FILE_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || echo "0")
    echo "   ✅ 签名完成: $DMG_PATH"
    echo "   📏 文件大小: ${FILE_SIZE} bytes"
  else
    echo "   ⚠️  未找到 DMG 文件"
  fi
fi

# 6. 代码签名（macOS ad-hoc）
if [ "$PLATFORM" = "Darwin" ]; then
  echo ""
  echo "🔏 [6/7] Ad-hoc 代码签名..."
  DMG_PATH=$(find dist/ -name "*.dmg" -type f | head -1)
  if [ -n "$DMG_PATH" ]; then
    codesign --force --deep --sign - "$DMG_PATH" 2>/dev/null || echo "   ⚠️  代码签名跳过（无证书）"
    echo "   ✅ 代码签名完成"
  fi
else
  echo ""
  echo "🔏 [6/7] Windows 代码签名跳过（需在 Windows 端执行）"
fi

# 7. 输出结果
echo ""
echo "🎉 [7/7] 发版完成！"
echo ""
echo "📦 安装包:"
ls -lh dist/ 2>/dev/null || echo "   dist/ 目录为空"
echo ""
echo "📋 后续步骤:"
echo "   1. 上传到 GitHub Releases:"
echo "      gh release create v${VERSION} dist/* --title \"v${VERSION}\" --notes \"更新说明\""
echo "   2. 更新 docs/appcast.xml:"
echo "      - sparkle:version=\"${BUILD_NUMBER}\""
echo "      - sparkle:shortVersionString=\"${VERSION}\""
echo "      - sparkle:edSignature=\"签名值\""
echo "      - length=\"文件大小\""
echo "   3. 推送 appcast.xml 到 GitHub Pages / 服务器"

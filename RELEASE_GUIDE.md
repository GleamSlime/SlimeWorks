# SlimeWorks 发版指南

> 技术栈：fastforge（打包） + auto_updater（自动更新） + GitHub Releases（托管）

---

## 一、前置条件

### 全局工具

```bash
# 安装 fastforge（flutter_distributor 的继任者）
dart pub global activate fastforge

# 安装 auto_updater CLI（用于生成签名密钥）
# 添加 auto_updater 依赖后自动可用
```

### 平台要求

| 平台 | 要求 |
|------|------|
| macOS | Xcode Command Line Tools, create-dmg（`brew install create-dmg`） |
| Windows | Inno Setup 6（[下载](https://jrsoftware.org/isdl.php)）, OpenSSL（`choco install openssl`） |

### 项目配置确认

- `pubspec.yaml` 中 `version: x.y.z+n` 已更新
- `flutter analyze` 无错误
- `flutter_rust_bridge_codegen generate` 绑定已更新
- `flutter pub run build_runner build` 代码生成已完成

---

## 二、目录结构

```
slime_works/
├── distribute_options.yaml              # fastforge 主配置
├── macos/packaging/dmg/make_config.yaml # macOS DMG 布局配置
├── windows/packaging/exe/inno_setup.iss # Windows Inno Setup 模板
├── docs/appcast.xml                     # Sparkle 更新源模板
├── scripts/release.sh                   # 一键发版脚本
└── dist/                                # 打包产物输出目录
```

---

## 三、fastforge 配置

### distribute_options.yaml

```yaml
output: dist/
releases:
  - name: release
    jobs:
      - name: release-macos
        package:
          platform: macos
          target: dmg
          build_args:
            release: true
      - name: release-windows
        package:
          platform: windows
          target: exe
          build_args:
            release: true
```

### macOS DMG 配置 (macos/packaging/dmg/make_config.yaml)

```yaml
title: 史莱姆工坊
contents:
  - x: 448
    y: 244
    type: link
    path: "/Applications"
  - x: 192
    y: 244
    type: file
    path: 史莱姆工坊.app
```

### Windows EXE 配置 (windows/packaging/exe/inno_setup.iss)

fastforge 会自动使用 Inno Setup 模板，如需自定义可编辑 `windows/packaging/exe/inno_setup.iss`。
关键配置项已由 distribute_options.yaml 中的变量注入。

---

## 四、auto_updater 自动更新配置

### 4.1 生成签名密钥

**macOS（EdDSA）：**
```bash
# 首次使用前需先执行 pod install 安装 Sparkle
cd macos && pod install && cd ..
dart run auto_updater:generate_keys
```
输出示例：
```
SUPublicEDKey: yAXFDhgJ/LYFRcYsW/UT/gLJ4hm4IE2wT6aiJW71kNg=
```
将此公钥添加到 `macos/Runner/Info.plist`。

**Windows（DSA）：**
在 Windows 机器上执行相同命令，将公钥添加到 Windows 配置。

### 4.2 Info.plist 添加 Sparkle 公钥

> 当前仓库**已移除** `SUPublicEDKey`，Sparkle 不再校验更新包签名。
> 恢复校验时再按下面方式加回去，并让 CI 用私钥生成 `sparkle:edSignature`。

在 `macos/Runner/Info.plist` 的 `</dict>` 前添加：
```xml
<key>SUPublicEDKey</key>
<string>你的公钥</string>
```

### 4.3 main.dart 集成

```dart
import 'package:auto_updater/auto_updater.dart';

// 在 main() 中，桌面端初始化阶段添加：
if (Platform.isMacOS || Platform.isWindows) {
  await autoUpdater.setFeedURL('https://你的域名/appcast.xml');
  await autoUpdater.checkForUpdates();
  await autoUpdater.setScheduledCheckInterval(3600); // 每小时检查一次
}
```

### 4.4 appcast.xml 更新源

托管在 GitHub Releases 或自有服务器，格式如下：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/rss-sparkle-1.0">
  <channel>
    <title>史莱姆工坊</title>
    <language>zh-CN</language>
    <item>
      <title>1.0.1</title>
      <description>
        <![CDATA[修复了若干问题，优化性能]]>
      </description>
      <pubDate>Thu, 29 May 2026 00:00:00 +0800</pubDate>
      <enclosure
        url="https://github.com/GleamSlime/slime_works/releases/download/v1.0.1/史莱姆工坊-1.0.1-macos.dmg"
        sparkle:version="26"
        sparkle:shortVersionString="1.0.1"
        sparkle:edSignature="EdDSA签名值"
        length="52428800"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

---

## 五、发版流程

### 5.1 日常发版步骤

```bash
# 1. 更新版本号
#    编辑 pubspec.yaml: version: 1.0.1+26

# 2. 更新代码生成
flutter_rust_bridge_codegen generate
flutter pub run build_runner build

# 3. 检查代码
flutter analyze

# 4. 打包（macOS 端执行）
fastforge release --name release

# 5. 签名安装包
dart run auto_updater:sign dist/史莱姆工坊-1.0.1-macos.dmg

# 6. 上传到 GitHub Releases
gh release create v1.0.1 \
  dist/史莱姆工坊-1.0.1-macos.dmg \
  dist/史莱姆工坊-1.0.1-windows.exe \
  --title "v1.0.1" \
  --notes "修复了若干问题"

# 7. 更新 appcast.xml 并推送到仓库
#    更新 sparkle:version / sparkle:shortVersionString / edSignature / length / url
```

### 5.2 一键发版脚本

```bash
bash scripts/release.sh 1.0.1 26
```

---

## 六、签名与公证（可选但推荐）

### macOS Ad-hoc 签名（无需 Apple Developer 账号）

```bash
codesign --force --deep --sign - "dist/史莱姆工坊-1.0.1-macos.dmg"
```

### macOS 正式签名 + 公证（需要 Apple Developer 账号）

```bash
# 签名
codesign --force --deep --sign "Developer ID Application: 你的名字 (TEAM_ID)" \
  "build/macos/Build/Products/Release/史莱姆工坊.app"

# 公证
xcrun notarytool submit "dist/史莱姆工坊-1.0.1-macos.dmg" \
  --apple-id "你的AppleID" \
  --team-id "TEAM_ID" \
  --password "App专用密码" \
  --wait

# 装订公证票据
xcrun stapler staple "dist/史莱姆工坊-1.0.1-macos.dmg"
```

---

## 七、注意事项

| 事项 | 说明 |
|------|------|
| 交叉编译 | macOS 构建必须在 macOS 机器，Windows 构建必须在 Windows 机器 |
| capture_proxy | 仅桌面端 cdylib 动态库，确认 Release 构建中正确包含 |
| Rust 版本 | 确保 Rust toolchain 与构建机器一致（1.92.0） |
| entitlements | 沙盒已关闭（`app-sandbox=false`），非 App Store 分发无需开启 |
| Bonjour | 局域网传输依赖 mDNS，DMG 安装后需确认网络权限弹窗正常 |
| Sparkle 签名 | 每次发版必须用 `dart run auto_updater:sign` 签名安装包，否则客户端拒绝更新 |
| appcast.xml | 必须通过 HTTPS 托管，GitHub Pages / Cloudflare 均可 |
| fastforge | flutter_distributor 已改名为 fastforge，配置格式和命令基本不变 |

---

## 八、GitHub Actions CI/CD

### 8.1 工作流说明

提交到 `main` 分支时，GitHub Actions 自动执行以下流程：

```
push main → detect-version → build-macos (DMG) + build-windows (EXE) → release (GitHub Release + appcast.xml 部署)
```

| Job | 运行环境 | 产物 |
|-----|----------|------|
| `detect-version` | ubuntu-latest | 从 pubspec.yaml 提取版本号和构建号 |
| `build-macos` | macos-latest | `.dmg` 安装包（含 Sparkle 签名） |
| `build-windows` | windows-latest | `.exe` 安装程序（Inno Setup） |
| `release` | ubuntu-latest | 创建 GitHub Release + 部署 appcast.xml 到 GitHub Pages |

### 8.2 工作流文件

`.github/workflows/release.yml`

### 8.3 GitHub Pages 配置

appcast.xml 通过 GitHub Pages 托管，访问地址：
```
https://gleamslime.github.io/slime_works/appcast.xml
```

**首次使用需配置：**
1. 进入仓库 Settings → Pages
2. Source 选择 `gh-pages` 分支
3. 保存

### 8.4 触发条件

- ✅ 推送到 `main` 分支时触发
- ❌ 仅修改 `docs/`、`*.md`、`.gitignore` 时不触发

### 8.5 版本号来源

`version` 从 `pubspec.yaml` 提取（`x.y.z+n` 的 `x.y.z` 部分），构建号由 CI 统一覆盖：

- 展示用构建号（About 页 / Release tag）：`YYYYMMDD.commit短hash`
- 数字构建号（macOS CFBundleVersion、Windows 文件版本、appcast `sparkle:version`）：`github.run_number`

两者分开是有意为之：tag 需要可读，Sparkle / WinSparkle 只认单调递增的数字。
若数字构建号与安装包内的版本不一致，客户端会永远提示"发现新版本"。

### 8.6 更新签名现状

- macOS：`Info.plist` 未配置 `SUPublicEDKey`，Sparkle 跳过 EdDSA 校验，`appcast.xml` 不写 `edSignature`
- Windows：`Runner.rc` 未嵌入 DSAPub，WinSparkle 跳过验签，`appcast.xml` 不写 `dsaSignature`
- 本次改动前的旧版本内置了公钥，升级到第一个"关闭验签"的版本需要手动下载安装一次

### 8.7 本地发版（备选）

如需手动发版，仍可使用一键脚本：
```bash
bash scripts/release.sh 1.0.1 26
```

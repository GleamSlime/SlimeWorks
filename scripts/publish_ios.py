#!/usr/bin/env python3
"""
iOS 一键构建并发布到蒲公英脚本

完整流程（推荐）：
  flutter build ios --release --no-codesign
  → xcodebuild archive → xcodebuild exportArchive（生成 IPA）→ 上传蒲公英

用法：
  # 完整构建并上传（xcodebuild archive→export，效果等价于 Xcode 产品→Archive→Distribute App→Release Testing）
  python3 publish_ios.py --use-xcodebuild -desc="1. 新功能\n2. Bug 修复"

  # 从已有 .xcarchive 直接 export + 上传（上次已 archive 但未 export 时）
  python3 publish_ios.py --from-archive build/ios/archive/Runner.xcarchive -desc="修复版"

  # 构建并上传（优先 flutter build ipa，失败自动切换到 xcodebuild）
  python3 publish_ios.py -desc="1. 新功能\n2. Bug 修复"

  # 仅上传已有 IPA（不重新构建）
  python3 publish_ios.py --ipa-only -desc="xxx"

  # 仅构建，不上传
  python3 publish_ios.py --build-only
"""

import os
import re
import sys
import time
import argparse
import requests

# ── 请在此处填写你的密钥 ──────────────────────────────────────────────────
PGYER_USER_KEY = "26d5078bcd28443c3554aae6a0812ee2"          # 蒲公英 User Key（https://www.pgyer.com/account/api）
PGYER_API_KEY  = "23fcb3ecd9274b169866fcb9d621e061"          # 蒲公英 API Key
TEAM_ID        = ""          # Apple Developer Team ID（留空则自动签名）
BUNDLE_ID      = ""          # Bundle Identifier（留空则使用项目默认值）
IPA_PATH       = "build/ios/ipa/史莱姆工坊.ipa"  # IPA 输出路径
# ─────────────────────────────────────────────────────────────────────────


class ProgressBar:
    """简单进度条"""

    def __init__(self, total_size: int, description: str = "上传中"):
        self.total_size = total_size
        self.description = description
        self.uploaded = 0
        self.start_time = time.time()

    def update(self, chunk_size: int):
        self.uploaded += chunk_size
        percent = min(100.0, self.uploaded / self.total_size * 100)
        elapsed = time.time() - self.start_time
        speed = self.uploaded / elapsed / 1024 / 1024 if elapsed > 0 else 0
        if speed > 0 and percent < 100:
            eta = (self.total_size - self.uploaded) / (speed * 1024 * 1024)
            eta_str = f"{int(eta // 60)}:{int(eta % 60):02d}"
        else:
            eta_str = "00:00"
        bar_length = 30
        filled = int(bar_length * percent / 100)
        bar = "█" * filled + "░" * (bar_length - filled)
        uploaded_mb = self.uploaded / 1024 / 1024
        total_mb = self.total_size / 1024 / 1024
        text = (
            f"\r\033[0;36;40m{self.description}: [{bar}] {percent:.1f}%"
            f" ({uploaded_mb:.1f}/{total_mb:.1f}MB) {speed:.1f}MB/s ETA:{eta_str}\033[0m"
        )
        print(text, end="", flush=True)
        if percent >= 100:
            print()


def _upload_with_progress(url: str, files: dict, data: dict, headers: dict, timeout: int = 600):
    """带进度显示的文件上传"""
    file_key = list(files.keys())[0]
    original_file = files[file_key]
    file_size = os.path.getsize(original_file.name)
    file_name = os.path.basename(original_file.name)
    progress = ProgressBar(file_size, f"上传 {file_name}")

    class _ProgressFile:
        def __init__(self, fp):
            self._fp = fp

        def read(self, size=-1):
            chunk = self._fp.read(size)
            if chunk:
                progress.update(len(chunk))
            return chunk

        def __getattr__(self, name):
            return getattr(self._fp, name)

    print("\033[0;36;40m 正在上传文件到蒲公英服务器...\033[0m")
    with open(original_file.name, "rb") as f:
        wrapped = {file_key: _ProgressFile(f)}
        try:
            resp = requests.post(url, data=data, headers=headers, files=wrapped, timeout=timeout)
            print("\033[0;32;40m 文件上传完成，服务器处理中...\033[0m")
            return resp
        except requests.exceptions.Timeout:
            print(f"\n\033[0;31;40m 上传超时（超过 {timeout} 秒），请检查网络后重试\033[0m")
            raise


def upload_to_pgyer(ipa_path: str, description: str) -> bool:
    """上传 IPA 到蒲公英"""
    if not PGYER_USER_KEY or not PGYER_API_KEY:
        print("\033[0;31;40m 错误：请先在脚本顶部填写 PGYER_USER_KEY 和 PGYER_API_KEY\033[0m")
        return False
    if not os.path.exists(ipa_path):
        print(f"\033[0;31;40m 错误：找不到 IPA 文件：{ipa_path}\033[0m")
        print("\033[0;33;40m 请先构建 IPA 或使用 --use-xcodebuild 参数\033[0m")
        return False

    file_size = os.path.getsize(ipa_path)
    print(f"\033[0;36;40m IPA 路径：{ipa_path}，大小：{file_size / 1024 / 1024:.1f} MB\033[0m")

    url = "https://upload.pgyer.com/apiv1/app/upload"
    headers = {"enctype": "multipart/form-data"}
    payload = {
        "uKey": PGYER_USER_KEY,
        "_api_key": PGYER_API_KEY,
        "updateDescription": description,
    }
    try:
        with open(ipa_path, "rb") as ipa:
            resp = _upload_with_progress(url, {"file": ipa}, payload, headers)
        resp.raise_for_status()
        result = resp.json()
        if result.get("code") == 0:
            shortcut = result["data"]["appShortcutUrl"]
            print(f"\033[0;32;40m ✓ iOS IPA 上传成功！\033[0m")
            print(f"\033[0;32;40m 📱 下载链接：https://www.pgyer.com/{shortcut}\033[0m")
            return True
        else:
            msg = result.get("message", "未知错误")
            print(f"\033[0;31;40m ✗ 上传失败：{msg}\033[0m")
            return False
    except requests.RequestException as e:
        print(f"\033[0;31;40m ✗ 网络请求失败：{e}\033[0m")
        return False
    except Exception as e:
        print(f"\033[0;31;40m ✗ 上传出错：{e}\033[0m")
        return False


def create_export_options_plist(team_id: str = "", method: str = "release-testing") -> str:
    """生成 ExportOptions.plist
    
    method 可选值:
      release-testing  — 蒲公英等内测分发（默认）
      ad-hoc           — Ad Hoc
      app-store        — App Store Connect
      development      — 开发调试
    """
    team_field = f"    <key>teamID</key>\n    <string>{team_id}</string>\n" if team_id else ""
    content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>{method}</string>
{team_field}    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>"""
    path = "ios/ExportOptions.plist"
    os.makedirs("ios", exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    print(f"\033[0;36;40m ExportOptions.plist 已生成：{path}（method={method}）\033[0m")
    return path


def export_archive_to_ipa(
    archive_path: str,
    ipa_dir: str,
    team_id: str = "",
    method: str = "release-testing",
    original_dir: str | None = None,
) -> str | None:
    """从 .xcarchive 导出 IPA，返回生成的 IPA 路径，失败返回 None。

    该步骤对应 Xcode 中 Archive 后点击 Distribute App → Release Testing 的流程。
    """
    if original_dir is None:
        original_dir = os.getcwd()

    os.makedirs(ipa_dir, exist_ok=True)
    plist_path = create_export_options_plist(team_id, method)

    # plist 路径相对于项目根目录，exportArchive 从 ios/ 内调用时需要带 ../
    abs_plist = os.path.abspath(plist_path)
    abs_archive = os.path.abspath(archive_path)
    abs_ipa_dir = os.path.abspath(ipa_dir)

    export_parts = [
        "xcodebuild -exportArchive",
        f"-archivePath \"{abs_archive}\"",
        f"-exportPath \"{abs_ipa_dir}\"",
        f"-exportOptionsPlist \"{abs_plist}\"",
        "-allowProvisioningUpdates",
    ]
    export_cmd = " \\\n    ".join(export_parts)
    print(f"\033[0;36;40m 执行 exportArchive:\n{export_cmd}\033[0m")

    if os.system(export_cmd) != 0:
        print("\033[0;31;40m IPA 导出失败！\033[0m")
        print("\033[0;33;40m 常见原因：\033[0m")
        print("\033[0;33;40m  1. 证书/Provisioning Profile 未配置或已过期\033[0m")
        print("\033[0;33;40m  2. method 与证书类型不匹配（蒲公英需用 release-testing 或 ad-hoc）\033[0m")
        print("\033[0;33;40m  3. 可先在 Xcode 中执行 Product → Archive → Distribute App 确认能通过\033[0m")
        return None

    # 查找并统一命名 IPA
    ipa_files = [f for f in os.listdir(abs_ipa_dir) if f.endswith(".ipa")]
    if not ipa_files:
        print(f"\033[0;31;40m 未找到 IPA 文件，导出目录：{abs_ipa_dir}\033[0m")
        return None

    src = os.path.join(abs_ipa_dir, ipa_files[0])
    dst = os.path.join(abs_ipa_dir, os.path.basename(IPA_PATH))
    if src != dst:
        os.rename(src, dst)
    size_mb = os.path.getsize(dst) / 1024 / 1024
    print(f"\033[0;32;40m IPA 已生成：{dst}（{size_mb:.1f} MB）\033[0m")
    return dst


def build_with_xcodebuild(team_id: str = "", bundle_id: str = "", method: str = "release-testing") -> bool:
    """完整 flutter build ios → xcodebuild archive → exportArchive 流程

    等价于在 Xcode 中依次执行：
      1. Product → Build（flutter build ios --no-codesign）
      2. Product → Archive
      3. Organizer → Distribute App → Release Testing → Export
    """
    original_dir = os.getcwd()
    ios_dir = os.path.join(original_dir, "ios")

    print("\033[0;36;40m 步骤 1/4：flutter build ios --release --no-codesign\033[0m")
    if os.system("flutter build ios --release --no-codesign") != 0:
        print("\033[0;31;40m Flutter iOS bundle 构建失败！\033[0m")
        return False

    os.chdir(ios_dir)
    print("\033[0;36;40m 步骤 2/4：pod install\033[0m")
    if os.system("pod install") != 0:
        print("\033[0;33;40m pod install 警告，继续...\033[0m")

    # archive 路径放在 ios/ 内，xcodebuild 从 ios/ 目录执行更稳定
    archive_path = "build/Runner.xcarchive"
    ipa_dir = os.path.join(original_dir, "build/ios/ipa")
    os.makedirs("build", exist_ok=True)

    archive_parts = [
        "xcodebuild archive",
        "-workspace Runner.xcworkspace",
        "-scheme Runner",
        "-configuration Release",
        f"-archivePath {archive_path}",
        "-allowProvisioningUpdates",
        "CODE_SIGN_STYLE=Automatic",
    ]
    if team_id:
        archive_parts.append(f"DEVELOPMENT_TEAM={team_id}")
    if bundle_id:
        archive_parts.append(f"PRODUCT_BUNDLE_IDENTIFIER={bundle_id}")

    print("\033[0;36;40m 步骤 3/4：xcodebuild archive（等价于 Xcode Product → Archive）\033[0m")
    if os.system(" \\\n    ".join(archive_parts)) != 0:
        print("\033[0;31;40m Archive 失败！请检查证书和 Bundle ID 配置，或先在 Xcode 中手动 Archive 一次\033[0m")
        os.chdir(original_dir)
        return False

    os.chdir(original_dir)

    print(f"\033[0;36;40m 步骤 4/4：xcodebuild exportArchive（等价于 Distribute App → {method}）\033[0m")
    abs_archive = os.path.join(ios_dir, archive_path)
    ipa_file = export_archive_to_ipa(abs_archive, ipa_dir, team_id, method, original_dir)
    return ipa_file is not None


def build_with_flutter(bundle_id: str = "") -> bool:
    """使用 flutter build ipa，失败自动切换到 xcodebuild"""
    cmd = "flutter build ipa --release"
    if bundle_id:
        cmd += f" --bundle-id={bundle_id}"
    print(f"\033[0;36;40m 执行：{cmd}\033[0m")
    if os.system(cmd) == 0:
        print("\033[0;32;40m flutter build ipa 成功！\033[0m")
        return True
    print("\033[0;33;40m flutter build ipa 失败，自动切换到 xcodebuild...\033[0m")
    return build_with_xcodebuild(TEAM_ID or "", bundle_id)


def update_version_numbers():
    """自增 pubspec.yaml + build.gradle 版本号"""
    pubspec_path = "pubspec.yaml"
    try:
        with open(pubspec_path) as f:
            content = f.read()
        m = re.search(r"version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)", content)
        if not m:
            print("\033[0;31;40m 错误：pubspec.yaml 中未找到 version: x.x.x+N\033[0m")
            sys.exit(1)
        version, build_number = m.group(1), int(m.group(2))
        new_build = build_number + 1
        with open(pubspec_path, "w") as f:
            f.write(content.replace(f"version: {version}+{build_number}", f"version: {version}+{new_build}"))
        print(f"\033[0;32;40m pubspec.yaml → {version}+{new_build}\033[0m")

        gradle_path = "android/app/build.gradle"
        if os.path.exists(gradle_path):
            with open(gradle_path) as f:
                gc = f.read()
            gm = re.search(r"versionCode\s+([0-9]+)", gc)
            if gm:
                with open(gradle_path, "w") as f:
                    f.write(gc.replace(f"versionCode {gm.group(1)}", f"versionCode {new_build}"))
                print(f"\033[0;32;40m build.gradle → versionCode {new_build}\033[0m")
    except FileNotFoundError as e:
        print(f"\033[0;31;40m 错误：找不到 {e.filename}\033[0m")
        sys.exit(1)


def parse_args():
    p = argparse.ArgumentParser(description="iOS 一键构建并发布到蒲公英")
    p.add_argument("-desc", "--description", default="优化体验，修复已知问题")
    p.add_argument("--ipa-only", action="store_true", help="跳过构建，直接上传已有 IPA")
    p.add_argument("--build-only", action="store_true", help="仅构建，不上传")
    p.add_argument("--use-xcodebuild", action="store_true", help="强制使用 xcodebuild archive+export 构建")
    p.add_argument("--from-archive", default="", metavar="PATH",
                   help="跳过构建，从已有 .xcarchive 直接 exportArchive 生成 IPA（例：ios/build/Runner.xcarchive）")
    p.add_argument("--export-method", default="release-testing",
                   choices=["release-testing", "ad-hoc", "app-store", "development"],
                   help="IPA 导出方式（默认: release-testing，适用于蒲公英）")
    p.add_argument("--team-id", default="", help="Apple Developer Team ID")
    p.add_argument("--bundle-id", default="", help="Bundle Identifier")
    p.add_argument("--ipa-path", default="", help=f"IPA 路径（默认：{IPA_PATH}）")
    return p.parse_args()


def main():
    args = parse_args()
    team_id = args.team_id or TEAM_ID
    bundle_id = args.bundle_id or BUNDLE_ID
    ipa_path = args.ipa_path or IPA_PATH

    update_version_numbers()

    if args.from_archive:
        # ── 模式 A：从已有 .xcarchive 直接 export（跳过 flutter build + xcodebuild archive）──
        print("\033[0;36;40m\n=== 从已有 Archive Export IPA ===\033[0m")
        ipa_dir = os.path.join(os.getcwd(), "build/ios/ipa")
        ipa_file = export_archive_to_ipa(
            args.from_archive, ipa_dir, team_id, args.export_method
        )
        if ipa_file is None:
            print("\033[0;31;40m Export 失败，退出。\033[0m")
            sys.exit(1)
        ipa_path = ipa_file
    elif not args.ipa_only:
        # ── 模式 B：完整构建 ──
        print("\033[0;36;40m\n=== 开始 iOS 构建 ===\033[0m")
        ok = (
            build_with_xcodebuild(team_id, bundle_id, args.export_method)
            if args.use_xcodebuild
            else build_with_flutter(bundle_id)
        )
        if not ok:
            print("\033[0;31;40m 构建失败，退出。\033[0m")
            sys.exit(1)

    if not args.build_only:
        print("\033[0;36;40m\n=== 开始上传到蒲公英 ===\033[0m")
        if not upload_to_pgyer(ipa_path, args.description):
            sys.exit(1)

    print("\033[0;32;40m\n=== 全部完成 ===\033[0m")


if __name__ == "__main__":
    main()

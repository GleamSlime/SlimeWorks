import os
import sys
import re
import argparse
import requests
import time

# python3 auto.py -desc="1. 新增xxx功能\n2. 优化xxx性能\n3. 修复xxx问题"
# python3 auto.py --description="更新内容"
# python3 auto.py

class ProgressBar:
    """简单的进度条显示类"""
    def __init__(self, total_size, description="上传中"):
        self.total_size = total_size
        self.description = description
        self.uploaded = 0
        self.start_time = time.time()
        
    def update(self, chunk_size):
        """更新进度"""
        self.uploaded += chunk_size
        percent = min(100.0, (self.uploaded / self.total_size) * 100)
        
        # 计算速度
        elapsed_time = time.time() - self.start_time
        if elapsed_time > 0:
            speed = self.uploaded / elapsed_time / 1024 / 1024  # MB/s
        else:
            speed = 0
            
        # 计算剩余时间
        if speed > 0 and percent < 100:
            remaining_size = self.total_size - self.uploaded
            eta = remaining_size / (speed * 1024 * 1024)
            eta_str = f"{int(eta//60)}:{int(eta%60):02d}"
        else:
            eta_str = "00:00"
            
        # 创建进度条
        bar_length = 30
        filled_length = int(bar_length * percent / 100)
        bar = '█' * filled_length + '░' * (bar_length - filled_length)
        
        # 格式化大小
        uploaded_mb = self.uploaded / 1024 / 1024
        total_mb = self.total_size / 1024 / 1024
        
        # 显示进度
        progress_text = f"\r\033[0;36;40m{self.description}: [{bar}] {percent:.1f}% ({uploaded_mb:.1f}/{total_mb:.1f}MB) {speed:.1f}MB/s ETA:{eta_str}\033[0m"
        print(progress_text, end='', flush=True)
        
        if percent >= 100:
            print()  # 完成后换行

def upload_file_with_progress(url, files, data, headers, timeout=300):
    """带进度显示的文件上传
    
    Args:
        url: 上传URL
        files: 文件字典
        data: 表单数据
        headers: 请求头
        timeout: 超时时间(秒)，默认300秒(5分钟)
    """
    # 获取文件大小
    file_path = list(files.values())[0]
    if hasattr(file_path, 'name'):
        file_size = os.path.getsize(file_path.name)
        file_name = os.path.basename(file_path.name)
    else:
        file_size = len(file_path)
        file_name = "文件"
    
    progress = ProgressBar(file_size, f"上传 {file_name}")
    
    # 创建自定义的文件对象来跟踪上传进度
    class ProgressFile:
        def __init__(self, file_obj, progress_bar):
            self.file_obj = file_obj
            self.progress_bar = progress_bar
            
        def read(self, size=-1):
            chunk = self.file_obj.read(size)
            if chunk:
                self.progress_bar.update(len(chunk))
            return chunk
            
        def __getattr__(self, name):
            return getattr(self.file_obj, name)
    
    # 重新打开文件并包装进度跟踪
    file_key = list(files.keys())[0]
    original_file = files[file_key]
    
    if hasattr(original_file, 'name'):
        with open(original_file.name, 'rb') as f:
            progress_file = ProgressFile(f, progress)
            files_with_progress = {file_key: progress_file}
            
            try:
                # 添加超时设置，并显示服务器处理提示
                print("\033[0;36;40m 正在上传文件到服务器...\033[0m")
                response = requests.post(url, data=data, headers=headers, files=files_with_progress, timeout=timeout)
                print("\033[0;32;40m 文件上传完成，服务器处理中...\033[0m")
                return response
            except requests.exceptions.Timeout:
                print()
                print(f"\033[0;31;40m 上传超时！(超过{timeout}秒) \033[0m")
                print("\033[0;33;40m 提示：大文件上传可能需要更长时间，请检查网络连接或稍后重试 \033[0m")
                raise
            except Exception as e:
                print()  # 确保在异常情况下也换行
                raise e
    else:
        # 如果不是文件对象，直接上传
        print("\033[0;36;40m 正在上传...\033[0m")
        response = requests.post(url, data=data, headers=headers, files=files, timeout=timeout)
        print("\033[0;32;40m 上传完成，服务器处理中...\033[0m")
        return response

def upload_ios_to_pgyer(update_description):
    """上传iOS IPA文件到蒲公英"""
    print("\033[0;36;40m \n开始上传 iOS IPA 到蒲公英... \033[0m")
    
    ipa_path = "build/ios/ipa/paopao_market.ipa"
    
    # 检查IPA文件是否存在
    if not os.path.exists(ipa_path):
        print(f"\033[0;31;40m 错误：找不到 IPA 文件：{ipa_path} \033[0m")
        print("\033[0;33;40m 请先运行以下命令构建 iOS IPA：\033[0m")
        print("\033[0;33;40m flutter build ipa --release \033[0m")
        return False
    
    # 上传到蒲公英
    upload_url = "https://upload.pgyer.com/apiv1/app/upload"
    headers = {"enctype": "multipart/form-data"}
    payload = {
        "uKey": "00931bd16aa0fa0da43d4bc45b2ab5d7",
        "_api_key": "b792d89d9cf971ae5ab008cb582bfe5f",
        "updateDescription": update_description
    }
    
    try:
        print(f"\033[0;36;40m 准备上传文件：{ipa_path} \033[0m")
        file_size = os.path.getsize(ipa_path)
        print(f"\033[0;36;40m 文件大小：{file_size / 1024 / 1024:.1f} MB \033[0m")
        
        with open(ipa_path, "rb") as ipa:
            ipa_file = {"file": ipa}
            print("\033[0;36;40m 开始上传 IPA 文件... \033[0m")
            r = upload_file_with_progress(upload_url, ipa_file, payload, headers)
            
            print("\033[0;36;40m 正在解析服务器响应... \033[0m")
            r.raise_for_status()
            json_result = r.json()
            
            if json_result.get('code') == 0:
                print("\033[0;32;40m \n✓ iOS IPA 上传成功！ \033[0m")
                print(f"\033[0;32;40m 响应结果：{json_result} \033[0m")
                app_shortcut_url = json_result["data"]["appShortcutUrl"]
                print(f"\033[0;32;40m \n📱 iOS 下载链接：https://www.pgyer.com/{app_shortcut_url} \033[0m")
                return True
            else:
                print(f"\033[0;31;40m ✗ iOS IPA 上传失败：{json_result.get('message', '未知错误')} \033[0m")
                return False
                
    except FileNotFoundError:
        print(f"\033[0;31;40m 找不到 IPA 文件：{ipa_path} \033[0m")
        return False
    except requests.RequestException as e:
        print(f"\033[0;31;40m 网络请求失败：{str(e)} \033[0m")
        return False
    except Exception as e:
        print(f"\033[0;31;40m 上传过程中出现错误：{str(e)} \033[0m")
        return False

def build_ios_ipa(use_xcodebuild=True, team_id=None, bundle_id=None):
    """构建iOS IPA文件 - 优先使用xcodebuild Archive方式"""
    print("\033[0;36;40m \n开始构建 iOS IPA... \033[0m")
    
    # 优先使用xcodebuild方法，因为这是正规的Archive流程
    if use_xcodebuild:
        print("\033[0;36;40m 使用 xcodebuild Archive 方式构建... \033[0m")
        return build_ios_with_xcodebuild(team_id, bundle_id)
    
    # 备用方法: 使用 flutter build ipa (可能在某些配置下不工作)
    print("\033[0;36;40m 使用 flutter build ipa 构建... \033[0m")
    build_cmd = 'flutter build ipa --release'
    
    # 如果提供了bundle-id，添加到命令中
    if bundle_id:
        build_cmd += f' --bundle-id={bundle_id}'
    
    build_result = os.system(build_cmd)
    if build_result == 0:
        print("\033[0;32;40m iOS IPA 构建成功！ \033[0m")
        return True
    
    print("\033[0;33;40m flutter build ipa 失败，自动切换到 xcodebuild 方法... \033[0m")
    
    # 如果flutter build ipa失败，自动使用xcodebuild
    return build_ios_with_xcodebuild(team_id, bundle_id)

def build_ios_with_xcodebuild(team_id=None, bundle_id=None):
    """使用xcodebuild构建iOS IPA文件 - 完整的Archive->Export流程"""
    print("\033[0;36;40m 使用 xcodebuild 完整构建流程... \033[0m")
    
    original_dir = os.getcwd()
    
    try:
        # 1. 清理和准备环境
        print("\033[0;36;40m 步骤1: 清理和准备环境... \033[0m")
        os.system('flutter clean')
        os.system('flutter pub get')
        
        # 2. 构建Flutter iOS（无签名）
        print("\033[0;36;40m 步骤2: 构建 Flutter iOS bundle... \033[0m")
        flutter_build_result = os.system('flutter build ios --release --no-codesign')
        if flutter_build_result != 0:
            print("\033[0;31;40m Flutter iOS 构建失败！ \033[0m")
            return False
        
        # 3. 进入iOS目录
        ios_dir = os.path.join(original_dir, 'ios')
        os.chdir(ios_dir)
        
        # 4. 更新CocoaPods
        print("\033[0;36;40m 步骤3: 更新 CocoaPods 依赖... \033[0m")
        pod_result = os.system('pod install --repo-update')
        if pod_result != 0:
            print("\033[0;33;40m Pod install 警告，继续执行... \033[0m")
        
        # 5. 清理Xcode构建产物
        print("\033[0;36;40m 步骤4: 清理 Xcode 构建缓存... \033[0m")
        os.system('rm -rf build/')
        os.system('rm -rf ~/Library/Developer/Xcode/DerivedData/*Runner*')
        
        # 6. 创建必要的目录
        archive_dir = "build"
        ipa_dir = os.path.join(original_dir, "build/ios/ipa")
        os.makedirs(archive_dir, exist_ok=True)
        os.makedirs(ipa_dir, exist_ok=True)
        
        # 7. 执行Archive（相当于Xcode中的Product -> Archive）
        print("\033[0;36;40m 步骤5: 执行 Archive (相当于 Product -> Archive)... \033[0m")
        
        workspace_path = "Runner.xcworkspace"
        scheme = "Runner"
        archive_path = "build/Runner.xcarchive"
        
        # Archive命令 - 这就是Xcode中Product->Archive的命令行等价操作
        archive_cmd_parts = [
            "xcodebuild archive",
            f"-workspace {workspace_path}",
            f"-scheme {scheme}",
            "-configuration Release",
            f"-archivePath {archive_path}",
            "-allowProvisioningUpdates",
            "CODE_SIGN_STYLE=Automatic"
        ]
        
        # 添加团队ID（如果提供）
        if team_id:
            archive_cmd_parts.append(f"DEVELOPMENT_TEAM={team_id}")
        
        # 添加Bundle ID（如果提供）
        if bundle_id:
            archive_cmd_parts.append(f"PRODUCT_BUNDLE_IDENTIFIER={bundle_id}")
            
        # 添加其他必要的签名设置
        # archive_cmd_parts.extend([
        #     "CODE_SIGN_IDENTITY='iPhone Distribution'",
        #     "-quiet"
        # ])
        
        archive_cmd = " \\\n    ".join(archive_cmd_parts)
        
        print(f"\033[0;36;40m 执行Archive命令:\n{archive_cmd} \033[0m")
        archive_result = os.system(archive_cmd)
        
        if archive_result != 0:
            print("\033[0;31;40m xcodebuild Archive 失败！ \033[0m")
            print("\033[0;33;40m 常见解决方案： \033[0m")
            print("\033[0;33;40m 1. 检查Bundle ID是否唯一: com.yourcompany.yourapp \033[0m")
            print("\033[0;33;40m 2. 检查开发者账号和证书配置 \033[0m")
            print("\033[0;33;40m 3. 在Xcode中手动Archive一次确认配置正确 \033[0m")
            return False
        
        # 8. 创建ExportOptions.plist
        print("\033[0;36;40m 步骤6: 创建导出配置文件... \033[0m")
        export_options_plist = create_export_options_plist(team_id)
        
        # 9. 导出IPA（相当于Xcode中Archive后的Export）
        print("\033[0;36;40m 步骤7: 导出 IPA (相当于 Archive 后的 Export)... \033[0m")
        
        export_cmd_parts = [
            "xcodebuild -exportArchive",
            f"-archivePath {archive_path}",
            f"-exportPath {ipa_dir}",
            f"-exportOptionsPlist {export_options_plist}",
            "-allowProvisioningUpdates",
            "-quiet"
        ]
        
        export_cmd = " \\\n    ".join(export_cmd_parts)
        
        print(f"\033[0;36;40m 执行Export命令:\n{export_cmd} \033[0m")
        export_result = os.system(export_cmd)
        
        if export_result != 0:
            print("\033[0;31;40m IPA 导出失败！ \033[0m")
            return False
        
        # 10. 检查并重命名IPA文件
        print("\033[0;36;40m 步骤8: 检查导出的 IPA 文件... \033[0m")
        
        # 查找生成的IPA文件
        ipa_files = [f for f in os.listdir(ipa_dir) if f.endswith('.ipa')]
        if not ipa_files:
            print("\033[0;31;40m 未找到导出的 IPA 文件！ \033[0m")
            print(f"\033[0;33;40m 导出目录内容: {os.listdir(ipa_dir)} \033[0m")
            return False
        
        # 重命名为标准名称
        original_ipa = os.path.join(ipa_dir, ipa_files[0])
        target_ipa = os.path.join(ipa_dir, "paopao_market.ipa")
        
        if original_ipa != target_ipa:
            os.rename(original_ipa, target_ipa)
        
        print(f"\033[0;32;40m iOS IPA 构建成功！ \033[0m")
        print(f"\033[0;32;40m IPA 文件位置: {target_ipa} \033[0m")
        
        # 显示文件大小
        file_size = os.path.getsize(target_ipa)
        print(f"\033[0;32;40m IPA 文件大小: {file_size / 1024 / 1024:.1f} MB \033[0m")
        
        return True
        
    except Exception as e:
        print(f"\033[0;31;40m 构建过程中出现异常: {str(e)} \033[0m")
        return False
    finally:
        # 恢复原始目录
        os.chdir(original_dir)

def create_export_options_plist(team_id=None):
    """创建导出选项plist文件"""
    # 只在team_id不为空时写入teamID字段，否则不写
    team_id_field = f"    <key>teamID</key>\n    <string>{team_id}</string>\n" if team_id else ""
    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>release-testing</string>
{team_id_field}    <key>signingStyle</key>
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
    plist_path = "ExportOptions.plist"
    with open(plist_path, 'w') as f:
        f.write(plist_content)
    return plist_path

def update_version_numbers():
    # 更新 pubspec.yaml 中的版本号
    pubspec_path = 'pubspec.yaml'
    try:
        with open(pubspec_path, 'r') as f:
            content = f.read()
            # 匹配 version: x.x.x+数字 格式
            version_match = re.search(r'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', content)
            if not version_match:
                print("\033[0;31;40m 错误：pubspec.yaml 中未找到正确格式的版本号 (例如: version: 1.0.0+40) \033[0m")
                sys.exit(1)

            version = version_match.group(1)
            build_number = int(version_match.group(2))
            new_build_number = build_number + 1
            
            # 更新 pubspec.yaml
            new_content = content.replace(
                f'version: {version}+{build_number}',
                f'version: {version}+{new_build_number}'
            )
            with open(pubspec_path, 'w') as f:
                f.write(new_content)
            print(f"\033[0;32;40m 已更新 pubspec.yaml 构建版本号：{version}+{new_build_number} \033[0m")
            
            # 更新 build.gradle
            gradle_path = 'android/app/build.gradle'
            with open(gradle_path, 'r') as f:
                gradle_content = f.read()
                # 匹配 versionCode 数字 格式
                gradle_match = re.search(r'versionCode\s+([0-9]+)', gradle_content)
                if not gradle_match:
                    print("\033[0;31;40m 错误：build.gradle 中未找到 versionCode \033[0m")
                    sys.exit(1)
                
                old_build_number = gradle_match.group(1)
                # 使用 pubspec.yaml 的新版本号更新 build.gradle
                new_gradle_content = gradle_content.replace(
                    f'versionCode {old_build_number}',
                    f'versionCode {new_build_number}'
                )
                with open(gradle_path, 'w') as f:
                    f.write(new_gradle_content)
                print(f"\033[0;32;40m 已同步 build.gradle versionCode 为：{new_build_number} \033[0m")

    except FileNotFoundError as e:
        print(f"\033[0;31;40m 错误：找不到文件 {e.filename} \033[0m")
        sys.exit(1)
    except Exception as e:
        print(f"\033[0;31;40m 更新版本号时出错：{str(e)} \033[0m")
        sys.exit(1)

def parse_arguments():
    parser = argparse.ArgumentParser(description='Build and upload APK/IPA to pgyer')
    parser.add_argument('-desc', '--description', 
                      help='Update description for the new version',
                      default='1. 优化用户体验\n2. 修复已知问题')
    parser.add_argument('--ios', action='store_true',
                      help='Build and upload iOS IPA instead of Android APK')
    parser.add_argument('--both', action='store_true',
                      help='Build and upload both iOS IPA and Android APK')
    parser.add_argument('--team-id', 
                      help='iOS Development Team ID (for signing)')
    parser.add_argument('--bundle-id', 
                      help='iOS Bundle Identifier (if different from default)')
    parser.add_argument('--use-xcodebuild', action='store_true',
                      help='Force use xcodebuild instead of flutter build ipa')
    return parser.parse_args()

def build_and_upload(update_description):
    # Build APK
    print("\033[0;32;40m \nwaiting for flutter build apk --release \033[0m")
    build_result = os.system('flutter build apk --release')
    if build_result != 0:
        print("\033[0;31;40m Build failed! \033[0m")
        return False

    # Upload APK
    print("\033[0;32;40m \nwaiting for upload android apk \033[0m")
    upload_url = "https://upload.pgyer.com/apiv1/app/upload"
    headers = {"enctype": "multipart/form-data"}
    payload = {
        "uKey": "26d5078bcd28443c3554aae6a0812ee2",
        "_api_key": "23fcb3ecd9274b169866fcb9d621e061",
        "updateDescription": update_description
    }
    apk_path = "build/app/outputs/flutter-apk/app-release.apk"
    
    try:
        file_size = os.path.getsize(apk_path)
        print(f"\033[0;36;40m APK文件大小：{file_size / 1024 / 1024:.1f} MB \033[0m")
        
        with open(apk_path, "rb") as apk:
            apk_file = {"file": apk}
            print("\033[0;36;40m 开始上传 APK 文件... \033[0m")
            r = upload_file_with_progress(upload_url, apk_file, payload, headers)
            
            print("\033[0;36;40m 正在解析服务器响应... \033[0m")
            r.raise_for_status()  # 检查请求是否成功
            json_result = r.json()
            
            if json_result.get('code') == 0:
                print("\033[0;32;40m \n✓ Android APK 上传成功！ \033[0m")
                print("\033[0;32;40m 响应结果：%s \033[0m" % json_result)
                app_shortcut_url = json_result["data"]["appShortcutUrl"]
                print("\033[0;32;40m \n📱 下载链接：https://www.pgyer.com/%s \033[0m" % app_shortcut_url)
                return True
            else:
                print("\033[0;31;40m ✗ 上传失败：%s \033[0m" % json_result.get('message', 'Unknown error'))
                return False
    except FileNotFoundError:
        print("\033[0;31;40m ✗ APK 文件未找到：%s \033[0m" % apk_path)
        return False
    except requests.RequestException as e:
        print("\033[0;31;40m ✗ 网络请求失败：%s \033[0m" % str(e))
        return False
    except Exception as e:
        print("\033[0;31;40m ✗ 上传过程出错：%s \033[0m" % str(e))
        return False

def main():
    args = parse_arguments()
    
    # 首先更新版本号
    update_version_numbers()
    
    # 根据参数决定构建哪个平台
    if args.ios:
        # 只构建和上传iOS
        print("\033[0;36;40m \n=== 开始iOS构建和上传流程 === \033[0m")
        if build_ios_ipa(True, args.team_id, args.bundle_id):
            upload_ios_to_pgyer(args.description)
        else:
            sys.exit(1)
    elif args.both:
        # 构建和上传两个平台
        print("\033[0;36;40m \n=== 开始iOS和Android构建和上传流程 === \033[0m")
        
        # 先构建iOS
        ios_success = build_ios_ipa(args.use_xcodebuild, args.team_id, args.bundle_id)
        if ios_success:
            upload_ios_to_pgyer(args.description)
        
        # 再构建Android
        print("\033[0;36;40m \n=== 开始Android构建流程 === \033[0m")
        android_success = build_and_upload(args.description)
        
        # 检查结果
        if not ios_success and not android_success:
            print("\033[0;31;40m iOS和Android构建都失败了！ \033[0m")
            sys.exit(1)
        elif not ios_success:
            print("\033[0;33;40m iOS构建失败，但Android构建成功 \033[0m")
        elif not android_success:
            print("\033[0;33;40m Android构建失败，但iOS构建成功 \033[0m")
        else:
            print("\033[0;32;40m iOS和Android构建都成功！ \033[0m")
    else:
        # 默认只构建和上传Android
        print("\033[0;36;40m \n=== 开始Android构建和上传流程 === \033[0m")
        build_and_upload(args.description)

if __name__ == "__main__":
    main()

# 使用说明：
# 构建和上传Android APK（默认）：
# python3 auto.py -desc="1. 新增xxx功能\n2. 优化xxx性能\n3. 修复xxx问题"

# 构建和上传iOS IPA：
# python3 auto.py --ios -desc="1. 新增xxx功能\n2. 优化xxx性能\n3. 修复xxx问题"

# 使用指定的开发者团队ID构建iOS：
# python3 auto.py --ios --team-id="XXXXXXXXXX" -desc="更新描述"

# 使用自定义Bundle ID构建iOS：
# python3 auto.py --ios --bundle-id="com.yourcompany.newapp" -desc="更新描述"

# 强制使用xcodebuild构建iOS（更精细控制）：
# python3 auto.py --ios --use-xcodebuild --team-id="XXXXXXXXXX" -desc="更新描述"

# 同时构建和上传iOS和Android：
# python3 auto.py --both --team-id="XXXXXXXXXX" -desc="1. 新增xxx功能\n2. 优化xxx性能\n3. 修复xxx问题"

# 注意事项：
# 1. iOS构建需要Mac环境和有效的开发者证书
# 2. Team ID可以在Apple Developer账户中查看
# 3. Bundle Identifier必须是唯一的，建议使用反向域名格式
# 4. 首次构建可能需要在Xcode中手动配置签名
# 5. 如果遇到签名问题，可以先在Xcode中打开项目并配置好签名设置

# 获取Team ID的方法：
# 1. 登录 https://developer.apple.com/account/
# 2. 在 "Membership" 页面查看 Team ID
# 3. 或者在Xcode中打开项目，在Signing & Capabilities中查看

# 解决Bundle Identifier冲突：
# 方法1：使用自定义Bundle ID
# python3 auto.py --ios --bundle-id="com.yourname.paopaomarket" -desc="更新描述"
# 
# 方法2：在Xcode中修改Bundle Identifier
# 打开 ios/Runner.xcworkspace，在 Runner -> Signing & Capabilities 中修改 Bundle Identifier

# archive ios
# print("\033[0;32;40m \nwaiting for fastlane adhoc \033[0m")
# os.chdir('ios')
# os.system('pod install')
# os.system('fastlane adhoc')

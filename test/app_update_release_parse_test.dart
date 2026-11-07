import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/app_update_service.dart';
import 'package:slime_works/core/services/macos_update_installer.dart';
import 'package:slime_works/core/services/windows_update_installer.dart';

/// 应用更新链路的两块纯逻辑：GitHub Release JSON 解析与 macOS 替换脚本生成。
/// （网络获取与真实安装在 flutter test 环境不可达，见文件头说明。）
void main() {
  group('AppUpdateService.parseRelease', () {
    test('标准 Release：解出版本/构建号/提交正文/DMG 地址与 sha256', () {
      final info = AppUpdateService.parseRelease(<String, dynamic>{
        'tag_name': 'v1.0.0+20261107.ae4a4a2',
        'name': 'SlimeWorks v1.0.0',
        'body': '### 提交记录\n- `ae4a4a2` ci: 代码生成',
        'html_url': 'https://github.com/GleamSlime/SlimeWorks/releases/tag/v1.0.0%2B20261107.ae4a4a2',
        'assets': <dynamic>[
          <String, dynamic>{
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/x/app-release.apk',
            'digest': 'sha256:15064931',
          },
          <String, dynamic>{
            'name': 'slime_works-1.0.0+155-macos.dmg',
            'browser_download_url': 'https://github.com/x/slime_works-1.0.0%2B155-macos.dmg',
            'digest': 'sha256:64e6fe0d',
          },
          <String, dynamic>{
            'name': '_1.0.0+155_windows_x64.exe',
            'browser_download_url': 'https://github.com/x/_1.0.0%2B155_windows_x64.exe',
            'digest': 'sha256:607f8b04',
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.version, '1.0.0');
      expect(info.buildNumber, '20261107.ae4a4a2');
      expect(info.description, contains('提交记录'));
      // 比较用数字构建号取自 DMG 资产名的 +N（CI run_number）
      expect(info.remoteBuildCode, 155);
      expect(info.downloadUrl, contains('macos.dmg'));
      expect(info.sha256, '64e6fe0d');
      expect(info.releaseUrl, contains('releases/tag'));
      // Windows Inno 安装包直链同样解析出来（自动安装用）
      expect(info.windowsDownloadUrl, contains('windows_x64.exe'));
      expect(info.windowsSha256, '607f8b04');
    });

    test('无 digest / 无 DMG：sha256 为空，downloadUrl 回退 Release 页面', () {
      final info = AppUpdateService.parseRelease(<String, dynamic>{
        'tag_name': 'v1.2.3+20260101.abc1234',
        'html_url': 'https://github.com/x/releases/tag/v1.2.3',
        'assets': <dynamic>[],
      });
      expect(info!.version, '1.2.3');
      expect(info.remoteBuildCode, isNull);
      expect(info.sha256, isNull);
      expect(info.windowsDownloadUrl, isNull);
      expect(info.downloadUrl, info.releaseUrl);
    });

    test('缺 tag：解析失败返回 null', () {
      expect(AppUpdateService.parseRelease(<String, dynamic>{}), isNull);
    });
  });

  group('MacosUpdateInstaller.buildInstallerScript', () {
    test('脚本包含完整替换流程骨架与注入值', () {
      final script = MacosUpdateInstaller.buildInstallerScript(
        dmgPath: '/tmp/SlimeWorksUpdate/sw.dmg',
        appPath: '/Applications/史莱姆工坊.app',
        mainPid: 4321,
      );
      expect(script, startsWith('#!/bin/bash'));
      expect(script, contains("DMG='/tmp/SlimeWorksUpdate/sw.dmg'"));
      expect(script, contains("APP='/Applications/史莱姆工坊.app'"));
      expect(script, contains('PID=4321'));
      // 关键流程步骤都在
      expect(script, contains('kill -0')); // 等主进程退出
      expect(script, contains('hdiutil attach'));
      expect(script, contains('ditto'));
      expect(script, contains('open -b'));
      expect(script, contains('CFBundleVersion')); // 版本回退保护
    });

    test('路径含单引号时正确转义，不破坏脚本', () {
      final script = MacosUpdateInstaller.buildInstallerScript(
        dmgPath: "/tmp/o'brien/sw.dmg",
        appPath: "/Applications/my app'.app",
        mainPid: 1,
      );
      expect(script, contains(r"DMG='/tmp/o'\''brien/sw.dmg'"));
      expect(script, contains(r"APP='/Applications/my app'\''.app'"));
    });
  });

  group('WindowsUpdateInstaller.buildInstallerScript', () {
    test('脚本包含等待→静默安装→重启骨架与注入值', () {
      final script = WindowsUpdateInstaller.buildInstallerScript(
        setupPath: r"C:\Users\me\AppData\Local\Temp\SlimeWorksUpdate\update_setup.exe",
        currentExe: r"C:\Users\me\AppData\Local\Programs\SlimeWorks\史莱姆工坊.exe",
        mainPid: 4321,
      );
      expect(script, contains(r"'C:\Users\me\AppData\Local\Temp\SlimeWorksUpdate\update_setup.exe'"));
      expect(script, contains(r"'C:\Users\me\AppData\Local\Programs\SlimeWorks\史莱姆工坊.exe'"));
      expect(script, contains(r'$Pid_ = 4321'));
      // 关键流程步骤：等主进程退出 → 静默参数 → 拉起 → 清理自身
      expect(script, contains('Get-Process -Id \$Pid_'));
      expect(script, contains('/VERYSILENT'));
      expect(script, contains('Stop-Process'));
      expect(script, contains('Start-Process'));
      expect(script, contains('Remove-Item'));
    });

    test('路径含单引号时按 PowerShell 规则转义，不破坏脚本', () {
      final script = WindowsUpdateInstaller.buildInstallerScript(
        setupPath: r"C:\o'brien\update_setup.exe",
        currentExe: r"C:\my app'\app.exe",
        mainPid: 1,
      );
      expect(script, contains(r"'C:\o''brien\update_setup.exe'"));
      expect(script, contains(r"'C:\my app''\app.exe'"));
    });
  });
}

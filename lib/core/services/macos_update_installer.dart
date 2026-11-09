import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/system_proxy.dart';

/// macOS 全自动更新安装器：下载 DMG → sha256 校验 → 挂载 → 落盘替换 → 自动重启。
///
/// 设计要点：
/// - 完整性靠 GitHub API 资产 digest（sha256）校验，不依赖 Sparkle 签名链；
/// - 替换动作交给一个独立 bash 脚本执行：主进程 spawn 脚本后立即退出，
///   脚本轮询等待主进程消失（避免"替换正在运行的 App"触发 SIGKILL），
///   再用 ditto 覆盖 /Applications 里的旧版本，最后 `open` 重新启动；
/// - 脚本与 DMG 都放在应用自己的临时目录，不污染用户空间；
/// - 本类只在 macOS 上被调用（服务层用 Platform.isMacOS 把关）。
class MacosUpdateInstaller {
  final Loggers logger;

  MacosUpdateInstaller({required this.logger});

  // 当前运行的 .app 路径：替换目标与脚本参数都从这里取
  final String _appPath =
      File(Platform.resolvedExecutable).parent.parent.parent.path;

  /// 下载 DMG 到临时目录并按 sha256 校验，返回本地路径。
  ///
  /// [expectedSha256] 为空时跳过校验（GitHub API 个别资产可能没有 digest 字段）。
  Future<String> download({
    required String url,
    required String? expectedSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await _workDir();
    // 每次下载清掉上次的残留，避免半截文件混用
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
    final fileName = Uri.parse(url).pathSegments.last;
    final target = File('${dir.path}/$fileName');

    // 边下边写盘；完成后从盘上流式算 sha256（OS 页缓存命中，不占双份内存）
    // GitHub Release 资产下载在部分网络环境必须走系统代理，这里自适应探测注入
    final dio = Dio();
    final proxy = SystemProxy.applyToDio(dio);
    logger.info('[macOS安装] 开始下载 DMG，代理: ${proxy ?? '直连'}');
    final sink = target.openWrite();
    try {
      final resp = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: const {'User-Agent': 'SlimeWorks-Updater'},
        ),
      );
      final total = resp.data?.contentLength ?? -1;
      var received = 0;
      await for (final chunk in resp.data!.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await target.exists()) await target.delete();
      rethrow;
    }

    final actual = (await target.openRead().transform(sha256).first).toString();
    if (expectedSha256 != null &&
        expectedSha256.isNotEmpty &&
        actual.toLowerCase() != expectedSha256.toLowerCase()) {
      await target.delete();
      throw StateError('下载文件 sha256 校验失败（期望 $expectedSha256，实际 $actual）');
    }
    logger.info('[macOS安装] DMG 下载完成并通过 sha256 校验: ${target.path}');
    return target.path;
  }

  /// 生成替换脚本、detached 启动，然后退出主进程让脚本完成替换并重启。
  ///
  /// 正常情况下本方法不会返回（进程已退出）；仅在脚本启动失败时抛异常。
  Future<void> installAndRelaunch(String dmgPath) async {
    final dir = await _workDir();
    final scriptFile = File('${dir.path}/sw_update_install.sh');
    await scriptFile.writeAsString(
      buildInstallerScript(dmgPath: dmgPath, appPath: _appPath),
    );
    await Process.run('chmod', ['+x', scriptFile.path]);

    logger.info('[macOS安装] 启动替换脚本并退出主进程: ${scriptFile.path}');
    // detached：脚本独立于主进程生命周期，主进程退出后它继续跑
    await Process.start(
      '/bin/bash',
      [scriptFile.path],
      mode: ProcessStartMode.detached,
    );
    // 给脚本一点启动时间后主动退出，让它尽快拿到"主进程已消失"的信号
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  Future<Directory> _workDir() async {
    final dir = Directory('${Directory.systemTemp.path}/SlimeWorksUpdate');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 替换脚本正文（供 [installAndRelaunch] 生成，独立成 static 便于测试静态形态）。
  ///
  /// 流程：等主进程退出 → hdiutil 挂载 → 找 .app → 校验新包版本号 →
  /// ditto 覆盖 /Applications 旧包 → open 重启 → 清理挂载与临时文件。
  /// 失败时把原因写进同目录 install_error.txt，下次启动可回查日志。
  static String buildInstallerScript({
    required String dmgPath,
    required String appPath,
    int? mainPid,
  }) {
    final dir = dmgPath.substring(0, dmgPath.lastIndexOf('/'));
    final currentPid = mainPid ?? pid;
    // 注入路径统一用单引号包 bash 字面量前先转义单引号，防路径含引号破坏脚本
    String esc(String s) => s.replaceAll("'", r"'\''");
    return '''#!/bin/bash
# SlimeWorks macOS 自动更新替换脚本（由 App 生成，勿手动编辑）
set -u
DIR='${esc(dir)}'
DMG='${esc(dmgPath)}'
APP='${esc(appPath)}'
PID=$currentPid
LOG="\$DIR/install.log"
ERR="\$DIR/install_error.txt"
rm -f "\$ERR"
log() { echo "\$(date +%H:%M:%S) \$1" >> "\$LOG"; }

log "等待主进程 \$PID 退出…"
for i in \$(seq 1 120); do
  kill -0 "\$PID" 2>/dev/null || break
  sleep 0.5
done
# 120 次轮询后仍存活就强送 TERM，保证替换能继续
if kill -0 "\$PID" 2>/dev/null; then
  log "主进程超时未退出，发送 SIGTERM"
  kill "\$PID" 2>/dev/null || true
  sleep 2
fi

MOUNT="\$(hdiutil attach "\$DMG" -nobrowse -noautoopen | grep -o '/Volumes/.*' | head -1)"
if [ -z "\$MOUNT" ]; then
  echo "hdiutil attach 失败" > "\$ERR"; log "attach 失败"; exit 1
fi
log "已挂载: \$MOUNT"
SRC="\$(find "\$MOUNT" -maxdepth 2 -name "*.app" -type d | head -1)"
if [ -z "\$SRC" ]; then
  echo "挂载点内未找到 .app" > "\$ERR"; log "未找到 .app"; hdiutil detach "\$MOUNT" -quiet; exit 1
fi
BUNDLE_ID="\$(defaults read "\$SRC/Contents/Info" CFBundleIdentifier 2>/dev/null)"

# 版本回退保护：新包 CFBundleVersion 必须 >= 旧包，避免降级安装
NEWV="\$(defaults read "\$SRC/Contents/Info" CFBundleVersion 2>/dev/null || echo 0)"
OLDV="\$(defaults read "\$APP/Contents/Info" CFBundleVersion 2>/dev/null || echo 0)"
case "\$NEWV\$OLDV" in
  *[!0-9]*) ;; # 含非数字版本号就跳过比较，直接替换
  *)
    if [ "\$NEWV" -lt "\$OLDV" ]; then
      echo "新包版本 \$NEWV 低于已装 \$OLDV，放弃替换" > "\$ERR"
      log "版本回退，放弃"; hdiutil detach "\$MOUNT" -quiet; rm -f "\$DMG"; exit 1
    fi
    ;;
esac

log "替换 \$APP ← \$SRC"
# rm+ditto 组合最稳（rsync --delete 在替换运行中 bundle 时有过失败先例）
rm -rf "\$APP"
if ! ditto "\$SRC" "\$APP"; then
  echo "替换失败（可能无写权限：请手动拖拽安装）" > "\$ERR"
  log "ditto 失败"; hdiutil detach "\$MOUNT" -quiet; exit 1
fi
hdiutil detach "\$MOUNT" -quiet
log "替换完成，重启应用"

# 优先按 bundle id 重启（路径含空格/中文更稳），失败再按路径
if [ -n "\$BUNDLE_ID" ]; then
  open -b "\$BUNDLE_ID" || open "\$APP"
else
  open "\$APP"
fi
rm -f "\$DMG" "\$0"
''';
  }
}

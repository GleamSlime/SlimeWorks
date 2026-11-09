import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../utils/logger.dart';
import '../utils/system_proxy.dart';

/// Windows 全自动更新安装器（与 MacosUpdateInstaller 同构，语义对齐）。
///
/// 流程：下载 Inno Setup 安装器 exe → GitHub API digest 的 sha256 校验 →
/// 生成脱离会话的 PowerShell 脚本：等主进程退出 → 以静默参数运行安装器
/// （`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`，配合 ISS 的
/// PrivilegesRequired=lowest，装到 %LOCALAPPDATA%\Programs，全程无 UAC）→
/// 拉起新进程后自删。
///
/// 为什么不像 macOS 那样等安装进程再自删临时文件：Inno 在自身进程内删除/
/// 替换运行中 exe 有 pending-rename 复杂度，交给安装器自己处理；
/// 我们只负责校验和"退出→启动安装"的接力。
class WindowsUpdateInstaller {
  WindowsUpdateInstaller({required this.logger});

  final Loggers logger;

  static const _workDirName = 'SlimeWorksUpdate';

  Dio get _dio {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
    ));
    // GitHub 直链在部分网络环境不可达：自适应探测系统代理
    // （env 变量 → Windows 注册表 Internet Settings），无代理则直连
    final proxy = SystemProxy.applyToDio(dio);
    logger.info('[Windows 更新] 下载客户端就绪，代理: ${proxy ?? '直连'}');
    return dio;
  }

  /// 更新工作目录（%TEMP%\SlimeWorksUpdate）
  Directory get _workDir {
    final tmp = Platform.environment['TEMP'] ??
        Platform.environment['TMP'] ??
        Directory.systemTemp.path;
    return Directory('$tmp\\$_workDirName');
  }

  /// 下载安装器 exe；[expectedSha256] 非空时校验，不符即删除并抛错。
  Future<String> download({
    required String url,
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = _workDir;
    if (dir.existsSync()) {
      // 清掉上一轮的残留，避免新旧文件混在一起
      dir.deleteSync(recursive: true);
    }
    dir.createSync(recursive: true);
    final target = File('${dir.path}\\update_setup.exe');

    final resp = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'application/octet-stream'},
      ),
    );
    final totalHeader = resp.data?.contentLength;
    final raf = target.openSync(mode: FileMode.write);
    var received = 0;
    try {
      await for (final chunk in resp.data!.stream) {
        raf.writeFromSync(chunk);
        received += chunk.length;
        onProgress?.call(received, totalHeader ?? 0);
      }
    } finally {
      await raf.close();
    }

    // 完整性校验：sha256 来自 GitHub API 的 asset digest（HTTPS 信道内可信）
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final actual =
          (await target.openRead().transform(sha256).first).toString();
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        target.deleteSync();
        throw StateError('安装包 sha256 校验不匹配（期望 $expectedSha256，实际 $actual）');
      }
      logger.info('[Windows 更新] sha256 校验通过: $actual');
    }
    return target.path;
  }

  /// 生成并脱离会话执行"等待→静默安装→重启"脚本，随后主进程应尽快 exit(0)。
  Future<void> installAndRelaunch(
    String setupPath, {
    required String currentExe,
    required int mainPid,
  }) async {
    final scriptFile = File('${_workDir.path}\\sw_update_install.ps1');
    scriptFile.writeAsStringSync(
      buildInstallerScript(
        setupPath: setupPath,
        currentExe: currentExe,
        mainPid: mainPid,
      ),
    );
    final proc = await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptFile.path,
      ],
      mode: ProcessStartMode.detached,
    );
    logger.info('[Windows 更新] 安装接力脚本已脱离会话启动 (pid=${proc.pid})，主进程即将退出');
    // 给脚本足够时间拉起并进入等待循环，再主动退出：
    // Inno 无法替换正在运行的 exe，必须由脚本观察到主进程消失后才开装
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  /// 安装脚本正文（独立成 static 便于单测检查生成形态）。
  ///
  /// 注意 PowerShell here-string 里插值的都是我们自己拼好的字面量：
  /// 所有路径与 PID 走 _q() 的单引号转义，天然免疫注入。
  static String buildInstallerScript({
    required String setupPath,
    required String currentExe,
    required int mainPid,
  }) {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final setup = q(setupPath);
    final exe = q(currentExe);

    return r'''
# SlimeWorks Windows 自动更新接力脚本（由 App 生成，勿手动编辑）
$ErrorActionPreference = 'Stop'
$Setup = __SETUP__
$Exe = __EXE__
$Pid_ = __PID__
$Log = Join-Path (Split-Path $Setup) 'install.log'
function Log($m) { "$(Get-Date -Format HH:mm:ss) $m" | Out-File -FilePath $Log -Append -Encoding utf8 }

Log "等待主进程 $Pid_ 退出…"
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
  if (-not (Get-Process -Id $Pid_ -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Milliseconds 500
}
if (Get-Process -Id $Pid_ -ErrorAction SilentlyContinue) {
  Log "主进程超时未退出，Stop-Process 强制结束"
  Stop-Process -Id $Pid_ -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

Log "开始静默安装：$Setup"
# PrivilegesRequired=lowest 的 Inno 安装器：无 UAC、装 %LOCALAPPDATA%\Programs
$p = Start-Process -FilePath $Setup -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait -PassThru
Log "安装器退出码 $($p.ExitCode)"
if ($p.ExitCode -ne 0) {
  Log "安装失败，保持原版本；保留安装包供排查"
  exit 1
}

Log "安装成功，重启应用"
try { Start-Process -FilePath $Exe } catch { Log "重启失败：$_" }

# 收尾：删掉工作目录里除日志外的一切
Remove-Item -LiteralPath $Setup -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$PSCommandPath" -Force -ErrorAction SilentlyContinue
'''.replaceAll('__SETUP__', setup).replaceAll('__EXE__', exe).replaceAll('__PID__', '$mainPid');
  }
}

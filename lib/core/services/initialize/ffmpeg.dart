import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/src/rust/api/ffmpeg.dart';
import 'package:slime_works/core/utils/logger.dart';
const Loggers _logger = Loggers(name: 'FFmpeg');


class RustFFmpeg {
  const RustFFmpeg();

  static Future<String?>? _pathFuture;
  static Future<String?>? _probeFuture;

  /// 返回可用 ffmpeg 可执行路径，优先探测系统 PATH（用户用 brew/包管理器安装的），
  /// PATH 未命中再按绝对路径探测 macOS 常见安装目录（GUI 启动的进程 PATH 不含包管理器目录），
  /// 仍未命中则检查内置模块，不存在则触发下载；
  /// 全部失败时返回 null。结果在本次运行期间只解析一次（无论成功或失败均缓存）。
  static Future<String?> resolvePath() async {
    if (_pathFuture != null) {
      _logger.info('[FFmpeg] resolvePath: 复用已缓存的 future');
      return _pathFuture!;
    }
    _logger.info('[FFmpeg] resolvePath: 开始首次解析');
    _pathFuture = _resolvePathImpl();
    final result = await _pathFuture!;
    _logger.info('[FFmpeg] resolvePath: 解析完成 → ${result ?? "未找到 ffmpeg"}');
    return result;
  }

  /// 返回可用 ffprobe 可执行路径。解析顺序与 [resolvePath] 一致：
  /// 先探测系统 PATH，未命中再下载内置，再 fallback。
  static Future<String?> resolveProbe() async {
    if (_probeFuture != null) return _probeFuture!;
    _probeFuture = _resolveProbeImpl();
    final result = await _probeFuture!;
    _logger.info('[FFmpeg] resolveProbe: 解析完成 → ${result ?? "未找到 ffprobe"}');
    return result;
  }

  /// macOS 常见 ffmpeg 安装目录（按优先级排序）：
  /// Apple Silicon Homebrew 原生 arm64 版优先，其次 Intel Homebrew / MacPorts，
  /// 最后 /usr/local/bin 里的软链（往往是管理员手动建立的指向）。
  /// GUI 方式（Dock/Finder）启动的应用不经过 path_helper，进程 PATH 通常是
  /// launchd 的最小集（/usr/bin:/bin:/usr/sbin:/sbin），不含包管理器目录，
  /// 所以必须用绝对路径显式探测，否则会错误地回落到内置的 Intel 静态包（Rosetta 转译）。
  static const List<String> _macosKnownDirs = [
    '/opt/homebrew/bin', // Apple Silicon Homebrew（原生 arm64）
    '/usr/local/bin', // Intel Homebrew / 手动软链
    '/opt/local/bin', // MacPorts
  ];

  /// macOS 下按绝对路径探测常见安装位；找到且能跑 `-version` 才返回。
  static String? _findInMacosKnownDirs(String exeName) {
    for (final dir in _macosKnownDirs) {
      final file = File('$dir/$exeName');
      if (!file.existsSync()) continue;
      try {
        // 轻量校验可执行且没坏（软链目标被 brew 清理过等情况），~40ms 开销，仅启动时一次
        final r = Process.runSync(file.path, ['-version']);
        if (r.exitCode == 0) return file.path;
        _logger.info('[FFmpeg] $dir/$exeName 存在但执行失败 exitCode=${r.exitCode}，继续探测');
      } catch (e) {
        _logger.info('[FFmpeg] $dir/$exeName 执行异常: $e，继续探测');
      }
    }
    return null;
  }

  /// Windows 下直接扫 PATH 找可执行文件，避免探测时弹出控制台窗口
  static String? _findInWindowsPath(String exeName) {
    final pathVar = Platform.environment['PATH'] ?? '';
    for (final raw in pathVar.split(';')) {
      final dir = raw.replaceAll('"', '').trim();
      if (dir.isEmpty) continue;
      final exe = File('$dir${Platform.pathSeparator}$exeName.exe');
      if (exe.existsSync()) return exe.path;
    }
    return null;
  }

  static Future<String?> _resolvePathImpl() async {
    if (!(Platform.isWindows || Platform.isMacOS)) {
      _logger.info('[FFmpeg] 非 Windows/macOS 平台，跳过');
      return null;
    }

    // ① 优先探测系统 PATH（用户用 brew/包管理器等安装的 ffmpeg）
    // Windows 下 Process.run 会闪出控制台黑窗，改用文件系统直接扫 PATH
    if (Platform.isWindows) {
      final found = _findInWindowsPath('ffmpeg');
      if (found != null) {
        _logger.info('[FFmpeg] 使用系统 PATH 中的 ffmpeg: $found');
        return found;
      }
      _logger.info('[FFmpeg] 系统 PATH 未发现 ffmpeg');
    } else {
      try {
        final r = await Process.run('ffmpeg', ['-version']);
        if (r.exitCode == 0) {
          _logger.info('[FFmpeg] 使用系统 PATH 中的 ffmpeg');
          return 'ffmpeg';
        }
        _logger.info('[FFmpeg] 系统 ffmpeg 检测失败 exitCode=${r.exitCode}');
      } catch (e) {
        _logger.info('[FFmpeg] 系统 PATH 未发现 ffmpeg: $e');
      }

      // ①.5 PATH 未命中（GUI 启动的进程 PATH 不含包管理器目录），
      // 按绝对路径探测 macOS 常见安装位，优先命中原生 arm64 版
      final known = _findInMacosKnownDirs('ffmpeg');
      if (known != null) {
        _logger.info('[FFmpeg] 使用 macOS 常见安装目录中的 ffmpeg: $known');
        return known;
      }
      _logger.info('[FFmpeg] macOS 常见安装目录未发现 ffmpeg');
    }

    // ② 系统 PATH 未命中，检查内置模块
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final ext = Platform.isWindows ? '.exe' : '';
      final internalPath = '${appDir.path}${sep}modules${sep}ffmpeg${sep}ffmpeg$ext';
      _logger.info('[FFmpeg] 检查内置路径: $internalPath');

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 内置 ffmpeg 已存在，直接使用');
        return internalPath;
      }

      // ③ 内置不存在，触发下载
      _logger.info('[FFmpeg] 内置 ffmpeg 未找到，触发下载...');
      await initialize();

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 下载后内置 ffmpeg 可用: $internalPath');
        return internalPath;
      }
      _logger.error('[FFmpeg] 下载后仍未找到内置 ffmpeg');
    } catch (e) {
      _logger.error('[FFmpeg] 内置路径检测/下载异常: $e');
    }

    _logger.error('[FFmpeg] 所有路径均不可用，返回 null');
    return null;
  }

  static Future<String?> _resolveProbeImpl() async {
    if (!(Platform.isWindows || Platform.isMacOS)) return null;

    // ① 优先探测系统 PATH
    if (Platform.isWindows) {
      final found = _findInWindowsPath('ffprobe');
      if (found != null) {
        _logger.info('[FFmpeg] 使用系统 PATH 中的 ffprobe: $found');
        return found;
      }
      _logger.info('[FFmpeg] 系统 PATH 未发现 ffprobe');
    } else {
      try {
        final r = await Process.run('ffprobe', ['-version']);
        if (r.exitCode == 0) {
          _logger.info('[FFmpeg] 使用系统 PATH 中的 ffprobe');
          return 'ffprobe';
        }
        _logger.info('[FFmpeg] 系统 ffprobe 检测失败 exitCode=${r.exitCode}');
      } catch (e) {
        _logger.info('[FFmpeg] 系统 PATH 未发现 ffprobe: $e');
      }

      // ①.5 PATH 未命中，按绝对路径探测 macOS 常见安装位（与 ffmpeg 保持一致，
      // 避免 ffmpeg 用原生版、ffprobe 回落到内置 Intel 版的混搭）
      final known = _findInMacosKnownDirs('ffprobe');
      if (known != null) {
        _logger.info('[FFmpeg] 使用 macOS 常见安装目录中的 ffprobe: $known');
        return known;
      }
      _logger.info('[FFmpeg] macOS 常见安装目录未发现 ffprobe');
    }

    // ② 系统 PATH 未命中，检查内置模块
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final ext = Platform.isWindows ? '.exe' : '';
      final internalPath = '${appDir.path}${sep}modules${sep}ffmpeg${sep}ffprobe$ext';
      _logger.info('[FFmpeg] 检查内置 ffprobe 路径: $internalPath');

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 内置 ffprobe 已存在，直接使用');
        return internalPath;
      }

      // ③ 尝试下载 ffprobe
      _logger.info('[FFmpeg] 内置 ffprobe 未找到，触发下载...');
      await _initializeProbe(internalPath);

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 下载后内置 ffprobe 可用: $internalPath');
        return internalPath;
      }
      _logger.error('[FFmpeg] 下载后仍未找到内置 ffprobe');
    } catch (e) {
      _logger.error('[FFmpeg] ffprobe 内置路径检测/下载异常: $e');
    }

    _logger.error('[FFmpeg] ffprobe 所有路径均不可用，返回 null');
    return null;
  }

  static Future<void> initialize() async {
    if (!(Platform.isWindows || Platform.isMacOS)) {
      return;
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      final windowsUrl = dotenv.env['FFMPEG_WINDOWS_URL']?.trim() ?? '';
      final macosUrl = dotenv.env['FFMPEG_MACOS_URL']?.trim() ?? '';

      _logger.info('[FFmpeg] initialize: windowsUrl="$windowsUrl" macosUrl="$macosUrl"');

      if (windowsUrl.isEmpty || macosUrl.isEmpty) {
        _logger.info('[FFmpeg] ⚠️ .env 中 FFMPEG_WINDOWS_URL / FFMPEG_MACOS_URL 未配置');
        return;
      }

      _logger.info('[FFmpeg] 开始下载 FFmpeg 到 ${appDir.path}...');
      await initializeFfmpeg(windowsUrl: windowsUrl, macosUrl: macosUrl, installDir: appDir.path);
      _logger.info('[FFmpeg] ✅ initializeFfmpeg 调用完成');
    } catch (e, st) {
      _logger.error('[FFmpeg] ❌ initialize 异常: $e\n$st');
    }
  }

  /// 下载 ffprobe 到与 ffmpeg 相同的目录。
  static Future<void> _initializeProbe(String targetPath) async {
    try {
      final windowsUrl = dotenv.env['FFPROBE_WINDOWS_URL']?.trim() ?? '';
      final macosUrl = dotenv.env['FFPROBE_MACOS_URL']?.trim() ?? '';
      if (windowsUrl.isEmpty || macosUrl.isEmpty) {
        _logger.info('[FFmpeg] ⚠️ .env 中 FFPROBE_WINDOWS_URL / FFPROBE_MACOS_URL 未配置，跳过 ffprobe 下载');
        return;
      }
      final url = Platform.isWindows ? windowsUrl : macosUrl;
      _logger.info('[FFmpeg] 开始下载 ffprobe: $url → $targetPath');
      final dir = File(targetPath).parent;
      await dir.create(recursive: true);
      final result = await Process.run(
        Platform.isWindows ? 'powershell' : 'curl',
        Platform.isWindows
            ? ['-Command', 'Invoke-WebRequest -Uri "$url" -OutFile "$targetPath"-UseBasicParsing']
            : ['-L', '-o', targetPath, url],
      );
      if (result.exitCode == 0 && File(targetPath).existsSync()) {
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', targetPath]);
        }
        _logger.info('[FFmpeg] ✅ ffprobe 下载完成: $targetPath');
      } else {
        _logger.error('[FFmpeg] ❌ ffprobe 下载失败 exitCode=${result.exitCode} stderr=${result.stderr}');
      }
    } catch (e) {
      _logger.error('[FFmpeg] ❌ ffprobe 下载异常: $e');
    }
  }
}

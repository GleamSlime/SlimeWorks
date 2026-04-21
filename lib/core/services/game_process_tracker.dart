import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/utils/logger.dart';

final Loggers _logger = Loggers(name: '游戏进程追踪');

/// 如果主进程在这个秒数内退出，认为它可能是一个启动器（Launcher）
const int _launcherExitThresholdSec = 45;

/// 检测子进程的最大轮询次数（每次间隔 2 秒）
const int _childScanMaxAttempts = 6;

/// 启动器退出后轮询游戏目录内进程的间隔
const Duration _pollInterval = Duration(seconds: 3);

/// 最长追踪时限，防止无限运行
const Duration _maxTrackDuration = Duration(hours: 24);

/// 游戏进程追踪器：负责启动游戏进程、监听 PID 生命周期并在退出后记录游玩时间。
/// 支持"启动器"模式：当主进程快速退出时，自动扫描游戏目录下的子进程并继续追踪。
class GameProcessTracker {
  GameProcessTracker({required GameLibraryService service}) : _service = service;

  final GameLibraryService _service;

  /// 当前正在运行的游戏 ID 集合（可响应式监听）
  final RxSet<String> runningGameIds = <String>{}.obs;

  /// 每完成一次游玩会话后自增，供 ViewModel 感知到数据变更并刷新
  final RxInt sessionSavedCount = 0.obs;

  /// 是否有任意游戏正在运行
  bool get hasRunningGame => runningGameIds.isNotEmpty;

  /// 判断指定游戏是否正在运行
  bool isRunning(String gameId) => runningGameIds.contains(gameId);

  /// 启动游戏并开始追踪进程
  Future<bool> launchAndTrack({
    required String gameId,
    required String exePath,
    required String workingDirectory,
  }) async {
    if (isRunning(gameId)) {
      _logger.info('游戏已在运行中，跳过重复启动: gameId=$gameId');
      return true;
    }

    try {
      _logger.info('启动游戏进程: exePath=$exePath, workDir=$workingDirectory');
      final Process process = await Process.start(
        exePath,
        <String>[],
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      _logger.info('游戏进程已启动: gameId=$gameId, pid=${process.pid}');

      final DateTime startTime = DateTime.now();
      runningGameIds.add(gameId);

      unawaited(
        process.exitCode.then((int exitCode) async {
          final int elapsedSec = DateTime.now().difference(startTime).inSeconds;
          _logger.info('主进程已退出: gameId=$gameId, exitCode=$exitCode, 运行时长=${elapsedSec}s');

          // ── 启动器模式检测 ──────────────────────────────────────────
          // 若主进程在阈值内退出，尝试寻找其在游戏目录中留下的子进程
          if (elapsedSec < _launcherExitThresholdSec && workingDirectory.isNotEmpty) {
            bool foundSuccessor = false;
            for (int attempt = 0; attempt < _childScanMaxAttempts; attempt++) {
              if (attempt > 0) {
                await Future<void>.delayed(const Duration(seconds: 2));
              }
              final List<int> pids = await _findProcessesInDir(workingDirectory);
              if (pids.isNotEmpty) {
                foundSuccessor = true;
                _logger.info('检测到启动器模式，发现 ${pids.length} 个子进程，继续追踪游戏: gameId=$gameId');
                // 轮询直到游戏目录内所有进程结束
                await _pollUntilDone(gameId: gameId, gameDir: workingDirectory);
                break;
              }
            }
            if (!foundSuccessor) {
              _logger.info('未发现子进程，认为游戏已正常退出: gameId=$gameId');
            }
          }
          // ────────────────────────────────────────────────────────────

          final DateTime endTime = DateTime.now();
          _logger.info('游戏会话结束: gameId=$gameId, 总时长=${endTime.difference(startTime).inMinutes}分钟');
          runningGameIds.remove(gameId);
          await _service.addPlaySession(gameId: gameId, startTime: startTime, endTime: endTime);
          sessionSavedCount.value++;
        }),
      );

      return true;
    } catch (e) {
      _logger.error('启动游戏进程失败: gameId=$gameId, error=$e');
      return false;
    }
  }

  // ── 内部工具方法 ──────────────────────────────────────────────────────────

  /// 在游戏目录下查找正在运行的进程（仅 Windows）
  Future<List<int>> _findProcessesInDir(String gameDir) async {
    if (!Platform.isWindows) return <int>[];
    try {
      // 规范化路径，避免大小写或斜杠差异
      final String normalizedDir = gameDir.replaceAll('/', '\\');
      final ProcessResult result = await Process.run('powershell', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith("' +
            normalizedDir +
            r'") } | Select-Object -ExpandProperty Id | Out-String',
      ], runInShell: false);
      if (result.exitCode != 0) return <int>[];
      final List<int> pids = result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((String line) => int.tryParse(line.trim()) ?? 0)
          .where((int id) => id > 0)
          .toList();
      return pids;
    } catch (e) {
      _logger.info('扫描子进程失败（可能是权限问题）: $e');
      return <int>[];
    }
  }

  /// 轮询直到游戏目录内无进程，或超时
  Future<void> _pollUntilDone({required String gameId, required String gameDir}) async {
    final DateTime deadline = DateTime.now().add(_maxTrackDuration);
    while (DateTime.now().isBefore(deadline) && runningGameIds.contains(gameId)) {
      await Future<void>.delayed(_pollInterval);
      final List<int> pids = await _findProcessesInDir(gameDir);
      if (pids.isEmpty) {
        _logger.info('游戏目录内已无进程，追踪结束: gameId=$gameId');
        break;
      }
    }
  }
}

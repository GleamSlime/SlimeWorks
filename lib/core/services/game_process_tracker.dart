import 'dart:async';

import 'package:get/get.dart';

import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/game_library.dart' as rust_api;

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
    bool useOpen = false,
  }) async {
    if (isRunning(gameId)) {
      _logger.info('游戏已在运行中，跳过重复启动: gameId=$gameId');
      return true;
    }

    try {
      _logger.info('启动游戏进程: exePath=$exePath, workDir=$workingDirectory, useOpen=$useOpen');
      // Rust 负责 spawn 游戏进程，返回 PID（架构约定：进程启动逻辑在 Rust 层）
      final int pid = await rust_api.gameLibraryLaunchGame(
        exePath: exePath,
        workingDir: workingDirectory,
        useOpen: useOpen,
      );
      _logger.info('游戏进程已启动: gameId=$gameId, pid=$pid');

      final DateTime startTime = DateTime.now();
      runningGameIds.add(gameId);

      unawaited(
        _trackByPid(
          pid: pid,
          gameId: gameId,
          workingDirectory: workingDirectory,
          startTime: startTime,
        ),
      );

      return true;
    } catch (e) {
      _logger.error('启动游戏进程失败: gameId=$gameId, error=$e');
      return false;
    }
  }

  /// 监测指定 PID 的进程，退出后触发游玩会话记录
  Future<void> _trackByPid({
    required int pid,
    required String gameId,
    required String workingDirectory,
    required DateTime startTime,
  }) async {
    await _waitForPidExit(pid);

    final int elapsedSec = DateTime.now().difference(startTime).inSeconds;
    _logger.info('主进程已退出: gameId=$gameId, pid=$pid, 运行时长=${elapsedSec}s');

    // ── 启动器模式检测 ──────────────────────────────────────────────────────
    if (elapsedSec < _launcherExitThresholdSec && workingDirectory.isNotEmpty) {
      bool foundSuccessor = false;
      for (int attempt = 0; attempt < _childScanMaxAttempts; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        final List<int> pids = await _findProcessesInDir(workingDirectory);
        if (pids.isNotEmpty) {
          foundSuccessor = true;
          _logger.info('检测到启动器模式，发现 ${pids.length} 个子进程，继续追踪: gameId=$gameId');
          await _pollUntilDone(gameId: gameId, gameDir: workingDirectory);
          break;
        }
      }
      if (!foundSuccessor) {
        _logger.info('未发现子进程，认为游戏已正常退出: gameId=$gameId');
      }
    }
    // ────────────────────────────────────────────────────────────────────────

    final DateTime endTime = DateTime.now();
    _logger.info('游戏会话结束: gameId=$gameId, 总时长=${endTime.difference(startTime).inMinutes}分钟');
    runningGameIds.remove(gameId);
    await _service.addPlaySession(gameId: gameId, startTime: startTime, endTime: endTime);
    sessionSavedCount.value++;
  }

  /// 轮询等待指定 PID 的进程退出
  Future<void> _waitForPidExit(int pid) async {
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!await _isPidAlive(pid)) break;
    }
  }

  /// 检测指定 PID 的进程是否仍在运行（委托给 Rust 层）
  Future<bool> _isPidAlive(int pid) async {
    try {
      return await rust_api.gameLibraryIsPidAlive(pid: pid);
    } catch (_) {
      return false;
    }
  }

  // ── 内部工具方法 ──────────────────────────────────────────────────────────

  /// 在游戏目录下查找正在运行的进程（委托给 Rust 层，仅 Windows 返回有效列表）
  Future<List<int>> _findProcessesInDir(String gameDir) async {
    try {
      // Int64List 在 native 为 List<int>，在 web 为 List<BigInt>，统一转换
      return (await rust_api.gameLibraryFindProcessesInDir(gameDir: gameDir))
          .map<int>((dynamic e) => e is BigInt ? e.toInt() : (e as num).toInt())
          .toList();
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

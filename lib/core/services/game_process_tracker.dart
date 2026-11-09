import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import 'package:slime_works/core/services/game_launcher_track_state.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/mock/seams/game_api_seam.dart' as rust_api;
const Loggers _logger = Loggers(name: '游戏进程追踪');


/// 如果主进程在这个秒数内退出，认为它可能是一个启动器（Launcher）
const int _launcherExitThresholdSec = 45;

/// 检测子进程的最大轮询次数（每次间隔 2 秒）
const int _childScanMaxAttempts = 6;

/// 启动器退出后按 PID 探活的间隔（旧的 3s 全进程枚举已废弃，见状态机）
const Duration _pollInterval = Duration(seconds: 2);

/// 最长追踪时限，防止无限运行
const Duration _maxTrackDuration = Duration(hours: 24);

/// 游戏进程追踪器：负责启动游戏进程、监听 PID 生命周期并在退出后记录游玩时间。
/// 支持"启动器"模式：当主进程快速退出时，自动扫描游戏目录下的子进程并继续追踪。
class GameProcessTracker {
  GameProcessTracker({
    required GameLibraryService service,
    Future<bool> Function(int pid)? pidAliveChecker,
    Future<List<int>> Function(String gameDir)? dirProcessScanner,
    Future<void> Function(Duration)? sleeper,
    DateTime Function()? clock,
  }) : _service = service,
       _pidAliveChecker = pidAliveChecker,
       _dirProcessScanner = dirProcessScanner,
       _sleeper = sleeper,
       _clock = clock;

  final GameLibraryService _service;

  /// 可注入的 PID 探活执行器（测试用；为空时走真实系统命令）
  final Future<bool> Function(int pid)? _pidAliveChecker;

  /// 可注入的目录进程扫描执行器（测试用；为空时走真实 PowerShell）
  final Future<List<int>> Function(String gameDir)? _dirProcessScanner;

  /// 可注入的等待执行器（测试用；为空时真实延时）
  final Future<void> Function(Duration)? _sleeper;

  /// 可注入的时钟（测试用；为空时用 DateTime.now）
  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  Future<void> _sleep(Duration duration) =>
      (_sleeper ?? (Duration d) => Future<void>.delayed(d))(duration);

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
          await _pollUntilDone(
            gameId: gameId,
            gameDir: workingDirectory,
            initialPids: pids,
          );
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
      await _sleep(const Duration(seconds: 2));
      if (!await _isPidAlive(pid)) break;
    }
  }

  /// 检测指定 PID 的进程是否仍在运行（可注入执行器供单测）
  Future<bool> _isPidAlive(int pid) async {
    final Future<bool> Function(int)? checker = _pidAliveChecker;
    if (checker != null) return checker(pid);
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('tasklist', <String>[
          '/FI',
          'PID eq $pid',
          '/NH',
          '/FO',
          'CSV',
        ], runInShell: false);
        return result.stdout.toString().contains('"$pid"');
      } else {
        // Unix/macOS: kill -0 不发送信号，只检查进程是否存在
        result = await Process.run('kill', <String>['-0', '$pid'], runInShell: false);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  // ── 内部工具方法 ──────────────────────────────────────────────────────────

  /// 在游戏目录下查找正在运行的进程（仅 Windows；可注入执行器供单测）
  Future<List<int>> _findProcessesInDir(String gameDir) async {
    final Future<List<int>> Function(String)? scanner = _dirProcessScanner;
    if (scanner != null) return scanner(gameDir);
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

  /// 轮询直到游戏进程全部退出，或超时。
  ///
  /// 性能修复（审计 #1）：不再每 3s 起 PowerShell 全进程枚举，改为
  /// [LauncherTrackStateMachine] 驱动的「按 PID 探活为主、目录扫描确认为辅」：
  /// - 常规轮次只对已捕获的 PID 逐个 tasklist /FI 探活（开销极小）；
  /// - PID 全灭后才做目录扫描（游戏可能换 exe / 重启换 PID）；
  /// - 目录扫描连续 2 次为空才结束，空扫描间隔 15s→30s 自适应退避。
  /// [initialPids] 为进入启动器模式时已捕获的子进程 PID，避免立刻重复扫目录。
  Future<void> _pollUntilDone({
    required String gameId,
    required String gameDir,
    List<int> initialPids = const <int>[],
  }) async {
    final LauncherTrackStateMachine machine = LauncherTrackStateMachine(
      pidPollInterval: _pollInterval,
      maxTrackDuration: _maxTrackDuration,
    );
    // 进入时已捕获的子进程直接作为初始追踪集合，省掉一次目录扫描
    if (initialPids.isNotEmpty) {
      machine.onDirScan(initialPids);
    }
    while (runningGameIds.contains(gameId)) {
      final LauncherDecision decision = machine.decide(_now.millisecondsSinceEpoch);
      final Object action = decision.action;
      if (action is LauncherDone) {
        _logger.info('游戏进程已全部退出，追踪结束: gameId=$gameId');
        break;
      }
      await _sleep(decision.delay);
      if (!runningGameIds.contains(gameId)) break;
      if (action is LauncherScanDir) {
        final List<int> pids = await _findProcessesInDir(gameDir);
        final bool ended = machine.onDirScan(pids);
        if (pids.isNotEmpty) {
          _logger.info('目录扫描捕获 ${pids.length} 个进程（含换 exe 重新捕获）: gameId=$gameId');
        }
        if (ended) {
          _logger.info('游戏目录连续多次扫描无进程，追踪结束: gameId=$gameId');
          break;
        }
      } else if (action is LauncherProbePids) {
        // 按 PID 探活：只查已追踪的 PID，不做全进程枚举
        final List<int> alive = <int>[];
        for (final int pid in machine.trackedPids) {
          if (await _isPidAlive(pid)) alive.add(pid);
        }
        machine.onPidProbe(alive);
        if (alive.isEmpty) {
          _logger.info('已追踪 PID 全部退出，转入目录扫描确认: gameId=$gameId');
        }
      }
    }
  }
}

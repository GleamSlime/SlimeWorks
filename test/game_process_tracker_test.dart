// 启动器模式追踪状态机 + GameProcessTracker 注入执行器的单测（性能审计 #1）。
//
// 覆盖两条关键状态转移：
// 1. 「PID 全灭 → 目录扫描确认 → 连续空扫描才结束」；
// 2. 「换 exe 重新捕获」：PID 全灭后目录扫描捕获新 PID，继续追踪不误判退出。
// 全部经注入执行器驱动，不依赖 Windows / 真实进程，可在 macOS CI 上跑。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/services/game_launcher_track_state.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

// ── 纯状态机测试 ─────────────────────────────────────────────────────────────

void main() {
  // MockMode.setRuntimeEnabled 走 SharedPreferences，需要 binding 与 mock 初值
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('LauncherTrackStateMachine - 纯逻辑', () {
    test('首轮未捕获 PID 时先做目录扫描', () {
      final LauncherTrackStateMachine m = LauncherTrackStateMachine();
      final LauncherDecision d = m.decide(0);
      expect(d.action, isA<LauncherScanDir>());
      expect(d.delay, kLauncherDirScanMinInterval);
    });

    test('捕获 PID 后常规轮次只探活，不再扫目录', () {
      final LauncherTrackStateMachine m = LauncherTrackStateMachine();
      m.onDirScan(<int>[100, 200]);
      final LauncherDecision d = m.decide(1000);
      expect(d.action, isA<LauncherProbePids>());
      expect(d.delay, kLauncherPidPollInterval);
      expect(m.trackedPids, <int>{100, 200});
    });

    test('PID 全灭 → 转目录扫描；连续 2 次为空才结束', () {
      final LauncherTrackStateMachine m = LauncherTrackStateMachine();
      m.onDirScan(<int>[100]);
      m.onPidProbe(<int>[]); // 全灭
      expect(m.trackedPids, isEmpty);

      // 第一次目录扫描为空：不结束，退避到 30s
      final LauncherDecision d1 = m.decide(2000);
      expect(d1.action, isA<LauncherScanDir>());
      expect(m.onDirScan(<int>[]), isFalse);
      expect(m.emptyScanCount, 1);
      final LauncherDecision d2 = m.decide(3000);
      expect(d2.action, isA<LauncherScanDir>());
      expect(d2.delay, kLauncherDirScanMaxInterval);

      // 第二次目录扫描仍为空：确认结束
      expect(m.onDirScan(<int>[]), isTrue);
      expect(m.isDone, isTrue);
      expect(m.decide(4000).action, isA<LauncherDone>());
    });

    test('换 exe 重新捕获：全灭后目录扫描发现新 PID，重置确认计数', () {
      final LauncherTrackStateMachine m = LauncherTrackStateMachine();
      m.onDirScan(<int>[100]);
      m.onPidProbe(<int>[]); // 旧 exe 退出
      m.onDirScan(<int>[]); // 第一次确认扫到空（换 exe 间隙）
      expect(m.emptyScanCount, 1);

      // 第二次确认扫描捕获新 exe 的 PID → 继续追踪
      expect(m.onDirScan(<int>[300]), isFalse);
      expect(m.isDone, isFalse);
      expect(m.emptyScanCount, 0);
      expect(m.trackedPids, <int>{300});
      final LauncherDecision d = m.decide(5000);
      expect(d.action, isA<LauncherProbePids>());
      expect(d.delay, kLauncherPidPollInterval);
      // 退避已重置回下限：新 PID 再全灭后，下一轮目录确认从 15s 重新起步
      m.onPidProbe(<int>[]);
      expect(m.decide(6000).delay, kLauncherDirScanMinInterval);
      m.onDirScan(<int>[]);
      expect(m.decide(7000).delay, kLauncherDirScanMaxInterval);
    });

    test('部分 PID 存活时继续探活，不进目录确认', () {
      final LauncherTrackStateMachine m = LauncherTrackStateMachine();
      m.onDirScan(<int>[100, 200]);
      m.onPidProbe(<int>[200]);
      expect(m.trackedPids, <int>{200});
      expect(m.decide(1000).action, isA<LauncherProbePids>());
    });

    test('目录扫描退避封顶 30s，不无限翻倍', () {
      final LauncherTrackStateMachine m = LauncherTrackStateMachine(
        emptyConfirmScans: 5,
      );
      m.onDirScan(<int>[100]);
      m.onPidProbe(<int>[]);
      final List<Duration> delays = <Duration>[];
      for (int i = 0; i < 4; i++) {
        delays.add(m.decide(1000 + i).delay);
        m.onDirScan(<int>[]);
      }
      expect(delays, <Duration>[
        const Duration(seconds: 15),
        const Duration(seconds: 30),
        const Duration(seconds: 30),
        const Duration(seconds: 30),
      ]);
    });

    test('超过最长追踪时限强制结束', () {
      final LauncherTrackStateMachine m = LauncherTrackStateMachine(
        maxTrackDuration: const Duration(seconds: 10),
      );
      m.onDirScan(<int>[100]);
      expect(m.decide(0).action, isA<LauncherProbePids>());
      expect(m.decide(10000).action, isA<LauncherDone>());
      expect(m.isDone, isTrue);
    });
  });

  // ── GameProcessTracker 注入执行器端到端（虚拟时钟） ─────────────────────────

  group('GameProcessTracker - 启动器模式（注入执行器）', () {
    // RustLib 官方 mock：launchAndTrack 走 MockMode 分支返回 pid=0，
    // 但 import 链上的 frb_generated 仍需已初始化，避免惰性检查抛错。
    setUpAll(() async {
      RustLib.initMock(api: _NoopRustApi());
      await MockMode.setRuntimeEnabled(true);
    });

    tearDownAll(() async {
      await MockMode.setRuntimeEnabled(false);
    });

    /// 驱动一次完整的 launchAndTrack：
    /// [aliveScript] 按探活轮次给出存活判定；[scanScript] 按扫描次序给出目录 PID。
    Future<_TrackResult> runTrack({
      required List<bool> aliveScript,
      required List<List<int>> scanScript,
    }) async {
      final _VirtualClock clock = _VirtualClock();
      final List<int> probedPids = <int>[];
      final List<Duration> scanDelays = <Duration>[];
      final List<Duration> probeDelays = <Duration>[];
      int aliveIdx = 0;
      int scanIdx = 0;
      final List<_SavedSession> saved = <_SavedSession>[];

      final GameProcessTracker tracker = GameProcessTracker(
        service: _RecordingService(saved),
        clock: clock.now,
        sleeper: (Duration d) async {
          clock.advance(d);
        },
        pidAliveChecker: (int pid) async {
          probedPids.add(pid);
          probeDelays.add(clock.lastSleep);
          final bool alive = aliveIdx < aliveScript.length
              ? aliveScript[aliveIdx]
              : false;
          aliveIdx++;
          return alive;
        },
        dirProcessScanner: (String dir) async {
          scanDelays.add(clock.lastSleep);
          final List<int> pids = scanIdx < scanScript.length
              ? scanScript[scanIdx]
              : <int>[];
          scanIdx++;
          return pids;
        },
      );

      final bool ok = await tracker.launchAndTrack(
        gameId: 'g1',
        exePath: '/games/g1/launcher.exe',
        workingDirectory: '/games/g1',
      );
      expect(ok, isTrue);
      // 等待后台 _trackByPid 完成（虚拟时钟下所有 sleep 立即返回）
      while (tracker.isRunning('g1')) {
        await Future<void>.delayed(Duration.zero);
      }
      return _TrackResult(
        probedPids: probedPids,
        scanCount: scanIdx,
        scanDelays: scanDelays,
        probeDelays: probeDelays,
        saved: saved,
        sessionSavedCount: tracker.sessionSavedCount.value,
      );
    }

    test('PID 全灭 → 目录确认 → 连续 2 次为空结束并保存会话', () async {
      // 主进程 pid=0 立即死亡（进启动器检测）；首扫捕获 [100]；
      // 探活轮 1 存活、轮 2 全灭；确认扫描 1、2 均为空 → 结束。
      final _TrackResult r = await runTrack(
        aliveScript: <bool>[false, true, false],
        scanScript: <List<int>>[
          <int>[100], // 启动器检测首扫
          <int>[], // 确认扫描 1
          <int>[], // 确认扫描 2 → 结束
        ],
      );
      expect(r.scanCount, 3);
      // 只对捕获的 PID 100 探活，无全进程枚举
      expect(r.probedPids, <int>[0, 100, 100]);
      // 确认扫描间隔：15s → 30s 退避
      expect(r.scanDelays.sublist(1), <Duration>[
        const Duration(seconds: 15),
        const Duration(seconds: 30),
      ]);
      expect(r.saved, hasLength(1));
      expect(r.saved.single.gameId, 'g1');
      expect(r.sessionSavedCount, 1);
    });

    test('换 exe 重新捕获：确认扫描发现新 PID 后继续追踪', () async {
      // 首扫捕获 [100]；探活全灭；确认扫描 1 为空（换 exe 间隙）；
      // 确认扫描 2 捕获 [300]（新 exe）；随后 300 全灭；再两次空扫描结束。
      final _TrackResult r = await runTrack(
        aliveScript: <bool>[false, false, false, false],
        scanScript: <List<int>>[
          <int>[100], // 启动器检测首扫
          <int>[], // 确认扫描 1（空）
          <int>[300], // 确认扫描 2：换 exe 重新捕获
          <int>[], // 新 PID 全灭后的确认扫描 1
          <int>[], // 确认扫描 2 → 结束
        ],
      );
      expect(r.scanCount, 5);
      // 探活序列：主进程 0 → 旧 PID 100 → 新 PID 300（各一轮即全灭）
      expect(r.probedPids, <int>[0, 100, 300]);
      expect(r.saved, hasLength(1));
      expect(r.sessionSavedCount, 1);
    });

    test('目录扫描捕获多个 PID 时逐个探活，部分存活不触发确认扫描', () async {
      // 首扫捕获 [100,200]；轮 1 两个都活；轮 2 只剩 200；轮 3 全灭；
      // 两次确认扫描为空 → 结束。
      final _TrackResult r = await runTrack(
        aliveScript: <bool>[
          false, // 主进程
          true, true, // 轮 1：100、200 都活
          false, true, // 轮 2：100 死、200 活
          false, // 轮 3：200 死
        ],
        scanScript: <List<int>>[
          <int>[100, 200],
          <int>[],
          <int>[],
        ],
      );
      expect(r.scanCount, 3);
      expect(r.probedPids, <int>[0, 100, 200, 100, 200, 200]);
      expect(r.saved, hasLength(1));
    });
  });
}

// ── 测试辅助 ─────────────────────────────────────────────────────────────────

/// 虚拟时钟：sleeper 直接把时间往前拨，测试无需真实等待。
class _VirtualClock {
  DateTime _now = DateTime(2026, 1, 1);
  Duration lastSleep = Duration.zero;

  DateTime now() => _now;

  void advance(Duration d) {
    lastSleep = d;
    _now = _now.add(d);
  }
}

class _SavedSession {
  _SavedSession(this.gameId, this.startTime, this.endTime);

  final String gameId;
  final DateTime startTime;
  final DateTime endTime;
}

/// 只记录 addPlaySession 的服务桩，其余成员不需要。
class _RecordingService implements GameLibraryService {
  _RecordingService(this.saved);

  final List<_SavedSession> saved;

  @override
  Future<void> addPlaySession({
    required String gameId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    saved.add(_SavedSession(gameId, startTime, endTime));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('测试不应调用: ${invocation.memberName}');
}

/// 空 FRB mock：本测试全程走 MockMode 分支，不应触达任何真实 FFI。
class _NoopRustApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('测试不应触达 FFI: ${invocation.memberName}');
}

class _TrackResult {
  _TrackResult({
    required this.probedPids,
    required this.scanCount,
    required this.scanDelays,
    required this.probeDelays,
    required this.saved,
    required this.sessionSavedCount,
  });

  final List<int> probedPids;
  final int scanCount;
  final List<Duration> scanDelays;
  final List<Duration> probeDelays;
  final List<_SavedSession> saved;
  final int sessionSavedCount;
}
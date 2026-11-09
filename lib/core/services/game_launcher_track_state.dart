// 启动器模式（Windows）进程追踪状态机。
//
// 背景（性能审计 #1）：旧实现在整个游戏会话期间每 3s 起一个 PowerShell
// `Get-Process` 全进程枚举（单次 0.5~2s CPU，最长 24h），属于持续性后台
// CPU 浪费。本状态机改为：
// 1. 进入追踪时先做一次目录扫描拿到子进程 PID 列表；
// 2. 之后只做廉价的「按 PID 探活」（tasklist /FI 单 PID 过滤）；
// 3. 全部 PID 消失后再做目录扫描确认（游戏可能换 exe / 重启换 PID）；
// 4. 目录扫描连续 N 次为空才判定结束；空扫描间隔自适应退避（15s→30s）。
//
// 本文件不依赖 dart:io / 平台分支，执行器全部经构造注入，可在任意平台单测。

/// 状态机动作：等待若干毫秒后继续下一轮
class LauncherWait {
  const LauncherWait(this.duration);

  final Duration duration;
}

/// 状态机动作：扫描游戏目录，用返回的 PID 集合更新追踪列表
class LauncherScanDir {
  const LauncherScanDir();
}

/// 状态机动作：对已追踪的 PID 逐个探活，返回仍存活的 PID 集合
class LauncherProbePids {
  const LauncherProbePids();
}

/// 状态机动作：确认游戏已结束，停止追踪
class LauncherDone {
  const LauncherDone();
}

/// 一次「动作 + 下次唤醒间隔」的调度决策
class LauncherDecision {
  const LauncherDecision(this.action, this.delay);

  final Object action;
  final Duration delay;
}

/// PID 探活间隔：与主路径 _waitForPidExit 同量级（tasklist /FI 开销极小）
const Duration kLauncherPidPollInterval = Duration(seconds: 2);

/// 目录扫描确认的起始间隔（自适应退避下限）
const Duration kLauncherDirScanMinInterval = Duration(seconds: 15);

/// 目录扫描确认的退避上限
const Duration kLauncherDirScanMaxInterval = Duration(seconds: 30);

/// 目录扫描连续为空的判定次数：连续 N 次为空才结束（防换 exe 间隙误判）
const int kLauncherEmptyConfirmScans = 2;

/// 启动器模式追踪状态机（纯逻辑，不含任何 IO）。
///
/// 用法：宿主循环每轮 `decide()` 拿到动作 → 执行 → 把结果经
/// [onDirScan] / [onPidProbe] 喂回来 → 等待 `decision.delay` 后进入下一轮。
class LauncherTrackStateMachine {
  LauncherTrackStateMachine({
    this.pidPollInterval = kLauncherPidPollInterval,
    this.dirScanMinInterval = kLauncherDirScanMinInterval,
    this.dirScanMaxInterval = kLauncherDirScanMaxInterval,
    this.emptyConfirmScans = kLauncherEmptyConfirmScans,
    this.maxTrackDuration = const Duration(hours: 24),
  });

  final Duration pidPollInterval;
  final Duration dirScanMinInterval;
  final Duration dirScanMaxInterval;
  final int emptyConfirmScans;
  final Duration maxTrackDuration;

  /// 当前正在追踪的 PID 集合（目录扫描/探活会更新它）
  final Set<int> _trackedPids = <int>{};

  /// 目录扫描连续为空的次数
  int _emptyScans = 0;

  /// 当前目录扫描退避间隔（构造时与下限对齐）
  late Duration _dirScanInterval = dirScanMinInterval;

  /// 是否已做过首次目录扫描（首次扫描拿到 PID 前必须先扫目录）
  bool _scannedOnce = false;

  /// 追踪起点（宿主时钟毫秒），用于 24h 超时兜底
  int? _startMs;

  /// 是否已结束
  bool _done = false;

  bool get isDone => _done;

  /// 当前追踪的 PID 集合（只读视图，供日志/测试观察）
  Set<int> get trackedPids => Set<int>.unmodifiable(_trackedPids);

  /// 目录扫描连续为空计数（供测试观察）
  int get emptyScanCount => _emptyScans;

  /// 产出下一步动作与等待间隔。[nowMs] 为宿主时钟（毫秒）。
  LauncherDecision decide(int nowMs) {
    _startMs ??= nowMs;
    if (_done) {
      return LauncherDecision(const LauncherDone(), Duration.zero);
    }
    // 超时兜底：与旧实现一致的 24h 上限
    if (nowMs - _startMs! >= maxTrackDuration.inMilliseconds) {
      _done = true;
      return LauncherDecision(const LauncherDone(), Duration.zero);
    }
    // 尚未拿到 PID（首次进入）或 PID 全灭待确认 → 目录扫描
    if (!_scannedOnce || _trackedPids.isEmpty) {
      return LauncherDecision(const LauncherScanDir(), _dirScanInterval);
    }
    // 常规路径：只按 PID 探活，不再起 PowerShell 全进程枚举
    return LauncherDecision(const LauncherProbePids(), pidPollInterval);
  }

  /// 目录扫描结果回喂。返回 true 表示游戏结束（连续空扫描达到阈值）。
  bool onDirScan(List<int> pids) {
    _scannedOnce = true;
    if (pids.isNotEmpty) {
      // 捕获到进程（含「换 exe 重新捕获」场景）：并入追踪集合，重置确认计数与退避
      _trackedPids.addAll(pids);
      _emptyScans = 0;
      _dirScanInterval = dirScanMinInterval;
      return false;
    }
    _emptyScans++;
    if (_emptyScans >= emptyConfirmScans) {
      _done = true;
      return true;
    }
    // 自适应退避：15s → 30s 封顶，避免空窗期反复起 PowerShell
    final int nextMs = _dirScanInterval.inMilliseconds * 2;
    _dirScanInterval = Duration(
      milliseconds: nextMs > dirScanMaxInterval.inMilliseconds
          ? dirScanMaxInterval.inMilliseconds
          : nextMs,
    );
    return false;
  }

  /// PID 探活结果回喂：[alivePids] 为仍存活的被追踪 PID。
  /// 全灭时清空追踪集合，下一轮 decide 会转入目录扫描确认。
  void onPidProbe(List<int> alivePids) {
    _trackedPids
      ..clear()
      ..addAll(alivePids);
  }
}
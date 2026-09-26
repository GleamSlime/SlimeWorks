import 'package:slime_works/core/utils/logger.dart';

/// 【临时埋点】定位远程节点连通确认与取数耗时用。
/// 问题闭环后删除本文件以及全部 `TimingTrace` / `elapsedTag` 调用点。
///
/// 输出统一为 `标签(+NN.NNNs)`，日志里 grep `耗时` 或 `(+` 即可串起整条链路。
class TimingTrace {
  TimingTrace(this.label, {this.scope}) {
    _watch.start();
    _lastLap = Duration.zero;
  }

  /// 被计时的操作名。
  final String label;

  /// 附加上下文（节点名 / 集合 id 等），跟在标签后面。
  final String? scope;

  static const Loggers _logger = Loggers(name: '耗时');

  final Stopwatch _watch = Stopwatch();
  Duration _lastLap = Duration.zero;
  bool _ended = false;

  String get _head => scope == null ? label : '$label[$scope]';

  Duration get elapsed => _watch.elapsed;

  /// 打印总耗时；超过 [slowOnlyMs] 才打印（用于刷屏的高频调用），不传则总是打印。
  /// 重复调用只有第一次会输出，成功/异常两条出口可以各写一次。
  String end({int? slowOnlyMs, String? note}) {
    final total = _watch.elapsed;
    if (_ended) {
      return elapsedTag(total);
    }
    _ended = true;
    if (slowOnlyMs == null || total.inMilliseconds >= slowOnlyMs) {
      _logger.info('$_head${note == null ? '' : ' $note'}${elapsedTag(total)}');
    }
    return elapsedTag(total);
  }

  /// 打印自上一次 [lap] / [end] 以来的分段耗时，用于拆出链路里最慢的一段。
  String lap(String step) {
    final now = _watch.elapsed;
    final segment = now - _lastLap;
    _lastLap = now;
    _logger.info('$_head > $step${elapsedTag(segment)}');
    return elapsedTag(segment);
  }
}

/// `(+NN.NNNs)` 片段。
String elapsedTag(Duration d) => '(+${(d.inMicroseconds / 1e6).toStringAsFixed(3)}s)';

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:slime_works/core/utils/logger.dart';

const Loggers _logger = Loggers(name: '缩略图队列');

/// 单个缩略图任务。
class _ThumbTask {
  _ThumbTask({required this.key, required this.work});

  /// 任务唯一标识（通常为 videoPath）。
  final String key;

  /// 实际执行逻辑，返回结果 T。
  final Future<void> Function() work;

  /// 任务完成/被取消时通知。
  final Completer<void> _completer = Completer<void>();

  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// 外部等待任务完成（不可传递 cancel 状态）。
  Future<void> get done => _completer.future;
}

/// 带优先级（前插）的串行任务队列，用于视频封面 / scrub 帧提取。
///
/// - 最大并发数 [concurrency]（可动态修改），默认 2。
/// - [enqueue]：将任务推入队尾，相同 key 的任务不重复入队。
/// - [prioritize]：将已有任务移到队首；若任务不存在则新建并插入队首。
/// - [cancel]：标记任务取消，正在执行中的任务不中断但结果会被忽略。
/// - [cancelGroup]：批量取消一批 key。
/// - [onTaskComplete]：每次任务完成（无论成功/取消/异常）时调用的回调。
class VideoThumbQueue {
  VideoThumbQueue({int concurrency = 2}) : _concurrency = concurrency;

  int _concurrency;
  int _running = 0;
  int _totalEnqueued = 0;
  int _completed = 0;

  /// 并发上限；setter 主动触发 _tick()，让用户改并发后立即拉起新任务，
  /// 而不是等到下次 enqueue/whenComplete 才生效。
  int get concurrency => _concurrency;
  set concurrency(int v) {
    if (v == _concurrency) return;
    _concurrency = v;
    _logger.info('[Queue] concurrency 变更: $v');
    _tick();
  }

  /// 每次任务完成后调用（可用于防抖触发缓存清理等）。
  VoidCallback? onTaskComplete;

  /// 进度变化回调（用于 UI 实时更新）。
  void Function(int completed, int total)? onProgress;

  /// 等待中的任务数 + 正在执行的任务数。
  int get pending => _queue.length + _running;

  /// 已完成任务数。
  int get completed => _completed;

  /// 总入队任务数（含已完成）。
  int get total => _totalEnqueued;

  final _queue = ListQueue<_ThumbTask>();

  /// key → task（仅在等待中，执行中不在此 map 内）。
  final _pending = <String, _ThumbTask>{};

  /// 新一批任务开始前清空上一批的计数。
  /// 队列空闲时 completed/total 都停留在上一批；不归零的话，下一批的进度
  /// 会把历史任务算进分母（例如新任务 3 个却显示 40/43）。
  void _resetBatchIfIdle() {
    if (_running == 0 && _queue.isEmpty) {
      _totalEnqueued = 0;
      _completed = 0;
    }
  }

  /// 将任务推入队尾；若 key 已存在（等待或执行）则忽略。
  /// 返回 future，任务完成时 resolve。
  Future<void> enqueue(String key, Future<void> Function() work) {
    _resetBatchIfIdle();
    if (_pending.containsKey(key)) {
      _logger.info('[Queue] enqueue skip (已存在) key=$key');
      return _pending[key]!.done;
    }
    final task = _ThumbTask(key: key, work: work);
    _pending[key] = task;
    _queue.addLast(task);
    _totalEnqueued++;
    _logger.info('[Queue] enqueue key=$key queueLen=${_queue.length}');
    _notifyProgress();
    _tick();
    return task.done;
  }

  /// 将 key 对应任务移到队首（高优先级），若不存在则新建任务插入队首。
  Future<void> prioritize(String key, Future<void> Function() work) {
    _resetBatchIfIdle();
    // 若已在等待中，移到队首
    if (_pending.containsKey(key)) {
      final existing = _pending[key]!;
      _queue.remove(existing);
      _queue.addFirst(existing);
      _logger.info(
        '[Queue] prioritize (移到队首) key=$key queueLen=${_queue.length}',
      );
      return existing.done;
    }
    // 若已在执行中（不在 _pending），直接等待
    final task = _ThumbTask(key: key, work: work);
    _pending[key] = task;
    _queue.addFirst(task);
    _totalEnqueued++;
    _logger.info(
      '[Queue] prioritize (新建到队首) key=$key queueLen=${_queue.length}',
    );
    _notifyProgress();
    _tick();
    return task.done;
  }

  /// 取消单个 key 的等待任务。正在执行的任务不中断。
  void cancel(String key) {
    if (_cancelWithoutNotify(key)) _notifyProgress();
  }

  /// 批量取消 [keys] 中每个 key 的等待任务（只发一次进度通知）。
  void cancelGroup(Iterable<String> keys) {
    var removed = false;
    for (final k in keys) {
      if (_cancelWithoutNotify(k)) removed = true;
    }
    if (removed) _notifyProgress();
  }

  /// 取消等待中的任务：未执行就取消的任务要从本批总数里扣除，
  /// 否则进度分母永远包含这些不会执行的任务（表现为卡在 2/10 不动）。
  bool _cancelWithoutNotify(String key) {
    final task = _pending.remove(key);
    if (task == null) return false;
    task._cancelled = true;
    _queue.remove(task);
    _totalEnqueued--;
    if (!task._completer.isCompleted) task._completer.complete();
    _logger.info('[Queue] cancel key=$key');
    return true;
  }

  /// 取消全部等待中（未执行）的任务。
  void cancelAll() {
    for (final task in List<_ThumbTask>.from(_queue)) {
      task._cancelled = true;
      if (!task._completer.isCompleted) task._completer.complete();
    }
    _queue.clear();
    _pending.clear();
    _totalEnqueued = 0;
    _completed = 0;
    _logger.info('[Queue] cancelAll');
    _notifyProgress();
  }

  /// 查询 key 是否已在队列或执行中。
  bool contains(String key) => _pending.containsKey(key);

  void _tick() {
    while (_running < concurrency && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _pending.remove(task.key);
      if (task.isCancelled) continue;
      _running++;
      _logger.info('[Queue] 开始执行 key=${task.key} running=$_running');
      task
          .work()
          .then((_) {
            if (!task._completer.isCompleted) task._completer.complete();
          })
          .catchError((e) {
            _logger.error('[Queue] 执行异常 key=${task.key} err=$e');
            if (!task._completer.isCompleted) task._completer.complete();
          })
          .whenComplete(() {
            _running--;
            _completed++;
            _logger.info(
              '[Queue] 执行完毕 key=${task.key} running=$_running completed=$_completed/$_totalEnqueued',
            );
            _notifyProgress();
            onTaskComplete?.call();
            _tick();
          });
    }
  }

  void _notifyProgress() {
    // 使用 scheduleMicrotask 避免在 build 期间同步触发 Obx 重建
    scheduleMicrotask(() => onProgress?.call(_completed, _totalEnqueued));
  }
}

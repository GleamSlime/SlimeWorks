import 'dart:async';
import 'dart:collection';

import 'package:get/get.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/whisper.dart' as whisper_api;

const Loggers _logger = Loggers(name: '转录队列');

/// 单个转录任务
class TranscriptionTask {
  final String id;
  final String audioFilePath;
  final String? language;
  final String displayName;

  /// 任务状态
  final Rx<TranscriptionTaskState> state = TranscriptionTaskState.queued.obs;

  /// 当前任务的识别进度 0.0~1.0
  final RxDouble progress = 0.0.obs;

  /// 错误信息
  final RxnString error = RxnString();

  /// 识别结果
  whisper_api.TranscriptionResultInfo? result;

  TranscriptionTask({
    required this.id,
    required this.audioFilePath,
    this.language,
    required this.displayName,
  });
}

/// 转录任务状态
enum TranscriptionTaskState {
  /// 排队中
  queued,

  /// 识别中
  running,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已取消
  cancelled,
}

/// 语音识别任务队列服务（GetIt 单例）
///
/// 串行执行转录任务，提供全局进度供 UI 消费
class TranscriptionTaskQueue {
  final _queue = ListQueue<TranscriptionTask>();
  bool _isProcessing = false;
  Timer? _progressTimer;

  // ── 响应式状态 ──────────────────────────────────────────────────────────

  /// 所有任务列表（含已完成）
  final tasks = <TranscriptionTask>[].obs;

  /// 已完成任务数
  final completedCount = 0.obs;

  /// 总入队任务数
  final totalCount = 0.obs;

  /// 当前正在执行的任务
  final Rx<TranscriptionTask?> currentTask = Rx<TranscriptionTask?>(null);

  /// 是否有任务在进行
  bool get hasActiveTasks => _queue.isNotEmpty || currentTask.value != null;

  /// 进度比例 0.0~1.0
  double get progress => totalCount.value == 0 ? 0 : completedCount.value / totalCount.value;

  // ── 操作 ────────────────────────────────────────────────────────────────

  /// 将音频文件加入转录队列
  TranscriptionTask enqueue({
    required String audioFilePath,
    String? language,
    required String displayName,
  }) {
    final id = '${audioFilePath}_${DateTime.now().millisecondsSinceEpoch}';
    final task = TranscriptionTask(
      id: id,
      audioFilePath: audioFilePath,
      language: language,
      displayName: displayName,
    );
    _queue.addLast(task);
    totalCount.value++;
    tasks.add(task);
    _logger.info('[转录队列] 入队: $displayName, 队列长度=${_queue.length}');
    _tick();
    return task;
  }

  /// 将文件夹下所有音频加入转录队列
  List<TranscriptionTask> enqueueBatch({
    required List<String> filePaths,
    required List<String> displayNames,
    String? language,
  }) {
    final batch = <TranscriptionTask>[];
    for (int i = 0; i < filePaths.length; i++) {
      batch.add(enqueue(
        audioFilePath: filePaths[i],
        language: language,
        displayName: displayNames[i],
      ));
    }
    return batch;
  }

  /// 取消等待中的任务
  void cancel(String taskId) {
    _queue.removeWhere((t) {
      if (t.id == taskId) {
        t.state.value = TranscriptionTaskState.cancelled;
        return true;
      }
      return false;
    });
  }

  /// 取消所有等待中的任务
  void cancelAll() {
    for (final task in _queue) {
      task.state.value = TranscriptionTaskState.cancelled;
    }
    _queue.clear();
  }

  /// 清除已完成的任务记录
  void clearCompleted() {
    tasks.removeWhere((t) =>
        t.state.value == TranscriptionTaskState.completed ||
        t.state.value == TranscriptionTaskState.cancelled);
    completedCount.value = 0;
    totalCount.value = tasks.where((t) =>
        t.state.value == TranscriptionTaskState.running ||
        t.state.value == TranscriptionTaskState.queued).length;
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  void _tick() {
    if (_isProcessing) return;
    _processNext();
  }

  /// 启动真实进度轮询定时器
  /// Whisper 识别通过 set_progress_callback_safe 将进度写入全局原子变量，
  /// Flutter 侧通过 whisperGetTranscriptionProgress() 轮询获取
  void _startProgressPolling(TranscriptionTask task) {
    _progressTimer?.cancel();
    task.progress.value = 0.0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final rawProgress = whisper_api.whisperGetTranscriptionProgress();
      if (rawProgress >= 0) {
        // rawProgress 是 0~100 的百分比，转为 0.0~1.0
        final progress = (rawProgress / 100.0).clamp(0.0, 0.99);
        task.progress.value = progress;
      }
    });
  }

  void _stopProgressPolling(TranscriptionTask task) {
    _progressTimer?.cancel();
    _progressTimer = null;
    task.progress.value = 1.0;
  }

  Future<void> _processNext() async {
    if (_queue.isEmpty) {
      _isProcessing = false;
      return;
    }

    _isProcessing = true;
    final task = _queue.removeFirst();
    if (task.state.value == TranscriptionTaskState.cancelled) {
      completedCount.value++;
      _processNext();
      return;
    }

    currentTask.value = task;
    task.state.value = TranscriptionTaskState.running;
    _startProgressPolling(task);
    _logger.info('[转录队列] 开始识别: ${task.displayName}');

    try {
      // 确保 whisper 已初始化
      whisper_api.whisperInitialize();
      final result = await whisper_api.whisperTranscribe(
        audioFilePath: task.audioFilePath,
        language: task.language,
      );
      task.result = result;
      task.state.value = TranscriptionTaskState.completed;
      _stopProgressPolling(task);
      _logger.info('[转录队列] 识别完成: ${task.displayName}, 片段数=${result.segments.length}');
    } catch (e) {
      task.state.value = TranscriptionTaskState.failed;
      task.progress.value = 0;
      task.error.value = e.toString();
      _progressTimer?.cancel();
      _progressTimer = null;
      _logger.info('[转录队列] 识别失败: ${task.displayName}, 错误=$e');
    } finally {
      currentTask.value = null;
      completedCount.value++;
      _processNext();
    }
  }
}

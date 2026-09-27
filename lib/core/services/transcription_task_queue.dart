import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/services/asr/asr_service.dart';
import 'package:slime_works/core/services/asr/asr_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/asr.dart' as asr_api;
import 'package:slime_works/src/rust/api/whisper.dart' as whisper_api;

const Loggers _logger = Loggers(name: '识别队列');

/// 任务类型
enum SpeechJobKind {
  /// Whisper 识别并生成 CUE 音轨索引（音乐专辑场景）
  whisperCue,

  /// 识别字幕并生成 SRT 文件（视频/音频字幕场景）
  subtitle,

  /// 把已有 SRT 翻译成中文 SRT（二次审核场景，走内网 NMT）
  subtitleTranslate,
}

/// 单个识别任务
class TranscriptionTask {
  final String id;
  final String audioFilePath;
  final String? language;
  final String displayName;

  /// 任务类型，默认走原有的 Whisper→CUE 流程
  final SpeechJobKind kind;

  /// 翻译任务的输入字幕路径；为空时按媒体文件同名 .srt 推导
  final String? subtitlePath;

  /// 任务状态
  final Rx<TranscriptionTaskState> state = TranscriptionTaskState.queued.obs;

  /// 当前任务的识别进度 0.0~1.0
  final RxDouble progress = 0.0.obs;

  /// 进度不可知（远程转写无阶段回报）时为 true，UI 显示不确定进度条
  final RxBool indeterminate = false.obs;

  /// 本次任务实际使用的引擎（远程/本地），完成后供日志与提示展示
  final RxnString engineLabel = RxnString();

  /// 错误信息
  final RxnString error = RxnString();

  /// Whisper 识别结果
  whisper_api.TranscriptionResultInfo? result;

  /// 字幕任务的产出文件路径
  String? outputPath;

  /// 远程任务的取消令牌
  CancelToken? cancelToken;

  TranscriptionTask({
    required this.id,
    required this.audioFilePath,
    this.language,
    required this.displayName,
    this.kind = SpeechJobKind.whisperCue,
    this.subtitlePath,
  });

  bool get isSubtitle => kind == SpeechJobKind.subtitle;

  bool get isTranslate => kind == SpeechJobKind.subtitleTranslate;
}

/// 识别任务状态
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
/// 串行执行识别任务，提供全局进度供 UI 消费。
/// 支持两类任务：Whisper→CUE（[enqueue]）与字幕→SRT（[enqueueSubtitle]）。
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

  /// 将音频文件加入转录队列（Whisper → CUE）
  TranscriptionTask enqueue({
    required String audioFilePath,
    String? language,
    required String displayName,
  }) {
    return _enqueue(TranscriptionTask(
      id: '${audioFilePath}_${DateTime.now().millisecondsSinceEpoch}',
      audioFilePath: audioFilePath,
      language: language,
      displayName: displayName,
    ));
  }

  /// 将媒体文件加入字幕队列（SenseVoice/内网大模型 → SRT）
  ///
  /// 引擎路由在任务开始执行时决定：优先内网大模型，其次本地 sidecar
  TranscriptionTask enqueueSubtitle({
    required String mediaFilePath,
    String? language,
    required String displayName,
  }) {
    final task = TranscriptionTask(
      id: 'srt_${mediaFilePath}_${DateTime.now().millisecondsSinceEpoch}',
      audioFilePath: mediaFilePath,
      language: language,
      displayName: displayName,
      kind: SpeechJobKind.subtitle,
    );
    return _enqueue(task);
  }

  /// 把已有字幕翻译成中文并写到同目录
  ///
  /// * [subtitlePath] 省略时按媒体文件同名 .srt 推导（识别字幕的默认产出）
  TranscriptionTask enqueueTranslate({
    required String mediaFilePath,
    required String displayName,
    String? subtitlePath,
    String? language,
  }) {
    final task = TranscriptionTask(
      id: 'tr_${subtitlePath ?? mediaFilePath}_${DateTime.now().millisecondsSinceEpoch}',
      audioFilePath: mediaFilePath,
      displayName: displayName,
      language: language ?? getIt<AsrSettingsService>().defaultLanguage.value,
      kind: SpeechJobKind.subtitleTranslate,
      subtitlePath: subtitlePath,
    );
    return _enqueue(task);
  }

  TranscriptionTask _enqueue(TranscriptionTask task) {
    _queue.addLast(task);
    totalCount.value++;
    tasks.add(task);
    _logger.info('[识别队列] 入队: ${task.displayName}, 队列长度=${_queue.length}');
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

  /// 取消任务：排队中的直接出队，正在跑的会中断底层识别
  void cancel(String taskId) {
    final running = currentTask.value;
    if (running != null && running.id == taskId) {
      _cancelRunning(running);
      return;
    }

    _queue.removeWhere((t) {
      if (t.id == taskId) {
        t.state.value = TranscriptionTaskState.cancelled;
        return true;
      }
      return false;
    });
  }

  void _cancelRunning(TranscriptionTask task) {
    if (task.isSubtitle || task.isTranslate) {
      task.cancelToken?.cancel('用户取消');
      if (!task.isTranslate) {
        try {
          asr_api.asrCancelTranscribe();
        } catch (e) {
          _logger.error('[识别队列] 取消本地识别失败', error: e);
        }
      }
    }
    task.state.value = TranscriptionTaskState.cancelled;
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
  ///
  /// Whisper/SenseVoice 都把进度写入 Rust 侧全局原子变量，
  /// Flutter 侧轮询 whisperGetTranscriptionProgress / asrGetTranscribeProgress。
  /// 翻译任务的进度由 Dart 侧按"已完成批次/总批次"直接写入，不需要轮询。
  void _startProgressPolling(TranscriptionTask task) {
    _progressTimer?.cancel();
    _progressTimer = null;
    task.progress.value = 0.0;
    task.indeterminate.value = false;
    if (task.isTranslate) return;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final rawProgress = task.isSubtitle
          ? _safeAsrProgress()
          : whisper_api.whisperGetTranscriptionProgress();
      if (rawProgress >= 0) {
        // rawProgress 是 0~100 的百分比，转为 0.0~1.0
        task.progress.value = (rawProgress / 100.0).clamp(0.0, 0.99);
      }
    });
  }

  double _safeAsrProgress() {
    try {
      return asr_api.asrGetTranscribeProgress();
    } catch (e) {
      return -1;
    }
  }

  void _stopProgressPolling(TranscriptionTask task) {
    _progressTimer?.cancel();
    _progressTimer = null;
    task.indeterminate.value = false;
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
    _logger.info('[识别队列] 开始识别: ${task.displayName}');

    try {
      if (task.isTranslate) {
        await _runTranslate(task);
      } else if (task.isSubtitle) {
        await _runSubtitle(task);
        _chainTranslateIfNeeded(task);
      } else {
        // 确保 whisper 已初始化
        whisper_api.whisperInitialize();
        final result = await whisper_api.whisperTranscribe(
          audioFilePath: task.audioFilePath,
          language: task.language,
        );
        task.result = result;
        _logger.info('[识别队列] 识别完成: ${task.displayName}, 片段数=${result.segments.length}');
      }
      task.state.value = TranscriptionTaskState.completed;
      _stopProgressPolling(task);
    } catch (e) {
      // 用户已取消时不要把状态改成失败，避免任务卡片闪一下红
      if (task.state.value != TranscriptionTaskState.cancelled) {
        task.state.value = TranscriptionTaskState.failed;
        task.progress.value = 0;
        task.indeterminate.value = false;
        task.error.value = e.toString();
      }
      _progressTimer?.cancel();
      _progressTimer = null;
      _logger.info('[识别队列] 识别失败: ${task.displayName}, 错误=$e');
    } finally {
      currentTask.value = null;
      completedCount.value++;
      _processNext();
    }
  }

  /// 字幕任务：优先内网大模型，失败或未配置时回落到本地 SenseVoice sidecar
  Future<void> _runSubtitle(TranscriptionTask task) async {
    final settings = getIt<AsrSettingsService>();
    final asrService = getIt<AsrService>();

    if (settings.preferRemote.value) {
      final server = await settings.pickAvailableServer();
      if (server != null) {
        try {
          await _runRemoteSubtitle(task, settings, asrService, server);
          return;
        } catch (e) {
          if (task.state.value == TranscriptionTaskState.cancelled) rethrow;
          _logger.info('[识别队列] 内网服务 ${server.name} 失败，回退本地引擎: $e');
        }
      }
    }

    if (!settings.supportsLocalEngine) {
      throw Exception('未找到可用的内网语音识别服务，且当前平台不支持本地引擎');
    }
    settings.refreshLocalStatus();
    if (!settings.localReady.value) {
      throw Exception('尚未部署本地语音识别引擎，请在资源库设置中完成一键部署');
    }

    task.engineLabel.value = '本地 SenseVoice';
    task.indeterminate.value = false;
    final result = await asr_api.asrTranscribeToSrt(
      mediaPath: task.audioFilePath,
      outputPath: null,
      language: task.language,
    );
    task.outputPath = result.srtPath;
    _logger.info(
      '[识别队列] 本地字幕完成: ${task.displayName}, ${result.segmentCount} 段 → ${result.srtPath}',
    );
  }

  Future<void> _runRemoteSubtitle(
    TranscriptionTask task,
    AsrSettingsService settings,
    AsrService asrService,
    AsrServer server,
  ) async {
    task.engineLabel.value = '内网 ${server.name}';
    // 远程转写只有上传阶段可量化，等待结果期间显示不确定进度
    task.indeterminate.value = true;
    task.cancelToken = CancelToken();

    final transcription = await asrService.transcribe(
      server,
      filePath: task.audioFilePath,
      language: task.language,
      cancelToken: task.cancelToken,
      onSendProgress: (status) {
        task.indeterminate.value = false;
        task.progress.value = status.clamp(0.0, 0.3);
      },
    );
    task.cancelToken = null;
    task.indeterminate.value = true;

    if (transcription.segments.isEmpty) {
      throw Exception('内网服务未返回任何字幕内容');
    }

    // 字幕落盘统一交给 Rust，避免 Dart 侧直接写媒体文件
    final outputDir = File(task.audioFilePath).parent.path;
    task.outputPath = asr_api.asrWriteSrt(
      mediaPath: task.audioFilePath,
      segments: transcription.segments
          .map((s) => asr_api.AsrSegmentInfo(
                startMs: BigInt.from(s.startMs),
                endMs: BigInt.from(s.endMs),
                text: s.text,
              ))
          .toList(),
      outputDir: outputDir,
    );
    _logger.info('[识别队列] 内网字幕完成: ${task.displayName}, ${transcription.segments.length} 段 → ${task.outputPath}');
  }

  /// 识别成功后按设置自动串一条翻译任务（审核流程需要中文 + 时间轴）
  void _chainTranslateIfNeeded(TranscriptionTask task) {
    final settings = getIt<AsrSettingsService>();
    final srtPath = task.outputPath;
    if (!settings.autoTranslate.value || srtPath == null) return;
    _enqueue(TranscriptionTask(
      id: 'tr_$srtPath${task.language ?? 'auto'}_${DateTime.now().millisecondsSinceEpoch}',
      audioFilePath: task.audioFilePath,
      displayName: task.displayName,
      // 识别时锁定的语言正是字幕的源语言，直接复用可以省掉服务端自检
      language: task.language,
      kind: SpeechJobKind.subtitleTranslate,
      subtitlePath: srtPath,
    ));
    _logger.info('[识别队列] 已按设置串入翻译任务: $srtPath');
  }

  /// 翻译任务：读原字幕 → 内网 NMT 逐段译中 → Rust 写 .zh.srt
  Future<void> _runTranslate(TranscriptionTask task) async {
    final settings = getIt<AsrSettingsService>();
    final server = await settings.pickAvailableTranslateServer();
    if (server == null) {
      throw Exception('未配置可用的内网字幕翻译服务，请在资源库设置中添加 NMT 服务地址');
    }

    final sourceSrt = task.subtitlePath ?? siblingSrtPath(task.audioFilePath);
    if (!File(sourceSrt).existsSync()) {
      throw Exception('未找到字幕文件 $sourceSrt，请先执行"识别字幕"');
    }

    // 字幕解析与落盘都在 Rust 侧，Dart 只走 HTTP
    final segments = asr_api.asrParseSrt(srtPath: sourceSrt);
    task.engineLabel.value = '内网 ${server.name}';
    task.indeterminate.value = true;
    task.cancelToken = CancelToken();

    final result = await settings.translateService.translate(
      server,
      texts: segments.map((s) => s.text).toList(),
      source: task.language ?? 'auto',
      cancelToken: task.cancelToken,
      onProgress: (done, total) {
        task.indeterminate.value = false;
        task.progress.value = total == 0 ? 0 : (done / total).clamp(0.0, 0.99);
      },
    );
    task.cancelToken = null;

    if (result.untranslatedCount > 0) {
      _logger.info(
        '[识别队列] ${task.displayName} 有 ${result.untranslatedCount} 段未翻译（已保留原文），请抽检译文',
      );
    }

    final bilingual = settings.bilingualSubtitle.value;
    final target = _swapExtension(sourceSrt, '.zh.srt');
    task.outputPath = asr_api.asrWriteSrt(
      mediaPath: sourceSrt,
      segments: [
        for (int i = 0; i < segments.length; i++)
          asr_api.AsrSegmentInfo(
            startMs: segments[i].startMs,
            endMs: segments[i].endMs,
            text: bilingual ? '${segments[i].text}\n${result.texts[i]}' : result.texts[i],
          ),
      ],
      outputDir: target,
    );
    _logger.info('[识别队列] 字幕翻译完成: ${task.displayName}, ${segments.length} 段 → ${task.outputPath}');
  }
}

/// 媒体文件路径 → 同目录同名 .srt（识别字幕的默认产出位置）
///
/// 右键菜单判断"有没有字幕可翻译"时也用这一个推导，避免两处规则不一致
String siblingSrtPath(String mediaPath) => _swapExtension(mediaPath, '.srt');

/// 替换文件扩展名，兼容 Windows 与 POSIX 两种分隔符
String _swapExtension(String path, String newExt) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final separator = slash > backslash ? slash : backslash;
  return (dot > separator) ? '${path.substring(0, dot)}$newExt' : '$path$newExt';
}

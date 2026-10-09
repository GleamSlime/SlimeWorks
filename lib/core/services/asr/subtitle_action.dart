import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/services/asr/asr_settings_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/services/transcription_task_queue.dart';
import 'package:slime_works/src/rust/api/asr.dart' as asr_api;

/// 右键「识别字幕」的统一入口：校验文件 → 入队 → 识别结束后提示产出路径
///
/// 进度由右下角 [FloatingTaskProgress] 悬浮窗承载，这里只负责开始与结束反馈。
/// [language] 来自右键子菜单的选择，同时记成下次的默认语言。
Future<void> recognizeSubtitleAction(
  BuildContext context, {
  required String filePath,
  required String displayName,
  required String language,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final settings = getIt<AsrSettingsService>();
  unawaited(settings.setDefaultLanguage(language));

  if (!asr_api.asrIsSupportedMedia(filePath: filePath)) {
    messenger.showSnackBar(const SnackBar(content: Text('该文件格式暂不支持字幕识别')));
    return;
  }
  if (!File(filePath).existsSync()) {
    messenger.showSnackBar(const SnackBar(content: Text('文件不在本机，无法识别字幕')));
    return;
  }

  // 只做了可用性判断，不做实际下载：真正的引擎选择与回退在队列任务里执行
  final hasRemote = settings.servers.any((s) => s.enabled);
  if (!hasRemote && settings.supportsLocalEngine && !settings.localReady.value) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('尚未部署本地语音识别引擎，也没有可用的内网大模型，请先到资源库设置中配置'),
        duration: AppMotion.dwellLong,
      ),
    );
    return;
  }

  final task = getIt<TranscriptionTaskQueue>().enqueueSubtitle(
    mediaFilePath: filePath,
    displayName: displayName,
    language: language,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text('「$displayName」已加入识别队列（${asrLanguageLabel(language)}）'),
      duration: AppMotion.dwell,
    ),
  );
  _notifyWhenDone(context, task);
}

/// 右键「翻译字幕」的统一入口：把同名 .srt 逐段译成中文并写出 .zh.srt
///
/// 源语言取上一次识别时选定的语言（[AsrSettingsService.defaultLanguage]），
/// 因此"先识别韩语字幕、再翻译"这条链路上不需要二次点选。
Future<void> translateSubtitleAction(
  BuildContext context, {
  required String filePath,
  required String displayName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final settings = getIt<AsrSettingsService>();

  if (!File(filePath).existsSync()) {
    messenger.showSnackBar(const SnackBar(content: Text('文件不在本机，无法翻译字幕')));
    return;
  }
  final sourceSrt = siblingSrtPath(filePath);
  if (!File(sourceSrt).existsSync()) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('未找到字幕文件 $sourceSrt，请先执行"识别字幕"'),
        duration: AppMotion.dwellLong,
      ),
    );
    return;
  }
  if (!settings.translateServers.any((s) => s.enabled)) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('尚未配置内网字幕翻译服务（LibreTranslate 兼容的 NMT 接口），请先到资源库设置中添加'),
        duration: AppMotion.dwellLong,
      ),
    );
    return;
  }

  final language = settings.defaultLanguage.value;
  final task = getIt<TranscriptionTaskQueue>().enqueueTranslate(
    mediaFilePath: filePath,
    displayName: displayName,
    subtitlePath: sourceSrt,
    language: language,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text('「$displayName」已加入翻译队列（源语言：${asrLanguageLabel(language)} → 中文）'),
      duration: AppMotion.dwell,
    ),
  );
  _notifyWhenDone(context, task);
}

/// 任务结束时提示结果（成功给出字幕文件路径，失败给出原因）
void _notifyWhenDone(BuildContext context, TranscriptionTask task) {  late final Worker worker;
  worker = ever(task.state, (state) {
    final isDone =
        state == TranscriptionTaskState.completed ||
        state == TranscriptionTaskState.failed ||
        state == TranscriptionTaskState.cancelled;
    if (!isDone) return;
    worker.dispose();
    if (!context.mounted) return;

    final isTranslate = task.kind == SpeechJobKind.subtitleTranslate;
    final message = switch (state) {
      TranscriptionTaskState.completed => task.outputPath == null
          ? (isTranslate ? '翻译完成' : '字幕识别完成')
          : '${isTranslate ? '中文字幕已生成：' : '字幕已生成：'}${task.outputPath}',
      TranscriptionTaskState.cancelled =>
        '已取消「${task.displayName}」的${isTranslate ? '翻译' : '识别'}',
      _ => '「${task.displayName}」${isTranslate ? '翻译' : '识别'}失败：${task.error.value ?? '未知错误'}',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        // 完成那条会把生成路径整段念出来，按"要读完的通知"档走；其余是短状态条
        duration: state == TranscriptionTaskState.completed
            ? AppMotion.dwellNotice
            : AppMotion.dwellLong,
      ),
    );
  });
}

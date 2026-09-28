import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/transcription_task_queue.dart'
    show siblingSrtPath;
import 'package:slime_works/core/utils/logger.dart';

const _logger = Loggers(name: '字幕挂载');

/// 播放时的字幕候选：先中文译文（翻译产出），再识别原文
///
/// 与识别/翻译队列的落盘位置保持同一推导规则，避免两处各自拼路径。
List<String> subtitleCandidates(String mediaPath) {
  final srt = siblingSrtPath(mediaPath);
  final dot = srt.lastIndexOf('.');
  return ['${srt.substring(0, dot)}.zh.srt', srt];
}

/// 取到可直接交给播放器的**本地**字幕文件路径；没有字幕返回 null。
///
/// 远程集合的 filePath 是节点磁盘上的路径，本机读不到，必须先从节点取回临时文件：
/// mpv 的 `sub-add` 靠文件名后缀判断字幕格式，而节点 URL 的路径部分是 `/node/media`
/// （字幕路径藏在 query 里），直接喂 URL 会被当成普通媒体流，所以一律落到本地文件。
Future<String?> resolvePlaybackSubtitlePath({
  required String mediaPath,
  String? nodeId,
}) async {
  if (mediaPath.isEmpty) return null;
  final candidates = subtitleCandidates(mediaPath);

  if (nodeId == null) {
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  final node = getIt<NodeSettingsService>();
  final dir = await _cacheDir();
  // 每次都重新取：字幕可能被重新识别/翻译覆盖，留着旧副本会显示过期内容
  return resolveSubtitleFromCandidates(
    candidates: candidates,
    saveDir: dir,
    fetch: (candidate, savePath) => node.downloadNodeFileTo(
      nodeId: nodeId,
      filePath: candidate,
      savePath: savePath,
    ),
  );
}

/// 逐个候选取字幕，第一个取到正文非空的即返回其本地路径；全部落空返回 null。
///
/// 取回失败（404「没有这个字幕」与网络异常同等看待）只让当前候选作废、继续试下一个，
/// 否则只有原文 `.srt`（没有译文 `.zh.srt`）的文件会在第一个候选就中断。
Future<String?> resolveSubtitleFromCandidates({
  required List<String> candidates,
  required Directory saveDir,
  required Future<void> Function(String candidate, String savePath) fetch,
}) async {
  Object? lastError;
  for (final candidate in candidates) {
    final savePath = '${saveDir.path}/${_cacheName(candidate)}';
    try {
      await fetch(candidate, savePath);
      final file = File(savePath);
      if (file.existsSync() && file.lengthSync() > 0) return savePath;
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError != null) {
    _logger.log('字幕取回失败，最后错误: $lastError', name: 'WARN');
  }
  return null;
}

Future<Directory> _cacheDir() async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/sw_subtitles');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// 保留原后缀（mpv 按后缀选字幕解析器），用路径哈希避免同名碰撞
String _cacheName(String subtitlePath) {
  final dot = subtitlePath.lastIndexOf('.');
  final ext = dot < 0 ? '.srt' : subtitlePath.substring(dot);
  return 'sub_${subtitlePath.hashCode.toUnsigned(32).toRadixString(16)}$ext';
}

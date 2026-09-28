// 播放时字幕挂载的路径解析单测：候选顺序与"取不到就换下一个"的策略。
//
// 不依赖 FFI 与 GetIt：nodeId==null 的本地分支只碰 dart:io；远程分支把取回
// 动作抽成 resolveSubtitleFromCandidates 的 fetch 注入点，用临时目录直测。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/services/asr/subtitle_mount.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sw_subtitle'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, [String content = '1\n00:00:01,000 --> 00:00:02,000\n你好\n']) {
    final file = File('${dir.path}/$name')..writeAsStringSync(content);
    return file.path;
  }

  group('subtitleCandidates', () {
    test('译文优先于原文', () {
      final candidates = subtitleCandidates('${dir.path}/show.mp3');
      expect(candidates, [
        '${dir.path}/show.zh.srt',
        '${dir.path}/show.srt',
      ]);
    });

    test('文件名含多个点时只在最后一个点处替换', () {
      final candidates = subtitleCandidates('/a/b/EP.01.1080p.m4a');
      expect(candidates, ['/a/b/EP.01.1080p.zh.srt', '/a/b/EP.01.1080p.srt']);
    });
  });

  group('resolvePlaybackSubtitlePath 本地分支', () {
    test('只有原文字幕时返回该 .srt', () async {
      final media = write('podcast.mp3', 'audio');
      final original = write('podcast.srt');

      expect(await resolvePlaybackSubtitlePath(mediaPath: media), original);
    });

    test('两种字幕都在时挂中文译文', () async {
      final media = write('anime.mkv', 'video');
      final original = write('anime.srt');
      final translated = write('anime.zh.srt');

      expect(
        await resolvePlaybackSubtitlePath(mediaPath: media),
        translated,
        reason: '识别原文是 $original',
      );
    });

    test('没有任何字幕文件时返回 null', () async {
      final media = write('silent.wav', 'audio');
      expect(await resolvePlaybackSubtitlePath(mediaPath: media), isNull);
    });

    test('空路径不抛异常', () async {
      expect(await resolvePlaybackSubtitlePath(mediaPath: ''), isNull);
    });
  });

  group('resolveSubtitleFromCandidates', () {
    /// 模拟节点：只有 named 这个字幕存在，其余按 404 抛错
    Future<void> Function(String, String) nodeServing(
      Set<String> exists, {
      Map<String, int> sizes = const {},
    }) {
      return (candidate, savePath) async {
        if (!exists.contains(candidate)) throw const SocketException('404');
        File(savePath).writeAsStringSync(sizes[candidate] == 0 ? '' : 'x\n');
      };
    }

    test('第一个候选 404 时继续试第二个（只有原文字幕的常见情形）', () async {
      final candidates = subtitleCandidates('/node/eps/show.mp3');

      final path = await resolveSubtitleFromCandidates(
        candidates: candidates,
        saveDir: dir,
        fetch: nodeServing({candidates.last}),
      );

      expect(path, isNotNull);
      expect(path, endsWith('.srt'));
      expect(File(path!).readAsStringSync(), isNotEmpty);
    });

    test('落地文件为空视为没字幕，继续找下一个候选', () async {
      final candidates = subtitleCandidates('/node/eps/show.mp3');

      final path = await resolveSubtitleFromCandidates(
        candidates: candidates,
        saveDir: dir,
        fetch: nodeServing(
          {candidates.first, candidates.last},
          sizes: {candidates.first: 0},
        ),
      );

      expect(path, isNotNull);
      expect(File(path!).lengthSync(), greaterThan(0), reason: '空文件不能当字幕挂上');
    });

    test('全部候选都取不到时返回 null 且不抛出', () async {
      final path = await resolveSubtitleFromCandidates(
        candidates: subtitleCandidates('/node/eps/show.mp3'),
        saveDir: dir,
        fetch: (_, _) async => throw const SocketException('connection refused'),
      );

      expect(path, isNull);
    });
  });
}

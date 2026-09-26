// 音乐播放器可测逻辑切片单测（ASMR 树 + 播放模式枚举）。
//
// 设计约束与放弃说明：
// - MusicPlayerViewModel 的字段初始化会构造 media_kit Player()，
//   其内部 DynamicLibrary.open(Mpv.framework) 在 flutter_tester 环境
//   必抛（实测报 "Cannot find Mpv.framework/Mpv"），因此 VM 实例本身
//   在单测中不可构造。依赖 VM 实例的目标全部无法触达：
//   * _extractWorkCode / _workCodeToApiId / _workCodeDirName / _fmtBytes —
//     私有方法，唯一公开入口 importAsmrLink 还需真实网络（Dio 内部构造，
//     无注入口）；
//   * _buildAsmrNode（JSON→树）— 私有且仅经网络路径触达；
//   * _updateBreadcrumb / _updateLyricIndex / formatDuration / filteredItems
//     — 需要 VM 实例。
// - 顶层公开类 AsmrTreeNode / AsmrWorkInfo 是纯 Dart 树模型（_buildAsmrNode
//   产出物的下游消费者），可独立于 VM 完整测试其遍历/选择/级联语义。
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';

AsmrTreeNode folder(String title, List<AsmrTreeNode> children) {
  return AsmrTreeNode(type: 'folder', title: title, children: children);
}

AsmrTreeNode audio(
  String title, {
  String? downloadUrl,
  String? streamUrl,
  double? durationSec,
  int? sizeBytes,
  bool selected = false,
}) {
  return AsmrTreeNode(
    type: 'audio',
    title: title,
    downloadUrl: downloadUrl,
    streamUrl: streamUrl,
    durationSec: durationSec,
    sizeBytes: sizeBytes,
    selected: selected,
  );
}

void main() {
  // ── AsmrTreeNode 单节点属性 ───────────────────────────────────────────────

  group('AsmrTreeNode 基础属性', () {
    test('isFile：folder 之外（audio/image/other）都算文件', () {
      expect(folder('碟', []).isFile, isFalse);
      expect(audio('a.mp3').isFile, isTrue);
      expect(AsmrTreeNode(type: 'image', title: 'c.jpg').isFile, isTrue);
      expect(AsmrTreeNode(type: 'other', title: 'x.txt').isFile, isTrue);
    });

    test('playUrl：优先流地址，回退下载地址，双空为 null', () {
      expect(
        audio('a', downloadUrl: 'http://d/a.mp3', streamUrl: 'http://s/a.mp3').playUrl,
        'http://s/a.mp3',
      );
      expect(audio('a', downloadUrl: 'http://d/a.mp3').playUrl, 'http://d/a.mp3');
      expect(audio('a', streamUrl: 'http://s/a.mp3').playUrl, 'http://s/a.mp3');
      expect(audio('a').playUrl, isNull);
    });

    test('durationMs：秒×1000 四舍五入；无时长为 null', () {
      expect(audio('a', durationSec: 90.0).durationMs, 90000);
      expect(audio('a', durationSec: 2.5).durationMs, 2500);
      expect(audio('a').durationMs, isNull);
    });
  });

  // ── 树遍历 ────────────────────────────────────────────────────────────────

  group('树遍历与选择', () {
    late AsmrTreeNode root;
    late AsmrTreeNode deepAudio;

    setUp(() {
      deepAudio = audio(
        'b.mp3',
        downloadUrl: 'http://d/b.mp3',
        selected: true,
      ); // 无 streamUrl
      final streamOnly = audio('c.mp3', streamUrl: 'http://s/c.mp3', selected: true); // 无下载地址
      root = folder('作品根', [
        audio('a.mp3', downloadUrl: 'http://d/a.mp3', selected: true),
        folder('嵌套夹', [deepAudio, streamOnly]),
        AsmrTreeNode(
          type: 'image',
          title: 'cover.jpg',
          downloadUrl: 'http://d/cover.jpg',
          selected: true,
        ),
        audio('未选.mp3', downloadUrl: 'http://d/u.mp3'), // selected=false
      ]);
    });

    test('audioFiles 深度优先收集全部音频节点（含嵌套，忽略 selected）', () {
      expect(root.audioFiles.map((n) => n.title).toList(), ['a.mp3', 'b.mp3', 'c.mp3', '未选.mp3']);
    });

    test('selectedFiles：仅 文件节点 && 选中 && 有下载地址（流地址不算、图片也算）', () {
      expect(
        root.selectedFiles.map((n) => n.title).toList(),
        ['a.mp3', 'b.mp3', 'cover.jpg'],
      );
      // c.mp3 只有 streamUrl → 被排除；未选.mp3 未勾选 → 被排除
    });

    test('syncChildren 将选中态级联覆盖整棵子树', () {
      root.selected = true;
      root.syncChildren();
      for (final n in root.audioFiles) {
        expect(n.selected, isTrue);
      }
      root.selected = false;
      root.syncChildren();
      expect(deepAudio.selected, isFalse);
    });
  });

  group('AsmrWorkInfo.tracks 展平', () {
    test('按根节点顺序展开各自 audioFiles，保持树内深度优先序', () {
      final disc1 = folder('碟1', [audio('1.mp3'), folder('x', [audio('2.mp3')])]);
      final single = audio('3.mp3');
      final info = AsmrWorkInfo(title: '作品', tree: [disc1, single]);
      expect(info.tracks.map((n) => n.title).toList(), ['1.mp3', '2.mp3', '3.mp3']);
      // 空树 → 空列表
      expect(AsmrWorkInfo(title: '空', tree: []).tracks, isEmpty);
    });
  });

  // ── 播放模式枚举 ──────────────────────────────────────────────────────────

  group('PlayerPlayMode', () {
    test('四个成员均有中文 label 与图标', () {
      expect(
        PlayerPlayMode.values.map((m) => m.label).toList(),
        ['顺序播放', '列表循环', '单曲循环', '随机播放'],
      );
      for (final m in PlayerPlayMode.values) {
        // 描边图标没有码位，能校验的是"真的有笔画可描"
        expect(m.icon.paths, isNotEmpty, reason: m.label);
      }
    });
  });
}

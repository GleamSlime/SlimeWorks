import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/services/asr/asr_settings_service.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/format.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class MediaItemTile extends StatefulWidget {
  const MediaItemTile({
    super.key,
    required this.item,
    required this.source,
    required this.onTap,
    this.onRequestScrubFrames,
    this.onRequestAudioCover,
    this.onOpenFolder,
    this.onDeleteFile,
    this.onDeleteNodeLocalFile,
    this.deleteNodeLocalFileLabel,
    this.onSaveToGallery,
    this.onRecognizeSubtitle,
    this.onTranslateSubtitle,
    this.fixedHeight,
    this.showOverlay = true,
    this.isLost = false,
    this.coverFallbackSource,
  });

  final media_api.MediaItem item;
  final String? source;
  final VoidCallback onTap;

  /// 仅本地视频提供：异步返回均匀分布的帧文件路径列表。
  final Future<List<String>> Function()? onRequestScrubFrames;

  /// 仅本地音频提供：异步返回提取出的嵌入专辑封面缩略图路径。
  final Future<String?> Function()? onRequestAudioCover;

  /// 在文件管理器中显示该文件（本地）。
  final VoidCallback? onOpenFolder;

  /// 删除该文件（本地）。
  final VoidCallback? onDeleteFile;

  /// 删除节点本地文件（远程资源）。
  final VoidCallback? onDeleteNodeLocalFile;

  /// 节点本地文件删除按钮的文案，默认为「删除节点本地文件」。
  final String? deleteNodeLocalFileLabel;

  /// 保存图片到相册（移动端）。
  final VoidCallback? onSaveToGallery;

  /// 识别该媒体文件的字幕并输出 SRT（仅本地音视频且扩展名受支持时由父级传入）。
  /// 参数为识别语言代码（auto/ko/ja/zh/yue/en），由右键子菜单选定。
  final void Function(String language)? onRecognizeSubtitle;

  /// 把同名 .srt 翻译成中文（仅本地音视频由父级传入；有无字幕由动作内部校验）。
  final VoidCallback? onTranslateSubtitle;

  /// 瀑布流模式下由外部指定的固定高度（null = 填满格子）。
  final double? fixedHeight;

  /// 远程图片兜底原图 URL：缩略图 2s 未返回时临时改用原图充当封面。
  final String? coverFallbackSource;

  /// 是否显示叠加层（类型标签 + 标题栏）。
  final bool showOverlay;

  final bool isLost;

  @override
  State<MediaItemTile> createState() => _MediaItemTileState();
}

class _MediaItemTileState extends State<MediaItemTile> {
  bool _hovering = false;
  double _hoverRatio = 0.0;
  List<String>? _scrubFrames;
  bool _loadingFrames = false;
  String? _audioCoverPath;
  bool _loadingAudioCover = false;

  Worker? _privacyWorker;

  // ── 远程缩略图 2s 超时兜底状态 ─────────────────────────────────────────
  // 缩略图请求后台继续生成；超时后临时切原图，生成完成再切回缩略图。
  bool _coverFallbackActive = false;
  bool _coverThumbReady = false;

  /// 预取缩略图失败（节点忙回 503、原图已丢等）：与「成功但还没解码完」区分开。
  bool _coverPrecacheFailed = false;
  Timer? _coverFallbackTimer;

  @override
  void initState() {
    super.initState();
    final prefs = getIt.isRegistered<MediaPrefsService>() ? getIt.get<MediaPrefsService>() : null;
    if (prefs != null) {
      _privacyWorker = ever(prefs.privacyMode, (_) {
        if (mounted) setState(() {});
      });
    }
    // 音频 tile：立即后台提取嵌入封面
    if (_isAudio && widget.onRequestAudioCover != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAudioCover());
    }
    // 远程图片：预取缩略图并启动 2s 兜底计时
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareCoverFallback());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 视频 scrub 预生成受「预生成视频悬停帧」开关控制（默认开）。
    // 不放 initState：MediaPrefsService 为异步 init，首帧构建时可能仍是字段默认值，
    // 且依赖建立后的重建会重新走这里，用户切开关后 tile 能实际生效。
    _maybePreloadScrub();
  }

  void _maybePreloadScrub() {
    if (!_isVideo || widget.onRequestScrubFrames == null) return;
    final prefs = getIt.isRegistered<MediaPrefsService>() ? getIt.get<MediaPrefsService>() : null;
    if (prefs != null && !prefs.videoScrubPreload.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadScrubFrames());
  }

  @override
  void didUpdateWidget(MediaItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.coverFallbackSource != widget.coverFallbackSource) {
      _coverFallbackActive = false;
      _coverThumbReady = false;
      _coverPrecacheFailed = false;
      _coverFallbackTimer?.cancel();
      _coverFallbackTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _prepareCoverFallback());
    }
  }

  @override
  void dispose() {
    _coverFallbackTimer?.cancel();
    _privacyWorker?.dispose();
    super.dispose();
  }

  /// 远程缩略图可用兜底时：预取缩略图 + 启动超时计时。
  void _prepareCoverFallback() {
    if (!mounted) return;
    final src = widget.source;
    final fallback = widget.coverFallbackSource;
    // 仅远程缩略图 URL 且提供了不同于缩略图的原图 URL 时启用
    if (src == null || !src.startsWith('http') || fallback == null || fallback == src) {
      return;
    }
    _coverThumbReady = false;
    _coverPrecacheFailed = false;
    // 后台预取缩略图（不阻塞 UI），完成后切回缩略图。
    // onError 必须显式给：不传时 precacheImage 会把加载失败上报给 FlutterError，
    // 节点并发打满回 503 时整屏卡片各报一条，日志全是这类噪声；而它一旦给了，
    // 失败的 Future 也会正常完成，所以成功分支要靠 _coverPrecacheFailed 挡掉。
    precacheImage(
      NetworkImage(src),
      context,
      onError: (_, _) {
        // 缩略图生成失败：直接改用原图兜底
        _coverPrecacheFailed = true;
        _coverFallbackTimer?.cancel();
        if (!mounted) return;
        setState(() => _coverFallbackActive = true);
      },
    ).then((_) {
      if (_coverPrecacheFailed) return;
      _coverFallbackTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _coverThumbReady = true;
        _coverFallbackActive = false;
      });
    });
    // 2s 未就绪则临时采用原图
    _coverFallbackTimer?.cancel();
    _coverFallbackTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _coverThumbReady) return;
      setState(() => _coverFallbackActive = true);
    });
  }

  /// 计算实际展示的图片源：远程缩略图超时未返回时临时使用原图。
  String? _coverEffectiveSrc(String? src) {
    if (src == null || !src.startsWith('http')) return src;
    if (_coverThumbReady) return src;
    if (_coverFallbackActive) return widget.coverFallbackSource ?? src;
    return src;
  }

  bool get _isVideo => widget.item.kind == media_api.MediaKind.video;
  bool get _isAudio => widget.item.kind == media_api.MediaKind.audio;
  bool get _isImage => widget.item.kind == media_api.MediaKind.image;

  /// 左下镂空标签用的类型名
  String get _kindLabel => _isAudio ? '音频' : _isVideo ? '视频' : '图片';

  String? get _displaySource {
    if (_isVideo) {
      // 未提供 scrub 帧处理器时，仅远程（节点 URL）的 source 可能是服务端生成的封面缩略图；
      // 本地视频的 source 是原始文件（如 .mp4），Image 无法解码，必须返回空占位而非原文件，
      // 否则会把视频当图片解码而抛「Invalid image data」。
      if (widget.onRequestScrubFrames == null) {
        final s = widget.source;
        if (s == null || s.isEmpty || !s.startsWith('http')) return null;
        return s;
      }
      final frames = _scrubFrames;
      if (frames != null && frames.isNotEmpty) {
        if (_hovering) {
          final idx = (_hoverRatio * (frames.length - 1)).round().clamp(0, frames.length - 1);
          return frames[idx];
        }
        return frames[frames.length > 1 ? 1 : 0];
      }
      return null;
    }
    if (_isAudio) {
      if (widget.onRequestAudioCover == null) return widget.source;
      return _audioCoverPath;
    }
    return widget.source;
  }

  Future<void> _loadScrubFrames() async {
    if (_loadingFrames || _scrubFrames != null) return;
    if (widget.onRequestScrubFrames == null) return;
    setState(() => _loadingFrames = true);
    try {
      final frames = await widget.onRequestScrubFrames!();
      if (mounted) {
        setState(() {
          _scrubFrames = frames;
          _loadingFrames = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFrames = false);
    }
  }

  Future<void> _loadAudioCover() async {
    if (_loadingAudioCover || _audioCoverPath != null) return;
    if (widget.onRequestAudioCover == null) return;
    setState(() => _loadingAudioCover = true);
    try {
      final path = await widget.onRequestAudioCover!();
      if (mounted) {
        setState(() {
          _audioCoverPath = path;
          _loadingAudioCover = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAudioCover = false);
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset globalPosition) async {
    final hasActions =
        widget.onOpenFolder != null ||
        widget.onDeleteFile != null ||
        widget.onDeleteNodeLocalFile != null ||
        widget.onSaveToGallery != null ||
        widget.onRecognizeSubtitle != null ||
        widget.onTranslateSubtitle != null;
    if (!hasActions) return;
    if (!mounted) return;
    // 将全局坐标换算为 Overlay 本地坐标，保证菜单在光标位置弹出（与 MediaCollectionCard 一致）
    final overlayBox = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final localPos = overlayBox.globalToLocal(globalPosition);
    final overlaySize = overlayBox.size;
    final hasDestructive =
        widget.onDeleteFile != null || widget.onDeleteNodeLocalFile != null;
    final hasPlainActions =
        widget.onOpenFolder != null ||
        widget.onSaveToGallery != null ||
        widget.onRecognizeSubtitle != null ||
        widget.onTranslateSubtitle != null;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPos.dx,
        localPos.dy,
        overlaySize.width - localPos.dx,
        overlaySize.height - localPos.dy,
      ),
      items: [
        if (widget.onOpenFolder != null)
          GlassMenuItem<String>(
            value: 'open_folder',
            label: '打开所在文件夹',
            icon: StrokeIcons.folderOpen,
          ),
        if (widget.onSaveToGallery != null)
          GlassMenuItem<String>(
            value: 'save',
            label: '保存到相册',
            icon: StrokeIcons.photoLibrary,
          ),
        if (widget.onRecognizeSubtitle != null)
          GlassMenuItem<String>(
            value: 'recognize_subtitle',
            label: '识别字幕',
            icon: StrokeIcons.recordVoiceOver,
          ),
        if (widget.onTranslateSubtitle != null)
          GlassMenuItem<String>(
            value: 'translate_subtitle',
            label: '翻译字幕为中文',
            icon: StrokeIcons.translate,
          ),
        if (hasDestructive) ...[
          // 不可逆动作和普通动作之间断一行：这条菜单是右键就地弹出的，
          // 鼠标停在原处就能连点，不分组很容易一顺手删掉文件。
          if (hasPlainActions) const PopupMenuDivider(),
          if (widget.onDeleteFile != null)
            GlassMenuItem<String>(
              value: 'delete',
              label: '删除本地文件',
              icon: StrokeIcons.deleteOutline,
              destructive: true,
            ),
          if (widget.onDeleteNodeLocalFile != null)
            GlassMenuItem<String>(
              value: 'delete_node_local',
              label: widget.deleteNodeLocalFileLabel ?? '删除节点本地文件',
              icon: StrokeIcons.cloudOff,
              destructive: true,
            ),
        ],
      ],
    );
    if (!mounted) return;
    if (action == 'open_folder') widget.onOpenFolder?.call();
    if (action == 'save') widget.onSaveToGallery?.call();
    if (action == 'delete') widget.onDeleteFile?.call();
    if (action == 'delete_node_local') widget.onDeleteNodeLocalFile?.call();
    if (action == 'recognize_subtitle') {
      // 上面 await 过菜单，这里确认 context 还挂在树上再取它弹子菜单
      if (!context.mounted) return;
      final language = await _showSubtitleLanguageMenu(context, localPos, overlaySize);
      if (language != null) widget.onRecognizeSubtitle?.call(language);
    }
    if (action == 'translate_subtitle') widget.onTranslateSubtitle?.call();
  }

  /// 识别字幕的语言子菜单：SenseVoice 的自动检测对日韩语音频经常判错，
  /// 所以这里让使用方按素材显式指定，并把本次选择记住作为下次默认
  Future<String?> _showSubtitleLanguageMenu(
    BuildContext context,
    Offset localPos,
    Size overlaySize,
  ) {
    final preferred = getIt<AsrSettingsService>().defaultLanguage.value;
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPos.dx,
        localPos.dy,
        overlaySize.width - localPos.dx,
        overlaySize.height - localPos.dy,
      ),
      items: [
        for (final option in kAsrLanguages)
          GlassMenuItem<String>(
            value: option.code,
            label: option.label,
            icon: StrokeIcons.translate,
            selected: option.code == preferred,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final item = widget.item;
    final src = _coverEffectiveSrc(_displaySource);
    final showTimeline =
        _hovering && _isVideo && (_scrubFrames?.isNotEmpty ?? false);

    // 正文这行是"这一格是什么"：分辨率 + 扩展名 + 体积，缺哪项就少哪项
    final dot = item.filePath.lastIndexOf('.');
    final ext = (dot > 0 && dot < item.filePath.length - 1)
        ? item.filePath.substring(dot + 1).toUpperCase()
        : '';
    final meta = <String>[
      if (item.width != null && item.height != null && item.height! > 0)
        '${item.width}×${item.height}',
      if (ext.isNotEmpty) ext,
      formatFileSize(item.fileSize),
    ];
    final durationMs = item.durationMs;
    // 时长是这一格唯一算得上"读数"的东西，放右上深色标签；图片没有就不挖这一块
    final duration =
        (!_isImage && durationMs != null && durationMs > BigInt.zero)
        ? _formatDuration(durationMs)
        : null;

    final hasMenuActions =
        widget.onOpenFolder != null ||
        widget.onDeleteFile != null ||
        widget.onDeleteNodeLocalFile != null ||
        widget.onSaveToGallery != null;
    final tile = GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapDown: hasMenuActions
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      onLongPressStart: (PlatformUtil.isMobile && hasMenuActions)
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovering = true);
          if (_isVideo && widget.onRequestScrubFrames != null) {
            _loadScrubFrames();
          }
        },
        onHover: (event) {
          if (!_isVideo || _scrubFrames == null || _scrubFrames!.isEmpty) return;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final ratio = (event.localPosition.dx / box.size.width).clamp(0.0, 1.0);
          final newIdx = (ratio * (_scrubFrames!.length - 1)).round();
          final curIdx = (_hoverRatio * (_scrubFrames!.length - 1)).round();
          if (newIdx != curIdx) setState(() => _hoverRatio = ratio);
        },
        onExit: (_) => setState(() {
          _hovering = false;
          _hoverRatio = 0.0;
        }),
        child: MediaCutoutCard(
          hovered: _hovering,
          withFoot: false,
          // 「隐藏叠加信息」只管图上这两块（类型标签、时长）。标题和元信息现在排在
          // 实色文字区里、不糊在图上，而且关掉它卡片高度也要跟着变，所以留着不动。
          label: widget.showOverlay ? _kindLabel : '',
          tagLabel: widget.showOverlay ? duration : null,
          tagIcon: duration != null ? StrokeIcons.schedule : null,
          title: item.title,
          body: meta.join(' · '),
          media: MediaCardCover(
            source: src,
            placeholderIcon: _isAudio ? StrokeIcons.musicNote : StrokeIcons.smartDisplay,
            lostIcon: StrokeIcons.brokenImage,
            isLost: widget.isLost,
          ),
          mediaOverlay: (widget.isLost || showTimeline)
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.isLost)
                      Positioned(
                        left: appMetrics.kSpace8,
                        top: appMetrics.kSpace8,
                        child: const LostBadge(),
                      ),
                    if (showTimeline)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: _hoverRatio,
                          minHeight: scaleW(3),
                          backgroundColor: s.surface,
                          valueColor: AlwaysStoppedAnimation<Color>(s.accent),
                        ),
                      ),
                  ],
                )
              : null,
        ),
      ),
    );
    if (widget.fixedHeight != null) {
      return SizedBox(height: widget.fixedHeight, child: tile);
    }
    return tile;
  }

  /// 将毫秒格式化为 M:SS 或 H:MM:SS 字符串。
  static String _formatDuration(BigInt ms) {
    final total = (ms.toInt() ~/ 1000).clamp(0, 359999); // max 99:59:59
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

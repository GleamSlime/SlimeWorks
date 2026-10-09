import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/fake_cover.dart';
import 'package:slime_works/pages/settings/components/asr_subtitle_section.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class MediaSettingsTab extends StatefulWidget {
  const MediaSettingsTab({super.key});

  @override
  State<MediaSettingsTab> createState() => _MediaSettingsTabState();
}

class _MediaSettingsTabState extends State<MediaSettingsTab> {
  late final MediaPrefsService _prefs;
  bool _loading = true;
  int _cacheSizeBytes = 0;
  bool _clearing = false;
  String _cachePath = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _prefs = getIt<MediaPrefsService>();
    await _prefs.init();
    final sz = await _prefs.calcCacheSizeBytes();
    final cacheDir = await _prefs.getMediaCacheBaseDir();
    if (!mounted) return;
    setState(() {
      _cacheSizeBytes = sz;
      _cachePath = cacheDir.path;
      _loading = false;
    });
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    await _prefs.clearCache();
    final sz = await _prefs.calcCacheSizeBytes();
    if (!mounted) return;
    setState(() {
      _cacheSizeBytes = sz;
      _clearing = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('缓存已清除'), duration: AppMotion.dwell));
  }

  /// 选一张本地图片当作伪封面
  Future<void> _pickFakeCoverImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await _prefs.setFakeCoverPath(path);
  }

  Future<void> _openCachePath() async {
    final dir = Directory(_cachePath);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    if (Platform.isMacOS) {
      await Process.run('open', [_cachePath]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [_cachePath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [_cachePath]);
    } else {
      // 移动端：复制路径
      await Clipboard.setData(ClipboardData(text: _cachePath));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('路径已复制')));
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.all(m.kSpace24),
      children: [
        // ── 隐私模式 ────────────────────────────────────────────────────────
        _SectionHeader(title: '隐私'),
        SizedBox(height: m.kSpace12),
        _SettingsCard(
          child: Obx(() {
            final on = _prefs.privacyMode.value;
            final sigma = _prefs.privacyBlurSigma.value;
            final fake = _prefs.fakeCover.value;
            final fakePath = _prefs.fakeCoverPath.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('隐私模式', style: AppTextStyles.cardTitle(context)),
                          SizedBox(height: m.kSpace4),
                          Text(
                            '开启后所有封面图将显示高斯模糊效果，防止敏感内容被旁人窥视。',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize12,
                              color: s.textTertiary,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: on, onChanged: (v) => _prefs.setPrivacyMode(v)),
                  ],
                ),
                // 伪封面开着的时候糊不糊都看不见，强度滑块就别占位了
                if (on && !fake) ...[
                  SizedBox(height: m.kSpace12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('模糊强度', style: AppTextStyles.cardTitle(context)),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: m.kSpace10,
                          vertical: m.kSpace3,
                        ),
                        decoration: BoxDecoration(
                          color: s.accentContainer,
                          borderRadius: m.radius999,
                        ),
                        child: Text(
                          sigma.toStringAsFixed(0),
                          maxLines: 1,
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize11,
                            weight: FontWeight.w600,
                            color: s.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    '值越大模糊越强，越小则越能看出轮廓。',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      color: s.textTertiary,
                      height: 1.6,
                    ),
                  ),
                  SizedBox(height: m.kSpace8),
                  Row(
                    children: [
                      Text('轻', style: AppTextStyles.caption(context)),
                      Expanded(
                        child: Slider(
                          value: sigma,
                          min: 5,
                          max: 40,
                          divisions: 7,
                          label: sigma.toStringAsFixed(0),
                          onChanged: (v) => _prefs.setPrivacyBlurSigma(v),
                        ),
                      ),
                      Text('强', style: AppTextStyles.caption(context)),
                    ],
                  ),
                ],
                SizedBox(height: m.kSpace12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('伪封面', style: AppTextStyles.cardTitle(context)),
                          SizedBox(height: m.kSpace4),
                          Text(
                            '开启后用一张无害图片整张顶替真实封面：不模糊、不加锁角标，'
                            '旁人看不出这里藏着内容。开启时优先于隐私模式的高斯模糊。',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize12,
                              color: s.textTertiary,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: fake, onChanged: (v) => _prefs.setFakeCover(v)),
                  ],
                ),
                if (fake) ...[
                  SizedBox(height: m.kSpace8),
                  Row(
                    children: [
                      // 小样直接复用真机上的同一个组件，这里看到的就是卡片上的效果
                      ClipRRect(
                        borderRadius: m.radius4,
                        child: SizedBox(
                          width: scaleW(96),
                          height: scaleW(64),
                          child: const FakeCover(),
                        ),
                      ),
                      SizedBox(width: m.kSpace12),
                      Expanded(
                        child: Text(
                          fakePath.isEmpty ? '未选择图片' : fakePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize12,
                            color: s.textTertiary,
                            height: 1.6,
                          ),
                        ),
                      ),
                      SizedBox(width: m.kSpace8),
                      OutlinedButton(
                        onPressed: _pickFakeCoverImage,
                        child: const Text('更换图片'),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    '图片文件读不到时封面退成纯色底，不会回落到真实封面。',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      color: s.textTertiary,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace24),

        // ── 文件检测 ────────────────────────────────────────────────────────
        _SectionHeader(title: '文件检测'),
        SizedBox(height: m.kSpace12),
        _SettingsCard(
          child: Obx(() {
            final depth = _prefs.fileCheckDepth.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('检测深度', style: AppTextStyles.cardTitle(context)),
                SizedBox(height: m.kSpace4),
                Text(
                  '封面文件异常时触发检测。深度检测会递归检查所有子资源文件是否存在，文件过多可能产生卡顿。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textTertiary,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: m.kSpace12),
                RadioGroup<FileCheckDepth>(
                  groupValue: depth,
                  onChanged: (v) {
                    if (v != null) _prefs.setFileCheckDepth(v);
                  },
                  child: Column(
                    children: FileCheckDepth.values
                        .map(
                          (d) => RadioListTile<FileCheckDepth>(
                            value: d,
                            title: Text(d.label, style: AppTextStyles.rowTitle(context)),
                            subtitle: Text(
                              d.description,
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize12,
                                color: s.textTertiary,
                                height: 1.6,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace24),

        // ── 视频清晰度 ──────────────────────────────────────────────────────
        _SectionHeader(title: '视频预览'),
        SizedBox(height: m.kSpace12),
        _SettingsCard(
          child: Obx(() {
            final q = _prefs.quality.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('视频清晰度', style: AppTextStyles.cardTitle(context))),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace10,
                        vertical: m.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: s.accentContainer,
                        borderRadius: m.radius999,
                      ),
                      child: Text(
                        MediaPrefsService.levels[q - 1].label,
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize11,
                          weight: FontWeight.w600,
                          color: s.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: m.kSpace4),
                Text(
                  '影响封面图片尺寸（${MediaPrefsService.levels[q - 1].scaleWidth}px 宽）与磁盘占用。'
                  '更改画质后需清空缓存以重新生成封面。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textTertiary,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: m.kSpace8),
                Row(
                  children: [
                    Text('极低', style: AppTextStyles.caption(context)),
                    Expanded(
                      child: Slider(
                        value: q.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: MediaPrefsService.levels[q - 1].label,
                        onChanged: (v) => _prefs.setQuality(v.round()),
                      ),
                    ),
                    Text('超高', style: AppTextStyles.caption(context)),
                  ],
                ),
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace16),

        // ── 节点可用图片清晰度 ──────────────────────────────────────────────
        _SettingsCard(
          child: Obx(() {
            final w = _prefs.remoteCoverWidth.value;
            final currentLabel = MediaPrefsService.remoteCoverWidthPresets
                .firstWhere((p) => p.value == w, orElse: () => (label: '${w}px', value: w))
                .label;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('节点可用图片清晰度', style: AppTextStyles.cardTitle(context)),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace10,
                        vertical: m.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: s.accentContainer,
                        borderRadius: m.radius999,
                      ),
                      child: Text(
                        currentLabel,
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize11,
                          weight: FontWeight.w600,
                          color: s.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: m.kSpace4),
                Text(
                  '从节点拉取集合封面缩略图时使用的目标宽度，降低清晰度可节省上行带宽。'
                  '选"随本地清晰度"则严格跟随本地缩略图质量（含原图）。仅作用于节点访问链路，不参与本地资源缩略图生成。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textTertiary,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: m.kSpace8),
                Wrap(
                  spacing: m.kSpace8,
                  runSpacing: m.kSpace4,
                  children: MediaPrefsService.remoteCoverWidthPresets
                      .map(
                        (p) => ChoiceChip(
                          label: Text(p.label),
                          selected: w == p.value,
                          onSelected: (_) => _prefs.setRemoteCoverWidth(p.value),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace16),

        // ── 拉取远程图片清晰度 ──────────────────────────────────────────────
        _SettingsCard(
          child: Obx(() {
            final w = _prefs.remoteImageWidth.value;
            final currentLabel = MediaPrefsService.remoteImageWidthPresets
                .firstWhere((p) => p.value == w, orElse: () => (label: '${w}px', value: w))
                .label;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('拉取远程图片清晰度', style: AppTextStyles.cardTitle(context)),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace10,
                        vertical: m.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: s.accentContainer,
                        borderRadius: m.radius999,
                      ),
                      child: Text(
                        currentLabel,
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize11,
                          weight: FontWeight.w600,
                          color: s.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: m.kSpace4),
                Text(
                  '点开图片预览时从节点拉取的最大宽度，与节点可用图片清晰度独立控制。选"原图"则不压缩（默认）。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textTertiary,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: m.kSpace8),
                Wrap(
                  spacing: m.kSpace8,
                  runSpacing: m.kSpace4,
                  children: MediaPrefsService.remoteImageWidthPresets
                      .map(
                        (p) => ChoiceChip(
                          label: Text(p.label),
                          selected: w == p.value,
                          onSelected: (_) => _prefs.setRemoteImageWidth(p.value),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace16),

        // ── 本地缩略图质量 ──────────────────────────────────────────────────
        _SettingsCard(
          child: Obx(() {
            final w = _prefs.localPreviewWidth.value;
            final currentLabel = MediaPrefsService.localPreviewWidthPresets
                .firstWhere((p) => p.value == w, orElse: () => (label: '${w}px', value: w))
                .label;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('本地缩略图质量', style: AppTextStyles.cardTitle(context))),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace10,
                        vertical: m.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: s.accentContainer,
                        borderRadius: m.radius999,
                      ),
                      child: Text(
                        currentLabel,
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize11,
                          weight: FontWeight.w600,
                          color: s.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: m.kSpace4),
                Text(
                  '为本地媒体资源生成缓存缩略图（写入资源旁 .SlimeWorks 目录）使用的目标宽度，'
                  '同时作为列表图片的解码宽度。选"原图"则按完整尺寸解码（适合高分辨率屏幕）。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textTertiary,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: m.kSpace8),
                Wrap(
                  spacing: m.kSpace8,
                  runSpacing: m.kSpace4,
                  children: MediaPrefsService.localPreviewWidthPresets
                      .map(
                        (p) => ChoiceChip(
                          label: Text(p.label),
                          selected: w == p.value,
                          onSelected: (_) => _prefs.setLocalPreviewWidth(p.value),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace16),

        // ── 视频 scrub 帧预生成 ────────────────────────────────────────────
        _SettingsCard(
          child: Obx(() {
            final on = _prefs.videoScrubPreload.value;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('预生成视频悬停帧', style: AppTextStyles.cardTitle(context)),
                      SizedBox(height: m.kSpace4),
                      Text(
                        '开启后视频缩略图出现在列表时即后台抽取全套悬停预览帧（每张 3~8 帧 ffmpeg），'
                        '悬停秒开。关闭后仅在悬停时才抽帧，导入/浏览含大量视频的资源库时 CPU 占用明显更低，'
                        '代价是首次悬停会有短暂等待；未悬停的视频使用默认封面帧。',
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize12,
                          color: s.textTertiary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: on, onChanged: (v) => _prefs.setVideoScrubPreload(v)),
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace16),

        // ── 并发量 ─────────────────────────────────────────────────────────
        _SettingsCard(
          child: Obx(() {
            final c = _prefs.concurrency.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('预览封面解析并发量', style: AppTextStyles.cardTitle(context)),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace10,
                        vertical: m.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: s.accentContainer,
                        borderRadius: m.radius999,
                      ),
                      child: Text(
                        '$c',
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize11,
                          weight: FontWeight.w600,
                          color: s.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: m.kSpace4),
                Text(
                  '同时解析的封面/悬停帧数量（图片缩略图、视频抽帧、音频封面共用）。'
                  '值越大生成越快，但 CPU 占用也越高。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textTertiary,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: m.kSpace8),
                Row(
                  children: [
                    Text('1', style: AppTextStyles.caption(context)),
                    Expanded(
                      child: Slider(
                        value: c.toDouble(),
                        min: 1,
                        max: 20,
                        divisions: 19,
                        label: '$c',
                        onChanged: (v) => _prefs.setConcurrency(v.round()),
                      ),
                    ),
                    Text('20', style: AppTextStyles.caption(context)),
                  ],
                ),
              ],
            );
          }),
        ),

        SizedBox(height: m.kSpace24),

        // ── 缓存管理 ───────────────────────────────────────────────────────
        _SectionHeader(title: '缓存管理'),
        SizedBox(height: m.kSpace12),
        _SettingsCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('清空预览缓存', style: AppTextStyles.cardTitle(context)),
                    SizedBox(height: m.kSpace4),
                    Text(
                      '当前缓存占用：${_formatBytes(_cacheSizeBytes)}',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize12,
                        color: s.textTertiary,
                        height: 1.6,
                      ),
                    ),
                    SizedBox(height: m.kSpace2),
                    Text(
                      '删除所有已生成的视频帧缓存和封面缩略图，下次打开集合时将重新生成。',
                      style: AppTextStyles.caption(context),
                    ),
                    if (_cachePath.isNotEmpty) ...[
                      SizedBox(height: m.kSpace6),
                      GestureDetector(
                        onTap: _openCachePath,
                        child: Row(
                          children: [
                            DrawIcon(StrokeIcons.folder,
                              size: m.iconSize13,
                              color: s.accent,
                            ),
                            SizedBox(width: m.kSpace4),
                            Expanded(
                              child: Text(
                                _cachePath,
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: m.fontSize11,
                                  color: s.accent,
                                ).copyWith(decoration: TextDecoration.underline),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: m.kSpace16),
              _clearing
                  ? SizedBox(
                      width: scaleW(36),
                      height: scaleW(36),
                      child: CircularProgressIndicator(strokeWidth: m.strokeEmphasis),
                    )
                  : FilledButton.tonal(
                      onPressed: _clearCache,
                      style: FilledButton.styleFrom(
                        backgroundColor: s.danger.container,
                        foregroundColor: s.danger.onContainer,
                      ),
                      child: const Text('清空'),
                    ),
            ],
          ),
        ),

        SizedBox(height: m.kSpace12),

        // ── 缓存大小上限 ────────────────────────────────────────────────────
        Obx(() {
          final limitBytes = _prefs.cacheLimitBytes.value;
          return _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('缓存大小上限', style: AppTextStyles.cardTitle(context)),
                SizedBox(height: m.kSpace4),
                Text(
                  '超出上限时，将自动删除最旧的缓存文件，直到缓存降至上限的 50%（每次生成预览图后 1 分钟触发检查）。',
                  style: AppTextStyles.caption(context),
                ),
                SizedBox(height: m.kSpace12),
                Wrap(
                  spacing: m.kSpace8,
                  runSpacing: m.kSpace8,
                  children: [
                    for (final preset in MediaPrefsService.cacheLimitPresets)
                      ChoiceChip(
                        label: Text(preset.label),
                        selected: limitBytes == preset.value,
                        onSelected: (_) => _prefs.setCacheLimitBytes(preset.value),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),

        SizedBox(height: m.kSpace24),

        // ── 语音识别字幕（内网大模型 + 本地 SenseVoice）──────────────────────
        const AsrSubtitleSection(),

        if (!Platform.isWindows && !Platform.isMacOS)
          Padding(
            padding: EdgeInsets.only(top: m.kSpace12),
            child: Text(
              '注意：视频封面功能仅在 Windows / macOS 上可用。',
              style: AppTextStyles.role(context, fontSize: m.fontSize12, color: s.danger.color),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Text(
      title,
      style: AppTextStyles.role(
        context,
        fontSize: m.fontSize13,
        weight: FontWeight.w600,
        color: s.accent,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radius12,
        border: Border.all(color: s.border),
      ),
      child: child,
    );
  }
}

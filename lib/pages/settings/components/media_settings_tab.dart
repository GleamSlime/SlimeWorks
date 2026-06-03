import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';

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
    ).showSnackBar(const SnackBar(content: Text('缓存已清除'), duration: Duration(seconds: 2)));
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
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace24),
      children: [
        // ── 隐私模式 ────────────────────────────────────────────────────────
        _SectionHeader(title: '隐私', theme: theme),
        SizedBox(height: AppTheme.metrics.kSpace12),
        _SettingsCard(
          theme: theme,
          child: Obx(() {
            final on = _prefs.privacyMode.value;
            final sigma = _prefs.privacyBlurSigma.value;
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
                          Text('隐私模式', style: theme.textTheme.titleSmall),
                          SizedBox(height: AppTheme.metrics.kSpace4),
                          Text(
                            '开启后所有封面图将显示高斯模糊效果，防止敏感内容被旁人窥视。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(150),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: on, onChanged: (v) => _prefs.setPrivacyMode(v)),
                  ],
                ),
                if (on) ...[
                  SizedBox(height: AppTheme.metrics.kSpace12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('模糊强度', style: theme.textTheme.titleSmall),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppTheme.metrics.kSpace10,
                          vertical: AppTheme.metrics.kSpace3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: AppTheme.metrics.radius999,
                        ),
                        child: Text(
                          sigma.toStringAsFixed(0),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace4),
                  Text(
                    '值越大模糊越强，越小则越能看出轮廓。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace8),
                  Row(
                    children: [
                      Text('轻', style: theme.textTheme.labelSmall),
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
                      Text('强', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ],
            );
          }),
        ),

        SizedBox(height: AppTheme.metrics.kSpace24),

        // ── 文件检测 ────────────────────────────────────────────────────────
        _SectionHeader(title: '文件检测', theme: theme),
        SizedBox(height: AppTheme.metrics.kSpace12),
        _SettingsCard(
          theme: theme,
          child: Obx(() {
            final depth = _prefs.fileCheckDepth.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('检测深度', style: theme.textTheme.titleSmall),
                SizedBox(height: AppTheme.metrics.kSpace4),
                Text(
                  '封面文件异常时触发检测。深度检测会递归检查所有子资源文件是否存在，文件过多可能产生卡顿。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace12),
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
                            title: Text(d.label),
                            subtitle: Text(
                              d.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withAlpha(150),
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

        SizedBox(height: AppTheme.metrics.kSpace24),

        // ── 视频清晰度 ──────────────────────────────────────────────────────
        _SectionHeader(title: '视频预览', theme: theme),
        SizedBox(height: AppTheme.metrics.kSpace12),
        _SettingsCard(
          theme: theme,
          child: Obx(() {
            final q = _prefs.quality.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('视频清晰度', style: theme.textTheme.titleSmall),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.metrics.kSpace10,
                        vertical: AppTheme.metrics.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppTheme.metrics.radius999,
                      ),
                      child: Text(
                        MediaPrefsService.levels[q - 1].label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.metrics.kSpace4),
                Text(
                  '影响封面图片尺寸（${MediaPrefsService.levels[q - 1].scaleWidth}px 宽）与磁盘占用。'
                  '更改画质后需清空缓存以重新生成封面。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                Row(
                  children: [
                    Text('极低', style: theme.textTheme.labelSmall),
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
                    Text('超高', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            );
          }),
        ),

        SizedBox(height: AppTheme.metrics.kSpace16),

        // ── 远程封面清晰度 ──────────────────────────────────────────────────
        _SettingsCard(
          theme: theme,
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
                    Text('远程封面清晰度', style: theme.textTheme.titleSmall),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.metrics.kSpace10,
                        vertical: AppTheme.metrics.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppTheme.metrics.radius999,
                      ),
                      child: Text(
                        currentLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.metrics.kSpace4),
                Text(
                  '从远程节点获取集合封面图片时使用的目标宽度，降低清晰度可节省上行带宽。选"原图"则不压缩。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
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

        SizedBox(height: AppTheme.metrics.kSpace16),

        // ── 远程图片清晰度 ──────────────────────────────────────────────────
        _SettingsCard(
          theme: theme,
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
                    Text('远程图片清晰度', style: theme.textTheme.titleSmall),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.metrics.kSpace10,
                        vertical: AppTheme.metrics.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppTheme.metrics.radius999,
                      ),
                      child: Text(
                        currentLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.metrics.kSpace4),
                Text(
                  '点开图片预览时从远程节点拉取的最大宽度，与封面清晰度独立控制。选"原图"则不压缩（默认）。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
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

        SizedBox(height: AppTheme.metrics.kSpace16),

        // ── 本地预览图质量 ──────────────────────────────────────────────────
        _SettingsCard(
          theme: theme,
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
                    Text('本地预览图质量', style: theme.textTheme.titleSmall),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.metrics.kSpace10,
                        vertical: AppTheme.metrics.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppTheme.metrics.radius999,
                      ),
                      child: Text(
                        currentLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.metrics.kSpace4),
                Text(
                  '列表中本地图片解码时的 cacheWidth，降低分辨率可减少内存占用和加载时间。'
                  '选"原图"则按完整尺寸解码（适合高分辨率屏幕）。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
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

        SizedBox(height: AppTheme.metrics.kSpace16),

        // ── 并发量 ─────────────────────────────────────────────────────────
        _SettingsCard(
          theme: theme,
          child: Obx(() {
            final c = _prefs.concurrency.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('预览封面解析并发量', style: theme.textTheme.titleSmall),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.metrics.kSpace10,
                        vertical: AppTheme.metrics.kSpace3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppTheme.metrics.radius999,
                      ),
                      child: Text(
                        '$c',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.metrics.kSpace4),
                Text(
                  '同时解析的视频封面数量。值越大封面生成越快，但 CPU 占用也越高。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                Row(
                  children: [
                    Text('1', style: theme.textTheme.labelSmall),
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
                    Text('20', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            );
          }),
        ),

        SizedBox(height: AppTheme.metrics.kSpace24),

        // ── 缓存管理 ───────────────────────────────────────────────────────
        _SectionHeader(title: '缓存管理', theme: theme),
        SizedBox(height: AppTheme.metrics.kSpace12),
        _SettingsCard(
          theme: theme,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('清空预览缓存', style: theme.textTheme.titleSmall),
                    SizedBox(height: AppTheme.metrics.kSpace4),
                    Text(
                      '当前缓存占用：${_formatBytes(_cacheSizeBytes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace2),
                    Text(
                      '删除所有已生成的视频帧缓存和封面缩略图，下次打开集合时将重新生成。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                    if (_cachePath.isNotEmpty) ...[
                      SizedBox(height: AppTheme.metrics.kSpace6),
                      GestureDetector(
                        onTap: _openCachePath,
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: AppTheme.metrics.iconSize13,
                              color: theme.colorScheme.primary,
                            ),
                            SizedBox(width: AppTheme.metrics.kSpace4),
                            Expanded(
                              child: Text(
                                _cachePath,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
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
              SizedBox(width: AppTheme.metrics.kSpace16),
              _clearing
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : FilledButton.tonal(
                      onPressed: _clearCache,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      ),
                      child: const Text('清空'),
                    ),
            ],
          ),
        ),

        SizedBox(height: AppTheme.metrics.kSpace12),

        // ── 缓存大小上限 ────────────────────────────────────────────────────
        Obx(() {
          final limitBytes = _prefs.cacheLimitBytes.value;
          return _SettingsCard(
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('缓存大小上限', style: theme.textTheme.titleSmall),
                SizedBox(height: AppTheme.metrics.kSpace4),
                Text(
                  '超出上限时，将自动删除最旧的缓存文件，直到缓存降至上限的 50%（每次生成预览图后 1 分钟触发检查）。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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

        if (!Platform.isWindows && !Platform.isMacOS)
          Padding(
            padding: EdgeInsets.only(top: AppTheme.metrics.kSpace12),
            child: Text(
              '注意：视频封面功能仅在 Windows / macOS 上可用。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, required this.theme});

  final Widget child;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: AppTheme.metrics.radius12,
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: child,
    );
  }
}

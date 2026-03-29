import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';

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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _prefs = getIt<MediaPrefsService>();
    await _prefs.init();
    final sz = await _prefs.calcCacheSizeBytes();
    if (!mounted) return;
    setState(() {
      _cacheSizeBytes = sz;
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('缓存已清除'), duration: Duration(seconds: 2)),
    );
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
      padding: const EdgeInsets.all(24),
      children: [
        // ── 视频清晰度 ──────────────────────────────────────────────────────
        _SectionHeader(title: '视频预览', theme: theme),
        const SizedBox(height: 12),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
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
                const SizedBox(height: 4),
                Text(
                  '影响封面图片尺寸（${MediaPrefsService.levels[q - 1].scaleWidth}px 宽）与磁盘占用。'
                  '更改画质后需清空缓存以重新生成封面。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 8),
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

        const SizedBox(height: 16),

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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
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
                const SizedBox(height: 4),
                Text(
                  '同时解析的视频封面数量。值越大封面生成越快，但 CPU 占用也越高。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 8),
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

        const SizedBox(height: 24),

        // ── 缓存管理 ───────────────────────────────────────────────────────
        _SectionHeader(title: '缓存管理', theme: theme),
        const SizedBox(height: 12),
        _SettingsCard(
          theme: theme,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('清空预览缓存', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      '当前缓存占用：${_formatBytes(_cacheSizeBytes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '删除所有已生成的视频帧缓存，下次打开集合时将重新生成。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
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

        if (!Platform.isWindows && !Platform.isMacOS)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '注意：视频封面功能仅在 Windows / macOS 上可用。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: child,
    );
  }
}

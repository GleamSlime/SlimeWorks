import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/src/rust/api/whisper.dart' as whisper_api;
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 播放器设置标签页（Whisper 模型管理）
class MusicPlayerSettingsTab extends StatefulWidget {
  const MusicPlayerSettingsTab({super.key});

  @override
  State<MusicPlayerSettingsTab> createState() => _MusicPlayerSettingsTabState();
}

class _MusicPlayerSettingsTabState extends State<MusicPlayerSettingsTab> {
  String _selectedModel = 'large-v3';
  List<_ModelInfo> _models = [];
  bool _loading = true;
  String? _downloadingModel;

  /// 下载进度 0.0~1.0
  double _downloadProgress = 0;

  /// 下载进度轮询定时器
  _DownloadProgressTracker? _progressTracker;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _progressTracker?.cancel();
    super.dispose();
  }

  void _loadModels() {
    try {
      whisper_api.whisperInitialize();
      final selected = whisper_api.whisperGetSelectedModel();
      final statuses = whisper_api.whisperGetModelStatuses();
      setState(() {
        _selectedModel = selected;
        _models = statuses
            .map(
              (s) => _ModelInfo(
                presetName: s.presetName,
                displayName: s.displayName,
                exists: s.modelFileExists,
                filePath: s.modelFilePath,
                fileSize: s.modelFileSize?.toInt(),
                approxSizeMb: s.approximateSizeMb.toInt(),
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _downloadModel(String presetName, int approxSizeMb) async {
    setState(() {
      _downloadingModel = presetName;
      _downloadProgress = 0;
    });

    // 先通过 HEAD 请求获取实际文件大小
    int actualSizeBytes = approxSizeMb * 1024 * 1024;
    try {
      final url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$presetName.bin';
      // 使用 HttpClient 以支持自动跟随重定向
      final httpClient = HttpClient();
      try {
        final request = await httpClient.headUrl(Uri.parse(url));
        final response = await request.close();
        // 优先使用 x-linked-size，其次 content-length
        final xLinkedSize = response.headers.value('x-linked-size');
        final contentLength = response.headers.value('content-length');
        final sizeStr = xLinkedSize ?? contentLength;
        if (sizeStr != null) {
          actualSizeBytes = int.tryParse(sizeStr) ?? actualSizeBytes;
        }
      } finally {
        httpClient.close();
      }
    } catch (_) {}

    // 启动进度追踪（轮询文件大小）
    _progressTracker = _DownloadProgressTracker(
      presetName,
      actualSizeBytes,
      (progress) {
        if (mounted) {
          setState(() => _downloadProgress = progress);
        }
      },
    );
    _progressTracker!.start();

    try {
      await whisper_api.whisperDownloadModel(presetName: presetName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$presetName 模型下载完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    } finally {
      _progressTracker?.cancel();
      if (mounted) {
        setState(() {
          _downloadingModel = null;
          _downloadProgress = 0;
        });
        _loadModels();
      }
    }
  }

  Future<void> _deleteModel(String presetName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 $presetName 模型文件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        whisper_api.whisperDeleteModel(presetName: presetName);
        _loadModels();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  void _selectModel(String presetName) {
    try {
      // 确保数据库表已注册
      whisper_api.whisperInitialize();
      final result = whisper_api.whisperSetSelectedModel(presetName: presetName);
      if (result) {
        setState(() => _selectedModel = presetName);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('切换模型失败，请重试')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return ListView(
      padding: EdgeInsets.all(m.kSpace24),
      children: [
        Row(
          children: [
            Container(
              width: m.kSpace24,
              height: m.kSpace24,
              decoration: BoxDecoration(
                color: s.accentContainer,
                borderRadius: m.radius6,
              ),
              child: DrawIcon(StrokeIcons.graphicEq, size: m.iconSize12, color: s.accent),
            ),
            SizedBox(width: m.kSpace8),
            Text(
              '语音识别设置',
              style: AppTextStyles.sectionTitle(context),
            ),
          ],
        ),
        SizedBox(height: m.kSpace8),
        Text(
          '播放音频没有歌词时，自动使用 Whisper 模型识别语音并生成 CUE 歌词文件。',
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize12,
            color: s.textTertiary,
            height: 1.6,
          ),
        ),
        SizedBox(height: m.kSpace16),
        ..._models.map((model) => _buildModelTile(context, model)),
      ],
    );
  }

  Widget _buildModelTile(BuildContext context, _ModelInfo model) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final isSelected = model.presetName == _selectedModel;
    final isDownloading = _downloadingModel == model.presetName;

    return Card(
      margin: EdgeInsets.only(bottom: m.kSpace8),
      child: Column(
        children: [
          ListTile(
            selected: isSelected,
            // 选中行只铺一层极淡的强调水洗：实心强调底会把整行变成一个按钮
            selectedTileColor: s.accent.withValues(alpha: 0.05),
            leading: DrawIcon(
              isSelected
                  ? StrokeIcons.radioButtonChecked
                  : StrokeIcons.radioButtonUnchecked,
              color: isSelected ? s.accent : null,
            ),
            title: Row(
              children: [
                Expanded(child: Text(model.displayName)),
                if (model.exists)
                  Chip(
                    label: Text(
                      _formatFileSize(model.fileSize),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            subtitle: model.exists
                ? Text(
                    '已下载',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      color: s.success.color,
                      height: 1.6,
                    ),
                  )
                : Text(
                    '未下载（约 ${model.approxSizeMb}MB）',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      color: s.textTertiary,
                      height: 1.6,
                    ),
                  ),
            trailing: _buildTrailing(context, model, isSelected, isDownloading),
            onTap: model.exists ? () => _selectModel(model.presetName) : null,
          ),
          // 下载进度条
          if (isDownloading && _downloadProgress > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: m.radius2,
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: m.kSpace4,
                      backgroundColor: s.surfaceSunken,
                    ),
                  ),
                  SizedBox(height: m.kSpace4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize12,
                          color: s.textTertiary,
                          height: 1.6,
                        ),
                      ),
                      Text(
                        _formatFileSize((_downloadProgress * _progressTracker!.totalBytes).round()),
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize12,
                          color: s.textTertiary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace8),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildTrailing(
    BuildContext context,
    _ModelInfo model,
    bool isSelected,
    bool isDownloading,
  ) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    if (isDownloading) {
      return SizedBox(
        width: m.iconSize24,
        height: m.iconSize24,
        child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeRegular),
      );
    }

    if (model.exists) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            Padding(
              padding: EdgeInsets.only(right: m.kSpace8),
              child: DrawIcon(StrokeIcons.checkCircle,
                color: s.accent,
                size: m.iconSize20,
              ),
            ),
          IconButton(
            icon: DrawIcon(StrokeIcons.deleteOutline, size: m.iconSize18),
            onPressed: () => _deleteModel(model.presetName),
            tooltip: '删除模型',
          ),
        ],
      );
    }

    return IconButton(
      icon: DrawIcon(StrokeIcons.download, size: m.iconSize20),
      onPressed: () => _downloadModel(model.presetName, model.approxSizeMb),
      tooltip: '下载模型',
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// 下载进度追踪器
///
/// 通过轮询文件大小估算下载进度
class _DownloadProgressTracker {
  final String presetName;
  final int totalBytes;
  final void Function(double progress) onProgress;
  Timer? _timer;

  _DownloadProgressTracker(this.presetName, this.totalBytes, this.onProgress);

  /// 获取模型文件路径
  String get _modelFilePath {
    // macOS: ~/Library/Application Support/SlimeWorks/whisper_models/ggml-{preset}.bin
    final appData = Platform.environment['APPDATA'] ??
        '${Platform.environment['HOME']}/Library/Application Support';
    return '$appData/SlimeWorks/whisper_models/ggml-$presetName.bin';
  }

  void start() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkProgress();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _checkProgress() {
    try {
      final file = File(_modelFilePath);
      if (file.existsSync()) {
        final fileSize = file.lengthSync();
        final progress = (fileSize / totalBytes).clamp(0.0, 0.99);
        onProgress(progress);
      }
    } catch (_) {}
  }
}

class _ModelInfo {
  final String presetName;
  final String displayName;
  final bool exists;
  final String? filePath;
  final int? fileSize;
  final int approxSizeMb;

  _ModelInfo({
    required this.presetName,
    required this.displayName,
    required this.exists,
    this.filePath,
    this.fileSize,
    required this.approxSizeMb,
  });
}

import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/src/rust/api/whisper.dart' as whisper_api;

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

  @override
  void initState() {
    super.initState();
    _loadModels();
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

  Future<void> _downloadModel(String presetName) async {
    setState(() => _downloadingModel = presetName);

    try {
      // whisperDownloadModel 是异步的（Rust 端阻塞下载）
      await whisper_api.whisperDownloadModel(presetName: presetName);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$presetName 模型下载完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingModel = null);
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  void _selectModel(String presetName) {
    try {
      whisper_api.whisperSetSelectedModel(presetName: presetName);
      setState(() => _selectedModel = presetName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      children: [
        Text(
          '语音识别设置',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: AppTheme.metrics.kSpace8),
        Text(
          '播放音频没有歌词时，自动使用 Whisper 模型识别语音并生成 CUE 歌词文件。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
        ),
        SizedBox(height: AppTheme.metrics.kSpace16),
        ..._models.map((model) => _buildModelTile(context, model)),
      ],
    );
  }

  Widget _buildModelTile(BuildContext context, _ModelInfo model) {
    final isSelected = model.presetName == _selectedModel;
    final isDownloading = _downloadingModel == model.presetName;

    return Card(
      margin: EdgeInsets.only(bottom: AppTheme.metrics.kSpace8),
      child: ListTile(
        selected: isSelected,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.05),
        leading: Icon(
          isSelected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
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
            ? Text('已下载', style: TextStyle(color: Colors.green.shade600))
            : Text(
                '未下载（约 ${model.approxSizeMb}MB）',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
        trailing: _buildTrailing(context, model, isSelected, isDownloading),
        onTap: model.exists ? () => _selectModel(model.presetName) : null,
      ),
    );
  }

  Widget? _buildTrailing(
    BuildContext context,
    _ModelInfo model,
    bool isSelected,
    bool isDownloading,
  ) {
    if (isDownloading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (model.exists) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            Padding(
              padding: EdgeInsets.only(right: AppTheme.metrics.kSpace8),
              child: Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            onPressed: () => _deleteModel(model.presetName),
            tooltip: '删除模型',
          ),
        ],
      );
    }

    return IconButton(
      icon: const Icon(Icons.download_rounded, size: 20),
      onPressed: () => _downloadModel(model.presetName),
      tooltip: '下载模型',
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
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

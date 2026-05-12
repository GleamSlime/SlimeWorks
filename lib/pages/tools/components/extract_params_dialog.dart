import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/pages/tools/components/extract_card.dart';

class ExtractParamsDialog extends StatefulWidget {
  const ExtractParamsDialog({super.key});

  @override
  State<ExtractParamsDialog> createState() => _ExtractParamsDialogState();
}

class _ExtractParamsDialogState extends State<ExtractParamsDialog> {
  String _sourceDir = '';
  String _outputDir = '';
  ExtractOutputMode _outputMode = ExtractOutputMode.byArchiveName;
  String _password = '';
  int _parallelCount = 1;
  final bool _deleteAfterExtract = false;
  bool _isScanning = false;
  List<ArchiveInfo> _scannedArchives = [];
  bool _isDraggingSource = false;
  bool _isDraggingOutput = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return AlertDialog(
      title: Text('解压参数', style: theme.textTheme.titleLarge),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionLabel('解压目录'),
              SizedBox(height: m.kSpace8),
              _buildDirectoryPicker(
                value: _sourceDir,
                hint: '选择包含压缩包的目录',
                onTap: _pickSourceDir,
                isDragging: _isDraggingSource,
                onDraggingChanged: (v) => setState(() => _isDraggingSource = v),
                onDropped: (path) {
                  setState(() => _sourceDir = path);
                  _scanArchives();
                },
              ),
              SizedBox(height: m.kSpace16),

              _buildSectionLabel('解压到哪里'),
              SizedBox(height: m.kSpace8),
              _buildOutputModeSelector(),
              if (_outputMode != ExtractOutputMode.sameDirectory) ...[
                SizedBox(height: m.kSpace8),
                _buildDirectoryPicker(
                  value: _outputDir,
                  hint: '选择输出目录',
                  onTap: _pickOutputDir,
                  isDragging: _isDraggingOutput,
                  onDraggingChanged: (v) => setState(() => _isDraggingOutput = v),
                  onDropped: (path) => setState(() => _outputDir = path),
                ),
              ],
              SizedBox(height: m.kSpace16),

              _buildSectionLabel('解压密码'),
              SizedBox(height: m.kSpace8),
              _buildPasswordInput(),
              SizedBox(height: m.kSpace16),

              _buildSectionLabel('解压后文件夹创建方式'),
              SizedBox(height: m.kSpace8),
              _buildFolderModeSelector(),
              SizedBox(height: m.kSpace16),

              _buildSectionLabel('并行解压数'),
              SizedBox(height: m.kSpace8),
              _buildParallelCountSelector(),
              SizedBox(height: m.kSpace16),

              if (_scannedArchives.isNotEmpty) ...[
                Divider(),
                SizedBox(height: m.kSpace8),
                Text(
                  '发现 ${_scannedArchives.length} 个压缩包',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              if (_isScanning)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: m.kSpace8),
                  child: const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isScanning ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(onPressed: _canStart() ? _onStart : null, child: const Text('开始解压')),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    final theme = Theme.of(context);
    return Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600));
  }

  Widget _buildDirectoryPicker({
    required String value,
    required String hint,
    required VoidCallback onTap,
    required bool isDragging,
    required ValueChanged<bool> onDraggingChanged,
    required ValueChanged<String> onDropped,
  }) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    Widget child = InkWell(
      onTap: onTap,
      borderRadius: m.radius8,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace10),
        decoration: BoxDecoration(
          color: isDragging
              ? theme.colorScheme.primary.withAlpha(15)
              : theme.inputDecorationTheme.fillColor,
          borderRadius: m.radius8,
          border: Border.all(
            color: isDragging
                ? theme.colorScheme.primary
                : value.isEmpty
                ? theme.dividerColor
                : theme.colorScheme.primary,
            width: isDragging ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isDragging ? Icons.folder_open_outlined : Icons.folder_outlined,
              size: m.iconSize18,
              color: isDragging ? theme.colorScheme.primary : theme.hintColor,
            ),
            SizedBox(width: m.kSpace8),
            Expanded(
              child: Text(
                isDragging ? '释放以选择此目录' : (value.isEmpty ? hint : value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDragging
                      ? theme.colorScheme.primary
                      : value.isEmpty
                      ? theme.hintColor
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (!Platform.isAndroid && !Platform.isIOS) {
      child = DropTarget(
        onDragEntered: (_) => onDraggingChanged(true),
        onDragExited: (_) => onDraggingChanged(false),
        onDragDone: (details) {
          onDraggingChanged(false);
          for (final file in details.files) {
            final path = file.path;
            if (FileSystemEntity.isDirectorySync(path)) {
              onDropped(path);
              return;
            }
          }
          if (details.files.isNotEmpty) {
            final path = details.files.first.path;
            final parent = File(path).parent.path;
            onDropped(parent);
          }
        },
        child: child,
      );
    }

    return child;
  }

  Widget _buildOutputModeSelector() {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Container(
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: m.radius8,
      ),
      child: Row(
        children: [
          _buildModeChip('同级目录', ExtractOutputMode.sameDirectory),
          _buildModeChip('指定目录', ExtractOutputMode.byArchiveName),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, ExtractOutputMode mode) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isSelected = _outputMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _outputMode = mode),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: m.kSpace8),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary.withAlpha(25) : Colors.transparent,
            borderRadius: m.radius8,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isSelected ? theme.colorScheme.primary : theme.hintColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordInput() {
    final service = getIt.get<ExtractService>();

    return TextField(
      decoration: InputDecoration(
        hintText: '输入解压密码（可选）',
        suffixIcon: PopupMenuButton<String>(
          icon: Icon(Icons.vpn_key_outlined, size: AppTheme.metrics.iconSize18),
          itemBuilder: (_) => service.passwords.isEmpty
              ? [const PopupMenuItem(value: '', child: Text('暂无保存的密码'))]
              : service.passwords
                    .map(
                      (p) => PopupMenuItem(
                        value: p.password,
                        child: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
          onSelected: (value) {
            if (value.isNotEmpty) {
              setState(() => _password = value);
            }
          },
        ),
      ),
      onChanged: (v) => _password = v,
      controller: TextEditingController(text: _password),
    );
  }

  Widget _buildFolderModeSelector() {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Container(
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: m.radius8,
      ),
      child: Column(
        children: [
          _buildFolderModeOption('按压缩包名称创建文件夹', ExtractOutputMode.byArchiveName),
          _buildFolderModeOption('全部解压到目录下', ExtractOutputMode.flatToOutput),
          _buildFolderModeOption('按原目录结构创建', ExtractOutputMode.preserveStructure),
        ],
      ),
    );
  }

  Widget _buildFolderModeOption(String label, ExtractOutputMode mode) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isSelected = _outputMode == mode;

    return InkWell(
      onTap: () => setState(() => _outputMode = mode),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withAlpha(15) : Colors.transparent,
          borderRadius: m.radius6,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: m.iconSize18,
              color: isSelected ? theme.colorScheme.primary : theme.hintColor,
            ),
            SizedBox(width: m.kSpace8),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParallelCountSelector() {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Row(
      children: [
        Expanded(
          child: Slider(
            value: _parallelCount.toDouble(),
            min: 1,
            max: 8,
            divisions: 7,
            label: _parallelCount.toString(),
            onChanged: (v) => setState(() => _parallelCount = v.round()),
          ),
        ),
        SizedBox(
          width: m.kSpace40,
          child: Text(
            _parallelCount.toString(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  bool _canStart() {
    if (_sourceDir.isEmpty) return false;
    if (_outputMode != ExtractOutputMode.sameDirectory && _outputDir.isEmpty) return false;
    return !_isScanning;
  }

  Future<void> _pickSourceDir() async {
    final result = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择解压目录');
    if (result != null) {
      setState(() => _sourceDir = result);
      _scanArchives();
    }
  }

  Future<void> _pickOutputDir() async {
    final result = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择输出目录');
    if (result != null) {
      setState(() => _outputDir = result);
    }
  }

  Future<void> _scanArchives() async {
    if (_sourceDir.isEmpty) return;
    setState(() => _isScanning = true);
    try {
      final service = getIt.get<ExtractService>();
      final archives = await service.scanArchives(_sourceDir);
      if (mounted) {
        setState(() {
          _scannedArchives = archives;
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _onStart() {
    final params = ExtractParams(
      sourceDir: _sourceDir,
      outputDir: _outputMode == ExtractOutputMode.sameDirectory ? _sourceDir : _outputDir,
      outputMode: _outputMode,
      password: _password.isEmpty ? null : _password,
      parallelCount: _parallelCount,
      deleteAfterExtract: _deleteAfterExtract,
    );
    Navigator.pop(context, params);
  }
}

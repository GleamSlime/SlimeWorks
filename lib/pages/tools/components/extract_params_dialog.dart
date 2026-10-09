import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/tools/components/extract_card.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

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
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return AlertDialog(
      title: Text(
        '解压参数',
        style: AppTextStyles.role(
          context,
          fontSize: m.fontSize15,
          height: 1.5,
          weight: FontWeight.w600,
          color: s.textPrimary,
        ),
      ),
      content: SizedBox(
        width: scaleW(480),
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
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize13,
                    height: 1.65,
                    weight: FontWeight.w600,
                    color: s.accentText,
                  ),
                ),
              ],

              if (_isScanning)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: m.kSpace8),
                  child: Center(
                    child: SizedBox(
                      width: m.kSpace16,
                      height: m.kSpace16,
                      child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeRegular),
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
    return Text(label, style: AppTextStyles.cardTitle(context));
  }

  Widget _buildDirectoryPicker({
    required String value,
    required String hint,
    required VoidCallback onTap,
    required bool isDragging,
    required ValueChanged<bool> onDraggingChanged,
    required ValueChanged<String> onDropped,
  }) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    Widget child = InkWell(
      onTap: onTap,
      borderRadius: m.radius8,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace10),
        decoration: BoxDecoration(
          color: isDragging ? s.accentContainer : s.surfaceSunken,
          borderRadius: m.radius8,
          border: Border.all(
            color: isDragging ? s.accent : value.isEmpty ? s.border : s.accent,
            width: scaleW(isDragging ? 2 : 1),
          ),
        ),
        child: Row(
          children: [
            DrawIcon(
              isDragging ? StrokeIcons.folderOpen : StrokeIcons.folder,
              size: m.iconSize18,
              color: isDragging ? s.accent : s.textTertiary,
            ),
            SizedBox(width: m.kSpace8),
            Expanded(
              child: Text(
                isDragging ? '释放以选择此目录' : (value.isEmpty ? hint : value),
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize13,
                  height: 1.65,
                  color: isDragging ? s.accent : value.isEmpty ? s.textTertiary : s.textSecondary,
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
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return Container(
      decoration: BoxDecoration(
        color: s.surfaceSunken,
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
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final isSelected = _outputMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _outputMode = mode),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: m.kSpace8),
          decoration: BoxDecoration(
            color: isSelected ? s.accentContainer : Colors.transparent,
            borderRadius: m.radius8,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              height: 1.6,
              weight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? s.accentText : s.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordInput() {
    final service = getIt.get<ExtractService>();

    return AppTextField(
      decoration: InputDecoration(
        hintText: '输入解压密码（可选）',
        suffixIcon: PopupMenuButton<String>(
          icon: DrawIcon(StrokeIcons.vpnKey, size: AppTheme.metrics.iconSize18),
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
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return Container(
      decoration: BoxDecoration(
        color: s.surfaceSunken,
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
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final isSelected = _outputMode == mode;

    return InkWell(
      onTap: () => setState(() => _outputMode = mode),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace8),
        decoration: BoxDecoration(
          color: isSelected ? s.accentContainer : Colors.transparent,
          borderRadius: m.radius6,
        ),
        child: Row(
          children: [
            DrawIcon(
              isSelected ? StrokeIcons.radioButtonChecked : StrokeIcons.radioButtonUnchecked,
              size: m.iconSize18,
              color: isSelected ? s.accent : s.textTertiary,
            ),
            SizedBox(width: m.kSpace8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  height: 1.6,
                  color: isSelected ? s.accentText : s.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParallelCountSelector() {
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
            style: AppTextStyles.body(context),
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

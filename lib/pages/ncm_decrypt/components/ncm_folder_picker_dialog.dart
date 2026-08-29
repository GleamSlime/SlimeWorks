import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ncm_decrypt_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class NcmFolderPickerDialog extends StatefulWidget {
  const NcmFolderPickerDialog({super.key});

  @override
  State<NcmFolderPickerDialog> createState() => _NcmFolderPickerDialogState();
}

class _NcmFolderPickerDialogState extends State<NcmFolderPickerDialog> {
  String? _selectedDir;
  bool _deleteAfterDecrypt = false;
  bool _isScanning = false;
  List<NcmFileInfo> _scannedFiles = [];
  int _totalSize = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return AlertDialog(
      title: const Text('NCM 解密'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 选择文件夹
            Text('选择包含 NCM 文件的文件夹', style: theme.textTheme.bodyMedium),
            SizedBox(height: m.kSpace12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedDir ?? '未选择文件夹',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _selectedDir != null ? theme.textTheme.bodySmall?.color : theme.hintColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: m.kSpace8),
                OutlinedButton.icon(
                  onPressed: _isScanning ? null : _pickFolder,
                  icon: Icon(Icons.folder_open, size: m.iconSize18),
                  label: const Text('浏览'),
                ),
              ],
            ),
            SizedBox(height: m.kSpace16),

            // 删除源文件选项
            CheckboxListTile(
              value: _deleteAfterDecrypt,
              onChanged: (v) => setState(() => _deleteAfterDecrypt = v ?? false),
              title: const Text('解密成功后删除源 NCM 文件'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            SizedBox(height: m.kSpace12),

            // 扫描结果
            if (_isScanning)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else if (_scannedFiles.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(m.kSpace12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(10),
                  borderRadius: m.radius8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发现 ${_scannedFiles.length} 个 NCM 文件',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: m.kSpace4),
                    Text(
                      '总大小: ${_formatFileSize(_totalSize)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
              SizedBox(height: m.kSpace8),
              // 文件列表预览（最多显示 5 个）
              ..._scannedFiles.take(5).map(
                    (f) => Padding(
                      padding: EdgeInsets.symmetric(vertical: m.kSpace2),
                      child: Row(
                        children: [
                          Icon(Icons.audio_file, size: m.iconSize16, color: theme.hintColor),
                          SizedBox(width: m.kSpace8),
                          Expanded(
                            child: Text(
                              f.fileName,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatFileSize(f.fileSize),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (_scannedFiles.length > 5)
                Padding(
                  padding: EdgeInsets.only(top: m.kSpace4),
                  child: Text(
                    '...还有 ${_scannedFiles.length - 5} 个文件',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ),
            ] else if (_selectedDir != null && !_isScanning)
              Padding(
                padding: EdgeInsets.symmetric(vertical: m.kSpace8),
                child: Text(
                  '该目录下未发现 NCM 文件',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _scannedFiles.isNotEmpty ? _startDecrypt : null,
          child: const Text('开始解密'),
        ),
      ],
    );
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择 NCM 文件所在文件夹');
    if (result == null) return;

    setState(() {
      _selectedDir = result;
      _isScanning = true;
      _scannedFiles = [];
      _totalSize = 0;
    });

    try {
      final service = getIt.get<NcmDecryptService>();
      final files = await service.scanFiles(result);
      if (mounted) {
        setState(() {
          _scannedFiles = files;
          _totalSize = files.fold(0, (sum, f) => sum + f.fileSize);
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _startDecrypt() {
    if (_selectedDir == null) return;

    final service = getIt.get<NcmDecryptService>();
    service.startDecrypt(
      sourceDir: _selectedDir!,
      deleteAfterDecrypt: _deleteAfterDecrypt,
    );

    Navigator.of(context).pop();
  }

  String _formatFileSize(int bytes) {
    const kb = 1024;
    const mb = 1024 * kb;
    const gb = 1024 * mb;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
    return '$bytes B';
  }
}

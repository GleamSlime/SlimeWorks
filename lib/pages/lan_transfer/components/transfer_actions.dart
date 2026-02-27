import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/lan_transfer_viewmodel.dart';

/// 传输操作组件
class TransferActions extends StatefulWidget {
  final LanTransferViewModel viewModel;

  const TransferActions({super.key, required this.viewModel});

  @override
  State<TransferActions> createState() => _TransferActionsState();
}

class _TransferActionsState extends State<TransferActions> {
  final TextEditingController _textController = TextEditingController();
  bool _showTextInput = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final device = widget.viewModel.selectedDevice.value;

    if (device == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('向 ${device.deviceName} 发送', style: AppTextStyles.h6()),
              IconButton(
                onPressed: widget.viewModel.unselectDevice,
                icon: const Icon(Icons.close),
                tooltip: '取消选择',
              ),
            ],
          ),

          SizedBox(height: AppTheme.metrics.kSpace16),

          // 操作按钮
          Wrap(
            spacing: AppTheme.metrics.kSpace12,
            runSpacing: AppTheme.metrics.kSpace12,
            children: [
              _ActionButton(
                icon: Icons.text_fields,
                label: '发送文本',
                onPressed: () => setState(() => _showTextInput = !_showTextInput),
              ),
              _ActionButton(
                icon: Icons.insert_drive_file,
                label: '发送文件',
                onPressed: _pickAndSendFile,
              ),
              _ActionButton(icon: Icons.image, label: '发送图片', onPressed: _pickAndSendImage),
              _ActionButton(icon: Icons.video_library, label: '发送视频', onPressed: _pickAndSendVideo),
            ],
          ),

          // 文本输入框
          if (_showTextInput) ...[
            SizedBox(height: AppTheme.metrics.kSpace16),
            TextField(
              controller: _textController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '输入要发送的文本...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _sendText),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      await widget.viewModel.sendFile(result.files.single.path!);
    }
  }

  Future<void> _pickAndSendImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      await widget.viewModel.sendFile(result.files.single.path!);
    }
  }

  Future<void> _pickAndSendVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      await widget.viewModel.sendFile(result.files.single.path!);
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      Get.snackbar('提示', '请输入文本内容');
      return;
    }

    await widget.viewModel.sendText(text);
    _textController.clear();
    setState(() => _showTextInput = false);
  }
}

/// 操作按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: scaleW(20)),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isDark ? DarkColors.white10 : LightColors.black10,
        foregroundColor: isDark ? DarkColors.white100 : LightColors.black100,
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace16,
          vertical: AppTheme.metrics.kSpace12,
        ),
      ),
    );
  }
}
